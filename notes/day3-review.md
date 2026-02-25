# Day 3 Review — 오늘 배운 것 정리

> 2026-02-25 (화) 학습 리뷰

---

## 완료한 항목 / Completed

- [x] InterestRateModel.sol practice 구현 — constructor, getUtilization, getBorrowRate, getBorrowRatePerSecond, getSupplyRate
- [x] MathTest.t.sol — Solidity 정수 연산 6개 테스트 작성 및 통과
- [x] InterestRate.practice.t.sol — compound-v2-scenario.md 기반 16개 테스트 통과
- [x] PriceOracle.sol practice 구현 — constructor, setPriceFeed, getAssetPrice, getAssetPriceNormalized, checkStaleness
- [x] PriceOracle.practice.t.sol — Mock 패턴 + staleness 12개 테스트 (11 passed, 1 메시지 수정 필요)
- [x] deep-dive 문서 3개 작성 (solidity-math-precision, evm-integer-only-design, price-normalization)

---

## 1. InterestRateModel Practice — Kink Model 직접 구현

### 구현한 함수들

```
practice/InterestRateModel.sol — 스켈레톤에 TODO 채우기 방식

  ① constructor: baseRate, multiplier, jumpMultiplier, kink 초기화
  ② getUtilization: totalBorrows * PRECISION / totalDeposits (0 나누기 방지)
  ③ getBorrowRate: kink 이하면 정상 구간, 초과면 jump 구간
  ④ getBorrowRatePerSecond: 연간 → 초당 변환 (÷ SECONDS_PER_YEAR)
  ⑤ getSupplyRate: borrowRate × utilization × (1 - reserveFactor)
```

### getBorrowRate — Kink 초과 시 2단계 계산

```
[상황] 10,000 예치, 9,000 대출 → utilization = 90%, kink = 80%

  Step 1: normalRate = baseRate + kink × multiplier = 2% + 80%×10% = 10%
          → "kink까지의 이자율"

  Step 2: excessUtil = 90% - 80% = 10%
          → "kink 초과분"

  Step 3: jumpPart = 10% × 300%(jumpMultiplier) = 30%
          → "초과분에 급경사 적용"

  최종: 10% + 30% = 40% ← 80%→90% 불과 10%p인데 이자율 4배 급등!
```

### getSupplyRate — 돈의 흐름으로 이해

```
풀: 20,000 USDC 예치, 10,000 USDC 대출 (util=50%)

  ① Alice(대출자) 이자 = 10,000 × 7% = 700 USDC/년
  ② 프로토콜 수수료 = 700 × 10%(RF) = 70 USDC
  ③ 예치자에게 배분 = 700 - 70 = 630 USDC
  ④ supplyRate = 630 / 20,000 = 3.15%

  공식: supplyRate = borrowRate × utilization × (1 - RF)
                   = 7% × 50% × 90% = 3.15% ✓
```

---

## 2. Solidity 정수 연산 — MathTest로 체감

### 3대 원칙 (MathTest 6개 테스트로 검증)

```
① 나눗셈은 소수점 버림 → PRECISION(1e18)으로 스케일링
   800 / 1000 = 0  (소수점 없음!)
   800 * 1e18 / 1000 = 0.8e18 = 80%  ✓

② 곱하기 먼저, 나누기 나중에
   1 * 1e18 / 3 = 333...333  ✓
   1 / 3 * 1e18 = 0          ← 완전 손실!

③ 스케일 값 × 스케일 값 → PRECISION으로 나눠서 복원
   0.8e18 × 0.1e18 = 8e34  (의미없음)
   0.8e18 × 0.1e18 / 1e18 = 0.08e18 = 8%  ✓
```

### 연간 → 초당 변환이 필요한 이유

```
이자는 "매 트랜잭션마다" 불규칙하게 계산됨:
  ratePerSec = annualRate / 31,536,000
  interest = totalBorrows × ratePerSec × 경과초

정밀도 손실: 0.07e18 → 초당 → 역산 = 0.06999...e18
  → 100만 달러 풀에서 연간 0.04센트 차이. 무시 가능.
```

### EVM이 float을 지원하지 않는 이유

```
① 합의 문제: float은 CPU마다 다른 결과 → 노드 간 상태 불일치 → 체인 포크
② 금융 정밀도: 오차 누적 → 잔고 불일치 → 자금 손실
③ 설계 단순화: uint256 하나로 opcode/가스 모델 간소화
→ "의도적 설계 결정" — 블록체인 합의의 필연적 선택
```

---

## 3. PriceOracle Practice — Chainlink 통합 + Mock 패턴

### 구현한 함수들

```
practice/PriceOracle.sol — Chainlink 가격 피드를 통한 USD 가격 제공

  ① constructor: owner = msg.sender, maxStaleness 설정
  ② setPriceFeed: 자산별 Chainlink 피드 주소 등록 (onlyOwner)
  ③ getAssetPrice: 4가지 안전 검증 후 가격 리턴 (핵심!)
  ④ getAssetPriceNormalized: 8 dec → 18 dec 스케일링
  ⑤ checkStaleness: 모니터링용 지연 상태 조회
```

### getAssetPrice — 4가지 안전 검증

```
latestRoundData() 호출 후:
  ① answer > 0          — 음수 가격 거부
  ② updatedAt > 0       — 미완료 라운드 거부
  ③ answeredInRound >= roundId — 오래된 라운드 답변 거부
  ④ block.timestamp - updatedAt <= maxStaleness — 시간 초과 거부

→ 이 중 하나라도 실패하면 revert → 프로토콜 보호
→ ④가 DevOps 모니터링의 핵심: "오라클이 죽으면 프로토콜도 멈춘다"
```

### Mock 패턴 — 외부 의존성 테스트

```
문제: 로컬에서 Chainlink 실제 컨트랙트 접근 불가
해결: IPriceFeed 인터페이스를 구현하는 MockChainlinkFeed 작성

  실제:  PriceOracle → IPriceFeed → [Chainlink 컨트랙트]
  테스트: PriceOracle → IPriceFeed → [MockChainlinkFeed] ← 가격 조작 가능!

핵심: 인터페이스만 같으면 뒤에 뭐가 오든 상관없음
     → "의존성 주입" 패턴의 실전 적용
```

### Foundry 치트코드 2개

```
vm.warp(timestamp):  block.timestamp를 원하는 값으로 변경
  → staleness 테스트: vm.warp(block.timestamp + 3601) → "1시간 넘음!"

vm.prank(address):   다음 호출의 msg.sender를 변경
  → 접근 제어 테스트: vm.prank(attacker) → revert("Only owner")
```

### 가격 정규화가 필요한 이유

```
같은 자산 내 계산 (이자율, 사용률): 가격 불필요 — 단위가 상쇄됨
서로 다른 자산 비교 (대출 승인, 청산): 가격 정규화 필수!

  담보: 10 ETH × $2,000 = $20,000   ← ETH/USD 가격 필요
  부채: 10,000 USDC × $1 = $10,000  ← USDC/USD 가격 필요
  HF = $20,000 × 0.75 / $10,000 = 1.5

→ 피드마다 decimals가 다를 수 있으므로 18 dec로 통일
```

---

## 4. Foundry 설정 삽질 / Configuration Troubleshooting

```
문제 1: test = "." 설정 → lib/ 전체 스캔 → OpenZeppelin 버전 충돌
해결:   test 디렉토리를 기본값(test/)으로 유지, 파일을 test/에 배치

문제 2: 프로젝트 루트에서 forge test 실행 → foundry.toml 못 찾음
해결:   contracts/ 디렉토리에서 실행하거나 --root contracts 옵션

교훈: Foundry 프로젝트는 foundry.toml이 있는 디렉토리에서 실행해야 함
```

---

## 생성/수정된 파일 / Files Created/Modified

### Practice 코드

| 파일                             | 내용                             |
| -------------------------------- | -------------------------------- |
| practice/InterestRateModel.sol   | Kink Model 구현 (5개 함수)       |
| practice/PriceOracle.sol         | Chainlink 오라클 통합 (5개 함수) |
| test/MathTest.t.sol              | Solidity 정수 연산 테스트 (6개)  |
| test/InterestRate.practice.t.sol | scenario 기반 이자율 검증 (16개) |
| test/PriceOracle.practice.t.sol  | Mock + staleness 테스트 (12개)   |

### Deep-dive 문서

| 문서                                                               | 핵심 내용                                                       |
| ------------------------------------------------------------------ | --------------------------------------------------------------- |
| [solidity-math-precision.md](deep-dive/solidity-math-precision.md) | PRECISION 스케일링, 3대 원칙, 초당 변환, 정밀도 손실 실측       |
| [evm-integer-only-design.md](deep-dive/evm-integer-only-design.md) | EVM이 float 배제한 3가지 이유, L2/타 체인 사례, DeFi 우회법     |
| [price-normalization.md](deep-dive/price-normalization.md)         | 가격 정규화가 이자율에는 불필요, 담보-부채 비교에서 필수인 이유 |

---

## 테스트 결과 / Test Results

```
forge test --match-contract MathTest -vvv
  → 6 passed, 0 failed ✅

forge test --match-contract InterestRatePracticeTest -vvv
  → 16 passed, 0 failed ✅

forge test --match-contract PriceOraclePracticeTest -vvv
  → 11 passed, 1 failed (revert 메시지 불일치 → 수정 필요)
```

---

## 오늘의 핵심 인사이트 / Key Insights

```
1. "스켈레톤 + TODO" 방식이 학습에 효과적
   → 전체 구조를 먼저 이해하고, TODO를 채우며 구현 세부사항 체득
   → 기존 테스트가 구현의 정답지 역할

2. Solidity 정수 연산은 "곱하기 먼저, 나누기 나중에"가 전부
   → PRECISION = 1e18로 스케일링, 나누기 시 소수점 버림
   → MathTest로 직접 확인하면 바로 체감됨

3. 초당 이자율 변환은 "트랜잭션 간격이 불규칙하기 때문에" 필수
   → 1시간, 3일, 30일 후에 올 수 있는 트랜잭션에 대응
   → 정밀도 손실은 $0.04/년 수준 (무시 가능)

4. Mock은 외부 의존성 테스트의 표준 패턴
   → 인터페이스만 맞추면 진짜든 가짜든 동작
   → Foundry 치트코드(vm.warp, vm.prank)로 시간/계정 조작

5. 가격 정규화는 "서로 다른 자산의 가치 비교"에 필요
   → 이자율 = 같은 자산끼리 → 불필요
   → 청산/HF = 다른 자산 비교 → 필수
```

---

## 내일 할 것 / Tomorrow

```
Phase 1 남은 Practice:
  ③ LToken.sol — ERC20 상속 + mint/burn, "왜 별도 토큰이 필요한가"
  ④ DebtToken.sol — transfer 불가 패턴, "부채가 왜 토큰인가"

Phase 2:
  ⑤ LendingPool.sol 통합 — deposit → borrow → repay → liquidate
```
