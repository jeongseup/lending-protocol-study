# Lending Protocol Decomposition — Base Architecture + Composable Models

> 렌딩 프로토콜을 **기본 구조 + 교체 가능한 모듈**로 분해
> 레버리지 렌딩 컴포넌트 분해와 동일한 접근법
>
> 참고: [pool-lending-comparison.md](pool-lending-comparison.md) (Compound V2 vs Aave V3 vs Euler 상세 비교)
> 참고: [lending-protocol-types.md](lending-protocol-types.md) (Pool vs CDP vs Fixed-rate 유형 비교)
> 참고: [aave-v3-vs-v4.md](aave-v3-vs-v4.md) (V3 vs V4 아키텍처 비교)

---

## 핵심 아이디어 / Core Idea

```
모든 Pool-based 렌딩 프로토콜은 같은 "뼈대"를 공유하고,
각 모듈을 어떤 모델로 채우느냐에 따라 다른 프로토콜이 된다.

Every pool-based lending protocol shares the same skeleton,
and becomes a different protocol depending on which model fills each module.

┌─────────────────────────────────────────────────────────────┐
│                   LENDING PROTOCOL                          │
│                                                             │
│   Base Operations:  deposit / borrow / repay / liquidate    │
│   Base Parameters:  LTV, HF, Utilization, Close Factor     │
│                                                             │
│   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│   │ Interest │ │ Position │ │ Liquida- │ │  Oracle  │     │
│   │   Rate   │ │  Token   │ │  tion    │ │  System  │     │
│   │  Model   │ │  Model   │ │  Engine  │ │          │     │
│   └──────────┘ └──────────┘ └──────────┘ └──────────┘     │
│   ┌──────────┐ ┌──────────┐                                │
│   │   Risk   │ │Governance│                                │
│   │ Isolation│ │  Model   │                                │
│   │  Model   │ │          │                                │
│   └──────────┘ └──────────┘                                │
└─────────────────────────────────────────────────────────────┘

레버리지 렌딩 컴포넌트 분해처럼:
  leverage lending = flash-loan + aggregator + lending protocol
  lending protocol = base ops + interest model + token model + liquidation + oracle + risk model
```

---

## Module 1: Interest Rate Model — 이자율 모델

```
"utilization에 따라 이자율을 어떻게 결정하는가?"

┌────────────────────────────────────────────────────────────────────┐
│ Model A: Two-Slope Kink (Compound V2, Venus, Radiant)             │
│                                                                    │
│   Rate │                    ╱                                      │
│        │              ────╱  ← jump slope (steep)                  │
│        │         ────      ← kink point                            │
│        │    ────           ← base slope (gentle)                   │
│        └────────────────────────                                   │
│         0%    50%  kink  100%                                      │
│                                                                    │
│   rate = baseRate + util * multiplier             (util ≤ kink)    │
│   rate = normalRate + excess * jumpMultiplier     (util > kink)    │
│                                                                    │
│   특징: 단순, 검증됨, 거버넌스로 파라미터 조정                        │
│   사용: Compound V2/III, Venus, Radiant, 대부분의 포크               │
├────────────────────────────────────────────────────────────────────┤
│ Model B: Optimal Utilization (Aave V3)                             │
│                                                                    │
│   같은 Two-Slope 구조이지만 공식이 다름:                              │
│   rate = base + (util / optimal) * slope1          (util ≤ opt)    │
│   rate = base + slope1 + excess/(1-opt) * slope2   (util > opt)    │
│                                                                    │
│   차이점:                                                           │
│   - "optimal utilization"이라는 개념 명시                            │
│   - 자산별 독립 파라미터 (V3.2+: Pool 레벨 전략, 자산별 파라미터)      │
│   - slope2가 slope1의 10-50x (더 공격적)                             │
│   사용: Aave V3/V4, Spark (non-DAI 자산)                            │
├────────────────────────────────────────────────────────────────────┤
│ Model C: Adaptive Curve IRM (Morpho Blue)                          │
│                                                                    │
│   거버넌스 없이 이자율이 자동으로 수렴:                                │
│   - target utilization에서 벗어나면 지수적으로 조정                    │
│   - util > target → rate 지수적 증가 (시간에 따라)                    │
│   - util < target → rate 지수적 감소                                 │
│                                                                    │
│   특징: self-tuning, 거버넌스 불필요, 시장이 균형 찾음                  │
│   사용: Morpho Blue                                                 │
├────────────────────────────────────────────────────────────────────┤
│ Model D: PI Controller (Silo Finance)                              │
│                                                                    │
│   제어 이론의 PI 컨트롤러를 적용:                                     │
│   - EMA(utilization)과 target의 차이를 기반으로 rate 조정              │
│   - deadband: target 근처에서는 변경 안 함                            │
│   - kink multiplier: 높은 utilization에서 급격히 증가                 │
│                                                                    │
│   특징: 공학적 접근, PID 제어의 PI 버전                               │
│   사용: Silo Finance                                                │
├────────────────────────────────────────────────────────────────────┤
│ Model E: EMA-based Adaptive (Ajna)                                 │
│                                                                    │
│   12시간마다 utilization EMA 기반으로 ±10% 조정:                      │
│   - util EMA > target → rate * 1.1                                 │
│   - util EMA < target → rate * 0.9                                 │
│                                                                    │
│   특징: 오라클 없이 작동, 완전 자율                                    │
│   사용: Ajna Protocol                                               │
├────────────────────────────────────────────────────────────────────┤
│ Model F: Governance-Set Flat Rate (Spark for DAI)                  │
│                                                                    │
│   이자율 = 거버넌스가 결정한 고정값                                    │
│   utilization과 무관하게 일정                                        │
│   D3M(Direct Deposit Module)으로 무한 유동성 제공 가능                 │
│                                                                    │
│   특징: 통화정책 도구, MakerDAO 전용                                  │
│   사용: Spark (DAI 자산)                                             │
├────────────────────────────────────────────────────────────────────┤
│ Model G: Kink IRM — Stateless (Euler V2)                           │
│                                                                    │
│   기본 Kink 모델이지만 각 vault가 독립적으로 선택 가능                  │
│   immutable & stateless (배포 후 변경 불가)                           │
│   vault 생성자가 IRM 컨트랙트 주소를 지정                              │
│                                                                    │
│   특징: pluggable, vault별 독립, immutable                           │
│   사용: Euler V2                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### Interest Rate Model 비교표

```
              거버넌스 의존     자동 조정     복잡도    검증 수준
              ─────────────   ──────────   ────────  ──────────
Kink (A)      높음 (파라미터)   없음         낮음      최고 (2019~)
Optimal (B)   높음             없음         중간      높음 (2022~)
Adaptive (C)  없음             ✅ 자동      높음      중간 (2024~)
PI (D)        낮음             ✅ 자동      높음      낮음 (2023~)
EMA (E)       없음             ✅ 자동      중간      낮음 (2023~)
Flat (F)      최고 (직접설정)   없음         최저      중간
Stateless (G) vault 생성시     없음         낮음      중간 (2024~)
```

---

## Module 2: Position Token Model — 포지션 토큰 모델

```
"예치/부채 포지션을 어떻게 표현하고 이자를 반영하는가?"

┌────────────────────────────────────────────────────────────────────┐
│ Type A: Exchange Rate Token (cToken — Compound V2, Venus)          │
│                                                                    │
│   토큰 수량 고정, exchange rate가 시간에 따라 증가                     │
│                                                                    │
│   deposit 1,000 USDC (rate = 0.02) → 50,000 cUSDC 수령             │
│   1년 후 rate = 0.025 → 50,000 × 0.025 = 1,250 USDC 가치           │
│                                                                    │
│   exchangeRate = (cash + totalBorrows - reserves) / totalSupply    │
│                                                                    │
│   장점: 수량 불변 → DeFi 조합성 우수 (Uniswap LP로 사용 가능)         │
│   단점: 직관적이지 않음 (잔고 = 50,000인데 가치는 1,250?)             │
├────────────────────────────────────────────────────────────────────┤
│ Type B: Rebasing Token (aToken — Aave, Spark, Radiant)             │
│                                                                    │
│   1:1 페깅, 잔고 자체가 시간에 따라 증가 (rebase)                     │
│                                                                    │
│   deposit 1,000 USDC → 1,000 aUSDC 수령                            │
│   1년 후 → 잔고가 1,050 aUSDC로 자동 증가                            │
│                                                                    │
│   내부: scaledBalance × liquidityIndex = actual balance             │
│                                                                    │
│   장점: 직관적 (잔고 = 자산 가치)                                     │
│   단점: 일부 DeFi 프로토콜과 호환성 문제 (rebase 미지원)               │
├────────────────────────────────────────────────────────────────────┤
│ Type C: ERC-4626 Vault Shares (Morpho, Euler V2)                   │
│                                                                    │
│   표준화된 토큰화 금고 인터페이스 (EIP-4626)                           │
│                                                                    │
│   deposit → shares 수령 (share price 증가)                          │
│   withdraw → shares 제출, underlying 수령                           │
│                                                                    │
│   convertToAssets(shares) = shares × totalAssets / totalShares     │
│                                                                    │
│   장점: ERC-4626 표준 → 모든 DeFi와 호환                             │
│   단점: cToken과 수학적으로 동일 (표준화만 다름)                       │
├────────────────────────────────────────────────────────────────────┤
│ Type D: Internal Accounting Only (Compound III, Liquity)           │
│                                                                    │
│   별도 토큰 없음 — 컨트랙트 내부 mapping으로만 추적                    │
│                                                                    │
│   Compound III: signed integer (양수 = 예치, 음수 = 대출)            │
│   Liquity: Trove 구조체에 collateral/debt 기록                      │
│                                                                    │
│   장점: 단순, 공격 표면 최소                                          │
│   단점: DeFi 조합성 없음 (별도 wrapper 필요)                          │
├────────────────────────────────────────────────────────────────────┤
│ Debt Token 유형 (부채 추적)                                          │
│                                                                    │
│   ① vToken (Aave): ERC-20 부채 토큰, transfer 불가                  │
│   ② dToken (Euler V2): ERC-4626 기반 부채 추적                      │
│   ③ mapping (Compound V2): accountBorrows[user]                    │
│   ④ 없음 (Compound III): 내부 signed int                            │
│   ⑤ 없음 (Liquity): Trove.debt 필드                                │
│   ⑥ borrow shares (Morpho Blue): 내부 share 기반                   │
└────────────────────────────────────────────────────────────────────┘
```

### Position Token 비교표

```
                  Supply Token     Debt Token       이자 반영 방식
                  ─────────────   ──────────────   ──────────────────
Compound V2       cToken (A)       mapping          exchangeRate ↑
Venus             vToken (A)       mapping          exchangeRate ↑
Aave V3           aToken (B)       vToken           liquidityIndex ↑
Spark             spToken (B)      vToken fork      liquidityIndex ↑
Radiant           rToken (B)       vToken fork      liquidityIndex ↑
Morpho Blue       내부 shares       내부 shares       share price ↑
Euler V2          ERC-4626 (C)     dToken           share price ↑
Compound III      내부 (D)          내부 (D)          signed int 변동
Silo              ERC-4626 (C)     ERC-20R          share price ↑
Ajna              LPB (내부+NFT)    내부              내부 계산
```

---

## Module 3: Liquidation Engine — 청산 엔진

```
"담보 부족 시 어떻게 포지션을 정리하는가?"

┌────────────────────────────────────────────────────────────────────┐
│ Engine A: Fixed Bonus Liquidation (Compound V2, Venus)             │
│                                                                    │
│   HF < 1 → 청산자가 부채의 50% 상환 → 담보 + 고정 보너스 수령         │
│                                                                    │
│   보너스: 프로토콜 전체 고정 (Compound: 8%, Venus: 10%)               │
│   Close Factor: 50% 고정                                           │
│                                                                    │
│   장점: 단순, 예측 가능                                               │
│   단점: 보너스 고정 → MEV 경쟁 → 가스 낭비, 차입자에게 불리              │
├────────────────────────────────────────────────────────────────────┤
│ Engine B: Per-Asset Bonus (Aave V3, Spark, Radiant)                │
│                                                                    │
│   HF < 1 → 자산별 다른 보너스 + 동적 Close Factor                    │
│                                                                    │
│   보너스: 자산별 설정 (ETH: 5%, volatile: 10-15%)                    │
│   Close Factor: HF < 0.95 → 100% (전액 청산 가능)                   │
│                HF ≥ 0.95 → 50%                                     │
│                                                                    │
│   장점: 자산 리스크에 맞춘 보너스, 위험 시 신속 청산                    │
│   단점: 여전히 MEV 경쟁 존재                                          │
├────────────────────────────────────────────────────────────────────┤
│ Engine C: Variable Bonus — Dutch Auction-like (Aave V4)            │
│                                                                    │
│   보너스가 HF에 따라 연속적으로 변동:                                   │
│   HF = 0.95 → 보너스 2%                                            │
│   HF = 0.50 → 보너스 10%                                           │
│   + Target Health Factor (청산 후 목표 HF로 복원)                    │
│   + Dust Prevention ($1,000 이하 잔여 → 전액 청산)                   │
│                                                                    │
│   장점: 시장이 적정 보너스 결정, 과도 청산 방지                         │
│   단점: 아직 미배포 (V4 개발 중)                                      │
├────────────────────────────────────────────────────────────────────┤
│ Engine D: Dutch Auction (Euler V1)                                 │
│                                                                    │
│   시간이 지나면서 할인율 증가:                                         │
│   T=0:   담보를 시장가에 제공                                         │
│   T=5m:  담보를 3% 할인에 제공                                       │
│   T=30m: 담보를 15% 할인에 제공                                      │
│                                                                    │
│   첫 번째 수익성 있는 청산자가 실행 → 자동으로 최소 보너스 결정           │
│                                                                    │
│   장점: 차입자에게 유리 (최소 보너스), MEV 감소                        │
│   단점: 시간 지연 → 급락 시 위험                                      │
├────────────────────────────────────────────────────────────────────┤
│ Engine E: Reverse Dutch Auction — Soft Liquidation (Euler V2)      │
│                                                                    │
│   discount = f(health score):                                      │
│   health 0.99 → 1% bonus                                          │
│   health 0.95 → 5% bonus                                          │
│   health 0.50 → 50% bonus                                         │
│                                                                    │
│   연속적, 비례적 → "soft" liquidation                                │
│   장점: 점진적 청산, MEV 감소                                         │
├────────────────────────────────────────────────────────────────────┤
│ Engine F: Absorption (Compound III)                                │
│                                                                    │
│   2단계 분리:                                                        │
│   ① absorb(): 프로토콜이 즉시 부채 흡수 + 담보 몰수                    │
│   ② buyCollateral(): 나중에 할인 가격에 담보 매각                     │
│                                                                    │
│   부채 해소 ≠ 담보 매각 (시간적 분리)                                  │
│   장점: 즉시 부채 해소, 시장 상황 좋을 때 담보 매각 가능                 │
│   단점: 프로토콜 reserve 부담, bad debt 리스크                        │
├────────────────────────────────────────────────────────────────────┤
│ Engine G: Stability Pool (Liquity V1/V2)                           │
│                                                                    │
│   사전 적립 풀에서 자동 청산:                                          │
│   ① SP 참여자가 LUSD/BOLD 예치 (사전 적립)                            │
│   ② 청산 시 SP의 LUSD/BOLD 소각 → 참여자에게 담보 분배                 │
│   ③ SP 부족 시 → 다른 Trove에 부채+담보 재분배                        │
│                                                                    │
│   장점: 즉시 청산 (봇 불필요), 110% MCR 가능                          │
│   단점: SP 규모에 의존, 별도 인센티브 필요                              │
├────────────────────────────────────────────────────────────────────┤
│ Engine H: Bond-Based Dutch Auction (Ajna)                          │
│                                                                    │
│   청산 개시자(kicker)가 bond 예치 필수:                                │
│   ① kicker가 1-3% bond 예치 → 경매 시작                              │
│   ② 가격이 256x reference에서 시작, 72시간 동안 지수적 감소            │
│   ③ Neutral Price 기준으로 bond 보상/몰수 결정                        │
│                                                                    │
│   장점: 청산자에게 skin in the game, 불공정 청산 방지                   │
│   단점: 복잡, bond 자본 필요                                          │
└────────────────────────────────────────────────────────────────────┘
```

### Liquidation Engine 비교표

```
                  방식                보너스 결정      즉시성    차입자 보호
                  ─────────────────  ──────────────  ────────  ──────────
Fixed (A)         외부 청산자          고정 (8-10%)     빠름      낮음
Per-Asset (B)     외부 청산자          자산별 고정      빠름      중간
Variable (C)      외부 청산자          HF 기반 동적     빠름      높음
Dutch Auction (D) 외부 청산자          시간 기반 동적   느림      높음
Soft (E)          외부 청산자          health 비례      빠름      높음
Absorption (F)    프로토콜 자동        할인 판매        즉시      중간
Stability Pool(G) 사전 적립 풀         자동             즉시      중간
Bond Auction (H)  bond+외부 청산자     시간 기반 동적   느림      최고
```

---

## Module 4: Oracle System — 오라클 시스템

```
"자산 가격을 어디서 어떻게 가져오는가?"

┌────────────────────────────────────────────────────────────────────┐
│ Type A: Single Source — Chainlink Only                             │
│                                                                    │
│   Chainlink AggregatorV3 직접 연동                                  │
│   latestRoundData() → (price, updatedAt)                           │
│   staleness check + sanity check                                   │
│                                                                    │
│   사용: Compound III, Radiant                                      │
│   장점: 단순, 검증됨 (Chainlink 보안 모델)                            │
│   단점: 단일 장애점, Chainlink 의존                                   │
├────────────────────────────────────────────────────────────────────┤
│ Type B: Primary + Fallback                                         │
│                                                                    │
│   주 오라클 실패 시 자동 전환:                                         │
│   Chainlink (primary) → Tellor (fallback)                          │
│   4시간 미응답 → 자동 전환 → 복구 시 원복                              │
│                                                                    │
│   사용: Liquity V1                                                  │
│   장점: 가용성 높음, 탈중앙화                                         │
│   단점: fallback 오라클의 신뢰도 차이                                  │
├────────────────────────────────────────────────────────────────────┤
│ Type C: Multi-Source Cross-Validation (Resilient Oracle)           │
│                                                                    │
│   3단계 검증:                                                        │
│   ① Main (Chainlink) → 가격 조회                                    │
│   ② Pivot (RedStone/Pyth) → 상한/하한 범위 검증                      │
│   ③ Fallback (Binance Oracle) → 백업                               │
│   범위 벗어나면 → invalidate                                         │
│                                                                    │
│   사용: Venus V4                                                    │
│   장점: 오라클 조작 방어 강화                                          │
│   단점: 복잡도 증가, 가스 비용                                         │
├────────────────────────────────────────────────────────────────────┤
│ Type D: Oracle-Agnostic (Pluggable)                                │
│                                                                    │
│   시장 생성 시 오라클 선택 (immutable):                                │
│   Chainlink, RedStone, Pyth, Uniswap TWAP, 커스텀 등                │
│   IPriceOracle 인터페이스만 구현하면 됨                                │
│                                                                    │
│   사용: Morpho Blue, Euler V2                                       │
│   장점: 유연, 새 오라클 즉시 지원                                      │
│   단점: 시장마다 오라클 품질이 다를 수 있음                              │
├────────────────────────────────────────────────────────────────────┤
│ Type E: Oracle-Free — Lender-Set Pricing                           │
│                                                                    │
│   외부 오라클 없음!                                                   │
│   대출자(lender)가 "이 가격에 빌려주겠다"고 예치 (price bucket)         │
│   ~7,000개 사전 정의 가격 구간 (50bps 간격)                           │
│   LUP (Lowest Utilized Price) = 시장 합의 가격                       │
│                                                                    │
│   사용: Ajna                                                        │
│   장점: 완전 탈중앙화, 오라클 조작 불가                                 │
│   단점: 비효율적 가격 발견, 참여자 합리성에 의존                        │
├────────────────────────────────────────────────────────────────────┤
│ Type F: Protocol Oracle (Aave V3)                                  │
│                                                                    │
│   AaveOracle 컨트랙트가 중앙에서 관리:                                │
│   asset → Chainlink feed 매핑                                      │
│   거버넌스로 오라클 소스 변경 가능                                      │
│   일부 자산은 커스텀 오라클 (sDAI, LST 등)                             │
│                                                                    │
│   사용: Aave V3, Spark                                              │
│   장점: 통합 관리, 자산별 커스터마이즈                                  │
│   단점: 거버넌스 의존                                                  │
└────────────────────────────────────────────────────────────────────┘
```

---

## Module 5: Risk Isolation Model — 리스크 격리 모델

```
"한 자산의 문제가 다른 자산에 영향을 미치는가?"

┌────────────────────────────────────────────────────────────────────┐
│ Model A: Shared Pool (Compound V2, Aave V2)                       │
│                                                                    │
│   ┌──────────────────────────────────────┐                         │
│   │          하나의 풀                     │                         │
│   │  ETH   USDC   LINK   UNI   SHIB     │                         │
│   │  $5B   $3B    $500M  $200M  $50M     │                         │
│   │                                      │                         │
│   │  → SHIB exploit 시 전체 풀 영향 가능  │                         │
│   └──────────────────────────────────────┘                         │
│                                                                    │
│   장점: 유동성 통합, 자본 효율성 최고                                  │
│   단점: 한 자산 리스크가 전체로 전파                                    │
├────────────────────────────────────────────────────────────────────┤
│ Model B: Shared Pool + Isolation Mode (Aave V3)                    │
│                                                                    │
│   ┌──────────────────────────────────────┐                         │
│   │          메인 풀                       │                         │
│   │  ETH   USDC   LINK   UNI            │                         │
│   │  ─────────────────────────           │                         │
│   │  │ Isolation: SHIB (한도 $10M) │     │                         │
│   │  └────────────────────────────┘      │                         │
│   └──────────────────────────────────────┘                         │
│                                                                    │
│   Isolation Mode: 신규/위험 자산은 격리 등록 (대출 한도 제한)           │
│   E-Mode: 상관 자산끼리 높은 LTV (stETH/ETH: 97%)                   │
│   장점: 검증 자산은 효율적, 위험 자산은 격리                            │
│   단점: 같은 풀 안이므로 완전한 격리는 아님                             │
├────────────────────────────────────────────────────────────────────┤
│ Model C: Hub & Spoke (Aave V4)                                     │
│                                                                    │
│   ┌─────────────────────────────┐                                  │
│   │       Liquidity Hub         │                                  │
│   │    (통합 유동성, credit line) │                                  │
│   └──┬──────────┬──────────┬───┘                                  │
│      │          │          │                                       │
│   Spoke A    Spoke B    Spoke C                                    │
│   Main       Stable     RWA                                        │
│   Market     Market     Market                                     │
│                                                                    │
│   장점: 유동성 통합 + 물리적 리스크 격리                                │
│   단점: Hub = 단일 장애점                                             │
├────────────────────────────────────────────────────────────────────┤
│ Model D: Fully Isolated — Per-Pair (Silo Finance)                  │
│                                                                    │
│   ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐                         │
│   │LINK  │  │UNI   │  │SHIB  │  │AAVE  │                         │
│   │+ETH  │  │+ETH  │  │+ETH  │  │+ETH  │  ← 각 자산이 Bridge     │
│   │      │  │      │  │      │  │      │    Asset과만 짝           │
│   └──────┘  └──────┘  └──────┘  └──────┘                         │
│                                                                    │
│   SHIB exploit → SHIB silo만 영향, 나머지 무관                       │
│   Bridge Asset (ETH, XAI)가 silo 간 연결 역할                       │
│   장점: 최강 리스크 격리                                               │
│   단점: 유동성 분산, 자본 효율성 낮음                                   │
├────────────────────────────────────────────────────────────────────┤
│ Model E: Modular Vaults (Euler V2)                                 │
│                                                                    │
│   각 vault = 독립된 ERC-4626 렌딩 마켓                                │
│   vault 생성자가 모든 파라미터 결정:                                    │
│   - 어떤 자산 허용, 어떤 IRM, 어떤 oracle, 어떤 LTV                   │
│   EVC (Ethereum Vault Connector)로 vault 간 연결                    │
│   → vault A의 position을 vault B의 담보로 사용 가능                   │
│                                                                    │
│   장점: 최대 유연성 + 격리 + 조합성                                    │
│   단점: vault 품질 편차, 사용자가 리스크 판단 필요                      │
├────────────────────────────────────────────────────────────────────┤
│ Model F: Permissionless Markets (Morpho Blue)                      │
│                                                                    │
│   단일 컨트랙트(~650 lines) 안에 모든 시장 존재                        │
│   각 시장 = (collateral, loan, oracle, IRM, LLTV) 튜플               │
│   시장 간 완전 격리 (같은 컨트랙트지만 독립 accounting)                 │
│   MetaMorpho Vault(ERC-4626)가 여러 시장에 자동 분배                  │
│                                                                    │
│   장점: permissionless 생성 + 격리 + curator 추상화                   │
│   단점: 시장 품질 편차                                                 │
└────────────────────────────────────────────────────────────────────┘
```

---

## Module 6: Governance Model — 거버넌스 모델

```
┌────────────────────────────────────────────────────────────────────┐
│ Full Governance (Compound, Aave, Venus)                            │
│   거버넌스 토큰 + 투표 + Timelock + 가디언                            │
│   파라미터 변경, 자산 추가, 업그레이드 모두 거버넌스                     │
├────────────────────────────────────────────────────────────────────┤
│ Governance-Minimized (Euler V2, Morpho Blue)                       │
│   프로토콜 코어는 immutable                                          │
│   vault/시장 생성자가 개별 파라미터 결정                                │
│   프로토콜 수준 거버넌스 최소화                                        │
├────────────────────────────────────────────────────────────────────┤
│ Governance-Free / Immutable (Liquity, Ajna)                        │
│   컨트랙트 배포 후 변경 불가                                          │
│   admin key 없음, 업그레이드 없음                                     │
│   "코드가 법" — 완전한 탈중앙화                                       │
└────────────────────────────────────────────────────────────────────┘
```

---

## 프로토콜 분해 매트릭스 / Protocol Decomposition Matrix

```
┌──────────────┬─────────────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐
│ Protocol     │ Interest    │ Position     │ Liquidation  │ Oracle       │ Risk         │ Governance   │
│              │ Rate Model  │ Token Model  │ Engine       │ System       │ Isolation    │ Model        │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Compound V2  │ Kink (A)    │ cToken (A)   │ Fixed (A)    │ Protocol (F) │ Shared (A)   │ Full Gov     │
│              │             │ + mapping    │ 8% bonus     │              │              │ COMP         │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Compound III │ Kink (A)    │ Internal (D) │ Absorb (F)   │ Chainlink(A) │ Single-asset │ Full Gov     │
│              │ decoupled   │ signed int   │ 2-step       │              │ per deploy   │ COMP         │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Aave V3      │ Optimal (B) │ aToken (B)   │ Per-Asset(B) │ Protocol (F) │ Isolation(B) │ Full Gov     │
│              │             │ + vToken     │ dynamic CF   │ Chainlink    │ + E-Mode     │ AAVE         │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Aave V4      │ Optimal (B) │ aToken (B)   │ Variable (C) │ Protocol (F) │ Hub&Spoke(C) │ Full Gov     │
│              │ +UserPremium│ + vToken     │ HF-based     │              │              │ AAVE         │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Euler V2     │ Kink (G)    │ ERC-4626 (C) │ Soft (E)     │ Pluggable(D) │ Vaults (E)   │ Gov-Min      │
│              │ pluggable   │ + dToken     │ reverse DA   │ ERC-7726     │ + EVC        │              │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Morpho Blue  │ Adaptive(C) │ Internal     │ LTV+bonus    │ Pluggable(D) │ Per-market(F)│ Gov-Min      │
│              │ or Fixed    │ + ERC-4626   │ +pre-liq     │              │              │              │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Silo         │ PI Ctrl (D) │ ERC-4626 (C) │ Partial      │ Pluggable(D) │ Per-pair (D) │ Gov-Min      │
│              │             │ + ERC-20R    │ hook-based   │              │ bridge asset │              │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Ajna         │ EMA (E)     │ LPB (custom) │ Bond DA (H)  │ None (E)     │ Per-pool     │ Gov-Free     │
│              │             │              │              │ lender-set   │              │ Immutable    │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Venus        │ Kink (A)    │ vToken (A)   │ Fixed (A)    │ Resilient(C) │ Isolated     │ Full Gov     │
│              │             │ + mapping    │ 10% bonus    │ 3-source     │ Pools (V4)   │ XVS          │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Spark        │ Flat (F)    │ spToken (B)  │ Per-Asset(B) │ Chainlink(A) │ Shared (A)   │ MakerDAO     │
│              │ for DAI     │ + vToken     │ Aave V3 fork │ + custom     │ Aave V3 fork │ Gov          │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Radiant      │ Optimal (B) │ rToken (B)   │ Per-Asset(B) │ Chainlink(A) │ Shared (A)   │ Full Gov     │
│              │ Aave V2     │ + vToken     │ Aave V2 fork │              │ + xchain     │ RDNT         │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Liquity V1   │ One-time    │ None         │ SP (G)       │ CL+Tellor(B) │ Per-trove    │ Gov-Free     │
│              │ fee only    │ (Trove)      │ +redistrib   │              │              │ Immutable    │
├──────────────┼─────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Liquity V2   │ User-set    │ None         │ SP (G)       │ Per-branch   │ Per-branch   │ Gov-Free     │
│              │ rate        │ (Trove)      │ +redistrib   │              │              │ Immutable    │
└──────────────┴─────────────┴──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘
```

---

## 조합 패턴 분석 / Composition Patterns

```
패턴 1: "Compound Fork" — 가장 많이 포크된 조합
  Interest: Kink + Position: cToken + Liquidation: Fixed + Oracle: Chainlink
  → Venus, Benqi, Cream Finance, Iron Bank...
  → 검증됨, 단순, 빠른 배포 가능

패턴 2: "Aave Fork" — 엔터프라이즈급 조합
  Interest: Optimal + Position: aToken+vToken + Liquidation: Per-Asset + Oracle: Protocol
  → Spark, Radiant, Seamless, Granary...
  → 기능 풍부, 멀티체인, 복잡도 높음

패턴 3: "New Wave" — 거버넌스 최소화 + 모듈형
  Interest: Pluggable + Position: ERC-4626 + Liquidation: Soft/DA + Oracle: Pluggable
  → Euler V2, Morpho Blue
  → permissionless 시장 생성, 최대 유연성

패턴 4: "Trust-Minimized" — 완전 탈중앙화
  Interest: 자동 조정 + Position: 내부 + Liquidation: 자동 풀 + Oracle: 없음/최소
  → Liquity, Ajna
  → immutable, admin 없음, 오라클 의존 최소

패턴 5: "Risk-First" — 격리 우선
  Interest: 자동/Kink + Position: ERC-4626 + Liquidation: 다양 + Oracle: Pluggable
  → Silo, Compound III
  → 리스크 격리가 최우선, 자본 효율성 트레이드오프
```

### 레버리지 렌딩 컴포넌트 분해와 비교 / vs Leverage Lending Decomposition

```
레버리지 렌딩 (Sui):
  flash-loan     → Scallop, Navi
  aggregator     → 7k
  lending        → Suilend, Navi, etc.

  = "어떤 서비스를 조합해서 전략을 만드는가"

렌딩 프로토콜 분해:
  interest model → Kink, Optimal, Adaptive, PI, EMA, Flat
  position token → cToken, aToken, ERC-4626, Internal
  liquidation    → Fixed, Per-Asset, Dutch Auction, Absorption, SP
  oracle         → Chainlink, Multi-source, Pluggable, None
  risk model     → Shared, Isolated, Hub&Spoke, Per-pair, Vaults

  = "어떤 모듈을 조합해서 프로토콜을 만드는가"

같은 분해 사고방식:
  레버리지 전략 = flash-loan(어디서) + swap(어디서) + lending(어디서)
  렌딩 프로토콜 = interest(어떤 모델) + token(어떤 방식) + liquidation(어떤 엔진) + ...
```

---

## 모듈 선택 가이드 / Module Selection Guide

```
프로토콜을 설계한다면, 어떤 조합을 선택해야 하는가?

Q: 검증된 안전성이 최우선?
  → Kink IRM + cToken + Fixed Liquidation + Chainlink (Compound V2 패턴)

Q: 기능이 풍부하고 멀티체인?
  → Optimal IRM + aToken/vToken + Per-Asset Liq + Protocol Oracle (Aave V3 패턴)

Q: 누구나 시장을 만들 수 있어야?
  → Pluggable IRM + ERC-4626 + Soft Liq + Pluggable Oracle (Euler V2 / Morpho 패턴)

Q: 완전한 탈중앙화, 거버넌스 0?
  → Auto-adjust IRM + Internal + SP/Bond Liq + Oracle-free (Liquity / Ajna 패턴)

Q: 한 자산의 해킹이 절대 다른 자산에 영향 없어야?
  → PI IRM + ERC-4626 + Partial Liq + Pluggable Oracle (Silo 패턴)

Q: L2에서 가스 효율 최우선?
  → Stateless IRM + ERC-4626 + Soft Liq + Pluggable Oracle (Euler V2 패턴)
```
