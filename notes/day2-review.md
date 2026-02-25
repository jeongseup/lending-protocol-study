# Day 2 Review — 오늘 배운 것 정리

> 2026-02-24 (월) 학습 리뷰

---

## 완료한 항목 / Completed

- [x] Compound V2 심화 학습 마무리 (Day 1에서 이어짐)
- [x] JumpRateModel 구현 및 테스트 — 18개 단위 + 6개 퍼즈 테스트 통과
- [x] Alberto Cuesta 아티클 읽기 → lending-protocol-types.md 작성
- [x] Compound V2 vs Aave V3 vs Euler 비교 → pool-lending-comparison.md 작성
- [x] Aave V3 코드 분석 (aave-v3-origin 기반) → aave-v3-code-reading.md 문서화
- [x] LendingPool.sol 스토리지를 Aave V3 PoolStorage 패턴으로 리팩토링
- [x] defi-lending-protocol-guide.md — Stable Rate 삭제 반영 업데이트

---

## 1. Compound V2 심화 — Day 1에서 이어진 부분

### CToken 상속 구조와 "Fresh" 패턴

```
CTokenInterface (abstract) ← 스토리지
    ↓
CToken (abstract) ← 핵심 로직 (mint/borrow/accrueInterest)
    ├── CErc20 ← ERC20 시장 (cUSDC, cDAI)
    └── CEther ← ETH 시장 (cETH)

getCashPrior()가 abstract: 자산 타입에 따라 잔고 조회 방식이 다름
  CErc20: EIP20.balanceOf(address(this))
  CEther: address(this).balance - msg.value
```

```
"Fresh" 패턴: 모든 함수가 "이자 최신화 → 검증 → 실행" 3단계

  mint() → mintInternal(accrueInterest 먼저!) → mintFresh(실제 로직)

  mintFresh() 첫 줄:
    if (accrualBlockNumber != getBlockNumber()) revert MintFreshnessCheck();
    → "이자가 최신(fresh)이 아니면 거부!"

  오라클 때문이 아니라 borrowIndex/exchangeRate가 stale하면 회계가 틀어짐
```

### 배포 구조와 크로스 마켓 흐름

```
Compound V2: 토큰별 독립 CToken 배포 + Comptroller 1개가 전체 묶음

  cUSDC ──┐
  cDAI  ──┤
  cWBTC ──┼──→ Comptroller (1개) ──→ PriceOracle
  cETH  ──┘      ├── enterMarkets() 담보 활성화
                  ├── borrowAllowed() HF 체크 (모든 시장 순회!)
                  └── liquidateBorrowAllowed() 청산 허가

ETH 담보로 USDC 대출 흐름:
  1. cETH.mint{value: 1 ETH}()             ← cETH 컨트랙트
  2. Comptroller.enterMarkets([cETH])       ← 담보 등록 (별도 tx!)
  3. cUSDC.borrow(1000e6)                   ← cUSDC 컨트랙트
     → cUSDC가 Comptroller에 물어봄 → 모든 시장 HF 계산 → 통과 시 USDC 전송
```

### Mantissa — Solidity 소수점 처리

```
Solidity는 float 없음 → 10^18 곱해서 정수로 저장 = "Mantissa"

  5% = 0.05 → 0.05 × 10^18 = 50,000,000,000,000,000
  exchangeRate 0.02 = 0.02e18 → 1 underlying = 50 cToken

  Mantissa 곱셈: result = a × b / 1e18 (스케일 보정)

  블록당 이자율 → 연이율: APR = borrowRatePerBlock × blocksPerYear / 1e18
  봇/대시보드 주의: Mantissa를 10^18로 나눠야 실제 값!
```

### accrueInterest() — 핵심 이자 누적 함수

```
모든 함수 전에 자동 실행. SSTORE 4번으로 전체 이자 정산:

  simpleInterestFactor = borrowRate × blockDelta
  interestAccumulated  = simpleInterestFactor × totalBorrows
  totalBorrowsNew      = totalBorrows + interestAccumulated
  totalReservesNew     = reserves + interestAccumulated × RF
  borrowIndexNew       = borrowIndex × (1 + simpleInterestFactor)

  → borrowIndex가 Aave의 liquidityIndex와 같은 역할 (scaled balance 패턴)
  → 전역 인덱스 1개만 업데이트하면 모든 대출자의 이자 반영
```

### Comptroller의 HF 계산 — getHypotheticalAccountLiquidityInternal()

```
"만약 이 사용자가 X만큼 빌리면 건전한가?" 시뮬레이션

  사용자의 모든 시장을 순회:
    sumCollateral += cTokenBalance × exchangeRate × oraclePrice × collateralFactor
    sumBorrowPlusEffects += borrowBalance × oraclePrice

  sumCollateral > sumBorrow → liquidity (여유)  = HF > 1
  sumBorrow > sumCollateral → shortfall (부족)  = HF < 1

  Compound는 HF 숫자 대신 liquidity/shortfall로 표현
```

### 오라클/청산 아키텍처

```
CToken 안에 가격 조회 없음. Comptroller만 oracle.getUnderlyingPrice() 호출.

청산 = 프로토콜이 자동 실행하는 게 아님. 외부 봇에 인센티브(8% 보너스)로 유인.

  ① 오라클이 가격 업데이트
  ② 봇이 getAccountLiquidity() 주기적 호출 → shortfall > 0 발견
  ③ 봇이 cToken.liquidateBorrow() 호출
  ④ 8% 보너스 획득
```

> 상세: [compound-v2-code-reading.md](deep-dive/compound-v2-code-reading.md), [compound-v2-scenario.md](deep-dive/compound-v2-scenario.md)

---

## 2. Compound V2 시나리오 시뮬레이션 — 숫자로 추적

### 전체 타임라인

```
Block 0:  배포 (JumpRate, Oracle, Comptroller, cETH, cUSDC)
          borrowIndex = 1e18 (곱셈의 항등원), exchangeRate = 0.02e18 (UX 선택)
Block 1:  Alice 10 ETH 예치 → 500 cETH (10/0.02)
          Bob 20,000 USDC 예치 → 1,000,000 cUSDC
Block 2:  Alice 10,000 USDC 대출 (U=50%, Borrow APR=7%)
Block 12: accrueInterest() → 10블록치 이자 0.003329 USDC 누적
Block 15: ETH $2,000 → $1,200 폭락
Block 20: Charlie가 Alice 청산 (5,000 USDC 대납, 225 cETH=$5,400 획득, $400 이득)
```

### 이자 계산 상세 (Block 12)

```
Step 1: 이자율 = baseRate + util × multiplier = 2% + 50%×10% = 7%
Step 2: borrowRatePerBlock = 33,295,281,582
Step 3: interestAccumulated = 33,295,281,582 × 10 × 10,000e6 / 1e18 = 3,329 (≈0.003329 USDC)
Step 4: SSTORE 4개 업데이트 (가스 ~20,000)

이자 분배:
  Alice가 낸 이자: 0.003329 USDC (100%)
  ├── 프로토콜 금고: 0.000333 USDC (RF 10%)
  └── Bob에게:      0.002996 USDC (90%)

검증: Supply APY = Borrow APR × U × (1-RF) = 7% × 50% × 90% = 3.15% ✓
```

### totalBorrows/totalReserves 분리 저장 이유

```
"어차피 뺄 거면 미리 빼서 저장하면?" → 안 됨.

  totalBorrows = 대출자의 총 빚 (이자 포함 전체) — borrowIndex 계산에 사용
  totalReserves = 프로토콜 몫 — 거버넌스의 _reduceReserves()로 인출 시 추적용

  줄여버리면: borrowIndex 틀어짐 → Alice 빚 과소 계산
             utilization 틀어짐 → 이자율 오류
             HF 틀어짐 → 청산 지연 → 프로토콜 손실

  → 회계 원칙: "원본 데이터는 가공하지 않고, 파생값은 계산으로 구한다"
```

> 상세: [compound-v2-scenario.md](deep-dive/compound-v2-scenario.md) — 배포~이자~청산 전체 숫자 추적

---

## 3. 렌딩 프로토콜 유형 3가지 — "돈을 어디서 가져오는가?"

```
이 한 가지 질문이 세 유형을 나눈다:

  Pool-based (Compound, Aave, Euler):
    → 다른 사용자가 예치한 돈을 빌림
    → 이자율 = f(사용률), 알고리즘 결정
    → 비유: 은행

  CDP-based (MakerDAO):
    → 프로토콜이 새로운 돈(DAI)을 찍어냄
    → 이자율 = Stability Fee, 거버넌스 결정
    → 비유: 중앙은행

  Fixed-rate (Yield Protocol):
    → fyToken(미래 가치 토큰)을 할인 발행
    → 이자율 = fyToken 할인율, 시장 결정
    → 비유: 채권 시장
```

```
종합 비교:
            Pool-based       CDP             Fixed-rate
빌리는 것    기존 토큰         새로 발행한 DAI    fyToken (할인)
이자율       변동 (사용률)     반고정 (거버넌스)   고정 (발행시 확정)
만기일       없음             없음              있음!
예치자 필요   필수             불필요            불필요
유동성 위험   있음 (bank run)  없음 (민팅)       없음
대표         Compound, Aave   MakerDAO, Liquity Yield, Notional
```

### 아키텍처 진화 흐름

```
MakerDAO (2017) "안전 최우선"
  ├─→ Compound V2 (2019) "cToken으로 조합성!" (예치 토큰화)
  ├─→ Aave V2 (2020) "부채도 토큰화 + Flash Loan"
  ├─→ Yield V2 (2021) "MakerDAO 구조 + 고정금리 (fyToken)"
  ├─→ Euler (2022) "단일 스토리지 + Diamond 패턴 (가스 극소화)"
  └─→ Compound V3 (2022) "다시 단순하게" (방향 반전: 안전성 재우선)
```

### DevOps 관점 차이

```
Pool-based:  사용률/HF 모니터링, bank run 감지, 청산 봇 운영
CDP-based:   Stability Fee 거버넌스 추적, DAI peg 모니터링, 경매 Keeper 봇
Fixed-rate:  만기일 관리, fyToken 내재금리 계산, 롤오버 이벤트 추적
```

> 상세: [lending-protocol-types.md](deep-dive/lending-protocol-types.md)

---

## 4. Compound V2 vs Aave V3 vs Euler — 동일 시나리오 비교

### 아키텍처 한눈에 보기

```
Compound V2: 시장별 독립 CToken + Comptroller (문지기)
  → User → cETH/cUSDC(각각) → Comptroller → Oracle
  → CToken이 자산보관 + 회계 + 로직 전부 담당 ("뚱뚱")
  → 새 시장 = 새 CToken 배포

Aave V3: 단일 Pool + Library delegatecall
  → User → Pool.sol(유일한 진입점) → SupplyLogic/BorrowLogic(library)
  → Pool은 "얇은 라우터", 로직은 Library에, 자산은 aToken에
  → 새 시장 = Pool 설정 변경만

Euler: 단일 Storage + 모듈 프록시 (Diamond-like)
  → User → eToken/dToken(프록시) → Storage(단일 상태)
  → 모든 데이터 한 컨트랙트, 모듈은 view → 가스 최소
```

### 핵심 차이점 (동일 시나리오: Alice 10 ETH 예치, Bob 3,000 USDC 대출)

```
예치:
  Compound: cETH.mint{value: 10 ether}() → 500 cETH (비율 0.02)
  Aave:     pool.supply(WETH, 10e18, alice, 0) → 10 aWETH (1:1, rebase)
  → 수학적으로 동일: cToken=shares×exchangeRate, aToken=scaledBalance×index

담보:
  Compound: enterMarkets([cETH]) 별도 호출 필요 (2 tx)
  Aave:     supply 하면 자동 담보 활성화 (1 tx)

부채:
  Compound: accountBorrows mapping에만 기록 (토큰 아님)
  Aave:     vToken (ERC-20) 발행 → 부채도 토큰화!

이자 단위:
  Compound: 블록 기반, 단리 근사, Mantissa (10^18)
  Aave:     초 기반, 복리, Ray (10^27)
  둘 다 "lazy evaluation" — 상호작용 시에만 계산

청산:
  Compound: Close Factor 항상 50%, 보너스 8% (전체 고정)
  Aave:     HF<0.95면 100%, HF>=0.95면 50%, 보너스 자산별 다름 (5~10%+)

가스:
  Compound ~150k, Aave ~200k, Euler ~120k (Supply 기준)
  Euler이 최소 (컨트랙트간 external call 없음)
```

> 상세: [pool-lending-comparison.md](deep-dive/pool-lending-comparison.md)

---

## 5. Aave V3 코드 분석 (aave-v3-origin 기반)

### aave-v3-core → aave-v3-origin 핵심 변경 (v3.2~v3.4)

```
1. Stable Rate 완전 제거 → Variable만 남음
2. InterestRateStrategy → Pool-level immutable로 이동 (컨트랙트 1개 통합)
3. Bad Debt (Deficit) 시스템 추가 → 청산 후 남은 부채를 deficit으로 관리
4. Position Manager 추가 → DeFi 프로토콜 간 통합 (대리 조작)
5. E-Mode 비트맵 방식 변경 → priceSource 삭제, collateral/borrowable 비트맵
6. virtualUnderlyingBalance 추가 → 실제 잔고와 프로토콜 인식 잔고 분리
7. 먼지(Dust) 방지 → 청산 후 잔여 < $1,000이면 revert
8. Liquidation Grace Period → reserve별 청산 유예 기간
```

### Pool.sol — "얇은 라우터" 패턴

```
abstract contract Pool is VersionedInitializable, PoolStorage, IPool, Multicall {
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    address public immutable RESERVE_INTEREST_RATE_STRATEGY;  // v3.4: Pool 레벨!

Pool.supply() → SupplyLogic.executeSupply()   (delegatecall)
Pool.borrow() → BorrowLogic.executeBorrow()   (delegatecall)
Pool.liquidationCall() → LiquidationLogic.executeLiquidationCall()

→ Pool은 24KB 이하 유지, 실제 로직은 Library에서
→ Library는 delegatecall로 Pool의 storage를 직접 사용
```

### SupplyLogic vs 우리 deposit()

```
우리 코드:                          Aave V3:
1. _accrueInterest(asset)     →   1. reserve.cache() + updateState()
2. safeTransferFrom(→ Pool)   →   2. safeTransferFrom(→ aToken!)
3. lToken.mint(user, amount)  →   3. aToken.mint(user, scaledAmount, index)
4. totalDeposits += amount    →   4. if isFirstSupply: 자동 담보 활성화

차이:
  - Aave: 자산을 aToken 컨트랙트에 보관 (Pool 해킹되어도 자산 안전)
  - Aave: user/onBehalfOf 분리 → 대리 예치 가능
  - Aave: cache 패턴 (SLOAD 1회 → MLOAD 여러 회, 가스 700배 절약)
  - Aave: scaledBalance = amount / index (정규화)
```

### BorrowLogic vs 우리 borrow()

```
핵심 차이: 부채 토큰화

  우리: debtToken.mint(user, amount)
        → balanceOf()는 원금만 반환 (이자 미반영!)

  Aave: IVariableDebtToken.mint(user, amount, amountScaled, index)
        → scaledBalance = amount / variableBorrowIndex
        → balanceOf() = scaledBalance × index → 이자 자동 반영!

  v3.4: HF 검증이 borrow 이후에 수행됨 (순서 변경)
        Stable Rate 경로 완전 삭제
```

### LiquidationLogic — v3.4 핵심 변경

```
기존 Close Factor:  항상 50%
v3.4 Close Factor:  기본 100%, 대형 포지션($2,000+) + HF>0.95면 50%
                    + 청산 후 잔여 < $1,000이면 revert (먼지 방지)

v3.4 신규 — Bad Debt 시스템:
  청산 후 담보=0인데 부채 남으면 → 모든 부채 _burnBadDebt()로 소각
  → reserve.deficit에 기록
  → Umbrella 컨트랙트가 eliminateReserveDeficit()로 해소
  (기존: "좀비 포지션" 방치)
```

### ReserveData vs 우리 Market struct

```
Aave ReserveData:                      우리 Market → ReserveData:
  configuration (비트맵)                  collateralFactor, liquidationThreshold, isActive
  liquidityIndex + variableBorrowIndex    borrowIndex
  aTokenAddress                           lToken
  variableDebtTokenAddress                debtToken
  deficit (v3.4 신규)                     (없음)
  virtualUnderlyingBalance (v3.4)         totalDeposits
  accruedToTreasury                       totalReserves
  lastUpdateTimestamp                     lastUpdateTime
  __deprecatedStableDebtTokenAddress      (삭제됨!)
  __deprecatedInterestRateStrategyAddress (Pool immutable로 이동!)
```

> 상세: [aave-v3-code-reading.md](deep-dive/aave-v3-code-reading.md) — Pool/Supply/Borrow/Liquidation 전체 코드 비교

---

## 6. 우리 코드 리팩토링 — Aave V3 PoolStorage 적용

### Before → After

```solidity
// BEFORE (v1)
struct Market { ... }                          // 10 fields
mapping(address => Market) public markets;
address[] public assetList;
modifier marketExists(address asset) { ... }
function addMarket(...) external onlyOwner { ... }

// AFTER (Aave V3 style)
struct ReserveData { ..., uint16 id, ... }         // 11 fields (+id)
struct UserConfigurationMap { uint256 data; }       // 비트맵
mapping(address => ReserveData) public reserves;
mapping(address => UserConfigurationMap) internal _usersConfig;
mapping(uint256 => address) public reservesList;
uint16 public reservesCount;
modifier reserveActive(address asset) { ... }
function initReserve(...) external onlyOwner { ... }
```

### 비트맵 헬퍼 함수

```solidity
_isUsingAsCollateral(config, reserveId) → bool   // bit 2*id
_isBorrowing(config, reserveId) → bool           // bit 2*id+1
_setUsingAsCollateral(config, reserveId, using) → config
_setBorrowing(config, reserveId, borrowing) → config
```

### 테스트 결과

```
리팩토링 전: 61 tests passed, 0 failed, 2 skipped
리팩토링 후: 62 tests passed, 0 failed, 2 skipped  (+1 bitmap test)

  AaveForkTest             | 2 passed | 2 skipped
  InterestRateFuzzTest     | 6 passed |
  JumpRateModelTest        | 18 passed |
  LendingPoolInvariantTest | 2 passed |
  LendingPoolTest          | 15 passed |  ← +1 bitmap test
  LiquidationTest          | 6 passed |
  OracleTest               | 13 passed |
```

---

## Q&A 정리 / Questions & Answers

### Q1. Compound V2의 "Fresh" 패턴이란?

```
A: 이자를 먼저 정산한 뒤에야 핵심 로직을 실행하는 패턴.

  mint() → mintInternal(accrueInterest 먼저!) → mintFresh(실제 로직)
  borrow() → borrowInternal(accrueInterest) → borrowFresh(실제 로직)

  왜?
  → 이자가 미정산되면 borrowIndex가 옛날 값
  → 그 상태에서 deposit/borrow하면 회계가 꼬임
  → 그래서 "Fresh"한 상태에서만 실행

  우리 코드의 _accrueInterest() 호출도 같은 원리:
    function deposit(...) { _accrueInterest(asset); ... }
    function borrow(...) { _accrueInterest(asset); ... }
```

### Q2. Mantissa(1e18) vs Ray(1e27) — 왜 다른 정밀도?

```
A: 복리 이자 계산의 정밀도 차이.

  Compound: Mantissa = 1e18 (= Solidity 기본 단위)
    → 블록당 이자율 ≈ 0.000000003... → 18자리로 충분
    → 간단하고 직관적

  Aave: Ray = 1e27 (= 10^27)
    → 초 단위 이자율 ≈ 더 작은 수 → 정밀도 부족 방지
    → exponentiation 과정에서 반올림 오차 누적 방지
    → WadRayMath 라이브러리로 연산

  현실적 차이: 대부분 상황에서 무시할 수준
  → 하지만 TVL $10B+ 프로토콜에서는 1e-18 오차도 $$
```

### Q3. reservesList를 왜 배열이 아닌 mapping으로?

```
A: 가스 효율 + 삭제 시 문제 회피.

  배열 (address[]):
    → 중간 삭제 시 배열 재정렬 필요 (O(n) 가스)
    → 또는 빈 슬롯 남기면 순회 시 체크 필요
    → push/pop으로 길이 변경 시 SSTORE 추가

  매핑 (mapping(uint256 => address)):
    → 고정 슬롯: reservesList[0] = WETH, reservesList[1] = USDC
    → reservesCount만 관리하면 순회 가능
    → 삭제: reservesList[id] = address(0)으로 무효화 (cheap)
    → Aave V3는 최대 128개 리저브 제한 (비트맵 256비트 / 2)
```

---

## 오늘의 핵심 인사이트 / Key Insights

```
1. Aave V3 = Compound V2의 아키텍처 진화
   → CToken(풀+토큰 일체형) → Pool + Token 분리
   → 배열 순회 → 비트맵 스킵
   → 블록 단위 → 초 단위 이자 계산
   → 단일 컨트랙트 → Logic 라이브러리 분리 (24KB 제한 해결)

2. 비트맵은 DeFi의 핵심 가스 최적화 패턴
   → uint256 하나로 128개 리저브 상태 관리 (SSTORE 1번)
   → HF 루프에서 미사용 리저브 O(1) 스킵
   → Compound의 enterMarkets[] 배열보다 압도적으로 효율적

3. "스토리지 레이아웃이 곧 아키텍처"
   → Aave V3의 3대 매핑이 전체 구조를 결정
   → reserves(자산설정), usersConfig(사용자상태), reservesList(순회용)
   → 이 구조를 이해하면 나머지 로직은 자연스럽게 따라옴

4. 프로토콜 유형은 "돈의 출처"로 나뉜다
   → Pool-based: 예치자 돈 빌림 (은행)
   → CDP: 프로토콜이 새 돈 발행 (중앙은행)
   → Fixed-rate: 미래 가치 토큰 할인 거래 (채권)
   → DevOps 관점에서 모니터링 포인트가 완전히 다름

5. "이자는 lazy evaluation"
   → 매 블록 계산하지 않음 → 다음 tx가 올 때 한꺼번에
   → SSTORE 4번(Compound) / 인덱스 2개(Aave)로 전체 정산
   → 이게 가스 최적화의 근본 원리
```

---

## 생성된 심화 문서 / Deep Dive Documents Created

| 문서 | 핵심 내용 |
|------|----------|
| [compound-v2-code-reading.md](deep-dive/compound-v2-code-reading.md) | CToken/Comptroller/JumpRateModel 코드, Fresh 패턴, Mantissa, 오라클/청산 |
| [compound-v2-scenario.md](deep-dive/compound-v2-scenario.md) | 배포→예치→대출→이자→청산 전체 숫자 추적, Kink 시뮬레이션, 회계 분리 |
| [lending-protocol-types.md](deep-dive/lending-protocol-types.md) | Pool-based vs CDP vs Fixed-rate 유형 비교, 아키텍처 진화, DevOps 관점 |
| [pool-lending-comparison.md](deep-dive/pool-lending-comparison.md) | Compound V2 vs Aave V3 vs Euler — 동일 시나리오 5단계 비교 |
| [aave-v3-code-reading.md](deep-dive/aave-v3-code-reading.md) | aave-v3-origin 기반 코드 리딩, v3.2~v3.4 변경사항, 우리 코드와 1:1 비교 |

---

## 내일 할 것 / Tomorrow (Day 3)

```
Day 3: 청산 + Foundry 테스트 심화

  오전: 청산 이론
    - 가이드 섹션 6 읽기 (Liquidation)
    - Aave 청산 문서 읽기
    - Health Factor < 1 → 청산 흐름 완전 이해

  오후: Foundry 테스트 패턴
    - Fork Testing — 메인넷 Aave V3 포크 상호작용 (이미 기본 구현됨)
    - Fuzz Testing — 이자율 엣지 케이스 (이미 구현됨)
    - Invariant Testing — 풀 불변성 (이미 구현됨)
    - Scenario Testing — 전체 라이프사이클 시나리오

  참고: 테스트의 상당 부분은 이미 작성됨 → 리뷰 + 보강에 집중
```
