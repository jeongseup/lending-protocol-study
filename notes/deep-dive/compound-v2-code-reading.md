# Compound V2 코드 리딩 가이드
# Compound V2 Code Reading Guide

> 핵심 컨트랙트 3개만 읽으면 됨. 나머지는 무시.
> Only 3 core contracts matter. Ignore the rest.

---

## 아키텍처 개요 / Architecture Overview

### 3개 컨트랙트의 역할

```
CToken          = 실행자 (돈 이동, 이자 계산)
Comptroller     = 문지기 (허가/거부, HF 계산, 오라클 가격 조회)
InterestRateModel = 계산기 (이자율)
```

### 사용자 호출 흐름

```
User → CToken.mint()        → Comptroller.mintAllowed()            ✓ → cToken 발행
User → CToken.borrow()      → Comptroller.borrowAllowed()         ✓ → 돈 전송
User → CToken.redeem()      → Comptroller.redeemAllowed()         ✓ → 원금+이자 회수
User → CToken.repayBorrow() → Comptroller.repayBorrowAllowed()    ✓ → 부채 상환
User → CToken.liquidate()   → Comptroller.liquidateBorrowAllowed() ✓ → 담보 청산
```

### CToken 상속 구조

```
CToken은 abstract contract. 실제 배포되는 건 CErc20과 CEther.

  CTokenInterface (abstract)  ← 인터페이스 + 스토리지
        ↓
  CToken (abstract)           ← 핵심 로직 (mint/borrow/accrueInterest)
        ↓                       getCashPrior()는 virtual로 선언만
        ├── CErc20 (concrete) ← ERC20 토큰 시장 (cUSDC, cDAI, cWBTC 등)
        └── CEther (concrete) ← ETH 시장 (cETH)

getCashPrior()가 abstract인 이유:
  CErc20: return EIP20Interface(underlying).balanceOf(address(this))
          → ERC20 토큰 잔고 조회
  CEther: return address(this).balance - msg.value
          → ETH 잔고에서 이번 tx 금액 제외 (이미 들어왔으니까)
  → 자산 타입에 따라 "풀의 현금"을 가져오는 방식이 다르므로 각각 override
```

### 배포 구조 — 토큰별 CToken + Comptroller 1개

```
Compound V2는 토큰별로 CToken을 각각 배포한다. Comptroller가 전체를 묶는 역할.

4개 자산을 지원하는 경우:
  ① CErc20 배포 → cUSDC (USDC 시장)
  ② CErc20 배포 → cDAI  (DAI 시장)
  ③ CErc20 배포 → cWBTC (WBTC 시장)
  ④ CEther 배포 → cETH  (ETH 시장)
  ⑤ Comptroller 배포 → 전체 묶어주는 문지기 (1개)

  총 5개 컨트랙트 배포. 실제 메인넷에서는 ~20개 CToken이 배포됨.

  cUSDC ──┐
  cDAI  ──┤
  cWBTC ──┼──→ Comptroller (1개)
  cETH  ──┤      ├── 시장 등록/관리
          ┘      ├── 담보/대출 허가 (borrowAllowed)
                  ├── HF 계산 (모든 시장을 순회!)
                  └── 청산 허가
```

### 크로스 마켓 흐름 — ETH 담보로 USDC 대출

```
사용자가 ETH 담보로 USDC를 빌리는 전체 흐름:

  1. User → cETH.mint{value: 1 ETH}()       ← cETH 컨트랙트 호출
  2. User → Comptroller.enterMarkets([cETH]) ← "cETH를 담보로 쓸게"
  3. User → cUSDC.borrow(1000e6)             ← cUSDC 컨트랙트 호출
     → cUSDC가 Comptroller.borrowAllowed() 호출
     → Comptroller가 모든 시장 순회하며 HF 계산
     → 통과하면 USDC 전송
```

### Compound V2 vs Aave V3 / 우리 프로젝트

```
┌──────────────┬─────────────────────────┬───────────────────────────┐
│              │ Compound V2             │ Aave V3 / 우리 프로젝트     │
├──────────────┼─────────────────────────┼───────────────────────────┤
│ 배포 구조     │ 토큰별 CToken 각각 배포  │ Pool 1개 + 토큰 N개        │
│              │ + Comptroller 1개       │                           │
├──────────────┼─────────────────────────┼───────────────────────────┤
│ 사용자 호출   │ 서로 다른 컨트랙트 각각   │ 같은 Pool 컨트랙트         │
├──────────────┼─────────────────────────┼───────────────────────────┤
│ 새 자산 추가  │ 새 CToken 배포 필요      │ Pool에 설정 추가만         │
├──────────────┼─────────────────────────┼───────────────────────────┤
│ 장점         │ 자산 간 격리 (하나 터져도 │ UX 간단, 가스비 절약       │
│              │ 다른 시장에 영향 적음)    │ (크로스콜 없음)             │
├──────────────┼─────────────────────────┼───────────────────────────┤
│ 단점         │ 가스비 높음, UX 복잡     │ 하나 터지면 전체 풀 위험    │
│              │                        │ (Isolation Mode로 완화)    │
└──────────────┴─────────────────────────┴───────────────────────────┘

Compound V3 (Comet): V2 문제를 인식, Aave처럼 단일 컨트랙트로 전환
→ 업계가 단일 풀 구조로 수렴하는 추세
```

---

## ① CToken.sol — 핵심 실행 로직

> GitHub: [`contracts/CToken.sol`](https://github.com/compound-finance/compound-protocol/blob/master/contracts/CToken.sol)
> 우리 프로젝트의 `LendingPool.sol` + `LToken.sol`에 해당
>
> abstract contract — 실제 배포는 CErc20(ERC20 시장) 또는 CEther(ETH 시장)
> getCashPrior() 등 자산 타입별로 다른 함수만 concrete에서 override

### accrueInterest() — 이자 누적 (제일 중요!)

```
역할: 모든 함수 호출 전에 자동 실행, 마지막 블록 이후 누적된 이자를 계산
Role: Auto-runs before every function, calculates interest since last block

호출 시점: mint, redeem, borrow, repay, liquidate 전부 이걸 먼저 호출
```

```solidity
function accrueInterest() public returns (uint) {
    uint currentBlockNumber = getBlockNumber();
    uint accrualBlockNumberPrior = accrualBlockNumber;

    // 같은 블록이면 이미 계산됨 → 스킵
    if (accrualBlockNumberPrior == currentBlockNumber) {
        return NO_ERROR;
    }

    // 이전 상태 읽기
    uint cashPrior = getCashPrior();          // 풀에 남은 현금
    uint borrowsPrior = totalBorrows;         // 총 대출금
    uint reservesPrior = totalReserves;       // 프로토콜 금고
    uint borrowIndexPrior = borrowIndex;      // 대출 인덱스 (scaled balance!)

    // 이자율 모델에서 현재 대출 이자율 가져오기
    uint borrowRateMantissa = interestRateModel.getBorrowRate(
        cashPrior, borrowsPrior, reservesPrior
    );

    // 경과 블록 수
    uint blockDelta = currentBlockNumber - accrualBlockNumberPrior;

    // 핵심 계산:
    //   이자 = 대출이자율 × 블록수 × 총대출금
    //   새 총대출금 = 기존 + 이자
    //   새 금고 = 기존 + (이자 × Reserve Factor)
    //   새 인덱스 = 기존 × (1 + 이자율 × 블록수)
    simpleInterestFactor = borrowRateMantissa * blockDelta;
    interestAccumulated = simpleInterestFactor * borrowsPrior;
    totalBorrowsNew = interestAccumulated + borrowsPrior;
    totalReservesNew = interestAccumulated * reserveFactor + reservesPrior;
    borrowIndexNew = simpleInterestFactor * borrowIndexPrior + borrowIndexPrior;

    // 전역 변수 4개만 업데이트 (SSTORE 4번)
    accrualBlockNumber = currentBlockNumber;
    borrowIndex = borrowIndexNew;        // ← scaled balance 패턴!
    totalBorrows = totalBorrowsNew;
    totalReserves = totalReservesNew;
}
```

```
포인트:
  borrowIndex가 바로 Aave의 liquidityIndex와 같은 역할
  → 전역 인덱스 1개만 업데이트하면 모든 대출자의 이자가 반영됨
  → 개별 사용자 잔고를 업데이트할 필요 없음 (가스 절약!)
```

### exchangeRateStoredInternal() — cToken 교환비율

```
역할: 1 cToken = 몇 USDC인지 계산
Role: How much underlying each cToken is worth
```

```solidity
function exchangeRateStoredInternal() internal view returns (uint) {
    uint _totalSupply = totalSupply;
    if (_totalSupply == 0) {
        return initialExchangeRateMantissa;  // 최초: 0.02 (50 cToken = 1 USDC)
    } else {
        // exchangeRate = (현금 + 대출금 - 금고) / 총 cToken 발행량
        uint totalCash = getCashPrior();
        uint cashPlusBorrowsMinusReserves = totalCash + totalBorrows - totalReserves;
        uint exchangeRate = cashPlusBorrowsMinusReserves * expScale / _totalSupply;
        return exchangeRate;
    }
}
```

```
이미 배운 것과 연결:
  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
  → deep-dive/deposit-tokens.md에서 배운 cToken 교환비율 공식과 동일!
  → 이자가 쌓이면 totalBorrows 증가 → exchangeRate 상승 → cToken 가치 상승
```

### mintFresh() — 예치 (= 우리 deposit)

```solidity
function mintFresh(address minter, uint mintAmount) internal {
    // 1. Comptroller한테 물어봄: "이 사람 예치해도 돼?"
    uint allowed = comptroller.mintAllowed(address(this), minter, mintAmount);
    if (allowed != 0) revert MintComptrollerRejection(allowed);

    // 2. 교환비율로 cToken 수량 계산
    Exp memory exchangeRate = Exp({mantissa: exchangeRateStoredInternal()});
    uint actualMintAmount = doTransferIn(minter, mintAmount);   // USDC 받기
    uint mintTokens = div_(actualMintAmount, exchangeRate);     // cToken 수량

    // 3. cToken 발행
    totalSupply = totalSupply + mintTokens;
    accountTokens[minter] = accountTokens[minter] + mintTokens;

    emit Mint(minter, actualMintAmount, mintTokens);
}
```

```
우리 코드와 비교:
  우리: pool.deposit() → LToken.mint(user, amount)     (1:1)
  Compound: CToken.mint() → amount / exchangeRate       (비율 적용)

  차이: 우리는 단순화해서 1:1, Compound는 교환비율로 변환
```

### borrowFresh() — 대출 (= 우리 borrow)

```solidity
function borrowFresh(address payable borrower, uint borrowAmount) internal {
    // 1. Comptroller한테 물어봄: "이 사람 빌려도 돼?" (HF 체크)
    uint allowed = comptroller.borrowAllowed(address(this), borrower, borrowAmount);
    if (allowed != 0) revert BorrowComptrollerRejection(allowed);

    // 2. 풀에 돈이 충분한지 확인
    if (getCashPrior() < borrowAmount) revert BorrowCashNotAvailable();

    // 3. 대출 기록 업데이트
    uint accountBorrowsPrev = borrowBalanceStoredInternal(borrower);
    uint accountBorrowsNew = accountBorrowsPrev + borrowAmount;

    accountBorrows[borrower].principal = accountBorrowsNew;
    accountBorrows[borrower].interestIndex = borrowIndex;  // ← 현재 인덱스 기록!
    totalBorrows = totalBorrowsNew;

    // 4. 돈 전송
    doTransferOut(borrower, borrowAmount);
}
```

```
포인트:
  accountBorrows[borrower].interestIndex = borrowIndex
  → 대출 시점의 인덱스를 기록해둠
  → 나중에 이자 계산: 현재빚 = 원금 × (현재index / 대출시점index)
  → Aave의 scaledBalance와 같은 원리!
```

### liquidateBorrowFresh() — 청산 (= 우리 liquidate)

```solidity
function liquidateBorrowFresh(
    address liquidator, address borrower,
    uint repayAmount, CTokenInterface cTokenCollateral
) internal {
    // 1. 청산 가능한지 체크 (shortfall > 0 = HF < 1)
    uint allowed = comptroller.liquidateBorrowAllowed(...);

    // 2. 대출금 일부 대납 (repayBorrowFresh 재사용)
    uint actualRepayAmount = repayBorrowFresh(liquidator, borrower, repayAmount);

    // 3. 담보 cToken을 청산자에게 전달 (보너스 포함)
    (uint amountSeizeError, uint seizeTokens) =
        comptroller.liquidateCalculateSeizeTokens(
            address(this), address(cTokenCollateral), actualRepayAmount
        );
    cTokenCollateral.seize(liquidator, borrower, seizeTokens);
}
```

```
청산 흐름 정리:
  1. HF < 1인 borrower 발견
  2. liquidator가 borrower의 대출금 일부를 대신 갚음
  3. 그 대가로 borrower의 담보를 할인된 가격으로 가져감 (보너스 ~5-10%)
  4. Close Factor: 한 번에 최대 50%까지만 청산 가능
```

---

## ② Comptroller.sol — 문지기 (리스크 관리)

> GitHub: [`contracts/Comptroller.sol`](https://github.com/compound-finance/compound-protocol/blob/master/contracts/Comptroller.sol)
> 우리 프로젝트에서는 `LendingPool.sol` 안에 통합됨

### 핵심 함수 1개만 이해하면 됨

### getHypotheticalAccountLiquidityInternal() — Health Factor 계산

```solidity
function getHypotheticalAccountLiquidityInternal(
    address account,
    CToken cTokenModify,    // "만약 이 시장에서..."
    uint redeemTokens,      // "이만큼 인출하면..."
    uint borrowAmount       // "이만큼 빌리면..."
) internal view returns (Error, uint, uint) {
    // → "그래도 건전한가?" 를 시뮬레이션

    // 사용자가 참여한 모든 시장을 순회
    CToken[] memory assets = accountAssets[account];
    for (uint i = 0; i < assets.length; i++) {
        CToken asset = assets[i];

        // cToken 잔고, 대출 잔고, 교환비율 조회
        (oErr, vars.cTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa)
            = asset.getAccountSnapshot(account);

        // 담보 가치 = cToken잔고 × 교환비율 × 오라클가격 × 담보인정비율
        vars.tokensToDenom = collateralFactor × exchangeRate × oraclePrice;
        vars.sumCollateral += tokensToDenom × cTokenBalance;

        // 부채 가치 = 대출잔고 × 오라클가격
        vars.sumBorrowPlusEffects += oraclePrice × borrowBalance;

        // "만약" 시뮬레이션: 인출/대출 효과 반영
        if (asset == cTokenModify) {
            vars.sumBorrowPlusEffects += tokensToDenom × redeemTokens;
            vars.sumBorrowPlusEffects += oraclePrice × borrowAmount;
        }
    }

    // 담보 > 부채 → liquidity (여유분)
    // 부채 > 담보 → shortfall (부족분 = 청산 가능!)
    if (sumCollateral > sumBorrowPlusEffects) {
        return (NO_ERROR, sumCollateral - sumBorrowPlusEffects, 0);
    } else {
        return (NO_ERROR, 0, sumBorrowPlusEffects - sumCollateral);
    }
}
```

```
우리가 배운 것과 매핑:
  sumCollateral = Σ(담보 × 가격 × CF)     ← Health Factor 분자
  sumBorrowPlusEffects = Σ(부채 × 가격)   ← Health Factor 분모

  Compound는 HF 숫자 대신 liquidity/shortfall로 표현:
    liquidity > 0 → 안전 (HF > 1과 동일)
    shortfall > 0 → 위험 (HF < 1과 동일)

  "Hypothetical" = "가정법"
    → "이 사용자가 추가로 X만큼 빌리면 건전한가?"를 시뮬레이션
    → borrowAllowed()에서 "빌리기 전에" 미리 체크하는 용도
```

### borrowAllowed() — 대출 허가

```solidity
function borrowAllowed(address cToken, address borrower, uint borrowAmount)
    external returns (uint)
{
    require(!borrowGuardianPaused[cToken], "borrow is paused");  // 일시정지 체크
    if (!markets[cToken].isListed) return MARKET_NOT_LISTED;     // 시장 등록 체크
    if (oracle.getUnderlyingPrice(CToken(cToken)) == 0) return PRICE_ERROR; // 오라클 체크

    // 대출 한도(Borrow Cap) 체크
    if (borrowCap != 0) {
        require(totalBorrows + borrowAmount < borrowCap, "market borrow cap reached");
    }

    // ★ 핵심: "이만큼 빌려도 건전한가?" 시뮬레이션
    (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(
        borrower, CToken(cToken), 0, borrowAmount
    );
    if (shortfall > 0) return INSUFFICIENT_LIQUIDITY;  // shortfall > 0 = HF < 1

    return NO_ERROR;  // 통과!
}
```

### liquidateBorrowAllowed() — 청산 허가

```solidity
function liquidateBorrowAllowed(
    address cTokenBorrowed, address cTokenCollateral,
    address liquidator, address borrower, uint repayAmount
) external returns (uint) {
    // 1. 시장 등록 체크
    if (!markets[cTokenBorrowed].isListed || !markets[cTokenCollateral].isListed)
        return MARKET_NOT_LISTED;

    // 2. shortfall 체크 (= HF < 1 인지)
    (Error err, , uint shortfall) = getAccountLiquidityInternal(borrower);
    if (shortfall == 0) return INSUFFICIENT_SHORTFALL;  // HF >= 1이면 청산 불가

    // 3. Close Factor 체크 (한 번에 50%까지만)
    uint maxClose = closeFactorMantissa * borrowBalance;
    if (repayAmount > maxClose) return TOO_MUCH_REPAY;

    return NO_ERROR;
}
```

### 오라클 아키텍처 — 가격 조회는 Comptroller만 한다

```
CToken 안에는 가격 조회 코드가 없다. 가격은 Comptroller만 사용한다.

  CToken ←→ Comptroller ←→ PriceOracle (별도 컨트랙트)
                               ↑
                     Chainlink Aggregator 등 외부 피드

오라클 호출 위치 (Comptroller.sol 안에서만):
  borrowAllowed():
    oracle.getUnderlyingPrice(CToken(cToken))          ← 대출 시 가격 조회
  getHypotheticalAccountLiquidityInternal():
    vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset)  ← HF 계산
  liquidateBorrowAllowed():
    getAccountLiquidityInternal() 안에서 가격 조회      ← 청산 시
```

> GitHub: [`contracts/SimplePriceOracle.sol`](https://github.com/compound-finance/compound-protocol/blob/master/contracts/SimplePriceOracle.sol)

### 청산 실행 — 프로토콜은 "수동적", 봇이 "능동적"

```
프로토콜이 자동으로 청산하는 게 아니다. 외부 봇에게 인센티브(보너스)를 줘서 유인.

  ① 오라클이 가격 업데이트 (Chainlink keeper 등)
  ② 청산 봇이 getAccountLiquidity()를 주기적으로 호출
     → Comptroller가 oracle.getUnderlyingPrice()로 최신 가격 조회
     → shortfall > 0 인 사용자 발견
  ③ 봇이 cToken.liquidateBorrow() 호출
  ④ cToken → Comptroller.liquidateBorrowAllowed() → 오라클 가격으로 HF 확인
  ⑤ 청산 실행, 봇은 8% 보너스 획득

  → 봇 인프라 운영이 DevOps 엔지니어의 업무 중 하나
  → 우리 프로젝트의 monitoring/cmd/monitor/ 가 이 봇 역할
```

---

## ③ JumpRateModelV2.sol — 이자율 모델

> GitHub: [`contracts/BaseJumpRateModelV2.sol`](https://github.com/compound-finance/compound-protocol/blob/master/contracts/BaseJumpRateModelV2.sol)
> 우리 프로젝트의 `JumpRateModel.sol`과 동일

```solidity
// 사용률 계산
function utilizationRate(uint cash, uint borrows, uint reserves) public pure returns (uint) {
    if (borrows == 0) return 0;
    return borrows * BASE / (cash + borrows - reserves);
}

// 대출 이자율 (우리가 이미 구현한 것!)
function getBorrowRateInternal(uint cash, uint borrows, uint reserves)
    internal view returns (uint)
{
    uint util = utilizationRate(cash, borrows, reserves);

    if (util <= kink) {
        // kink 이하: 완만한 증가
        return (util * multiplierPerBlock / BASE) + baseRatePerBlock;
    } else {
        // kink 초과: 급격한 증가
        uint normalRate = (kink * multiplierPerBlock / BASE) + baseRatePerBlock;
        uint excessUtil = util - kink;
        return (excessUtil * jumpMultiplierPerBlock / BASE) + normalRate;
    }
}

// 예치 이자율
function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa)
    public view returns (uint)
{
    uint oneMinusReserveFactor = BASE - reserveFactorMantissa;
    uint borrowRate = getBorrowRateInternal(cash, borrows, reserves);
    uint rateToPool = borrowRate * oneMinusReserveFactor / BASE;
    return utilizationRate(cash, borrows, reserves) * rateToPool / BASE;
}
```

```
우리 JumpRateModel.sol과 1:1 대응:
  utilizationRate() = 동일
  getBorrowRate()   = 동일 (kink 분기)
  getSupplyRate()   = borrowRate × utilization × (1 - RF) = 동일
```

---

## 무시해도 되는 파일들

```
❌ Governance/        — 거버넌스 투표 (지금 안 중요)
❌ Lens/              — 프론트엔드용 헬퍼
❌ Maximillion.sol    — ETH 래핑 유틸리티
❌ Timelock.sol       — 거버넌스 타임락
❌ CErc20*.sol        — CToken의 ERC20 버전 (CToken만 보면 됨)
❌ CEther.sol         — CToken의 ETH 버전 (로직 동일)
❌ CompoundLens.sol   — 읽기 전용 헬퍼
❌ Reservoir.sol      — COMP 토큰 분배
❌ Unitroller.sol     — Comptroller 프록시 (Day 5에서 다룸)
```

---

## 우리 코드와의 매핑 / Mapping to Our Code

```
┌────────────────────────┬─────────────────────────────────┐
│ Compound V2            │ 우리 프로젝트                    │
├────────────────────────┼─────────────────────────────────┤
│ CToken.sol             │ LendingPool.sol + LToken.sol    │
│  mint()                │  deposit()                      │
│  redeem()              │  withdraw()                     │
│  borrow()              │  borrow()                       │
│  repayBorrow()         │  repay()                        │
│  liquidateBorrow()     │  liquidate()                    │
│  accrueInterest()      │  updateInterest()               │
│  exchangeRate          │  1:1 (단순화)                    │
├────────────────────────┼─────────────────────────────────┤
│ Comptroller.sol        │ LendingPool.sol 안에 통합        │
│  borrowAllowed()       │  borrow() 안의 HF 체크          │
│  getAccountLiquidity() │  getHealthFactor()              │
├────────────────────────┼─────────────────────────────────┤
│ JumpRateModelV2.sol    │ JumpRateModel.sol (동일)        │
│  getBorrowRate()       │  getBorrowRate()                │
│  getSupplyRate()       │  getSupplyRate()                │
└────────────────────────┴─────────────────────────────────┘
```

---

## "Fresh" 패턴 — 왜 함수 이름에 Fresh가 붙는가?

```
Compound의 함수 호출 체인:

  mint()  → mintInternal()  → mintFresh()
               ↑
         accrueInterest() 호출!

  1. mint()           ← 사용자가 호출 (external)
  2. mintInternal()   ← 여기서 accrueInterest() 먼저 실행
  3. mintFresh()      ← "이자가 최신(fresh) 상태"에서 실행

"Fresh" = "accrueInterest()가 방금 실행되어 이자가 최신인 상태"
```

```
mintFresh() 첫 줄:
  if (accrualBlockNumber != getBlockNumber()) {
      revert MintFreshnessCheck();  ← "신선하지 않으면 거부!"
  }

  → accrueInterest()가 이번 블록에서 실행되었는지 확인
  → 안 됐으면 revert

왜? exchangeRate, borrowIndex, totalBorrows가 전부 이자에 의존하니까
    stale(오래된) 데이터로 계산하면 교환비율이 틀어짐

  Fresh = "오늘 이자 정산 완료된 통장"   → 거래 가능
  Stale = "어제까지만 이자 반영된 통장"   → 거래 불가!

  오라클 때문이 아니라, "이자 누적"이 최신인지 확인하는 것.
```

```
모든 핵심 함수가 이 패턴:
  mintFresh()          — Freshness 체크 후 예치 실행
  redeemFresh()        — Freshness 체크 후 인출 실행
  borrowFresh()        — Freshness 체크 후 대출 실행
  repayBorrowFresh()   — Freshness 체크 후 상환 실행
  liquidateBorrowFresh() — Freshness 체크 후 청산 실행

→ 모두 "이자 최신화 → 검증 → 실행"의 3단계 구조
```

---

## Mantissa — Solidity에서 소수점을 다루는 방법

```
문제: Solidity는 소수점(float/double)을 지원하지 않음
     0.05 (5%) 같은 값을 어떻게 저장하나?

해결: 10^18을 곱해서 정수로 저장 = "Mantissa"

  5% = 0.05 → 0.05 × 10^18 = 50,000,000,000,000,000 (50 quadrillion)
  100% = 1.0 → 1.0 × 10^18 = 1,000,000,000,000,000,000

  1 Mantissa unit = 1 × 10^18 (ETH의 Wei 단위와 동일한 스케일)
```

```
Compound 코드에서 실제로 보이는 것:

  // CTokenInterfaces.sol
  uint internal constant borrowRateMaxMantissa = 0.0005e16;
  uint internal constant reserveFactorMaxMantissa = 1e18;  // = 100%

  // Comptroller.sol
  uint public closeFactorMantissa;  // 0.5e18 = 50% (Close Factor)

  // exchangeRate도 Mantissa
  initialExchangeRateMantissa = 0.02e18;  // 1 underlying = 50 cToken
```

```
연산 규칙:

  일반 곱셈: result = a × b / 1e18
    → Mantissa끼리 곱하면 스케일이 두 배가 되니까 1e18로 나눠야 함
    → 예: 50% × 80% = 0.5e18 × 0.8e18 / 1e18 = 0.4e18 = 40%

  Compound의 Exp 구조체:
    struct Exp { uint mantissa; }
    function mul_(Exp a, Exp b) → a.mantissa × b.mantissa / 1e18
    function div_(uint a, Exp b) → a × 1e18 / b.mantissa
```

```
블록당 이자율 → 연이율 변환:

  코드에서 보이는 borrowRate = 블록당 이자율 (Mantissa)
  연이율로 바꾸려면: APR = borrowRate × blocksPerYear / 1e18

  예: borrowRateMantissa = 23,782,343,987 (블록당)
      blocksPerYear ≈ 2,102,400 (ETH ~15초/블록)
      APR = 23,782,343,987 × 2,102,400 / 1e18 ≈ 5% 연이율

  봇/대시보드 개발 시 주의:
    항상 Mantissa를 10^18로 나눠야 실제 소수점 값!
    안 나누면 5%가 50,000,000,000,000,000으로 보임
```

```
정밀도 관련 주의사항:

  ① 반올림 오차: 정수 나눗셈이라 미세한 오차 발생
     하지만 10^18 정밀도면 대부분 무시 가능
     (Wei 단위에서 1 차이 = $0.000000000000000001)

  ② 정수 오버플로우:
     Solidity 0.8+: 자동 overflow 체크 (revert)
     Solidity 0.7 이하: unchecked → 과거 많은 해킹의 원인
     Compound의 Mantissa 곱셈이 오버플로우되면 잘못된 이자 계산 → 자금 탈취 가능

  ③ Aave의 Ray:
     Compound: 10^18 (Mantissa)
     Aave:     10^27 (Ray) — 더 높은 정밀도
     우리 프로젝트: 10^18 (Compound 스타일)
```

---

## 읽는 순서 (30분이면 충분)

```
1. CToken.sol → Cmd+F "accrueInterest" (5분)
   → borrowIndex 업데이트 = scaled balance 패턴 확인

2. CToken.sol → Cmd+F "mintFresh" (5분)
   → amount / exchangeRate로 cToken 수량 계산 확인

3. CToken.sol → Cmd+F "borrowFresh" (5분)
   → interestIndex 기록 = 대출 시점 인덱스 저장 확인

4. Comptroller.sol → Cmd+F "getHypotheticalAccountLiquidity" (10분)
   → sumCollateral vs sumBorrowPlusEffects = Health Factor 확인

5. BaseJumpRateModelV2.sol → 전체 읽기 (5분)
   → 우리가 이미 구현한 것과 동일한지 확인
```

---

## initialExchangeRateMantissa — 0.02는 어디서 나온 값인가?

```
Q: initialExchangeRateMantissa = 0.02e18 (1 ETH = 50 cETH)
   이 비율은 어떻게 정해지는가?

A: Compound 팀의 UX 선택. 수학적 근거 없음. 생성자 파라미터로 전달.
```

### 1. 코드에서의 초기화

```solidity
// CToken.sol — initialize()
function initialize(
    ComptrollerInterface comptroller_,
    InterestRateModel interestRateModel_,
    uint initialExchangeRateMantissa_,  // ← 여기서 받음
    string memory name_,
    string memory symbol_,
    uint8 decimals_
) internal {
    require(initialExchangeRateMantissa_ > 0, "initial exchange rate must be > 0");
    initialExchangeRateMantissa = initialExchangeRateMantissa_;
}
```

```
배포 스크립트에서 0.02e18을 하드코딩해서 넘긴다.
모든 cToken (cUSDC, cDAI, cETH, cWBTC 등)이 동일하게 0.02e18 사용.
```

### 2. 왜 0.02인가?

```
UX를 위한 선택:
  exchangeRate = 0.02 → 1 underlying = 50 cTokens

  사용자가 1 ETH 예치 → 50 cETH 수령
  사용자가 100 USDC 예치 → 5,000 cUSDC 수령

  → cToken 숫자가 크게 보임 → 심리적으로 "많이 받은 느낌"
  → 소수점 이하 정밀도도 확보 (작은 금액도 cToken으로 표현 가능)

만약 반대로 initialExchangeRate = 50 이었다면:
  1 ETH → 0.02 cETH  ← 숫자가 너무 작음, 정밀도 손실 우려
```

### 3. 이 값은 프로토콜 동작에 영향 있는가?

```
없다. 시작점일 뿐이고, 이후 이자가 쌓이면서 exchangeRate가 계속 올라간다.

  배포 직후:   exchangeRate = 0.020000  (1 ETH = 50.00 cETH)
  1년 후:     exchangeRate = 0.020500  (1 ETH ≈ 48.78 cETH)
  5년 후:     exchangeRate = 0.025000  (1 ETH = 40.00 cETH)

  → 시작값이 0.02든 0.01이든, 상대적 증가율은 동일
  → 예금자 수익에 영향 없음
  → 유일한 요구사항: 0보다 크기만 하면 됨
```

### 4. 다른 프로토콜은 어떤 값을 쓰는가?

```
Compound V2:  0.02e18      (모든 cToken 동일, = 1:50)
Compound V3:  exchangeRate 개념 자체를 없앰 (Comet은 다른 구조)
Aave:         liquidityIndex = 1e27 (Ray) 에서 시작 (= 1:1)
ERC-4626:     보통 1:1에서 시작 (1 share = 1 asset)

→ Compound만 1:50으로 시작하는 독특한 선택
→ 나머지 프로토콜은 1:1이 표준
```
