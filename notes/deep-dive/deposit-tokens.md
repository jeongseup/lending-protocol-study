# Deposit Tokens 심화 — aToken vs cToken
# Deposit Tokens Deep Dive — aToken vs cToken

> 예치 영수증 토큰의 동작 방식 비교
> Comparing how deposit receipt tokens work internally

---

## 공통점 — 둘 다 "예치 영수증"

```
역할은 동일: 예치하면 받는 토큰, 나중에 돌려주면 원금+이자를 회수
Common role: Receipt token for deposits, redeem for principal + interest

User → deposit(1,000 USDC) → Pool → Mint receipt token → User
User → redeem(receipt token) → Pool → Return USDC + interest → User
```

---

## 핵심 차이 — "이자를 어떻게 반영하느냐"

```
┌─────────────┬──────────────────────────────────────────┐
│ cToken      │ 토큰 수량 고정, 교환비율이 올라감          │
│ (Compound)  │ Balance stays same, exchange rate grows   │
│             │                                          │
│             │ 예치: 1,000 USDC → 50,000 cUSDC 발행     │
│             │       (교환비율 0.02)                      │
│             │ 1년후: 50,000 cUSDC 그대로                │
│             │       교환비율 0.025로 상승               │
│             │ 인출: 50,000 × 0.025 = 1,250 USDC 회수   │
├─────────────┼──────────────────────────────────────────┤
│ aToken      │ 토큰 수량이 자동으로 늘어남 (rebase)      │
│ (Aave)      │ Balance itself increases over time        │
│             │                                          │
│             │ 예치: 1,000 USDC → 1,000 aUSDC 발행      │
│             │       (1:1 비율)                          │
│             │ 1년후: 지갑에 1,050 aUSDC로 늘어남         │
│             │ 인출: 1,050 aUSDC → 1,050 USDC 회수      │
└─────────────┴──────────────────────────────────────────┘
```

---

## 사용자 경험 차이 / UX Difference

```
cToken: "내 잔고가 50,000인데... 이게 지금 얼마지?"
        → 교환비율을 곱해야 실제 가치를 알 수 있음
        → 계산이 필요해서 직관적이지 않음

aToken: "내 잔고가 1,050이네, 50 USDC 이자 붙었구나"
        → 잔고 = 실제 가치 (1:1)
        → 직관적, 지갑에서 바로 확인 가능

그래서 Aave가 UX 측면에서 더 직관적이라는 평가를 받음
Aave is generally considered more intuitive for end users
```

---

## 기술적 구현 / Technical Implementation

```
cToken (교환비율 방식 / Exchange Rate Model):

  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply

  - 비율이 단조증가 (이자가 누적되면서)
  - Exchange rate monotonically increases as interest accrues
  - ERC20 표준 그대로 사용 가능 (transfer 정상 작동)
  - Standard ERC20 — transfer works normally

  deposit:  cTokenAmount = depositAmount / exchangeRate
  redeem:   underlyingAmount = cTokenAmount × exchangeRate
```

```
aToken (리베이스 방식 / Rebase Model):

  balanceOf(user) = scaledBalance × liquidityIndex

  - balanceOf()를 override해서 실시간으로 이자 반영
  - Overrides balanceOf() to reflect interest in real-time
  - 내부적으로 scaled balance + liquidity index로 계산
  - Internally uses scaled balance + liquidity index

  deposit:  scaledBalance = depositAmount / currentIndex
  balanceOf: return scaledBalance × currentIndex  (항상 최신 이자 반영)
```

---

## 장단점 비교 / Trade-offs

```
┌──────────┬────────────────────────┬────────────────────────┐
│          │ cToken (Compound)      │ aToken (Aave)          │
├──────────┼────────────────────────┼────────────────────────┤
│ 직관성    │ ✗ 교환비율 계산 필요    │ ✓ 잔고 = 실제 가치     │
│ UX       │ ✗ Needs rate calc      │ ✓ Balance = value      │
├──────────┼────────────────────────┼────────────────────────┤
│ 호환성    │ ✓ 표준 ERC20           │ ✗ rebase라 일부 DeFi와 │
│ Compat.  │ ✓ Standard ERC20       │   호환 문제 가능       │
├──────────┼────────────────────────┼────────────────────────┤
│ DeFi     │ ✓ DEX/Vault에서        │ ✗ rebase 미지원 프로토콜│
│ 조합성    │   바로 사용 가능       │   에서 이자 손실 가능   │
│ Compos.  │ ✓ Works in DEX/Vaults  │ ✗ May lose interest in │
│          │                        │   non-rebase protocols │
├──────────┼────────────────────────┼────────────────────────┤
│ 가스비    │ ✓ 단순한 계산          │ ✗ index 조회 필요      │
│ Gas      │ ✓ Simple calculation   │ ✗ Needs index lookup   │
└──────────┴────────────────────────┴────────────────────────┘

실제 트렌드 / Actual trend:
  - Aave V3: aToken 유지 (UX 우선)
  - Compound V3 (Comet): cToken 폐지, 내부 잔고 직접 관리
  - ERC-4626: "Tokenized Vault" 표준 — cToken 방식을 표준화한 것
    → 업계가 교환비율 방식을 표준으로 수렴하는 추세
```

---

## 수학적으로 동일 — "언제 곱하느냐"만 다름

```
cToken:  amount = shares × exchangeRate      (인출할 때 곱셈)
aToken:  balance = scaledBalance × index     (조회할 때 곱셈)

결과는 같음 — 곱셈 시점만 다름!
Same result — only the timing of multiplication differs!

cToken: 인출 시점에 곱셈 → 사용자가 직접 계산해야 실제 가치를 앎
aToken: 조회 시점에 곱셈 → 지갑에서 바로 실제 가치가 보임
```

**aToken 내부 동작 상세:**

```
aToken의 balanceOf()는 이렇게 override 됨:

  // 저장된 값 (예치 시점에 고정)
  scaledBalance = 1000

  // 실시간으로 계산
  function balanceOf(user) {
    return scaledBalance × liquidityIndex / userIndex
  }

  예치 시점: liquidityIndex = 1.00
    → balanceOf = 1000 × 1.00 / 1.00 = 1,000 aUSDC

  1년 후: liquidityIndex = 1.05 (이자 5% 누적)
    → balanceOf = 1000 × 1.05 / 1.00 = 1,050 aUSDC

  실제로 토큰이 추가 mint 되는 게 아님!
  balanceOf()가 호출될 때마다 계산해서 보여주는 것
  No actual minting — calculated on every balanceOf() call
```

---

## Walrus 스테이킹과 cToken — 같은 패턴

```
핵심 패턴: "Share-Based Accounting" (지분 기반 회계)

┌──────────────────────────────────────────────────────────┐
│  1. 풀에 총 자산과 총 지분이 있음                          │
│  2. 예치: 자산 → 현재 비율로 지분 변환                     │
│  3. 시간 경과: 총 자산 증가 (이자/보상), 총 지분은 그대로   │
│  4. 인출: 지분 → 새로운(더 높은) 비율로 자산 변환          │
│  5. 차이 = 수익                                          │
└──────────────────────────────────────────────────────────┘
```

**나란히 비교:**

```
Compound cToken:
  exchange_rate = (totalCash + totalBorrows - totalReserves) / totalSupply
  deposit:  shares = amount / exchange_rate        (ETH → cETH)
  withdraw: amount = shares × exchange_rate        (cETH → ETH)

Walrus StakingPool:
  exchange_rate = total_wal / total_shares
  stake:    shares = principal × total_shares / total_wal
  withdraw: amount = shares × total_wal / total_shares

  → 같은 공식, 변수명만 다름!
```

**구체적 숫자 비교:**

```
Compound 예시:
  예치: 10 ETH / 0.02 = 500 cETH
  시간 경과: exchange_rate 0.02 → 0.02103456
  인출: 500 cETH × 0.02103456 = ~10.05 ETH
  수익: ~0.05 ETH

Walrus 예시:
  스테이킹: 1,000,000,000 WAL → 999,922,610 shares
           (e4 rate: 6710485646776390 / 6709966322808817)
  시간 경과: rate 변동 (리워드 누적)
  인출: 999,922,610 shares → 1,000,217,678 WAL
           (e8 rate: 6705234809326492 / 6703256739865348)
  수익: 217,678 WAL
```

**이 패턴을 쓰는 프로토콜들:**

```
DeFi Lending:
  Compound cToken     ← 원조 (2019)
  ERC-4626            ← cToken 패턴을 ERC 표준으로 (2022)

Liquid Staking:
  Lido wstETH         ← wrapped stETH가 이 패턴
  Rocket Pool rETH    ← exchange rate 방식
  Walrus StakingPool  ← 동일한 share 기반 회계

공통 이유: "토큰 수량을 바꾸지 않고 가치를 반영"하는 가장 깔끔한 방법
         rebase(잔고 자체를 바꾸는 것)보다 ERC20 호환성이 좋음

참고: Lido의 stETH는 rebase 방식 (aToken과 유사)
     wstETH는 wrapped 버전으로 share 방식 (cToken과 유사)
     → 하나의 프로토콜이 두 방식을 모두 제공하는 사례
```

---

## Borrow APR vs Supply APY — 왜 항상 Borrow > Supply?

```
Supply APY = Borrow APR × Utilization × (1 - Reserve Factor)

Utilization < 1 이고, (1 - RF) < 1 이니까:
Supply = Borrow × (1보다 작은 수) × (1보다 작은 수)
       → Supply는 무조건 Borrow보다 작음

이유:
① 풀의 돈이 100% 빌려진 게 아님 (Utilization < 100%)
   → 안 빌려간 돈은 이자를 안 벌음
② 프로토콜이 중간에 떼감 (Reserve Factor)
   → 대출자가 낸 이자의 일부가 프로토콜 금고로

단, Layer 2 (토큰 인센티브)까지 포함하면 역전 가능:
  2020 DeFi Summer: COMP 보상 > 대출 이자 → "빌리면 돈 버는" 상황
  하지만 이건 기본 이자 구조의 역전이 아니라 외부 인센티브 때문
```

---

## Variable Rate vs Stable Rate (Aave)

```
Compound:
  Borrow: Variable APR만 (사용률에 따라 실시간 변동)
  Supply: Variable APY만

Aave:
  Borrow: Variable APR + Stable APR (두 가지 옵션)
  Supply: Variable APY만

Stable Rate = 빌리는 시점의 이자율을 "고정"하는 옵션
  Variable: 오늘 5% → 내일 8% → 모레 3% (계속 변동)
  Stable:   빌릴 때 6%로 고정 → 6% → 6% → 6%

현실 비유:
  Variable = 변동금리 주택담보대출
  Stable   = 고정금리 주택담보대출 (약간 더 비쌈)
```

**Stable Rate가 줄어든 이유:**

```
① 악용: 낮은 Stable Rate로 빌린 뒤 시장 이자율 오르면 이득
② 복잡성: Variable + Stable 두 개 관리 → 코드/감사 비용 증가
③ 수요 부족: DeFi 사용자 대부분 단기 차입 → 변동금리 선호

Aave V3 현재: 대부분 자산에서 Stable Rate 비활성화
업계 전체: Variable Rate로 수렴하는 추세
고정금리 수요 → Notional, Pendle 같은 전문 프로토콜로 이동
```

---

## 우리 프로젝트의 LToken

```
contracts/src/LToken.sol → Aave 스타일 (1:1 mint/burn)

  deposit: pool이 LToken.mint(user, amount) 호출 → 1:1 발행
  withdraw: pool이 LToken.burn(user, amount) 호출 → 1:1 소각

  단순화를 위해 rebase 없이 구현
  Simplified without rebase for learning purposes
  실제 Aave는 scaledBalance + liquidityIndex로 이자를 반영
```
