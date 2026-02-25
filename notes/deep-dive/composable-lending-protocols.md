# 차세대 렌딩 프로토콜: 조합형 아키텍처 비교
# Next-Gen Lending Protocols: Composable Architecture Comparison

> Euler V2, Silo Finance, Ajna Protocol 의 모듈형/격리형/오라클프리 설계 비교
> Comparing modular / isolated / oracle-free designs of Euler V2, Silo Finance, and Ajna Protocol

> 참고 / References:
> - [Euler Docs](https://docs.euler.finance/introduction/)
> - [Euler EVC](https://docs.euler.finance/concepts/core/evc/)
> - [Euler Price Oracle](https://docs.euler.finance/euler-price-oracle/)
> - [Euler Lite Paper](https://docs.euler.finance/lite-paper/)
> - [Silo Protocol Design](https://silopedia.silo.finance/the-silo-protocol/protocol-design)
> - [Silo V2 Docs](https://docs.silo.finance/docs/developers/protocol-overview/architecture/)
> - [Silo Bridge Assets](https://silopedia.silo.finance/the-silo-protocol/protocol-design/base-and-bridge-assets)
> - [Ajna Whitepaper](https://www.ajna.finance/pdf/Ajna_Protocol_Whitepaper_01-11-2024.pdf)
> - [Ajna FAQs](https://faqs.ajna.finance/faqs/general)
> - [MixBytes: Ajna](https://mixbytes.io/blog/modern-defi-lending-protocols-how-its-made-ajna)
> - [MixBytes: Euler V2](https://mixbytes.io/blog/modern-defi-lending-protocols-how-its-made-euler-v2)

---

## 종합 비교 요약 / Structured Summary

```
┌──────────────────┬──────────────────────┬──────────────────────┬──────────────────────┐
│                  │ Euler V2             │ Silo Finance         │ Ajna Protocol        │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ Base             │ Isolated (Modular    │ Isolated (Pair-based │ Pool-based           │
│ 기반 구조         │ Vault per asset)     │ markets)             │ (Peer-to-Pool)       │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ Interest Model   │ Kink IRM (linear     │ Dynamic PI Controller│ EMA-based adaptive   │
│ 이자율 모델       │ kink, configurable)  │ (+ kink multiplier)  │ (10% step, 12h cycle)│
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ Deposit Token    │ ERC-4626 vault shares│ ERC-4626 vault shares│ LPB (Liquidity       │
│ 예치 토큰         │ (eToken)             │ (sToken + debt token)│ Provider Balance)    │
│                  │                      │                      │ + optional NFT       │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ Liquidation      │ Reverse Dutch Auction│ Partial liquidation  │ Dutch Auction +      │
│ 청산 방식         │ (soft liquidation)   │ (hook-based module)  │ Bond mechanism       │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ Oracle           │ Adapter pattern      │ Oracle-agnostic      │ NONE (oracle-free)   │
│ 오라클           │ (ERC-7726, router)   │ (Chainlink, Pyth...) │ Lender-set prices    │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ Risk Model       │ Isolated per vault   │ Isolated per pair    │ Isolated per pool    │
│ 리스크 모델       │ (vault creator sets) │ (bridge asset link)  │ (no shared risk)     │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ Governance       │ Governance-minimized │ DAO governed         │ ZERO governance      │
│ 거버넌스          │ (vault-level choice) │ (market creation     │ (fully immutable)    │
│                  │                      │  via vote)           │                      │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ Unique Feature   │ EVC (vault-to-vault  │ Bridge Assets        │ Oracle-free +        │
│ 핵심 차별점       │ collateral network)  │ (risk containment    │ Bond-based           │
│                  │                      │  via ETH/XAI pairs)  │ liquidation          │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ Permissionless   │ Yes (anyone deploys  │ Partial (DAO vote    │ Yes (anyone creates  │
│ 시장 생성         │ vaults via EVK)      │ for new silos)       │ pools, like Uniswap) │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ NFT Collateral   │ No (ERC-20 only)     │ No (ERC-20 only)     │ Yes (ERC-721 +      │
│ NFT 담보         │                      │                      │ ERC-20 supported)    │
└──────────────────┴──────────────────────┴──────────────────────┴──────────────────────┘
```

---

## 1. Euler V2 (Post-Hack Relaunch)

> 2023년 $197M 해킹 이후, 31회 감사를 거쳐 완전히 재설계된 모듈형 렌딩 프로토콜
> Fully redesigned modular lending protocol after $197M hack, with 31 audits

### 아키텍처 개요 / Architecture Overview

```
Euler V2 = EVC (Ethereum Vault Connector) + EVK (Euler Vault Kit) + Price Oracles

세 가지 핵심 레이어로 구성:
Three core layers:

1. EVC (Ethereum Vault Connector)
   = 볼트 간 통신을 중재하는 불변(immutable) 프리미티브
   = Immutable primitive mediating vault-to-vault communication

2. EVK (Euler Vault Kit)
   = ERC-4626 볼트를 퍼미션리스하게 배포하는 도구
   = Toolkit for permissionless ERC-4626 vault deployment

3. Euler Price Oracles
   = IPriceOracle 인터페이스 기반 어댑터 라이브러리
   = Adapter library built on IPriceOracle interface (ERC-7726)
```

### 1.1 EVC (Ethereum Vault Connector) 아키텍처

```
                    사용자 (User)
                        │
                        │ batch([op1, op2, op3])
                        ▼
              ┌──────────────────────┐
              │  EthereumVault       │ ← 불변(immutable), 거버넌스 없음
              │  Connector (EVC)     │   No governance, zero fees
              │                      │   "True public good for DeFi"
              │  - Sub-accounts      │
              │  - Operators         │
              │  - Batch execution   │
              │  - Deferred checks   │
              └──────────┬───────────┘
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
   ┌────────────┐ ┌────────────┐ ┌────────────┐
   │  Vault A   │ │  Vault B   │ │  Vault C   │  ← 각각 독립된 ERC-4626 볼트
   │ (USDC)     │ │ (ETH)      │ │ (wstETH)   │     Independent lending markets
   │            │ │            │ │            │
   │ Collateral │←│ Borrows    │←│ Collateral │  ← EVC가 볼트간 담보 관계를 관리
   │ accepted   │ │ against A  │ │ accepted   │     EVC manages cross-vault collateral
   └────────────┘ └────────────┘ └────────────┘

핵심 개념:
Key concepts:

1. Sub-accounts (서브 계정):
   → 하나의 EOA에서 최대 256개의 독립 포지션 생성 가능
   → Up to 256 isolated positions per EOA
   → 각 서브 계정은 별도의 담보/부채 포지션
   → Each sub-account has its own collateral/debt position

2. Batch Execution (배치 실행):
   → 여러 볼트에 대한 작업을 단일 트랜잭션으로 실행
   → Multiple vault operations in a single transaction
   → 유동성/담보 검증을 배치 끝에서 한 번만 수행 (deferred checks)
   → Liquidity/collateral checks deferred to end of batch

3. Operators (오퍼레이터):
   → 외부 컨트랙트가 사용자 계정을 대신 조작 가능
   → External contracts can act on behalf of user accounts
   → 인텐트 기반 청산, 스탑로스 등 구현 가능
   → Enables intent-based liquidations, stop-losses, etc.
```

### 1.2 볼트(Vault) = 독립 렌딩 마켓 / Vaults as Independent Markets

```
EVK로 배포되는 각 볼트:
Each vault deployed via EVK:

┌─────────────────────────────────────────────────────┐
│  EVault (ERC-4626 + Borrowing)                      │
│                                                     │
│  하나의 자산만 보유 (single underlying asset)          │
│  Holds only ONE asset type                          │
│                                                     │
│  asset categories:                                  │
│    ├─ cash: 볼트에 실제 보관된 토큰                    │
│    │        Tokens actually held in vault            │
│    └─ totalBorrows: 미상환 대출 + 누적 이자            │
│                     Outstanding loans + accrued int  │
│                                                     │
│  exchangeRate = (cash + totalBorrows) / totalShares  │
│  → eToken 1개의 가치 = 위 비율                        │
│                                                     │
│  Vault creator configures:                          │
│    - Oracle (어떤 가격 피드 사용?)                     │
│    - IRM (어떤 이자율 모델?)                          │
│    - LTV / Liquidation threshold                    │
│    - Collateral types (어떤 볼트를 담보로 인정?)       │
│    - Governance model (governed or ungoverned)       │
│    - Hook targets (커스텀 로직)                       │
└─────────────────────────────────────────────────────┘

볼트 유형:
Vault types:

  Governed Vault → 리스크 매니저가 파라미터 관리
                   Risk manager controls parameters
                   (일반 사용자에게 적합 / Suitable for passive lenders)

  Ungoverned Vault → 배포 후 파라미터 불변
                     Immutable after deployment
                     (코드 레벨 신뢰만 필요 / Only trust the code)

  Nested Vault → 다른 eToken을 underlying으로 사용
                 Uses another eToken as underlying
                 (수익률 레이어링 가능 / Yield layering)
```

### 1.3 이자율 모델 / Interest Rate Model

```
Euler V2는 볼트별로 IRM을 자유롭게 선택 가능:
Euler V2 allows each vault to choose its own IRM:

[기본 제공] Kink IRM (Linear Kink Model):

  이자율
  (Rate)
    │
    │                              ╱ ← 킹크 이후: 급격한 기울기
    │                            ╱    (Above kink: steep slope)
    │                          ╱
    │                     ───·╱  ← 킹크 포인트 (Kink point)
    │                 ───·     (target utilization)
    │             ───·
    │         ───·    ← 킹크 이전: 완만한 기울기
    │     ───·         (Below kink: gradual slope)
    │ ───·
    │·
    └────────────────────────────────── 사용률 (Utilization)
    0%          kink (예: 80%)      100%

  파라미터 (배포 시 설정, 이후 불변):
  Parameters (set at deployment, immutable):

    baseRate      = 사용률 0%일 때의 기본 이자율
    kinkRate      = 킹크 포인트에서의 이자율
    maxRate       = 사용률 100%일 때의 최대 이자율
    kink          = 목표 사용률 (예: 80%)

  특징:
    - Stateless (상태 없음) — 순수하게 현재 사용률만으로 이자율 계산
    - Immutable (불변) — 배포 후 파라미터 변경 불가
    - Kink IRM Factory를 통해 쉽게 배포 가능

[커스텀 IRM도 가능]:
  → IRMLinearKink 외에 커스텀 IRM 배포 가능
  → IPriceOracle 처럼 IRM도 인터페이스 기반
  → 볼트 생성자가 시장 특성에 맞는 IRM 선택
```

### 1.4 청산 메커니즘 / Liquidation Mechanism

```
Reverse Dutch Auction (역 네덜란드 경매):

  건강도     청산 보너스
  (Health)   (Discount)
    │
  1.0 ─────── 0%      ← 건강도 1.0 = 보너스 없음
    │ ╲                   (Health 1.0 = no bonus)
  0.99 ────── ~1%     ← 약간 미달 = 최소 보너스
    │   ╲                 (Slightly unhealthy = small bonus)
  0.95 ────── ~5%     ← 보너스 점진적 증가
    │     ╲               (Bonus increases gradually)
  0.90 ────── ~10%
    │       ╲
  0.80 ────── ~20%    ← 깊은 부실 = 큰 보너스
    │         ╲           (Deeply underwater = large bonus)
    ▼          ╲
  0.00 ────── max%    ← 볼트 설정 최대값
                          (Max set by vault config)

핵심 원리:
Key principles:

  1. 비례적 페널티 (Proportional Penalty):
     → health 0.99 = 1% 보너스, health 0.95 = 5% 보너스
     → 약간만 미달인 포지션에 과도한 청산 안 됨
     → Slightly unhealthy positions not excessively penalized

  2. Soft Liquidation (부분 청산):
     → 포지션 전체가 아닌 일부만 청산 가능
     → Progressive unwinding, not cliff-edge events
     → 차입자가 operator를 통해 커스텀 부분 청산/스탑로스 설정 가능

  3. Free-Market Liquidation (V2 신규):
     → 볼트 생성자가 커스텀 청산 플로우 구현 가능
     → 기본값은 V1의 reverse Dutch auction 유지
     → 고급 사용자는 intent 기반 청산 선택 가능

  vs Aave/Compound:
    Aave: 고정 보너스 (ETH 5%, volatile 10%+) + closeFactor
    Compound: 고정 8% 보너스 + 50% closeFactor
    Euler V2: 건강도에 비례하는 동적 보너스 → 차입자에게 더 공정
              Dynamic bonus proportional to health → fairer for borrowers
```

### 1.5 오라클 시스템 / Oracle System

```
Euler Price Oracle = Adapter Pattern (ERC-7726 호환)

                    EVault
                      │
                      │ getQuote(amount, base, quote)
                      ▼
              ┌───────────────┐
              │  EulerRouter  │ ← 라우터: 자산별 어댑터로 위임
              │  (per vault)  │    Routes to asset-specific adapter
              └───────┬───────┘
                      │
        ┌─────────────┼──────────────┐
        ▼             ▼              ▼
  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │Chainlink │  │  Pyth    │  │ Uniswap  │  ← 벤더별 어댑터
  │ Adapter  │  │ Adapter  │  │V3 Adapter│     Vendor-specific adapters
  └──────────┘  └──────────┘  └──────────┘

지원 어댑터 (모두 불변, 거버넌스 없음):
Supported adapters (all immutable, ungoverned):

  Push-based:
    - Chainlink (가장 범용)
    - Chronicle
    - RedStone

  Pull-based:
    - Pyth (크로스체인)
    - Uniswap V3 TWAP

  Rate-based:
    - Lido (wstETH/stETH)
    - Balancer Rate Provider
    - Pendle

핵심 차별점: Quote-based Interface
  → 정적 가격(getPrice)이 아닌 견적(getQuote) 기반
  → getQuotes() → bid/ask 두 가격 반환 (매수/매도)
  → 렌딩 마켓에서 즉시적 가격 스프레드를 정확히 반영
  → Returns both bid and ask prices for safer lending market pricing
```

### 1.6 V1 vs V2 차이점 / V1 vs V2 Differences

```
┌──────────────────┬──────────────────────┬──────────────────────┐
│                  │ Euler V1             │ Euler V2             │
├──────────────────┼──────────────────────┼──────────────────────┤
│ 아키텍처          │ Monolithic           │ Modular (EVC + EVK)  │
│ Architecture     │ (Diamond proxy,      │ (independent vaults, │
│                  │  single storage)     │  ERC-4626)           │
├──────────────────┼──────────────────────┼──────────────────────┤
│ 리스크 모델       │ Shared pool          │ Per-vault isolation  │
│ Risk model       │ (cross-contamination │ (one vault = one     │
│                  │  possible)           │  market)             │
├──────────────────┼──────────────────────┼──────────────────────┤
│ 시장 생성         │ Governance-gated     │ Permissionless       │
│ Market creation  │ (tiered listing:     │ (anyone deploys via  │
│                  │  isolated/cross/     │  EVK)                │
│                  │  collateral tier)    │                      │
├──────────────────┼──────────────────────┼──────────────────────┤
│ 오라클           │ Uniswap V3 TWAP only │ Any oracle adapter   │
│ Oracle           │                      │ (Chainlink, Pyth...) │
├──────────────────┼──────────────────────┼──────────────────────┤
│ IRM              │ Fixed reactive IRM   │ Pluggable IRM        │
│                  │                      │ (vault creator picks)│
├──────────────────┼──────────────────────┼──────────────────────┤
│ 청산             │ Reverse Dutch Auction│ Reverse Dutch Auction│
│ Liquidation      │ (fixed)              │ + customizable flows │
├──────────────────┼──────────────────────┼──────────────────────┤
│ 거버넌스          │ Protocol-level DAO   │ Vault-level choice   │
│ Governance       │                      │ (governed or not)    │
├──────────────────┼──────────────────────┼──────────────────────┤
│ 보안 사고         │ $197M hack (2023)    │ 31 audits post-hack  │
│ Security         │ flash loan attack    │ (yAudit, Certora,    │
│                  │                      │  Spearbit, Trail of  │
│                  │                      │  Bits, etc.)         │
└──────────────────┴──────────────────────┴──────────────────────┘

핵심 변화: "Opinionated Monolith" → "Unopinionated Modular Toolkit"
Key shift: From monolithic protocol to composable vault network
```

---

## 2. Silo Finance

> 각 토큰 자산이 자체 격리된 렌딩 마켓을 가지는 리스크 격리형 프로토콜
> Risk-isolated lending where each token asset has its own isolated market

### 아키텍처 개요 / Architecture Overview

```
Silo Finance = 격리 시장 + 브릿지 자산으로 연결

                ┌──────────┐     ┌──────────┐     ┌──────────┐
                │ Silo A   │     │ Silo B   │     │ Silo C   │
                │ (LINK)   │     │ (UNI)    │     │ (CRV)    │
                │          │     │          │     │          │
                │ LINK/ETH │     │ UNI/ETH  │     │ CRV/ETH  │
                │ LINK/XAI │     │ UNI/XAI  │     │ CRV/XAI  │
                └────┬─────┘     └────┬─────┘     └────┬─────┘
                     │                │                │
                     └────────────────┼────────────────┘
                                      │
                                      ▼
                           ┌──────────────────┐
                           │  Bridge Assets   │
                           │                  │
                           │  ETH  ←→  XAI   │
                           │  (가장 유동성 높은  │
                           │   자산으로 연결)   │
                           └──────────────────┘

모든 사일로는 Bridge Asset과만 쌍을 이룸:
Every silo is paired ONLY with bridge assets:

  User deposits LINK → Silo_LINK
    → Can borrow ETH or XAI against LINK
    → Can then use ETH/XAI as collateral in another silo

  리스크 격리: LINK 가격 폭락 → Silo_LINK만 영향
  Risk isolation: LINK crash → only Silo_LINK affected
  (Aave에서는 같은 풀의 모든 대출자가 영향받음)
  (In Aave, all lenders in the same pool would be affected)
```

### 2.1 격리 시장 설계 / Isolated Market Design

```
Silo V2 구조:

  각 Silo = 2개의 ERC-4626 볼트
  Each Silo = 2 ERC-4626 vaults

  ┌─────────────────────────────────────────┐
  │  Silo (예: LINK/ETH)                    │
  │                                         │
  │  ┌──────────────┐  ┌──────────────┐     │
  │  │   Silo0      │  │   Silo1      │     │
  │  │ (LINK vault) │  │ (ETH vault)  │     │
  │  │              │  │              │     │
  │  │ Borrowable   │  │ Borrowable   │     │
  │  │ deposits     │  │ deposits     │     │
  │  │ (이자 수익)   │  │ (이자 수익)   │     │
  │  │              │  │              │     │
  │  │ Protected    │  │ Protected    │     │
  │  │ deposits     │  │ deposits     │     │
  │  │ (대출 불가,   │  │ (대출 불가,   │     │
  │  │  이자 없음)   │  │  이자 없음)   │     │
  │  └──────────────┘  └──────────────┘     │
  │                                         │
  │  Share tokens:                          │
  │    - Borrowable share (ERC-4626)        │
  │    - Protected share (non-borrowable)   │
  │    - Debt token (ERC-20R)               │
  └─────────────────────────────────────────┘

예치 옵션:
Deposit options:

  1. Borrowable deposit (대출 가능 예치):
     → 다른 사용자가 빌릴 수 있음
     → 이자 수익 발생
     → ERC-4626 share token 수령

  2. Protected deposit (보호 예치):
     → 대출 불가 (담보로만 사용)
     → 이자 수익 없음
     → 대신 bank run 위험 없음
     → 별도 share token 수령
```

### 2.2 브릿지 자산 개념 / Bridge Assets Concept

```
왜 Bridge Asset이 필요한가?
Why are bridge assets needed?

문제: 격리 시장이면 유동성이 파편화됨
Problem: Isolated markets fragment liquidity

해결: ETH와 XAI를 "브릿지"로 사용해 모든 시장을 연결
Solution: Use ETH and XAI as "bridges" connecting all markets

  LINK 보유자가 UNI를 빌리고 싶다면:
  If a LINK holder wants to borrow UNI:

    Step 1: LINK를 Silo_LINK에 예치 → ETH 대출
    Step 2: ETH를 Silo_UNI에 예치 → UNI 대출

    LINK → [Silo_LINK] → ETH → [Silo_UNI] → UNI
                              ↑
                        Bridge Asset가 연결 역할
                        Bridge asset as connector

  XAI = Silo 자체 발행 과담보 스테이블코인:
  XAI = Silo's own over-collateralized stablecoin:
    → SiloDAO가 각 사일로에 XAI 크레딧 라인 제공
    → 모든 사일로에서 담보로 사용 가능 (ETH와 동일)
    → 스테이블코인 대출 수요를 프로토콜 내에서 해결

리스크 노출:
Risk exposure:

  Aave:    대출자 → 풀의 모든 자산 리스크에 노출
           Lender → exposed to ALL assets in the pool

  Silo:    대출자 → ETH/XAI 리스크에만 노출
           Lender → exposed ONLY to ETH/XAI risk
           (특정 토큰 사일로의 개별 리스크는 그 사일로에 격리)
```

### 2.3 이자율 모델 / Interest Rate Model

```
Silo V2: Dynamic PI Controller + Deadband

  기존 Kink IRM의 문제:
  Problem with basic Kink IRM:
    → 정적 파라미터로는 시장 변화에 적응 불가
    → Static parameters can't adapt to market changes

  Silo의 해결:
  Silo's solution:
    → PI 컨트롤러 (비례-적분 제어기) 사용
    → PI Controller (Proportional-Integral controller)
    → 목표 사용률에서 벗어나면 이자율 자동 조정
    → Auto-adjusts rates when deviating from target utilization

  추가 특징:
    - Deadband: 목표 근처의 작은 변동은 무시 (노이즈 필터링)
    - Kink Multiplier: 킹크 포인트 이후 추가 가속
    - 모듈형: 볼트 배포자가 자산 특성에 맞는 IRM 선택 가능
      (스테이블코인, 롱테일 자산, 고유동성 자산, RWA 등)

  사용률 기반 기본 동작:
  Basic utilization-based behavior:
    Low utilization  → 이자율 하락 → 차입 유도
    High utilization → 이자율 상승 → 상환 유도 + 예치 유인
```

### 2.4 청산 메커니즘 / Liquidation Mechanism

```
Silo V2: Hook-based Partial Liquidation

  청산 조건:
  Liquidation condition:
    → Health Factor = 0% (포지션 부실)
    → 포지션의 담보 가치 < 부채 가치 (LTV 기준)

  메커니즘:
  Mechanism:

    1. 누구나 청산 실행 가능 (퍼미션리스)
       Permissionless - anyone can liquidate

    2. 기본적으로 부분 청산 (partial liquidation):
       → 부채의 일부만 상환하고 그에 해당하는 담보 + 수수료 획득
       → Repay part of debt, seize proportional collateral + fee
       → 청산 후 "더스트" 남으면 전체 청산 강제

    3. 청산 수수료는 배포자가 시장별로 설정:
       → 배포자가 각 시장의 리스크에 맞게 청산 인센티브 조정
       → Deployer sets liquidation fee per market

    4. Hook System으로 커스텀 청산 모듈 가능:
       → Silo Hooks System을 통해 청산 로직 교체 가능
       → 예: 네덜란드 경매, 고정 보너스, 외부 DEX 연동 등

  vs Aave:
    Aave: 자산별 고정 보너스 (5~15%), HF < 0.95면 100% 청산
    Silo: 배포자가 설정하는 유연한 수수료, 기본 부분 청산
```

### 2.5 리스크 격리 vs Aave 공유 풀 / Risk Isolation vs Aave Shared Pool

```
Aave V3 (Shared Pool):

  ┌─────────────────────────────────────────┐
  │              Lending Pool               │
  │                                         │
  │  ETH │ USDC │ DAI │ LINK │ UNI │ ...   │
  │   ▲                                     │
  │   │  LINK exploit → 전체 풀에 영향        │
  │   │  LINK exploit → affects entire pool  │
  │                                         │
  │  대출자 A의 USDC도 위험에 노출             │
  │  Lender A's USDC is also at risk        │
  └─────────────────────────────────────────┘

Silo Finance (Isolated):

  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │ LINK/ETH │  │ UNI/ETH  │  │ DAI/ETH  │
  │          │  │          │  │          │
  │ LINK     │  │ UNI      │  │ DAI      │
  │ exploit  │  │ safe     │  │ safe     │
  │  ↓       │  │          │  │          │
  │ 이 사일로 │  │ 영향없음  │  │ 영향없음  │
  │ 만 피해   │  │ unaffected│  │ unaffected│
  └──────────┘  └──────────┘  └──────────┘
    ↑
    LINK exploit → 이 사일로만 영향
    LINK exploit → only this silo affected

  트레이드오프:
  Tradeoff:
    격리 → 더 안전 but 자본 효율 낮음
    Isolation → safer but lower capital efficiency
    공유 풀 → 자본 효율 높음 but 시스템 리스크
    Shared pool → higher capital efficiency but systemic risk

  Aave V3의 절충안: Isolation Mode + E-Mode
    → 특정 자산을 격리 모드로 설정 가능 (Silo와 유사한 효과)
    → 하지만 근본적으로는 여전히 공유 풀 구조
```

---

## 3. Ajna Protocol

> 오라클 없음, 거버넌스 없음, 완전 퍼미션리스 렌딩 프로토콜
> No oracles, no governance, fully permissionless lending protocol

### 아키텍처 개요 / Architecture Overview

```
Ajna = "Bring Your Own Oracle" — 대출자가 가격을 결정

  전통적 렌딩:
  Traditional lending:
    Chainlink Oracle → "ETH = $2,000" → Protocol uses this price

  Ajna:
    Lender decides → "I'll lend at price 2,000 USDC per ETH"
    → 오라클 불필요 (No oracle needed)
    → 대출자가 직접 가격 판단
    → 시장 참여자들의 합의가 곧 가격

Pool 구조:
  ┌─────────────────────────────────────────────┐
  │  Ajna Pool (예: ETH/USDC)                    │
  │                                              │
  │  Quote token: USDC (빌려주는 토큰)             │
  │  Collateral token: ETH (담보 토큰)             │
  │                                              │
  │  Price Buckets (가격 버킷):                    │
  │  ┌─────────┬──────────┬───────────────────┐  │
  │  │ Bucket  │ Price    │ USDC Deposited    │  │
  │  ├─────────┼──────────┼───────────────────┤  │
  │  │ #4156   │ $2,100   │ 50,000 USDC  ←─  │  │ ← 높은 가격 = 안전한 대출
  │  │ #4132   │ $2,000   │ 100,000 USDC ←─  │  │    High price = safe lending
  │  │ #4108   │ $1,900   │ 80,000 USDC  ←─  │  │
  │  │ #4084   │ $1,800   │ 30,000 USDC      │  │ ← LUP 아래 = 이자 못 받음
  │  │ #4060   │ $1,700   │ 10,000 USDC      │  │    Below LUP = no interest
  │  │  ...    │  ...     │  ...             │  │
  │  └─────────┴──────────┴───────────────────┘  │
  │                                              │
  │  LUP = Lowest Utilized Price                 │
  │  (최저 사용 가격 — 차입 수요가 있는 최저 버킷)    │
  └─────────────────────────────────────────────┘

버킷은 50bps 간격으로 미리 정의된 가격 포인트:
Buckets are predefined price points at 50bps intervals:
  → 약 7,000개의 버킷이 하드코딩됨
  → ~7,000 buckets hardcoded into the protocol
```

### 3.1 오라클 없는 작동 원리 / How Oracle-Free Works

```
핵심: 대출자가 가격을 설정하고, 시장이 수렴한다
Core: Lenders set prices, market converges

1. 대출자(Lender)가 특정 가격 버킷에 예치:
   Lender deposits into a specific price bucket:

   Alice: "ETH 1개당 2,000 USDC까지 빌려줄게"
          → 버킷 #4132 ($2,000)에 10,000 USDC 예치

   Bob:   "ETH 1개당 1,900 USDC까지만 빌려줄게"
          → 버킷 #4108 ($1,900)에 5,000 USDC 예치

2. 차입자(Borrower)가 담보를 넣고 대출:
   Borrower posts collateral and borrows:

   Carol: 10 ETH 담보 → 풀에서 USDC 대출
          → 가장 높은 버킷부터 순서대로 소비
          → Borrows from highest-priced buckets first

3. LUP (Lowest Utilized Price) 결정:
   → 모든 차입 수요를 충족하는 데 필요한 가장 낮은 버킷의 가격
   → "시장이 합의한 실질 가격"
   → LUP 위의 모든 대출자는 동일 이자율 수령
   → LUP 아래의 대출자는 이자 수령 불가 (리스크 프리미엄)

4. 가격 추적 메커니즘:
   External price tracking without oracle:

   ETH 시장가 하락 ($2,000 → $1,500):
     → 차입자 담보 가치 하락 → 청산 발생
     → 대출자들이 더 낮은 버킷으로 이동 (자체 판단)
     → LUP가 자연스럽게 시장 가격 추적

   ETH 시장가 상승:
     → 대출자들이 더 높은 버킷에 예치 (더 많이 빌려줄 의향)
     → LUP 상승

핵심: 오라클 대신 "시장 참여자의 집단 지성"이 가격을 결정
Key: Instead of oracles, "collective intelligence of market participants" sets price
```

### 3.2 이자율 모델 / Interest Rate Model

```
EMA 기반 적응형 이자율 (Adaptive Rate):

  Aave/Compound: 이자율 = f(현재 사용률)
                 Rate = f(current utilization)

  Ajna:          이자율 = f(EMA 사용률, 시간)
                 Rate = f(EMA utilization, time)

  동작 방식:
  How it works:

    1. "의미있는 실질 사용률" = 부채 / LUP 이상 예치금의 EMA
       "Meaningful actual utilization" = EMA of debt / deposits above LUP

    2. 이자율 조정 주기: 12시간 (12-hour cycle)

    3. 조정 폭: +/-10% per cycle
       → 상승 시: rate = rate * 1.1
       → 하락 시: rate = rate * 0.9

    4. 조정 방향:
       → 대출자 과잉 (유동성 충분) → 이자율 하락 → 차입 유도
       → 대출자 부족 (유동성 부족) → 이자율 상승 → 예치 유인 + 상환 유도

  특징:
    - 거버넌스 없이 완전 자동 조정
    - EMA 사용으로 단기 변동에 과잉 반응 방지
    - 모든 LUP 이상 대출자가 동일 이자율 수령
    - 대출은 영구적 (perpetual — 만기 없음)
```

### 3.3 청산 메커니즘 / Liquidation Mechanism

```
Bond-based Dutch Auction (본드 기반 네덜란드 경매):

  1단계: 킥(Kick) — 청산 개시
    → 청산자(Kicker)가 "청산 본드" 매입
    → 본드 가격 = 부채의 1~3%
    → Bond Factor = min(3%, (TP/NP ratio - 1) / 10)
    → 본드 = "이 청산이 정당하다"는 베팅
    → Bond = bet that this liquidation is justified

  2단계: Take — 담보 경매
    Dutch Auction 형태:

    담보 가격
    (Collateral
     price)
      │
    256x│ ← 시작가: 기준가의 256배 (매우 비쌈)
      │      Start: 256x reference price
      │╲
      │ ╲    6번의 20분 반감기
      │  ╲   (6 halvings of 20 minutes)
      │   ╲
      │    ╲  6번의 2시간 반감기
      │     ╲ (6 halvings of 2 hours)
      │      ╲
      │       ╲  이후 시간당 반감기
      │        ╲ (hourly halvings until end)
      │         ╲
    0 │──────────╲───────────────── 시간 (Time)
      0         72 hours (최대 경매 기간)

  3단계: Settle — 정산
    → 경매 종료 후 본드 보상/손실 결정

  본드 메커니즘의 핵심:
  Key insight of bond mechanism:

    Neutral Price (NP) = 대출의 "손익분기" 가격
    → 담보 가격 > NP → 청산 비합리적 (본드 손실)
    → 담보 가격 < NP → 청산 합리적 (본드 이익)

    → 부당한 청산 방지 (disincentivize unfair liquidations)
    → 청산자가 리스크를 감수해야 함 (skin in the game)

  vs 다른 프로토콜:
    Aave/Compound: 청산자 리스크 없음 (무조건 이익)
                   Liquidator always profits
    Euler V2:      청산 보너스만 있음 (리스크 없음)
    Ajna:          청산자가 본드 리스크를 감수
                   Liquidator risks bond → fairer
```

### 3.4 퍼미션리스 시장 생성 / Truly Permissionless Market Creation

```
Uniswap처럼 누구나 풀을 만들 수 있음:
Like Uniswap, anyone can create a pool:

  ERC-20 / ERC-20 Pool:
    → 임의의 ERC-20 토큰 페어로 풀 생성
    → 예: SHIB/USDC, ARB/WETH, 커스텀토큰/DAI

  ERC-721 / ERC-20 Pool:
    → NFT를 담보로 사용하는 풀 생성!
    → 예: BAYC/WETH, CryptoPunks/USDC
    → NFT 담보 대출을 오라클 없이 구현

  생성 과정:
  Creation process:
    1. PoolFactory.deployPool(collateral, quote) 호출
    2. 거버넌스 승인 불필요
    3. 오라클 설정 불필요
    4. 리스크 파라미터 설정 불필요
    → 완전 자동, 코드가 모든 것을 결정

  Deposit Token:
    → LPB (Liquidity Provider Balance) = 내부 잔고 단위
    → LPB를 NFT로 민팅 가능 (선택적)
    → NFT = 전송 가능한 LP 포지션 (다른 DeFi에서 사용 가능)
    → 여러 버킷에 걸쳐 여러 LP 포지션 보유 가능

비교:
Comparison:

  ┌──────────────────┬────────────┬────────────┬────────────┐
  │                  │ Aave V3    │ Euler V2   │ Ajna       │
  ├──────────────────┼────────────┼────────────┼────────────┤
  │ 시장 생성 권한    │ DAO 투표   │ 누구나     │ 누구나      │
  │ Who creates      │ DAO vote   │ Anyone     │ Anyone     │
  ├──────────────────┼────────────┼────────────┼────────────┤
  │ 오라클 필요       │ 필수       │ 필수       │ 불필요      │
  │ Oracle needed    │ Required   │ Required   │ Not needed │
  ├──────────────────┼────────────┼────────────┼────────────┤
  │ 리스크 설정       │ DAO       │ 볼트생성자  │ 코드 자동   │
  │ Risk config      │ DAO       │ Vault      │ Automatic  │
  │                  │           │ creator    │            │
  ├──────────────────┼────────────┼────────────┼────────────┤
  │ NFT 담보         │ X         │ X          │ O          │
  │ NFT collateral   │ No        │ No         │ Yes        │
  ├──────────────────┼────────────┼────────────┼────────────┤
  │ 거버넌스 의존     │ 높음      │ 선택적     │ 없음        │
  │ Gov dependency   │ High      │ Optional   │ None       │
  └──────────────────┴────────────┴────────────┴────────────┘
```

---

## 설계 철학 비교 / Design Philosophy Comparison

```
세 프로토콜의 핵심 철학:
Core philosophy of each protocol:

Euler V2:  "모듈화의 극대화 — 볼트 네트워크"
           "Maximum modularity — vault network"
           → 레고 블록처럼 볼트를 조합
           → EVC가 접착제 역할
           → 볼트 생성자에게 최대 자유도
           → Vault creators have maximum freedom

Silo:      "격리를 통한 안전 — 브릿지 연결"
           "Safety through isolation — bridge connections"
           → 각 자산을 감옥에 가둠
           → 브릿지 자산만이 열쇠
           → 간단하지만 강력한 리스크 모델
           → Simple but powerful risk model

Ajna:      "최소 의존성 — 순수 시장"
           "Minimum dependencies — pure market"
           → 오라클 의존 제거
           → 거버넌스 의존 제거
           → 시장 참여자만으로 작동
           → Works with market participants alone

스펙트럼으로 보면:
On a spectrum:

  Governance-heavy ←──────────────────────→ Governance-free
  Aave V3          Silo        Euler V2         Ajna
  (DAO 필수)       (DAO 관리)   (볼트별 선택)     (거버넌스 없음)

  Oracle-dependent ←──────────────────────→ Oracle-free
  Aave V3     Silo/Euler V2                    Ajna
  (Chainlink   (어댑터 패턴,                   (대출자가
   필수)        선택 가능)                      가격 결정)

  Shared Risk ←───────────────────────────→ Isolated Risk
  Aave V3          Euler V2     Silo          Ajna
  (공유 풀)        (볼트별 격리)  (사일로별     (풀별 완전 격리)
                                 격리)
```

---

## DevOps / 모니터링 관점 / DevOps / Monitoring Perspective

```
┌──────────────────┬──────────────────────┬──────────────────────┬──────────────────────┐
│                  │ Euler V2             │ Silo Finance         │ Ajna Protocol        │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ 모니터링 대상      │ 볼트별 개별 모니터링   │ 사일로별 모니터링     │ 풀별 모니터링         │
│ Monitor target   │ Per-vault            │ Per-silo             │ Per-pool             │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ 오라클 감시       │ 어댑터별 staleness   │ Chainlink/Pyth 등    │ 불필요               │
│ Oracle watch     │ check 필요           │ staleness check      │ Not needed           │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ 청산 봇 설계      │ 볼트별 health 추적    │ 사일로별 HF 추적      │ NP vs 시장가 비교     │
│ Liquidation bot  │ + reverse auction    │ + 부분청산 로직       │ + 본드 수익성 계산    │
│                  │   타이밍 최적화        │                      │ + 경매 타이밍 최적화  │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ 위험 지표         │ 볼트 utilization,    │ 사일로 utilization,   │ LUP 변동,           │
│ Risk metrics     │ 담보 가치 변동,       │ 브릿지 자산 건전성,   │ 버킷 유동성 분포,    │
│                  │ 오라클 편차           │ 오라클 편차           │ EMA utilization     │
├──────────────────┼──────────────────────┼──────────────────────┼──────────────────────┤
│ 사고 대응         │ 볼트별 독립 pause     │ 사일로별 독립 조치    │ 불가 (immutable)     │
│ Incident resp.   │ (governed vaults)    │ (DAO 의결 필요)       │ 코드에 의존          │
│                  │                      │                      │ Rely on code only   │
└──────────────────┴──────────────────────┴──────────────────────┴──────────────────────┘

핵심:
  Euler V2: 볼트가 많아질수록 모니터링 복잡도 증가, 하지만 각 볼트는 독립적
  Silo:     브릿지 자산(ETH/XAI) 건전성이 전체 시스템의 핵심 → 집중 모니터링
  Ajna:     오라클 리스크 제거, 하지만 LUP/버킷 동태 분석이 새로운 과제
```
