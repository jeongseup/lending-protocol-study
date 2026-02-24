# Pool-based 렌딩 프로토콜 비교: Compound V2 vs Aave V3 vs Euler

# Pool-based Lending Protocol Comparison: Compound V2 vs Aave V3 vs Euler

> 동일 시나리오를 세 프로토콜에서 실행하며 아키텍처 차이를 비교
> Run the same scenario through all three protocols to compare architectures

---

## 아키텍처 한눈에 보기 / Architecture at a Glance

### Compound V2: "시장(Market)별 독립 컨트랙트"

```
                    사용자 (User)
                   ╱            ╲
                  ╱              ╲
          ┌──────────┐    ┌──────────┐
          │  cETH    │    │  cUSDC   │    ← 시장별 독립 컨트랙트
          │ (CEther) │    │ (CErc20) │       Each market = separate contract
          │          │    │          │
          │ mint()   │    │ mint()   │    ← 자산 보관 + 입출금 로직
          │ borrow() │    │ borrow() │       Asset custody + supply/borrow
          │ repay()  │    │ repay()  │
          └────┬─────┘    └────┬─────┘
               │               │
               └──────┬────────┘
                      ▼
              ┌───────────────┐
              │  Comptroller  │    ← 리스크 관리 (진입/퇴장/청산 허용 여부)
              │               │       Risk management hub
              │ enterMarkets()│
              │ checkMembership│
              │ liquidateBorrow│
              └───────┬───────┘
                      │
                      ▼
              ┌───────────────┐
              │  PriceOracle  │    ← 가격 피드
              └───────────────┘

특징:
  - CToken이 "자산 보관 + 회계 + 입출금"을 모두 담당
  - Comptroller는 "허용/거부"만 판단 (실행은 CToken이 함)
  - 시장 추가 = 새 CToken 배포 + Comptroller에 등록
```

### Aave V3: "단일 Pool 컨트랙트 + Library 패턴"

```
                    사용자 (User)
                        │
                        │ supply() / borrow() / liquidationCall()
                        ▼
              ┌──────────────────┐
              │     Pool.sol     │    ← 유일한 사용자 진입점
              │   (Single Entry) │       Single entry point for ALL assets
              │                  │
              │  delegatecall →  │
              └────────┬─────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
   ┌────────────┐ ┌──────────┐ ┌──────────────┐
   │SupplyLogic │ │BorrowLogic│ │LiquidationLogic│  ← Library (delegatecall)
   │            │ │          │ │              │     로직만 있고 상태 없음
   │executeSupply│ │executeBorrow│ │executeLiquidation│  Logic only, no state
   └────────────┘ └──────────┘ └──────────────┘
                       │
                       ▼
              ┌──────────────────┐
              │  aToken / vToken │    ← 별도 토큰 컨트랙트
              │  (per asset)     │       예치증서 / 부채증서
              │                  │       Deposit receipt / Debt receipt
              └──────────────────┘
                       │
                       ▼
              ┌──────────────────┐
              │ PoolAddresses    │    ← 레지스트리 (모든 주소 관리)
              │ Provider         │       Registry for all addresses
              └──────────────────┘

특징:
  - Pool이 모든 자산의 입출금/대출/청산을 처리
  - 로직은 Library로 분리 (delegatecall → Pool의 storage 사용)
  - 시장 추가 = Pool 설정에 자산 등록 (새 컨트랙트 배포 최소화)
  - aToken(예치) + variableDebtToken(부채) 별도 토큰화
```

### Euler: "단일 Storage + 모듈 프록시 (Diamond-like)"

```
                    사용자 (User)
                        │
                        │
          ┌─────────────┼─────────────┐
          ▼             ▼             ▼
   ┌────────────┐ ┌──────────┐ ┌──────────────┐
   │ eToken     │ │ dToken   │ │ Exec Module  │  ← 프록시 모듈들
   │ (Deposit)  │ │ (Debt)   │ │ (Liquidation)│     Proxy modules
   └─────┬──────┘ └─────┬────┘ └──────┬───────┘
         │              │             │
         └──────────────┼─────────────┘
                        ▼
              ┌──────────────────┐
              │    Storage.sol   │    ← 단일 스토리지 (모든 상태)
              │  (Single State)  │       ALL state in one contract
              │                  │
              │  assets[]        │
              │  users[]         │
              │  markets[]       │
              └──────────────────┘

특징:
  - 모든 데이터가 하나의 Storage 컨트랙트에 저장
  - 모듈은 delegatecall로 Storage를 읽고 씀
  - eToken/dToken은 "뷰(view)" — 실제 데이터는 Storage에
  - 가스 최소: 컨트랙트간 call 없이 내부 호출만
  - 모듈별 독립 업그레이드 가능 (Storage 유지 시)
```

---

## 동일 시나리오 비교 / Same Scenario Comparison

### 시나리오: Alice가 ETH 예치, Bob이 ETH 담보로 USDC 대출

```
조건:
  Alice: 10 ETH 예치 (예치자)
  Bob: 2 ETH 담보, 3,000 USDC 대출 (차입자)
  ETH = $2,000, USDC = $1
```

---

### Step 1: Alice가 10 ETH 예치 / Alice Deposits 10 ETH

#### Compound V2

```solidity
// Alice가 직접 cETH 컨트랙트를 호출
cETH.mint{value: 10 ether}();

// 내부 흐름:
// 1. CEther.mint()
//    → mintInternal(msg.value)
//    → accrueInterest()         ← 먼저 이자 정산
//    → mintFresh(msg.sender, msg.value)
//
// 2. mintFresh():
//    → comptroller.mintAllowed(address(this), minter, mintAmount)
//    → exchangeRate = getCashPrior() + totalBorrows - totalReserves
//                     ─────────────────────────────────────────────
//                                   totalSupply
//    → mintTokens = actualMintAmount / exchangeRate
//    → totalSupply += mintTokens
//    → accountTokens[minter] += mintTokens

// 결과:
//   Alice의 cETH 잔고: 10 / 0.02 = 500 cETH
//   cETH 컨트랙트의 ETH 잔고: 10 ETH
//   ETH는 cETH 컨트랙트 안에 보관됨
```

#### Aave V3

```solidity
// Alice가 Pool 컨트랙트를 호출 (단일 진입점)
pool.supply(WETH, 10 ether, alice, 0);

// 내부 흐름:
// 1. Pool.supply()
//    → SupplyLogic.executeSupply()   ← delegatecall (Library)
//
// 2. executeSupply():
//    → reserve.updateState()         ← 이자 인덱스 업데이트
//    → reserve.updateInterestRates() ← 새 이자율 계산
//    → IERC20(WETH).safeTransferFrom(user, aToken, amount)
//       ↑ 자산이 aToken 컨트랙트로 전송됨!
//    → IAToken(aToken).mint(user, amount, index)
//       ↑ aToken 민팅 (scaledBalance 사용)

// 결과:
//   Alice의 aWETH 잔고: 10 aWETH (1:1, 시간이 지나면 늘어남)
//   WETH는 aToken 컨트랙트에 보관됨
//   scaledBalance = amount / liquidityIndex
```

#### 핵심 차이점 / Key Difference

```
┌────────────────┬─────────────────────┬─────────────────────┐
│                │ Compound V2         │ Aave V3             │
├────────────────┼─────────────────────┼─────────────────────┤
│ 호출 대상       │ cETH (자산별 컨트랙트)│ Pool (단일 컨트랙트) │
│ Call target    │ Per-asset contract  │ Single contract     │
├────────────────┼─────────────────────┼─────────────────────┤
│ 자산 보관       │ cETH 컨트랙트 내부   │ aWETH 컨트랙트       │
│ Asset custody  │ Inside cToken       │ Inside aToken       │
├────────────────┼─────────────────────┼─────────────────────┤
│ 수령 토큰       │ 500 cETH            │ 10 aWETH            │
│ Token received │ (비율 0.02)          │ (1:1, rebase)       │
├────────────────┼─────────────────────┼─────────────────────┤
│ 잔고 변화       │ cETH 수량 고정       │ aWETH 수량 자동 증가 │
│ Balance change │ Fixed, rate grows   │ Balance rebases up  │
├────────────────┼─────────────────────┼─────────────────────┤
│ 이자 반영       │ exchangeRate 증가    │ liquidityIndex 증가  │
│ Interest via   │ Exchange rate grows │ Liquidity index grows│
└────────────────┴─────────────────────┴─────────────────────┘

수학적으로 동일한 공식:
  Compound: value = cTokenAmount × exchangeRate
  Aave:     value = scaledBalance × liquidityIndex
```

---

### Step 2: Bob이 2 ETH 담보 넣기 / Bob Deposits 2 ETH as Collateral

#### Compound V2

```solidity
// Step 2a: Bob이 cETH에 예치
cETH.mint{value: 2 ether}();

// Step 2b: Bob이 Comptroller에 담보 활성화
comptroller.enterMarkets([address(cETH)]);

// enterMarkets():
//   → accountMembership[cETH][bob] = true
//   → accountAssets[bob].push(cETH)
//   → 이제 Bob의 cETH가 담보로 인정됨

// 담보 가치:
//   2 ETH × $2,000 × 0.75 (collateralFactor) = $3,000
```

#### Aave V3

```solidity
// Aave는 supply 하면 자동으로 담보 활성화됨!
pool.supply(WETH, 2 ether, bob, 0);

// 내부적으로:
//   → reserve의 configuration에서 usageAsCollateralEnabled 확인
//   → 자동으로 bob의 userConfig에 담보 플래그 설정
//   → pool.setUserUseReserveAsCollateral(WETH, true) 는 기본값

// 담보 가치:
//   2 ETH × $2,000 × 0.825 (LTV) = $3,300
//   청산 기준: 2 ETH × $2,000 × 0.86 (liquidationThreshold) = $3,440
```

#### 핵심 차이점 / Key Difference

```
Compound V2:
  ① mint() — 예치
  ② enterMarkets() — 별도로 담보 활성화 필요!
  → 2번의 트랜잭션 (또는 2번의 함수 호출)

Aave V3:
  ① supply() — 예치하면 자동으로 담보 활성화
  → 1번의 트랜잭션

  추가로 Aave V3에는 LTV ≠ liquidationThreshold:
    LTV = 82.5% → 최대 빌릴 수 있는 비율
    liquidationThreshold = 86% → 이 아래로 떨어지면 청산
    → 사이에 3.5% 버퍼가 있음 (safety margin)
```

---

### Step 3: Bob이 3,000 USDC 대출 / Bob Borrows 3,000 USDC

#### Compound V2

```solidity
// Bob이 cUSDC 컨트랙트에서 직접 대출
cUSDC.borrow(3000e6);

// 내부 흐름:
// 1. borrow()
//    → borrowInternal(borrowAmount)
//    → accrueInterest()
//    → borrowFresh(msg.sender, borrowAmount)
//
// 2. borrowFresh():
//    → comptroller.borrowAllowed(address(this), borrower, borrowAmount)
//       → Comptroller가 모든 시장의 담보 합산
//       → getHypotheticalAccountLiquidity() 계산
//       → 담보가치 $3,000 ≥ 대출가치 $3,000 → 허용
//    → accountBorrows[borrower].principal = 3,000 USDC
//    → accountBorrows[borrower].interestIndex = borrowIndex
//    → totalBorrows += 3,000 USDC
//    → doTransferOut(borrower, 3000e6)  ← USDC 전송

// Bob의 상태:
//   담보: 100 cETH (= 2 ETH)
//   부채: 3,000 USDC
//   Health: $3,000 / $3,000 = 1.0 (위험!)
```

#### Aave V3

```solidity
// Bob이 Pool에서 대출 (단일 진입점)
pool.borrow(USDC, 3000e6, 2, 0, bob);
//                        ↑ interestRateMode: 2 = Variable

// 내부 흐름:
// 1. Pool.borrow()
//    → BorrowLogic.executeBorrow()   ← delegatecall
//
// 2. executeBorrow():
//    → ValidationLogic.validateBorrow()
//       → 모든 담보의 가치 합산 (USD 기준)
//       → 모든 부채의 가치 합산
//       → healthFactor 계산
//    → reserve.updateState()         ← 이자 인덱스 업데이트
//    → IVariableDebtToken(vToken).mint(user, amount, index)
//       ↑ 부채 토큰 발행! (Compound에는 없는 개념)
//    → IAToken(aToken).transferUnderlying(user, amount)
//       ↑ aToken에서 USDC를 Bob에게 전송
//    → reserve.updateInterestRates()

// Bob의 상태:
//   담보: 2 aWETH (= 2 ETH)
//   부채: 3,000 vUSDC (variableDebtToken)
//   Health: ($2,000 × 2 × 0.86) / $3,000 = 1.147
```

#### 핵심 차이점 / Key Difference

```
┌────────────────┬─────────────────────┬─────────────────────┐
│                │ Compound V2         │ Aave V3             │
├────────────────┼─────────────────────┼─────────────────────┤
│ 부채 추적       │ mapping으로 기록     │ vToken 토큰 발행     │
│ Debt tracking  │ accountBorrows map  │ Debt token (ERC-20) │
├────────────────┼─────────────────────┼─────────────────────┤
│ 부채 토큰화     │ ❌                  │ ✅ vToken            │
│ Tokenized debt │ No                  │ Yes                 │
├────────────────┼─────────────────────┼─────────────────────┤
│ 이자율 유형     │ 변동만              │ 변동 + 고정(stable)   │
│ Rate types     │ Variable only       │ Variable + Stable   │
├────────────────┼─────────────────────┼─────────────────────┤
│ USDC 출처       │ cUSDC 컨트랙트      │ aUSDC 컨트랙트       │
│ USDC source    │ From cToken         │ From aToken         │
├────────────────┼─────────────────────┼─────────────────────┤
│ Health Factor  │ Comptroller 계산     │ Pool 내부 계산       │
│ Calculated by  │ Comptroller          │ Pool (inline)        │
└────────────────┴─────────────────────┴─────────────────────┘

vToken의 의미:
  - Compound: Bob의 부채는 cUSDC 컨트랙트의 mapping에만 존재
  - Aave: Bob의 부채 = vUSDC 토큰 잔고 → ERC-20이므로 조회/추적 쉬움
  - 부채 이전(debt transfer)도 이론적으로 가능 (실제로는 제한됨)
```

---

### Step 4: 100 블록 후 이자 발생 / Interest Accrual After 100 Blocks

#### Compound V2

```solidity
// 누군가 cUSDC와 상호작용하면 accrueInterest() 자동 호출
// (또는 직접 호출 가능)

// accrueInterest():
//   blockDelta = currentBlock - accrualBlockNumber = 100
//   borrowRate = getBorrowRate(cash, totalBorrows, totalReserves)
//   interestAccumulated = borrowRate × blockDelta × totalBorrows
//
//   totalBorrows += interestAccumulated
//   totalReserves += interestAccumulated × reserveFactor
//   borrowIndex = borrowIndex × (1 + borrowRate × blockDelta)

// Bob의 현재 부채:
//   debt = principal × (currentBorrowIndex / accountBorrowIndex)
//   debt = 3,000 × (newIndex / oldIndex)
```

#### Aave V3

```solidity
// Aave는 "블록 기반"이 아니라 "시간 기반(timestamp)"
// Aave uses timestamp-based, not block-based

// reserve.updateState():
//   timeDelta = block.timestamp - lastUpdateTimestamp
//   currentLiquidityRate = calculateLiquidityRate(...)
//   currentVariableBorrowRate = calculateVariableBorrowRate(...)
//
//   // 복리 계산 (Compound V2는 단리 근사)
//   cumulatedLiquidityInterest = (1 + rate × timeDelta / SECONDS_PER_YEAR)
//   liquidityIndex = liquidityIndex × cumulatedLiquidityInterest
//   variableBorrowIndex = variableBorrowIndex × cumulatedBorrowInterest

// Bob의 현재 부채:
//   debt = scaledBalance × variableBorrowIndex
//   (scaledBalance = 발행 시점의 정규화된 잔고)
```

#### 핵심 차이점 / Key Difference

```
┌──────────────────┬─────────────────────┬─────────────────────┐
│                  │ Compound V2         │ Aave V3             │
├──────────────────┼─────────────────────┼─────────────────────┤
│ 시간 단위         │ 블록 (block)         │ 초 (seconds)        │
│ Time unit        │ Per block           │ Per second          │
├──────────────────┼─────────────────────┼─────────────────────┤
│ 이자 계산         │ 단리 근사            │ 복리 (compound)      │
│ Interest calc    │ Simple interest     │ Compound interest   │
│                  │ approx              │                     │
├──────────────────┼─────────────────────┼─────────────────────┤
│ 인덱스 이름       │ borrowIndex         │ variableBorrowIndex │
│ Index name       │                     │ + liquidityIndex    │
├──────────────────┼─────────────────────┼─────────────────────┤
│ 정밀도           │ Mantissa (10^18)     │ Ray (10^27)         │
│ Precision        │                     │                     │
├──────────────────┼─────────────────────┼─────────────────────┤
│ 업데이트 트리거    │ 상호작용 시 자동      │ 상호작용 시 자동     │
│ Update trigger   │ On interaction      │ On interaction      │
│                  │ (lazy evaluation)   │ (lazy evaluation)   │
└──────────────────┴─────────────────────┴─────────────────────┘

둘 다 "lazy evaluation" 패턴:
  - 매 블록/초마다 계산하지 않음
  - 누군가 상호작용할 때만 한 번에 계산
  - SSTORE 가스 절약
```

---

### Step 5: 가격 하락 → 청산 / Price Drop → Liquidation

```
ETH 가격 하락: $2,000 → $1,200
```

#### Compound V2

```solidity
// 1. 청산 가능 여부 확인
// Comptroller.getAccountLiquidity(bob):
//   담보가치 = 2 ETH × $1,200 × 0.75 = $1,800
//   부채가치 = 3,000+ USDC (이자 포함)
//   shortfall = $3,000 - $1,800 = $1,200 → 청산 가능!

// 2. 청산자(Liquidator)가 실행
cUSDC.liquidateBorrow(bob, repayAmount, cETH);

// 내부 흐름:
// liquidateBorrowFresh():
//   → comptroller.liquidateBorrowAllowed(...)
//   → repayAmount ≤ borrowBalance × closeFactor (50%)
//      최대 상환: 3,000 × 0.5 = 1,500 USDC
//   → 청산자가 1,500 USDC를 cUSDC에 전송
//   → seizeTokens = repayAmount × liquidationIncentive / exchangeRate
//      = 1,500 × 1.08 / $1,200 / 0.02 = 67,500 cETH
//   → Bob의 cETH에서 Liquidator로 cETH 이전
//      (실제로는 1,620 USDC 가치의 ETH = 1.35 ETH)
```

#### Aave V3

```solidity
// 1. Health Factor 확인
// pool.getUserAccountData(bob):
//   totalCollateralBase = 2 ETH × $1,200 = $2,400
//   totalDebtBase = 3,000+ USDC
//   healthFactor = ($2,400 × 0.86) / $3,000 = 0.688 → 청산 가능!

// 2. 청산자가 실행
pool.liquidationCall(WETH, USDC, bob, repayAmount, false);
//                                                   ↑ receiveAToken?

// 내부 흐름:
// LiquidationLogic.executeLiquidationCall():
//   → ValidationLogic.validateLiquidationCall()
//      → healthFactor < 1e18 확인
//   → debtToCover 계산 (closeFactor 적용)
//      HF < 0.95 → closeFactor = 100% (전액 청산 가능!)
//      HF ≥ 0.95 → closeFactor = 50%
//   → liquidationBonus = 5% (ETH의 경우)
//   → collateralToSeize = debtToCover × liquidationBonus / collateralPrice
//   → variableDebtToken.burn(bob, debtToCover)    ← 부채 토큰 소각
//   → aToken.transferOnLiquidation(bob, liquidator, collateralToSeize)
```

#### 핵심 차이점 / Key Difference

```
┌──────────────────┬─────────────────────┬──────────────────────┐
│                  │ Compound V2         │ Aave V3              │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 청산 기준         │ shortfall > 0       │ healthFactor < 1.0   │
│ Liquidation      │ (accountLiquidity)  │ (explicit HF)        │
│ trigger          │                     │                      │
├──────────────────┼─────────────────────┼──────────────────────┤
│ Close Factor     │ 항상 50%            │ HF < 0.95: 100%      │
│                  │ Always 50%         │ HF ≥ 0.95: 50%       │
│                  │                     │ (더 공격적 청산 가능)   │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 청산 보너스       │ 8% (프로토콜 전체)   │ 자산별 다름           │
│ Liquidation      │ 8% (global)        │ ETH: 5%, BTC: 5%    │
│ bonus            │                     │ volatile: 10%+       │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 보상 수령         │ cToken으로 수령      │ aToken 또는 underlying│
│ Reward format    │ Always cTokens     │ Choose: aToken/asset │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 호출 대상         │ cToken.liquidate    │ Pool.liquidationCall │
│ Call target      │ Borrow() (cUSDC)    │ (단일 진입점)         │
└──────────────────┴─────────────────────┴──────────────────────┘
```

---

## 컨트랙트 구조 비교 / Contract Structure Comparison

```
Compound V2:                    Aave V3:
──────────                      ────────
CToken.sol (2,000+ lines)      Pool.sol (~300 lines, thin)
  ├─ CErc20.sol                   ├─ SupplyLogic.sol (library)
  ├─ CEther.sol                   ├─ BorrowLogic.sol (library)
  └─ CToken abstract              ├─ LiquidationLogic.sol (library)
Comptroller.sol (1,500+ lines)    ├─ ValidationLogic.sol (library)
JumpRateModelV2.sol               └─ ReserveLogic.sol (library)
PriceOracle.sol                 AToken.sol (deposit receipt)
                                VariableDebtToken.sol (debt receipt)
                                StableDebtToken.sol (stable debt)
                                DefaultReserveInterestRateStrategy.sol
                                AaveOracle.sol
                                PoolAddressesProvider.sol (registry)

핵심 차이:
  Compound: CToken이 "뚱뚱" (자산보관 + 회계 + 로직 다 포함)
  Aave: Pool이 "얇음" (로직은 Library에, 자산은 aToken에)
  → Aave가 더 모듈화되어 있지만, 코드 읽기는 더 어려움
     (delegatecall 따라가야 해서)
```

---

## 오라클 사용 패턴 비교 / Oracle Usage Pattern

```
Compound V2:
  CToken → Comptroller → PriceOracle.getUnderlyingPrice(cToken)
  - CToken은 가격을 모름 (가격 조회 없음)
  - Comptroller만 오라클 호출
  - 가격: CToken 주소 기준 (underlying 가격)

Aave V3:
  Pool → AaveOracle.getAssetPrice(asset)
  - Pool이 내부적으로 오라클 호출 (Library를 통해)
  - PoolAddressesProvider에서 오라클 주소 조회
  - 가격: underlying 자산 주소 기준
  - Chainlink 직접 연동 (Compound는 래퍼 사용)

Euler:
  Module → Storage 내 오라클 조회
  - 오라클도 단일 Storage에서 관리
  - 외부 호출 최소화

세 프로토콜 모두:
  - 오라클 실패 시 트랜잭션 revert (graceful degradation 없음)
  - DevOps: 오라클 staleness 모니터링 필수!
```

---

## 가스 비용 비교 / Gas Cost Comparison

```
작업별 대략적 가스 비용 (추정치):

                    Compound V2    Aave V3      Euler
                    ──────────     ──────       ─────
Supply/Deposit      ~150k gas      ~200k gas    ~120k gas
Borrow              ~300k gas      ~350k gas    ~200k gas
Repay               ~150k gas      ~200k gas    ~120k gas
Liquidation         ~400k gas      ~450k gas    ~250k gas

Euler이 가장 효율적:
  - 컨트랙트간 external call 없음 (internal만)
  - 단일 스토리지 → SLOAD 최소화

Aave V3가 가장 비쌈:
  - Library delegatecall 오버헤드
  - aToken + vToken 양쪽 업데이트
  - 하지만 기능이 가장 풍부

Compound V2는 중간:
  - CToken → Comptroller external call
  - 단순한 구조이지만 cross-contract call 비용
```

---

## DevOps 관점 비교 / DevOps Perspective

```
배포 & 업그레이드:
  Compound V2: 새 시장 = 새 CToken 배포 → 거버넌스 제안 → Comptroller 등록
  Aave V3:    새 시장 = Pool 설정 변경 → PoolConfigurator → 프록시 업그레이드
  Euler:      새 시장 = Storage 설정 변경 → 모듈 업데이트

모니터링 복잡도:
  Compound V2: CToken 개수만큼 모니터링 대상 (N개 컨트랙트)
  Aave V3:    Pool 하나 + aToken/vToken N개 → 이벤트는 Pool에서 수집
  Euler:      Storage 하나만 모니터링 → 가장 단순

청산 봇:
  Compound V2: cToken별로 liquidateBorrow() 호출
  Aave V3:    Pool.liquidationCall() 하나로 통일
  Euler:      Exec 모듈을 통해 호출

사고 대응:
  Compound V2: Comptroller에서 시장별 pause 가능
  Aave V3:    Pool 전체 또는 자산별 pause 가능 (더 세밀한 제어)
  Euler:      모듈별 비활성화 가능 (가장 유연)
```

---

## 요약: 어떤 프로토콜을 언제? / When to Use Which?

```
Compound V2: "검증된 단순함"
  ✅ 가장 오래 검증됨 (2019~)
  ✅ 코드가 읽기 쉬움
  ❌ 새 시장마다 컨트랙트 배포 필요
  → 적합: 학습, 간단한 포크

Aave V3: "기능의 왕"
  ✅ E-Mode, Isolation Mode, Portal
  ✅ 가장 큰 TVL ($10B+)
  ✅ 멀티체인 배포
  ❌ 코드 복잡도 높음
  → 적합: 프로덕션, 엔터프라이즈

Euler: "효율의 극대화"
  ✅ 가스 최소
  ✅ 모듈 업그레이드 용이
  ❌ 2023년 $200M 해킹 (V1)
  ❌ V2로 재출시
  → 적합: 가스 최적화 중요한 체인 (L2 등)
```
