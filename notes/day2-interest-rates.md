# Day 2: 이자율 모델 + Solidity 심화

# Day 2: Interest Rate Models + Solidity Deep Dive

---

## Compound V2 심화 학습 (Day 1에서 이어짐)

> Day 1에서 시작한 Compound V2 코드 리딩을 마무리하고, 아키텍처/이자계산/회계처리까지 완전히 이해함.

### 완료한 항목

- CToken 상속 구조: abstract CToken → CErc20/CEther, getCashPrior() override 패턴
- "Fresh" 패턴: mint() → mintInternal(accrueInterest) → mintFresh(FreshnessCheck)
- Mantissa: Solidity에서 소수점 처리 (10^18 스케일링), Aave Ray(10^27)와 비교
- initialExchangeRateMantissa: 0.02e18은 UX 선택, 수학적 근거 없음
- borrowIndex 초깃값 = 1e18: 누적 이자 배수의 시작점 (곱셈의 항등원)
- Kink 개념: 이자율 그래프의 꺾이는 지점 (80%), kink 초과 시 jumpMultiplier 발동
- 실제 코드와 함께 이자 계산: utilizationRate() → getBorrowRateInternal() → accrueInterest()
- totalBorrows/totalReserves 분리 저장 이유: 회계 원칙 (원본 데이터 가공 금지)
- 오라클 아키텍처: CToken에는 가격 조회 없음, Comptroller만 oracle.getUnderlyingPrice() 호출
- 청산 실행 구조: 프로토콜은 수동적, 외부 봇이 능동적 (8% 보너스 유인)

### 생성/업데이트된 문서

| 문서                                                                 | 작업 내용                                                                                  |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| [compound-v2-code-reading.md](deep-dive/compound-v2-code-reading.md) | Q&A를 본문에 통합, Architecture Overview 확장 (배포구조/상속/Aave비교), 오라클/청산봇 통합 |
| [compound-v2-scenario.md](deep-dive/compound-v2-scenario.md)         | Kink 설명 추가, 실제 코드 매핑 상세 계산 추가, totalBorrows 분리 저장 설명 통합            |
| [lending-protocol-types.md](deep-dive/lending-protocol-types.md)     | **신규** — Pool-based vs CDP vs Fixed-rate 프로토콜 유형 비교 (Alberto Cuesta 아티클 기반) |
| [pool-lending-comparison.md](deep-dive/pool-lending-comparison.md)   | **신규** — Compound V2 vs Aave V3 vs Euler 시나리오 기반 아키텍처 비교                     |
| [aave-v3-code-reading.md](deep-dive/aave-v3-code-reading.md)         | **신규** — Aave V3 코드 리딩 가이드 (Pool/Supply/Borrow/Liquidation, 우리 코드와 비교)     |

---

## Jump Rate Model — 점프 이자율 모델

### 작동 원리 / How it Works

```
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

### 핵심 파라미터 / Key Parameters

- `baseRate`: 기본 이자율 (예: 2%) — utilization 0%일 때의 이자율
- `multiplier`: kink 이하 기울기 (예: 10%) — 정상 구간 기울기
- `jumpMultiplier`: kink 이상 급격한 기울기 (예: 300%) — 긴급 구간 기울기
- `kink`: 최적 사용률 (보통 80%) — 두 구간의 경계

### 구현 코드 / Implementation

- `contracts/src/JumpRateModel.sol` — 18개 테스트 통과
- `contracts/test/JumpRateModel.t.sol`
- `contracts/test/InterestRate.fuzz.t.sol` — 6개 퍼즈 테스트 통과

---

## cToken vs aToken 모델 비교 / cToken vs aToken Comparison

```
cToken (Compound): 토큰 수량 고정, 교환비율(exchangeRate)이 올라감
  예치: 1,000 USDC → 50,000 cUSDC (비율 0.02)
  1년후: 50,000 cUSDC 그대로, 비율 0.025
  인출: 50,000 × 0.025 = 1,250 USDC

aToken (Aave): 토큰 수량이 자동으로 늘어남 (rebase)
  예치: 1,000 USDC → 1,000 aUSDC (1:1)
  1년후: 지갑에 1,050 aUSDC로 늘어남
  인출: 1,050 aUSDC → 1,050 USDC

수학적으로 동일:
  cToken: amount = shares × exchangeRate     (인출할 때 곱셈)
  aToken: balance = scaledBalance × index    (조회할 때 곱셈)
```

> 상세: [deep-dive/deposit-tokens.md](deep-dive/deposit-tokens.md)

---

## 테스트 현황 / Test Status

```
전체 61개 테스트 통과 (2개 스킵):

  AaveForkTest             | 2 passed | 2 skipped  ← 메인넷 포크 필요
  InterestRateFuzzTest     | 6 passed |
  JumpRateModelTest        | 18 passed |
  LendingPoolInvariantTest | 2 passed |
  LendingPoolTest          | 14 passed |
  LiquidationTest          | 6 passed |
  OracleTest               | 13 passed |
```

---

## 할 일 / TODO

- [x] Compound V2 심화 학습 마무리 (Day 1에서 이어짐)
- [x] JumpRateModel 구현 및 테스트 — 18개 + 6개 퍼즈 테스트 통과
- [x] compound-v2-code-reading.md Q&A → 본문 통합 리팩토링
- [x] [Alberto Cuesta 아티클](https://alcueca.medium.com/how-to-design-a-lending-protocol-on-ethereum-18ba5849aaf0) 읽기 → lending-protocol-types.md 작성
- [x] Compound V2 vs Aave V3 vs Euler 비교 → pool-lending-comparison.md 작성
- [x] Aave V3 코드 분석 → deep-dive/aave-v3-code-reading.md 문서화
  - Pool.sol, SupplyLogic.sol, BorrowLogic.sol, LiquidationLogic.sol
  - 우리 코드(LendingPool.sol)와 비교하며 읽기
- [x] 가이드 섹션 5 읽기 / Read guide Section 5 (Interest Rate Models)
