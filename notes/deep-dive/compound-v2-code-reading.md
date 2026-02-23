# Compound V2 코드 리딩 가이드
# Compound V2 Code Reading Guide

> 핵심 컨트랙트 3개만 읽으면 됨. 나머지는 무시.
> Only 3 core contracts matter. Ignore the rest.

---

## 아키텍처 개요 / Architecture Overview

```
사용자 호출 흐름 / User Call Flow:

  User → CToken.mint()      → Comptroller.mintAllowed()      ✓ → cToken 발행
  User → CToken.borrow()    → Comptroller.borrowAllowed()    ✓ → 돈 전송
  User → CToken.redeem()    → Comptroller.redeemAllowed()    ✓ → 원금+이자 회수
  User → CToken.repayBorrow() → Comptroller.repayBorrowAllowed() ✓ → 부채 상환
  User → CToken.liquidate() → Comptroller.liquidateBorrowAllowed() ✓ → 담보 청산

  CToken = 실행자 (돈 이동)
  Comptroller = 문지기 (허가/거부)
  InterestRateModel = 계산기 (이자율)
```

---

## ① CToken.sol — 핵심 실행 로직

> GitHub: `contracts/CToken.sol`
> 우리 프로젝트의 `LendingPool.sol` + `LToken.sol`에 해당

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

> GitHub: `contracts/Comptroller.sol`
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

---

## ③ JumpRateModelV2.sol — 이자율 모델

> GitHub: `contracts/BaseJumpRateModelV2.sol`
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
