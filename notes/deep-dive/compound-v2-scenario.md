# Compound V2 시나리오 시뮬레이션
# Compound V2 Example Scenario — Deployment to Interest Accrual

> 컨트랙트 배포부터 10블록 후 이자 계산까지 전체 흐름을 숫자로 추적
> Trace the full flow from deployment to interest accrual after 10 blocks

---

## Phase 1: 컨트랙트 배포 / Contract Deployment

```
배포 순서 (5개 컨트랙트):

  Block 0: 배포 시작

  ① JumpRateModelV2 배포
     파라미터:
       baseRatePerYear    = 2%   (0.02e18)
       multiplierPerYear  = 10%  (0.10e18)
       jumpMultiplierPerYear = 300% (3.00e18)
       kink               = 80%  (0.80e18)

     블록당으로 변환 (blocksPerYear = 2,102,400):
       baseRatePerBlock       = 0.02e18 / 2,102,400 ≈ 9,512,937,595
       multiplierPerBlock     = 0.10e18 / 2,102,400 ≈ 47,564,687,975
       jumpMultiplierPerBlock = 3.00e18 / 2,102,400 ≈ 1,426,940,639,269

  ② PriceOracle 배포
     ETH/USD = $2,000
     USDC/USD = $1.00

  ③ Comptroller 배포
     oracle = PriceOracle 주소
     closeFactorMantissa = 0.5e18  (50%)
     liquidationIncentiveMantissa = 1.08e18  (8% 보너스)

  ④ CEther 배포 (cETH 시장)
     comptroller = Comptroller 주소
     interestRateModel = JumpRateModel 주소
     initialExchangeRateMantissa = 0.02e18  (1 ETH = 50 cETH)
     reserveFactorMantissa = 0.10e18  (10%)

     → Comptroller에 등록: _supportMarket(cETH)
     → collateralFactorMantissa = 0.75e18  (75%)

  ⑤ CErc20 배포 (cUSDC 시장)
     underlying = USDC 주소
     comptroller = Comptroller 주소
     interestRateModel = JumpRateModel 주소
     initialExchangeRateMantissa = 0.02e18  (1 USDC = 50 cUSDC)
     reserveFactorMantissa = 0.10e18  (10%)

     → Comptroller에 등록: _supportMarket(cUSDC)
     → collateralFactorMantissa = 0.85e18  (85%)
```

```
배포 후 상태:

  cETH:                       cUSDC:
    totalSupply    = 0          totalSupply    = 0
    totalBorrows   = 0          totalBorrows   = 0
    totalReserves  = 0          totalReserves  = 0
    borrowIndex    = 1e18       borrowIndex    = 1e18
    exchangeRate   = 0.02e18    exchangeRate   = 0.02e18

  초깃값 비교:
    borrowIndex = 1e18 (= 1.0 Mantissa)
      → 수학적 필연. "누적 이자 배수"를 나타내므로 1.0(곱셈의 항등원)에서 시작
      → 이자가 쌓이면: 1.0 → 1.05(+5%) → 1.10(+10%) ...
      → 대출자 빚 = principal × (현재index / 대출시점index)
      → Aave도 동일: liquidityIndex = 1e27 (= 1.0 in Ray)

    exchangeRate = 0.02e18
      → UX 선택. 수학적 근거 없음. 0보다 크면 아무 값이나 가능
      → 0.02 = 1/50 → 1 underlying = 50 cToken (숫자 크게 보이는 효과)
      → 상세: compound-v2-code-reading.md "initialExchangeRateMantissa" 섹션
    accrualBlock   = 0          accrualBlock   = 0

  Comptroller:
    markets[cETH].collateralFactor  = 0.75  (75%)
    markets[cUSDC].collateralFactor = 0.85  (85%)
    oracle: ETH=$2,000, USDC=$1.00
```

---

## Phase 2: 예치 / Deposits (Block 1)

```
Block 1: Alice가 10 ETH 예치, Bob이 20,000 USDC 예치

═══ Alice: 10 ETH 예치 (cETH.mint{value: 10 ETH}()) ═══

  1. accrueInterest() 호출
     → accrualBlock(0) != currentBlock(1) → 계산 시작
     → totalBorrows = 0 → 이자 없음 → borrowIndex 그대로
     → accrualBlock = 1

  2. getCashPrior() = address(this).balance - msg.value
     = 10 ETH - 10 ETH = 0 ETH (이전 잔고)

  3. exchangeRate = initialExchangeRateMantissa = 0.02e18
     (totalSupply가 0이니까 초기값 사용)

  4. mintTokens = 10 ETH / 0.02 = 500 cETH

  5. 상태 변경:
     totalSupply = 500 cETH
     accountTokens[Alice] = 500 cETH
     컨트랙트 ETH 잔고 = 10 ETH

═══ Bob: 20,000 USDC 예치 (cUSDC.mint(20000e6)) ═══

  1. accrueInterest() → 이자 없음 (대출 없으니까)
  2. getCashPrior() = USDC.balanceOf(cUSDC) = 0 (이전 잔고)
  3. exchangeRate = 0.02e18 (초기값)
  4. mintTokens = 20,000 / 0.02 = 1,000,000 cUSDC
  5. 상태 변경:
     totalSupply = 1,000,000 cUSDC
     accountTokens[Bob] = 1,000,000 cUSDC
     USDC 잔고 = 20,000 USDC
```

```
Block 1 이후 상태:

  cETH:                         cUSDC:
    totalSupply   = 500           totalSupply   = 1,000,000
    totalBorrows  = 0             totalBorrows  = 0
    totalReserves = 0             totalReserves = 0
    borrowIndex   = 1e18          borrowIndex   = 1e18
    cash          = 10 ETH        cash          = 20,000 USDC
    exchangeRate  = 0.02          exchangeRate  = 0.02
    accrualBlock  = 1             accrualBlock  = 1
```

---

## Phase 3: 대출 / Borrow (Block 2)

```
Block 2: Alice가 ETH 담보로 10,000 USDC 대출

═══ Alice: Comptroller.enterMarkets([cETH]) ═══
  → Alice의 cETH를 담보로 등록

═══ Alice: cUSDC.borrow(10000e6) ═══

  1. accrueInterest() on cUSDC
     → 대출 없음 → 이자 없음 → accrualBlock = 2

  2. Comptroller.borrowAllowed(cUSDC, Alice, 10000e6) 호출

     getHypotheticalAccountLiquidityInternal(Alice, cUSDC, 0, 10000e6):

     ── cETH 시장 순회 ──
       cTokenBalance = 500 cETH
       exchangeRate  = 0.02e18
       oraclePrice   = $2,000
       collateralFactor = 0.75

       담보 가치 = 500 × 0.02 × $2,000 × 0.75 = $15,000
       sumCollateral = $15,000

     ── cUSDC 시장 순회 ──
       borrowBalance = 0 (아직 안 빌림)
       oraclePrice = $1.00

       기존 부채 = 0 × $1.00 = $0

       "만약" 효과: borrowAmount = 10,000
       sumBorrowPlusEffects = $0 + $1.00 × 10,000 = $10,000

     ── 판정 ──
       sumCollateral($15,000) > sumBorrowPlusEffects($10,000)
       → liquidity = $5,000, shortfall = $0
       → 통과! ✓

  3. borrowFresh() 실행:
     accountBorrows[Alice].principal = 10,000 USDC
     accountBorrows[Alice].interestIndex = 1e18  (현재 borrowIndex)
     totalBorrows = 10,000 USDC

  4. USDC 전송: cUSDC → Alice에게 10,000 USDC
```

```
Block 2 이후 상태:

  cETH:                         cUSDC:
    totalSupply   = 500           totalSupply   = 1,000,000
    totalBorrows  = 0             totalBorrows  = 10,000
    totalReserves = 0             totalReserves = 0
    borrowIndex   = 1e18          borrowIndex   = 1e18
    cash          = 10 ETH        cash          = 10,000 USDC  ← 20K - 10K
    exchangeRate  = 0.02          accrualBlock  = 2
    accrualBlock  = 1

  Alice:
    cETH: 500 cETH (담보)
    USDC 대출: 10,000 USDC (interestIndex = 1e18)
    지갑: 10,000 USDC

  USDC 풀 Utilization:
    U = totalBorrows / (cash + totalBorrows)
      = 10,000 / (10,000 + 10,000) = 50%
```

---

## Phase 4: 10블록 경과 — 이자 계산 / Interest Accrual (Block 12)

```
Block 12: 아무나 cUSDC에 트랜잭션을 보내면 accrueInterest() 실행
          (예: Bob이 잔고 확인, 또는 새 사용자가 예치)

═══ cUSDC.accrueInterest() 실행 (Block 12) ═══

  Step 1: 경과 블록 수
    blockDelta = 12 - 2 = 10 블록

  Step 2: 현재 상태 읽기
    cashPrior     = 10,000 USDC
    borrowsPrior  = 10,000 USDC
    reservesPrior = 0
    borrowIndexPrior = 1e18

  Step 3: 이자율 계산 (Jump Rate Model)
    utilization = 10,000 / (10,000 + 10,000) = 50% = 0.5e18

    50% ≤ kink(80%) → 완만한 구간

    borrowRatePerBlock = baseRatePerBlock + (util × multiplierPerBlock / 1e18)
                       = 9,512,937,595 + (0.5e18 × 47,564,687,975 / 1e18)
                       = 9,512,937,595 + 23,782,343,987
                       = 33,295,281,582

    연이율로 환산:
      APR = 33,295,281,582 × 2,102,400 / 1e18 ≈ 7.0%
      (= baseRate 2% + util 50% × multiplier 10% = 2% + 5% = 7%) ✓

  Step 4: 이자 누적 계산
    simpleInterestFactor = borrowRatePerBlock × blockDelta
                         = 33,295,281,582 × 10
                         = 332,952,815,820

    interestAccumulated = simpleInterestFactor × borrowsPrior / 1e18
                        = 332,952,815,820 × 10,000e6 / 1e18
                        ≈ 3,329 (약 0.003329 USDC)

    → 10블록 동안 이자 = ~0.003329 USDC
    → 연간으로 보면: 10,000 × 7% = 700 USDC/년
    → 블록당: 700 / 2,102,400 ≈ 0.000333 USDC/블록
    → 10블록: 0.00333 USDC ✓

  Step 5: 새 상태 계산
    totalBorrowsNew  = 10,000 + 0.003329 = 10,000.003329 USDC
    totalReservesNew = 0 + (0.003329 × 10%) = 0.000333 USDC  ← RF 10%
    borrowIndexNew   = 1e18 × (1 + 332,952,815,820 / 1e18)
                     = 1.000000332952815820e18

  Step 6: SSTORE (4개 전역 변수만 업데이트!)
    accrualBlockNumber = 12
    borrowIndex        = 1.000000332952815820e18
    totalBorrows       = 10,000.003329 USDC
    totalReserves      = 0.000333 USDC
```

### Step 3~5 실제 코드와 함께 상세 계산

> 위 요약만으로 헷갈릴 수 있으니, 실제 Compound 코드 한 줄씩 매핑하며 재계산.

**Step 3 상세: utilizationRate() + getBorrowRateInternal()**

```
실제 코드 (BaseJumpRateModelV2.sol):
┌──────────────────────────────────────────────────────────────┐
│ function utilizationRate(                                    │
│     uint cash, uint borrows, uint reserves                   │
│ ) public pure returns (uint) {                               │
│     if (borrows == 0) return 0;                              │
│     return borrows * BASE / (cash + borrows - reserves);     │
│ }                                                            │
└──────────────────────────────────────────────────────────────┘

숫자 대입:
  cash = 10,000 USDC, borrows = 10,000 USDC, reserves = 0

  utilization = 10,000 × 1e18 / (10,000 + 10,000 - 0)
              = 10,000e18 / 20,000
              = 0.5e18  (= 50%)
```

```
실제 코드 (BaseJumpRateModelV2.sol):
┌──────────────────────────────────────────────────────────────┐
│ function getBorrowRateInternal(                              │
│     uint cash, uint borrows, uint reserves                   │
│ ) internal view returns (uint) {                             │
│     uint util = utilizationRate(cash, borrows, reserves);    │
│                                                              │
│     if (util <= kink) {                                      │ ← 50% ≤ 80%? YES!
│         return (util * multiplierPerBlock / BASE)            │
│                + baseRatePerBlock;                            │
│     } else {                                                 │
│         // kink 초과 구간 (이번엔 여기 안 옴)                  │
│         uint normalRate = (kink * multiplierPerBlock / BASE) │
│                          + baseRatePerBlock;                  │
│         uint excessUtil = util - kink;                        │
│         return (excessUtil * jumpMultiplierPerBlock / BASE)   │
│                + normalRate;                                  │
│     }                                                        │
│ }                                                            │
└──────────────────────────────────────────────────────────────┘

배포 시 파라미터 (연이율 → 블록당 변환):
  baseRatePerBlock       = 0.02e18  / 2,102,400 = 9,512,937,595
  multiplierPerBlock     = 0.10e18  / 2,102,400 = 47,564,687,975
  jumpMultiplierPerBlock = 3.00e18  / 2,102,400 = 1,426,940,639,269
  kink = 0.80e18

util(50%) ≤ kink(80%) → if 분기 진입 (완만한 구간):

  borrowRatePerBlock = (util × multiplierPerBlock / BASE) + baseRatePerBlock
                     = (0.5e18 × 47,564,687,975 / 1e18) + 9,512,937,595
                       ─────────────────────────────────
                       = 23,782,343,987                   ← util × 기울기
                     = 23,782,343,987 + 9,512,937,595
                     = 33,295,281,582                     ← 블록당 대출 이자율

  검증 (연이율):
    APR = 33,295,281,582 × 2,102,400 / 1e18 ≈ 0.07 = 7%
    수식: baseRate + util × multiplier = 2% + 50% × 10% = 2% + 5% = 7% ✓

  [참고] 만약 util이 90%였다면? (kink 초과):
    normalRate = (0.8e18 × multiplierPerBlock / 1e18) + baseRatePerBlock
               = kink까지의 이자율 = 10% (연이율)
    excessUtil = 0.9e18 - 0.8e18 = 0.1e18 (10%)
    borrowRate = (0.1e18 × jumpMultiplierPerBlock / 1e18) + normalRate
               = 30% + 10% = 40% (연이율)  ← 급등!
```

**Step 4 상세: accrueInterest() — 이자 누적**

```
실제 코드 (CToken.sol):
┌──────────────────────────────────────────────────────────────┐
│ uint blockDelta = currentBlockNumber - accrualBlockNumberPrior;│
│                                                              │
│ simpleInterestFactor = borrowRate × blockDelta               │
│ interestAccumulated  = simpleInterestFactor × totalBorrows   │
│ totalBorrowsNew      = totalBorrows + interestAccumulated    │
│ totalReservesNew     = reserves + interestAccumulated × RF   │
│ borrowIndexNew       = borrowIndex × (1 + simpleInterestFactor)│
└──────────────────────────────────────────────────────────────┘

숫자 대입:
  blockDelta         = 12 - 2 = 10 블록
  borrowRatePerBlock = 33,295,281,582  (Step 3에서 계산)
  borrowsPrior       = 10,000e6 = 10,000,000,000  (USDC는 decimals=6)
  borrowIndexPrior   = 1e18
  reserveFactor      = 0.1e18  (10%)

  ① simpleInterestFactor = borrowRatePerBlock × blockDelta
                          = 33,295,281,582 × 10
                          = 332,952,815,820
                          (= 0.00000033295... → 10블록 동안의 이자율)

  ② interestAccumulated = simpleInterestFactor × borrowsPrior / 1e18
                         = 332,952,815,820 × 10,000,000,000 / 1e18
                         = 3,329,528,158,200,000,000,000 / 1e18
                         = 3,329  (USDC 최소 단위)
                         = 3,329 / 1e6 = 0.003329 USDC

     검증:
       연이자 = 10,000 × 7% = 700 USDC
       블록당 = 700 / 2,102,400 = 0.000333 USDC
       10블록 = 0.00333 USDC ≈ 0.003329 USDC ✓
       (미세한 차이는 정수 나눗셈 반올림 때문)
```

**Step 5 상세: SSTORE 4개 업데이트**

```
실제 코드 (CToken.sol):
┌──────────────────────────────────────────────────────────────┐
│ accrualBlockNumber = currentBlockNumber;                     │ ← SSTORE ①
│ borrowIndex = borrowIndexNew;                                │ ← SSTORE ②
│ totalBorrows = totalBorrowsNew;                              │ ← SSTORE ③
│ totalReserves = totalReservesNew;                            │ ← SSTORE ④
└──────────────────────────────────────────────────────────────┘

숫자 대입:
  ① accrualBlockNumber = 12

  ② borrowIndexNew = borrowIndexPrior × (1e18 + simpleInterestFactor) / 1e18
                    = 1e18 × (1e18 + 332,952,815,820) / 1e18
                    = 1e18 × 1,000,000,332,952,815,820 / 1e18
                    = 1,000,000,332,952,815,820  (= 1.00000033295...)

  ③ totalBorrowsNew = borrowsPrior + interestAccumulated
                    = 10,000,000,000 + 3,329
                    = 10,000,003,329  (= 10,000.003329 USDC)

  ④ totalReservesNew = reservesPrior + (interestAccumulated × reserveFactor / 1e18)
                     = 0 + (3,329 × 0.1e18 / 1e18)
                     = 0 + 332
                     = 332  (= 0.000332 USDC)

  → SSTORE 4번 = 가스비 ~20,000 gas
  → 이걸로 모든 대출자의 이자가 한 번에 반영됨!
```

```
Block 12 이후 상태:

  cUSDC:
    totalSupply   = 1,000,000
    totalBorrows  = 10,000.003329 USDC  ← 이자 누적!
    totalReserves = 0.000333 USDC       ← 프로토콜 금고
    borrowIndex   = 1.000000332952...e18
    cash          = 10,000 USDC         ← 현금은 안 변함 (아직 안 갚았으니까)
    accrualBlock  = 12

  돈의 흐름 (10블록 동안):
    Alice(대출자) 이자 발생: +0.003329 USDC (totalBorrows에 반영)
    프로토콜 금고:          +0.000333 USDC (RF 10%)
    예치자들(Bob)에게:      +0.002996 USDC (나머지 90%)
```

---

## Phase 5: 각 참여자의 현재 가치 / Current Values

### Alice의 대출 잔고 (borrowBalanceStored)

```
Alice의 대출 잔고 계산:

  borrowBalanceStoredInternal(Alice):
    principal = 10,000 USDC (대출 시 기록)
    interestIndex = 1e18 (대출 시점의 borrowIndex)

    현재 빚 = principal × (현재 borrowIndex / 대출시점 interestIndex)
           = 10,000 × (1.000000332952e18 / 1e18)
           = 10,000 × 1.000000332952
           = 10,000.003329 USDC

  → Alice는 10블록 동안 0.003329 USDC의 이자가 붙었음
  → 하지만 Alice의 accountBorrows.principal은 안 바뀜! (10,000 그대로)
  → borrowIndex 비율로 계산만 함 (= scaled balance 패턴!)
```

### Bob의 예치 가치 (balanceOfUnderlying)

```
Bob의 예치 가치 계산:

  exchangeRateStoredInternal():
    totalCash    = 10,000 USDC
    totalBorrows = 10,000.003329 USDC
    totalReserves= 0.000333 USDC
    totalSupply  = 1,000,000 cUSDC

    exchangeRate = (10,000 + 10,000.003329 - 0.000333) / 1,000,000
                 = 20,000.002996 / 1,000,000
                 = 0.020000002996

  Bob의 실제 가치:
    balanceOfUnderlying = accountTokens[Bob] × exchangeRate
                        = 1,000,000 × 0.020000002996
                        = 20,000.002996 USDC

  → Bob은 20,000 USDC 예치했는데 지금 20,000.002996 USDC
  → 0.002996 USDC 이자를 받은 것 (Alice 이자의 90%)
  → cUSDC 수량(1,000,000)은 그대로, exchangeRate가 올랐을 뿐!
```

### 이자 분배 검증

```
Alice가 낸 이자:    0.003329 USDC (100%)
  ├── 프로토콜 금고: 0.000333 USDC ( 10% = Reserve Factor)
  └── Bob에게:      0.002996 USDC ( 90%)

Supply APY 검증:
  = Borrow APR × Utilization × (1 - RF)
  = 7% × 50% × 90%
  = 3.15%

  Bob의 실제 수익률:
  = 0.002996 / 20,000 × (2,102,400 / 10)  ← 10블록을 연간으로 환산
  ≈ 3.15% ✓
```

### totalBorrows와 totalReserves를 분리 저장하는 이유

```
exchangeRate = (cash + totalBorrows - totalReserves) / totalSupply

"어차피 뺄 거면 totalBorrows에 미리 빼서 저장하면 되지 않나?"
→ 안 된다. 둘은 서로 다른 것을 추적하기 때문.

  totalBorrows  = 대출자들이 갚아야 할 총 빚 (이자 포함 전체)
  totalReserves = 그 빚 중에서 프로토콜 몫 (예치자에게 안 줌)
```

```
totalBorrows가 "전체 금액 그대로"여야 하는 이유:

  ① 대출자 빚 계산에 사용됨
     Alice의 빚 = principal × (현재 borrowIndex / 대출시점 borrowIndex)
     → borrowIndex는 totalBorrows 기반으로 계산됨
     → reserve를 빼면 Alice 빚이 실제(0.003329)보다 적게(0.002997) 나옴

  ② utilization 계산에 사용됨
     U = totalBorrows / (cash + totalBorrows - reserves)
     → 줄여버리면 utilization이 달라짐 → 이자율 계산 오류

  ③ HF 계산에 사용됨 (부채 가치 = borrowBalance × oraclePrice)
     → 줄여버리면 HF가 높게 나옴 → 청산이 늦어짐 → 프로토콜 손실
```

```
totalReserves가 별도로 필요한 이유:

  ① 거버넌스의 _reduceReserves()로 프로토콜 수익 인출 시
     → 별도 추적하지 않으면 "얼마나 쌓였는지" 모름

  ② 감사/투명성: "프로토콜이 얼마 벌었는지" 별도 조회 가능

  → 회계 원칙: "원본 데이터는 가공하지 않고, 파생값은 계산으로 구한다"
  → SSTORE 1개 ($2.70) 추가하는 게 데이터 무결성 훼손보다 저렴
```

---

## Phase 6: 가격 하락 → 청산 / Price Drop → Liquidation (Block 20)

```
Block 15: ETH 가격이 $2,000 → $1,200로 하락 (40% 폭락)
          → Oracle이 새 가격 반영

Block 20: 청산 봇 Charlie가 발견

═══ Alice의 Health Factor 확인 ═══

  봇이 Comptroller.getAccountLiquidity(Alice) 호출:

    cETH 시장:
      cTokenBalance = 500 cETH
      exchangeRate  = 0.02 (cETH는 대출 없어서 변동 없음)
      oraclePrice   = $1,200  ← 하락!
      collateralFactor = 0.75

      담보 가치 = 500 × 0.02 × $1,200 × 0.75 = $9,000

    cUSDC 시장:
      borrowBalance ≈ 10,000.01 USDC (20블록치 이자 포함)
      oraclePrice = $1.00

      부채 가치 = 10,000.01 × $1.00 = $10,000.01

    판정:
      sumCollateral($9,000) < sumBorrowPlusEffects($10,000.01)
      → shortfall = $1,000.01
      → 청산 가능! (HF < 1)

═══ Charlie가 청산 실행 ═══

  Charlie → cUSDC.liquidateBorrow(Alice, 5000e6, cETH)
            "Alice의 USDC 대출 중 5,000을 대신 갚고, cETH를 받겠다"

  1. Comptroller.liquidateBorrowAllowed() 체크:
     → shortfall > 0 ✓
     → repayAmount(5,000) ≤ maxClose(10,000 × 50% = 5,000) ✓

  2. repayBorrowFresh(): Charlie가 5,000 USDC를 cUSDC에 전송
     → Alice의 대출: 10,000 → 5,000 USDC

  3. liquidateCalculateSeizeTokens():
     seizeAmount = repayAmount × liquidationIncentive / exchangeRate × priceRatio
     = 5,000 × 1.08 / 0.02 / $1,200 × $1.00
     = 5,400 / $24 = 225 cETH

     → Charlie가 Alice의 cETH 225개를 가져감
     → 225 cETH × 0.02 = 4.5 ETH × $1,200 = $5,400
     → $5,000 갚고 $400 이득 (8% 보너스)

  4. 청산 후 Alice 상태:
     cETH: 500 - 225 = 275 cETH (= 5.5 ETH = $6,600 at $1,200)
     대출: ~5,000 USDC
     새 HF: ($6,600 × 0.75) / $5,000 = $4,950 / $5,000 = 0.99
     → 아직 약간 위험! (추가 청산 가능)
```

---

## 전체 타임라인 요약

```
Block 0:  컨트랙트 배포 (JumpRate, Oracle, Comptroller, cETH, cUSDC)
Block 1:  Alice 10 ETH 예치 → 500 cETH
          Bob 20,000 USDC 예치 → 1,000,000 cUSDC
Block 2:  Alice 10,000 USDC 대출 (Utilization = 50%)
          → Borrow APR = 7%, Supply APY = 3.15%
Block 3-11: (아무 행동 없음, 이자는 다음 tx 때 한꺼번에 계산)
Block 12: 누군가 cUSDC 트랜잭션 → accrueInterest() 실행
          → 10블록치 이자 누적: 0.003329 USDC
          → 프로토콜: 0.000333, Bob: 0.002996
Block 15: ETH 가격 $2,000 → $1,200 (오라클 업데이트)
Block 20: Charlie가 Alice 청산
          → 5,000 USDC 대납, 225 cETH(=$5,400) 획득
          → $400 이득 (8% 보너스)
```

---

## Kink이란? — Jump Rate Model의 핵심

```
Kink = "꺾이는 지점" (직역: 꼬임, 굽힘)

이자율 그래프에서 기울기가 급격히 변하는 분기점.

  이자율
  │
  │                          ╱ ← jumpMultiplier (급경사, 300%)
  │                        ╱
  │                      ╱
  │                    ╱
  │────────────────╱──── ← 여기가 kink (80%)
  │              ╱
  │           ╱  ← multiplier (완만한 경사, 10%)
  │        ╱
  │     ╱
  │  ╱
  │╱ ← baseRate (2%)
  └──────────────────────────────── 사용률(Utilization)
  0%                80%           100%
                     ↑
                   kink

kink 이하: "정상 상태" — 이자율 완만하게 올라감 (빌려도 괜찮음)
kink 초과: "긴급 상태" — 이자율 급등 (빨리 갚아! 유동성이 부족해!)
```

```
왜 이런 구조가 필요한가?

  풀의 돈이 80% 이상 빌려나가면 → 남은 유동성 20% 이하
  → 예치자가 인출하고 싶어도 돈이 없을 수 있음 (bank run 위험)
  → 이자율을 확 올려서:
    ① 대출자가 빨리 갚도록 유인
    ② 높은 이자율이 새 예치자를 끌어들임

  "정상 = 완만" + "위험 = 급등" = Jump Rate Model
  kink = 이 두 구간을 나누는 경계선
```

---

## Jump Rate Model 이자율 변화 시뮬레이션

```
같은 풀에서 Utilization만 바뀌면 이자율이 어떻게 변하는지:

파라미터: baseRate=2%, multiplier=10%, jumpMultiplier=300%, kink=80%

┌──────────┬──────────────────────────────────┬───────────┬──────────┐
│ 사용률    │ 계산                              │ Borrow APR│ Supply APY│
├──────────┼──────────────────────────────────┼───────────┼──────────┤
│ 0%       │ 2% + 0% × 10%                   │ 2.0%      │ 0.0%     │
│ 20%      │ 2% + 20% × 10%                  │ 4.0%      │ 0.72%    │
│ 40%      │ 2% + 40% × 10%                  │ 6.0%      │ 2.16%    │
│ 50%      │ 2% + 50% × 10% ← Alice의 상황    │ 7.0%      │ 3.15%    │
│ 60%      │ 2% + 60% × 10%                  │ 8.0%      │ 4.32%    │
│ 80%      │ 2% + 80% × 10% = kink!          │ 10.0%     │ 7.20%    │
│ ─────────│── kink 초과: jumpMultiplier 발동 ─│───────────│──────────│
│ 85%      │ 10% + 5% × 300%                 │ 25.0%     │ 19.13%   │
│ 90%      │ 10% + 10% × 300%                │ 40.0%     │ 32.40%   │
│ 95%      │ 10% + 15% × 300%                │ 55.0%     │ 47.03%   │
│ 100%     │ 10% + 20% × 300%                │ 70.0%     │ 63.00%   │
└──────────┴──────────────────────────────────┴───────────┴──────────┘

Supply APY = Borrow APR × Utilization × (1 - RF)
           = Borrow APR × U × 0.9

80% → 85%: 불과 5%p 증가인데 이자율 10% → 25%로 2.5배 급등!
→ 이게 "Jump" Rate의 핵심: kink 초과 시 급격한 이자율로 유동성 복귀 유도
```

---

## 핵심 포인트 정리

```
① 이자는 "다음 tx가 올 때" 한꺼번에 계산 (lazy evaluation)
   → Block 3~11 동안 아무것도 안 일어남
   → Block 12에서 10블록치를 한 번에 계산
   → 가스비 절약 (매 블록마다 계산하면 너무 비쌈)

② exchangeRate가 이자를 반영하는 메커니즘:
   이자 → totalBorrows 증가 → exchangeRate 상승 → cToken 가치 상승
   예치자(Bob)는 아무것도 안 해도 cToken 가치가 올라감

③ 오라클은 별도 컨트랙트:
   CToken 안에는 가격 조회 없음
   Comptroller만 필요할 때 oracle.getUnderlyingPrice() 호출
   청산은 외부 봇이 가격 모니터링 → liquidateBorrow() 호출하는 구조

④ 청산은 "유인 구조":
   프로토콜이 자동 청산하는 게 아님
   청산 봇에게 8% 보너스를 줘서 청산하도록 유인
   → 봇 운영이 DevOps 엔지니어의 업무 중 하나!
```
