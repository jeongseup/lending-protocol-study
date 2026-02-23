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

## 우리 프로젝트의 LToken

```
contracts/src/LToken.sol → Aave 스타일 (1:1 mint/burn)

  deposit: pool이 LToken.mint(user, amount) 호출 → 1:1 발행
  withdraw: pool이 LToken.burn(user, amount) 호출 → 1:1 소각

  단순화를 위해 rebase 없이 구현
  Simplified without rebase for learning purposes
  실제 Aave는 scaledBalance + liquidityIndex로 이자를 반영
```
