# Day 1: 핵심 개념 + 첫 스마트 컨트랙트
# Day 1: Core Concepts + First Smart Contract

## 오전 — 이론 (2시간) / Morning — Theory (2h)

### 핵심 개념 / Key Concepts

#### LTV (Loan-to-Value) — 담보 대비 대출 비율
- LTV = 대출금 / 담보 가치 × 100%
- LTV = Loan Amount / Collateral Value × 100%
- 예: ETH $2,000 담보, $1,500 대출 → LTV = 75%
- Example: ETH $2,000 collateral, $1,500 borrow → LTV = 75%

#### Health Factor — 헬스팩터 (청산 지표)
- HF = Σ(담보 × 가격 × 청산기준) / Σ(부채 × 가격)
- HF = Σ(collateral × price × liquidation_threshold) / Σ(debt × price)
- HF > 1: 안전 / Safe
- HF < 1: 청산 가능! / Liquidatable!
- **스테이킹 비유**: 검증자 유효 잔액과 유사 — 임계값 이하로 내려가면 슬래싱(청산)

**예시: BTC $100,000 기준, 0.001 BTC ($100) 담보, LTV 80%, Liquidation Threshold 85%**
**Example: BTC $100,000, 0.001 BTC ($100) collateral, LTV 80%, Liquidation Threshold 85%**

```
대출금: $80 USDC (LTV 80%로 최대한 빌림)
Borrowed: $80 USDC (max borrow at LTV 80%)

HF = (담보 × 가격 × 청산기준) / (부채 × 가격)
HF = ($100 × 0.85) / ($80 × 1) = 1.0625
```

| BTC 가격 / Price | 담보 가치 / Collateral | HF | 상태 / Status |
|---|---|---|---|
| $100,000 | $100 | **1.0625** | 안전 (간신히) / Safe (barely) |
| $96,000 | $96 | **1.02** | 위험! / Dangerous! |
| $94,118 | $94.12 | **1.00** | 경계선 / Borderline |
| $90,000 | $90 | **0.956** | 청산 가능! / Liquidatable! |
| $80,000 | $80 | **0.85** | 확실히 청산 / Definitely liquidated |

```
핵심: BTC가 6%만 떨어져도 ($100K → $94K) 청산 당할 수 있음!
Key: Just a 6% BTC drop ($100K → $94K) can trigger liquidation!

안전한 대출 vs 위험한 대출 / Safe vs Risky borrowing:
보수적 LTV 50%: $100 담보 → $50 대출 → HF=1.70 → BTC 41% 하락까지 버팀
보통   LTV 65%: $100 담보 → $65 대출 → HF=1.31 → BTC 24% 하락까지 버팀
공격적 LTV 80%: $100 담보 → $80 대출 → HF=1.06 → BTC  6% 하락에 청산!

Conservative LTV 50%: $100 → borrow $50 → HF=1.70 → survives 41% BTC drop
Moderate     LTV 65%: $100 → borrow $65 → HF=1.31 → survives 24% BTC drop
Aggressive   LTV 80%: $100 → borrow $80 → HF=1.06 → liquidated at 6% drop!
```

**간편 공식 / Quick Formulas:**

```
외울 것 두 개 / Two formulas to memorize:

① HF = LT / LTV                (헬스팩터 / Health Factor)
② 최대 하락률 = 1 - (1/HF)     (몇 프로까지 버티나 / Max price drop before liquidation)

합치면 한 방에 계산 가능 / Combined into one:
③ 최대 하락률 = 1 - (LTV / LT)

이유: 가격이 X% 떨어지면 담보 가치도 X% 줄고, HF도 같은 비율로 줄기 때문
Why: When price drops X%, collateral value drops X%, and HF drops proportionally
     HF가 1이 되는 지점을 역산하면 됨 / Just find the point where HF reaches 1

예시 / Examples (LT = 85% 고정 / fixed):

  LTV 50%: HF = 0.85/0.50 = 1.70  → 하락률 = 1-(1/1.70) = 41%
  LTV 65%: HF = 0.85/0.65 = 1.31  → 하락률 = 1-(1/1.31) = 24%
  LTV 80%: HF = 0.85/0.80 = 1.06  → 하락률 = 1-(1/1.06) =  6%

  또는 한 방에 / Or directly:
  LTV 65%: 하락률 = 1-(0.65/0.85) = 1-0.7647 = 23.5%
```

#### Utilization Rate — 사용률
- U = 총 대출금 / 총 예치금
- U = Total Borrows / Total Deposits
- 높을수록 → 이자율 높아짐 (유동성 복귀 유도)
- Higher → interest rates increase (incentivizes liquidity return)
- **스테이킹 비유**: 검증자 큐와 유사 — 수요가 많으면 진입이 어려움

```
예치자 (Depositor)                          대출자 (Borrower)
   Alice: $1,000 예치 ──→ ┌──────────┐ ──→ Charlie: $600 대출
   Bob:   $1,000 예치 ──→ │ 렌딩 풀   │ ──→ Dave:    $200 대출
                          │ $2,000    │
                          └──────────┘
                    총 예치: $2,000 / 총 대출: $800

Utilization = $800 / $2,000 = 40%
```

**이자의 흐름 / Interest Flow:**
```
대출자 (이자를 냄)  ──→  렌딩 풀  ──→  예치자 (이자를 받음)
Borrower (pays)    ──→   Pool   ──→  Depositor (earns)

대출 이자율 (Borrow APR): 대출자가 빌린 돈에 대해 내는 이자
Supply 이자율 (Supply APY): 예치자가 맡긴 돈에 대해 받는 이자

핵심: 대출자가 내는 이자 → 프로토콜 수수료 제외 → 예치자에게 분배
Key: Borrower's interest → minus protocol fee → distributed to depositors
```

**예시: 풀에 $10,000 예치, 프로토콜 수수료(Reserve Factor) 10%**
**Example: $10,000 deposited, Reserve Factor 10%**

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

#### Reserve Factor — 프로토콜 수수료 (준비금 비율)

**개념 / Concept:**
```
대출자가 내는 이자의 일부를 프로토콜 금고(Treasury)에 적립
A portion of borrower's interest goes to the protocol treasury

Reserve Factor = 프로토콜이 가져가는 비율
Reserve Factor = % of interest the protocol keeps

예: RF 10% → 대출자 이자의 10%는 프로토콜로, 90%는 예치자에게
Ex: RF 10% → 10% of borrower interest to protocol, 90% to depositors
```

**주요 프로토콜별 Reserve Factor / Major Protocol Reserve Factors:**
```
┌───────────────┬──────────────────┬─────────────────────────────┐
│ 프로토콜       │ Reserve Factor   │ 비고 / Notes                │
├───────────────┼──────────────────┼─────────────────────────────┤
│ Aave V3       │ 10~35%          │ 자산별로 다름 / Varies by    │
│               │                  │ asset                       │
│  - Stablecoins│ 20~25%          │ USDC/USDT: 15~20%           │
│  - WETH       │ 15~20%          │                             │
│  - GHO        │ 10~15%          │ 자체 스테이블코인 / Native   │
│               │                  │ stablecoin                  │
│ Compound V2   │ 7~25%           │ USDC: 7%, DAI: 15%          │
│ Compound V3   │ 10~20%          │ 단순화된 구조 / Simplified   │
│ MakerDAO      │ Stability Fee   │ 다른 구조 — DAI 민팅 수수료  │
│               │                  │ Different — DAI minting fee  │
│ Venus (BSC)   │ 10~25%          │ Aave와 유사 / Similar to Aave│
│ Radiant       │ 15~30%          │ 크로스체인 / Cross-chain     │
└───────────────┴──────────────────┴─────────────────────────────┘
```

**RF를 조절하는 이유 / Why Protocols Adjust RF:**
```
RF 낮추기 (유저 유치) / Lowering RF (User Acquisition):
  → 예치자에게 더 많은 이자 지급 → APY 높아짐 → 유동성 유치
  → Depositors get more interest → higher APY → attract liquidity
  예: 새 체인 런칭 시 Aave가 RF를 낮게 설정하여 유동성 부트스트래핑
  Ex: When launching on new chains, Aave sets lower RF to bootstrap liquidity

RF 높이기 (수익 확보) / Raising RF (Revenue):
  → 프로토콜 금고에 더 많이 적립 → 개발 자금, 보험 기금
  → More to protocol treasury → development fund, insurance
  예: 2024년 Aave 거버넌스에서 RF 하한선 제안 (수익성 확보)
  Ex: 2024 Aave governance proposed RF floors (ensure profitability)

RF 0% 사례 / RF 0% Cases:
  → 일부 프로토콜이 초기에 RF 0%로 설정 → 모든 이자를 예치자에게
  → Some protocols launch with RF 0% → all interest to depositors
  → 유저 유치 후 거버넌스로 점진적 인상
  → After user acquisition, gradually increase via governance

핵심: RF는 "프로토콜 수익 vs 사용자 인센티브"의 균형 조절 레버
Key: RF is the lever balancing "protocol revenue vs user incentives"
```

#### 이자 계산 예제 — $80 USDC 대출 기준 (위 BTC 예제 연속)
#### Interest Calculation Example — $80 USDC Borrow (Continuing BTC Example)

```
핵심: 이자는 "빌린 자산"의 풀에서 발생
     BTC를 담보로 넣었지만, 빌린 건 USDC → 이자는 USDC 풀에서 계산
Key: Interest accrues in the "borrowed asset" pool
     BTC is collateral, but USDC is borrowed → interest in USDC pool

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

**RF 10% 적용 이자 흐름 / Interest Flow with RF 10%:**
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

**사용률별 이자 변화 / Interest by Utilization:**
```
┌───────────┬────────────┬──────────────┬──────────────┬────────────┐
│ 사용률     │ Borrow APR │ $80 연이자    │ 프로토콜(10%)│ Supply APY │
│ Util Rate │            │ Annual int.  │ Protocol     │            │
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
Just 10%p increase (80%→90%) causes 4x rate jump (10%→40%)!
Jump Rate's purpose — spike rates above kink to incentivize liquidity return
```

#### 이자율의 3개 레이어 — RF만이 아니다!
#### 3 Layers of Interest — RF Is Not Everything!

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

**DeFi 대시보드에서 실제로 보이는 것 / What Users See on DeFi Dashboards:**
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

**실제 사례 / Real Examples:**
```
Compound (2020-2021 DeFi Summer):
  USDC Borrow APR: 4%
  COMP 보상:      -8%  (대출자에게 COMP 토큰 지급)
  Net:            -4%  ← 빌리면 오히려 4% 벌었음!
  → "Yield Farming" 열풍의 핵심 원인
  → Core driver of the "Yield Farming" craze
  → 빌리고 → COMP 받고 → 팔고 → 또 빌리고 (레버리지 파밍)

Aave V3 (현재 / Current):
  stkAAVE 보상은 Safety Module 스테이킹에 집중
  Borrow/Supply 보상은 거버넌스로 결정 (Merit 프로그램)

최신 프로토콜 (Morpho, Euler V2 등 / Newer protocols):
  포인트 시스템 → 미래 에어드랍 기대감 유도
  "예치하면 포인트 적립 → 나중에 토큰으로 전환"
  Points system → anticipation of future airdrop
```

**이자율 결정 요소 총정리 / All Interest Rate Factors:**
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

#### Collateral Factor — 담보 인정 비율
- 자산별로 다름 (ETH: ~80%, USDC: ~85%)
- Varies by asset (ETH: ~80%, USDC: ~85%)
- 변동성이 큰 자산 → 낮은 CF

### 왜 과담보인가? / Why Over-Collateralized?
- 블록체인에는 신원 확인 없음 → 신용점수 불가
- No identity on blockchain → no credit scores possible
- 따라서 대출금보다 더 많은 담보를 요구
- Therefore require more collateral than loan amount

### 풀 기반 아키텍처 / Pool-Based Architecture
```
사용자A (예치) → [렌딩 풀] → 사용자B (대출)
User A (deposit) → [Lending Pool] → User B (borrow)
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

  정리:
  ┌──────────┬──────┬───────────────────────────────┐
  │          │ 표기 │ 이유                           │
  ├──────────┼──────┼───────────────────────────────┤
  │ Borrow   │ APR  │ 낮아 보이게 (대출자 유치)      │
  │ Supply   │ APY  │ 높아 보이게 (예치자 유치)      │
  │ Borrow   │ APR  │ Looks lower (attract borrowers)│
  │ Supply   │ APY  │ Looks higher (attract depositors)│
  └──────────┴──────┴───────────────────────────────┘

  실제로는 둘 다 블록 단위 복리 — 표기만 다를 뿐!
  In reality both compound per block — only the label differs!
```

---

## 할 일 / TODO
- [ ] `defi-lending-protocol-guide.md` 섹션 1-3 읽기 / Read Sections 1-3
- [ ] Finematics 영상 시청 / Watch Finematics video
- [ ] SpeedRunEthereum 렌딩 챌린지 완료 / Complete SpeedRunEthereum lending challenge
- [ ] Compound V2 코드 읽기 / Read Compound V2 code
