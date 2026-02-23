# Interest Rates 심화
# Interest Rates Deep Dive

> Day 1 학습 중 발생한 Q&A를 정리한 심화 노트입니다.
> Deep-dive notes from Day 1 Q&A sessions.

---

## Utilization Rate — 풀 다이어그램

```
예치자 (Depositor)                          대출자 (Borrower)
   Alice: $1,000 예치 ──→ ┌──────────┐ ──→ Charlie: $600 대출
   Bob:   $1,000 예치 ──→ │ 렌딩 풀   │ ──→ Dave:    $200 대출
                          │ $2,000    │
                          └──────────┘
                    총 예치: $2,000 / 총 대출: $800

Utilization = $800 / $2,000 = 40%
```

---

## 이자의 흐름 — 누가 내고 누가 받나

```
대출자 (이자를 냄)  ──→  렌딩 풀  ──→  예치자 (이자를 받음)
Borrower (pays)    ──→   Pool   ──→  Depositor (earns)

핵심: 대출자가 내는 이자 → 프로토콜 수수료 제외 → 예치자에게 분배
Key: Borrower's interest → minus protocol fee → distributed to depositors
```

**예시: 풀에 $10,000 예치, Reserve Factor 10%**

```
사용률 30% (한가한 풀 / Quiet pool):
  대출: $3,000 / 남은 현금: $7,000
  Borrow APR:  5%   → 대출자가 1년에 $150 이자를 냄
  Supply APY:  1.35% → 예치자가 1년에 $135 이자를 받음
  ($150 × 90% = $135 → $10,000에 나누면 1.35%)

사용률 70% (바쁜 풀 / Busy pool):
  대출: $7,000 / 남은 현금: $3,000
  Borrow APR:  9%   → 대출자가 1년에 $630 이자를 냄
  Supply APY:  5.67% → 예치자가 1년에 $567 이자를 받음
  대출 수요 많으니 이자율 올려서 대출 억제 + 예치 유도

사용률 95% (위험한 풀 / Dangerous pool — kink 80% 초과!):
  대출: $9,500 / 남은 현금: $500 ← 출금 여유가 거의 없음!
  Borrow APR: 50%   → Jump Rate 발동! 이자율 급등!
  Supply APY: 42.75% → 예치자에게 큰 보상으로 유동성 유도
  ① 대출자가 빨리 갚게 유도 / Incentivize borrowers to repay
  ② 새 예치자가 돈을 넣게 유도 / Attract new depositors
```

**예치 이자 공식 / Supply Rate Formula:**

```
예치 이자율 = 대출 이자율 × 사용률 × (1 - 프로토콜 수수료)
Supply APY  = Borrow APR × Utilization × (1 - Reserve Factor)

검증 (사용률 70%):
= 9% × 0.70 × (1 - 0.10) = 9% × 0.70 × 0.90 = 5.67% ✓

예치 이자율이 항상 대출 이자율보다 낮은 이유 / Why Supply < Borrow:
① 사용률 < 100%: 빌려간 돈에서만 이자 발생 (안 빌려간 돈은 이자 없음)
② 프로토콜 수수료: Reserve Factor만큼 프로토콜이 가져감
```

---

## Reserve Factor — 프로토콜 수수료

```
대출자가 내는 이자의 일부를 프로토콜 금고(Treasury)에 적립
A portion of borrower's interest goes to the protocol treasury

예: RF 10% → 대출자 이자의 10%는 프로토콜로, 90%는 예치자에게
Ex: RF 10% → 10% of borrower interest to protocol, 90% to depositors
```

**주요 프로토콜별 Reserve Factor:**

```
┌───────────────┬──────────────────┬─────────────────────────────┐
│ 프로토콜       │ Reserve Factor   │ 비고 / Notes                │
├───────────────┼──────────────────┼─────────────────────────────┤
│ Aave V3       │ 10~35%          │ 자산별로 다름 / Varies by    │
│  - Stablecoins│ 20~25%          │ USDC/USDT: 15~20%           │
│  - WETH       │ 15~20%          │                             │
│  - GHO        │ 10~15%          │ 자체 스테이블코인            │
│ Compound V2   │ 7~25%           │ USDC: 7%, DAI: 15%          │
│ Compound V3   │ 10~20%          │ 단순화된 구조 / Simplified   │
│ MakerDAO      │ Stability Fee   │ 다른 구조 — DAI 민팅 수수료  │
│ Venus (BSC)   │ 10~25%          │ Aave와 유사 / Similar to Aave│
│ Radiant       │ 15~30%          │ 크로스체인 / Cross-chain     │
└───────────────┴──────────────────┴─────────────────────────────┘
```

**RF를 조절하는 이유:**

```
RF 낮추기 (유저 유치) / Lowering RF (User Acquisition):
  → 예치자에게 더 많은 이자 지급 → APY 높아짐 → 유동성 유치
  예: 새 체인 런칭 시 Aave가 RF를 낮게 설정하여 유동성 부트스트래핑

RF 높이기 (수익 확보) / Raising RF (Revenue):
  → 프로토콜 금고에 더 많이 적립 → 개발 자금, 보험 기금
  예: 2024년 Aave 거버넌스에서 RF 하한선 제안 (수익성 확보)

RF 0% 사례 / RF 0% Cases:
  → 일부 프로토콜이 초기에 RF 0%로 설정 → 모든 이자를 예치자에게
  → 유저 유치 후 거버넌스로 점진적 인상

핵심: RF는 "프로토콜 수익 vs 사용자 인센티브"의 균형 조절 레버
Key: RF is the lever balancing "protocol revenue vs user incentives"
```

---

## 이자 계산 예제 — $80 USDC 대출 기준

```
핵심: 이자는 "빌린 자산"의 풀에서 발생
     BTC를 담보로 넣었지만, 빌린 건 USDC → 이자는 USDC 풀에서 계산
Key: Interest accrues in the "borrowed asset" pool

USDC 풀 상황 (가정) / USDC Pool (assumed):
  총 예치: $10,000 USDC / 총 대출: $4,000 USDC (우리의 $80 포함)
  사용률 = $4,000 / $10,000 = 40%

Jump Rate Model 파라미터 / Parameters:
  baseRate       = 2%    (기본 이자율 / base rate)
  multiplier     = 10%   (kink 이하 기울기 / slope below kink)
  kink           = 80%   (최적 사용률 / optimal utilization)
  jumpMultiplier = 300%  (kink 초과 기울기 — 급등! / slope above kink)

Borrow APR 계산 (사용률 40%) / Borrow APR calc (40% util):
  borrowRate = baseRate + (utilization × multiplier)
             = 2% + (40% × 10%)
             = 2% + 4% = 6%
```

**RF 10% 적용 이자 흐름:**

```
① Borrow APR = 6%
② 연간 이자 = $80 × 6% = $4.80 (대출자가 냄 / borrower pays)

③ Reserve Factor 10% 적용 / Apply RF 10%:
   프로토콜 금고로 / To treasury: $4.80 × 10% = $0.48
   예치자들에게 / To depositors: $4.80 × 90% = $4.32

④ Supply APY 검증 / Verify:
   = Borrow APR × Utilization × (1 - RF)
   = 6% × 0.40 × 0.90 = 2.16%
   → $10,000 × 2.16% = $216/년 (풀 전체 / whole pool)

돈의 흐름 (풀 전체) / Money flow (whole pool):
대출자들 ──$600/년──→ 프로토콜 ──$60──→ 금고 (Treasury)
  ($4,000 × 6%)               ──$540──→ 예치자들 (Depositors)
```

**사용률별 이자 변화:**

```
┌───────────┬────────────┬──────────────┬──────────────┬────────────┐
│ 사용률     │ Borrow APR │ $80 연이자    │ 프로토콜(10%)│ Supply APY │
├───────────┼────────────┼──────────────┼──────────────┼────────────┤
│ 20%       │ 4%         │ $3.20        │ $0.32        │ 0.72%      │
│ 40%       │ 6%         │ $4.80        │ $0.48        │ 2.16%      │
│ 60%       │ 8%         │ $6.40        │ $0.64        │ 4.32%      │
│ 80%(kink) │ 10%        │ $8.00        │ $0.80        │ 7.20%      │
│ 90%       │ 40% ← 급등 │ $32.00       │ $3.20        │ 32.40%     │
│ 95%       │ 55%        │ $44.00       │ $4.40        │ 47.03%     │
└───────────┴────────────┴──────────────┴──────────────┴────────────┘

80% → 90%로 10%p만 올라도 이자율이 10% → 40%로 4배 급등!
Jump Rate의 핵심 — kink 초과 시 이자 폭등으로 유동성 복귀 유도
```

---

## 이자율의 3개 레이어 — RF만이 아니다!
## 3 Layers of Interest — RF Is Not Everything!

```
실제 사용자가 보는 이자율 = 기본 이자 ± 토큰 인센티브 ± 포인트/에어드랍
Actual user-facing rate = Base interest ± Token incentives ± Points/Airdrops

Layer 1: 기본 이자율 (Base Interest)
  → Jump Rate Model로 계산 (utilization 기반)
  → RF로 프로토콜/예치자 분배

Layer 2: 토큰 인센티브 (Token Incentives)
  → 프로토콜 자체 토큰을 추가 보상으로 지급
  → Compound: COMP 토큰, Aave: stkAAVE 보상

Layer 3: 포인트/에어드랍 (Points/Airdrops)
  → 최신 프로토콜들이 사용 (토큰 출시 전)
  → e.g., Blast, EigenLayer points
```

**DeFi 대시보드에서 실제로 보이는 것:**

```
  USDC Supply APY
  Base:  2.16%  ← Layer 1 (이자율 모델 / Interest model)
  +COMP: 3.50%  ← Layer 2 (토큰 보상 / Token reward)
  ─────────────
  Total: 5.66%

  USDC Borrow APR
  Base:  6.00%  ← Layer 1 (이자율 모델 / Interest model)
  -COMP: 2.00%  ← Layer 2 (대출자도 보상! / Borrowers rewarded too!)
  ─────────────
  Net:   4.00%  ← 실질 대출 비용 / Effective borrow cost

  극단적 경우: 토큰 보상 > 대출 이자 → "빌리면 돈을 버는" 상황!
  Extreme: Token reward > borrow interest → "earn money by borrowing"!
```

**실제 사례:**

```
Compound (2020-2021 DeFi Summer):
  USDC Borrow APR: 4%
  COMP 보상:      -8%  (대출자에게 COMP 토큰 지급)
  Net:            -4%  ← 빌리면 오히려 4% 벌었음!
  → "Yield Farming" 열풍의 핵심 원인
  → 빌리고 → COMP 받고 → 팔고 → 또 빌리고 (레버리지 파밍)

Aave V3 (현재 / Current):
  stkAAVE 보상은 Safety Module 스테이킹에 집중
  Borrow/Supply 보상은 거버넌스로 결정 (Merit 프로그램)

최신 프로토콜 (Morpho, Euler V2 등 / Newer protocols):
  포인트 시스템 → 미래 에어드랍 기대감 유도
  "예치하면 포인트 적립 → 나중에 토큰으로 전환"
```

**이자율 결정 요소 총정리:**

```
┌──────────────────┬──────────────────────────────────────┐
│ ① 이자율 모델     │ Jump Rate Model (utilization 기반)   │
│   Interest Model │ baseRate + multiplier + jumpRate     │
├──────────────────┼──────────────────────────────────────┤
│ ② Reserve Factor │ 프로토콜 vs 예치자 분배 비율           │
│                  │ Protocol vs depositor split          │
├──────────────────┼──────────────────────────────────────┤
│ ③ 토큰 인센티브   │ COMP, AAVE 등 추가 보상              │
│   Token Rewards  │ Can make net borrow rate negative!   │
├──────────────────┼──────────────────────────────────────┤
│ ④ 포인트/에어드랍  │ 토큰 출시 전 유저 유치 전략            │
│   Points/Airdrop │ Pre-token user acquisition strategy  │
├──────────────────┼──────────────────────────────────────┤
│ ⑤ 거버넌스       │ 위 모든 파라미터를 DAO 투표로 조정      │
│   Governance     │ All params adjustable via DAO vote   │
└──────────────────┴──────────────────────────────────────┘
```

---

## Jump Rate Model은 표준인가? — 프로토콜별 이자율 모델 비교

```
DEX 비유 / DEX Analogy:
  CPMM (x·y=k)  →  Uniswap V1/V2의 원조 모델
  Jump Rate      →  Compound V2의 원조 모델

  둘 다 "업계 표준처럼 널리 쓰이지만" 각 프로토콜이 변형/개량함
  Both are "widely adopted as de facto standards" but each protocol customizes
```

**프로토콜별 이자율 모델:**

```
┌─────────────────┬─────────────────────────────────────────────┐
│ Compound V2     │ Jump Rate Model (원조 / Original)            │
│                 │ - baseRate + multiplier + jumpMultiplier     │
│                 │ - kink 하나 (보통 80%)                       │
│                 │ - 가장 단순한 형태                             │
├─────────────────┼─────────────────────────────────────────────┤
│ Aave V2/V3      │ Variable Rate Strategy (자체 설계)           │
│                 │ - 컨셉은 비슷 (optimal utilization = kink)   │
│                 │ - 하지만 파라미터 구조가 다름:                  │
│                 │   · baseVariableBorrowRate                   │
│                 │   · variableRateSlope1 (optimal 이하)        │
│                 │   · variableRateSlope2 (optimal 초과)        │
│                 │ - Stable Rate도 별도로 존재 (고정금리 옵션)    │
├─────────────────┼─────────────────────────────────────────────┤
│ Compound V3     │ 단순화된 모델 / Simplified                   │
│ (Comet)         │ - 자산별 단일 이자율 곡선                     │
│                 │ - V2보다 가스비 최적화                        │
├─────────────────┼─────────────────────────────────────────────┤
│ MakerDAO        │ 완전 다른 구조 / Completely different         │
│                 │ - Stability Fee: 거버넌스가 직접 이자율 설정   │
│                 │ - 알고리즘이 아니라 사람(DAO)이 결정!          │
│                 │ - DSR (DAI Savings Rate)도 거버넌스로 설정    │
├─────────────────┼─────────────────────────────────────────────┤
│ Morpho          │ 하부 프로토콜의 이자율을 최적화               │
│                 │ - Aave/Compound 위에서 P2P 매칭              │
│                 │ - 자체 모델 없이 기존 모델의 비효율을 개선     │
├─────────────────┼─────────────────────────────────────────────┤
│ Euler V2        │ 모듈형 이자율 / Modular                      │
│                 │ - 풀 생성자가 이자율 모델을 직접 선택/배포     │
│                 │ - "이자율 모델 마켓플레이스" 컨셉              │
├─────────────────┼─────────────────────────────────────────────┤
│ Fraxlend        │ Time-Weighted Variable Rate                  │
│                 │ - 사용률 기반이 아닌 시간 가중 모델           │
│                 │ - 이자율이 시간에 따라 자동 조정              │
└─────────────────┴─────────────────────────────────────────────┘
```

**DEX 모델 진화와 1:1 대응:**

```
DEX (AMM) 진화:                     Lending (이자율 모델) 진화:
─────────────────                   ─────────────────────────
Uniswap V1: CPMM (x·y=k)          Compound V2: Jump Rate Model
  ↓ 가장 단순                         ↓ 가장 단순
Uniswap V3: Concentrated LP        Aave V3: Variable Rate Strategy
  ↓ 자본 효율성 개선                   ↓ 파라미터 세분화
Curve: StableSwap (스테이블 특화)    MakerDAO: Governance-set Rate
  ↓ 특수 목적                         ↓ 알고리즘 대신 사람이 결정
Balancer: Weighted Pool             Euler V2: Modular Rate Models
  ↓ 가중치 커스텀                      ↓ 모델 자체를 커스텀
Uniswap V4: Hooks (무한 확장)       Morpho: P2P 매칭 최적화
  ↓ 로직 자체를 플러그인               ↓ 기존 모델 위에 최적화 레이어

공통점: 원조 모델(CPMM/Jump Rate)이 업계 기반이 되고,
       각 프로토콜이 자신만의 차별화 포인트를 만들어 경쟁
```

**핵심 차이: "같은 컨셉, 다른 구현"**

```
공통점 (거의 모든 렌딩 프로토콜) / Common across all:
  ✓ 사용률(Utilization) 기반 이자율 결정
  ✓ 사용률 높으면 → 이자율 올림 (유동성 복귀 유도)
  ✓ "꺾이는 지점" 존재 (kink / optimal utilization)

차이점 / Differences:
  ✗ 꺾이는 지점의 개수 (1개 vs 여러 개)
  ✗ 곡선의 모양 (선형 vs 비선형 vs 시간 가중)
  ✗ 파라미터 결정 방식 (하드코딩 vs 거버넌스 vs 알고리즘)
  ✗ 고정금리 옵션 유무 (Aave Stable Rate, Notional)

결론: Jump Rate는 "CPMM 같은 원조 모델"이고,
     각 프로토콜이 이를 기반으로 자체 변형을 만듦
     우리 프로젝트에서 구현한 건 Compound V2 스타일의 원조 버전!
```

---

## 용어 정리 / Glossary

#### APR vs APY — 이자율 표기 차이

```
APR (Annual Percentage Rate) — 연이율 (단리)
  이자에 이자가 붙지 않음 / No compounding
  예: APR 10%, $1,000 → 1년 뒤 $1,100

APY (Annual Percentage Yield) — 연수익률 (복리)
  이자에 이자가 붙음 / Compounding applied
  예: APY 10%, $1,000 → 1년 뒤 $1,105.12 (매월 복리 시)

변환 공식 / Conversion:
  APY = (1 + APR/n)^n - 1   (n = 복리 주기 수 / compounding periods)

  APR 10%, 매월 복리 (n=12):
  APY = (1 + 0.10/12)^12 - 1 = 1.10471 - 1 = 10.47%
  → APY는 항상 APR보다 높음 / APY is always >= APR
```

#### 왜 Borrow는 APR, Supply는 APY로 표기하나?

```
DeFi 관행 / DeFi convention:

  Borrow → APR로 표기
    대출자에게 "내가 내야 할 이자"를 낮아 보이게 표시 (마케팅)
    실제로는 블록마다 복리가 적용되므로 실제 비용은 APR보다 높음

  Supply → APY로 표기
    예치자에게 "내가 받을 이자"를 높아 보이게 표시 (마케팅)
    예치 이자는 블록마다 자동 복리 적용 (aToken 잔액이 계속 증가)

  ┌──────────┬──────┬───────────────────────────────┐
  │          │ 표기 │ 이유                           │
  ├──────────┼──────┼───────────────────────────────┤
  │ Borrow   │ APR  │ 낮아 보이게 (대출자 유치)      │
  │ Supply   │ APY  │ 높아 보이게 (예치자 유치)      │
  └──────────┴──────┴───────────────────────────────┘

  실제로는 둘 다 블록 단위 복리 — 표기만 다를 뿐!
  In reality both compound per block — only the label differs!
```
