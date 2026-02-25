# 가격 정규화(Normalization)가 필요한 이유

> "이자율은 같은 자산끼리 계산하니까 단위가 상관없는데, 왜 가격을 18 decimals로 통일하나?"

---

## 이자율 계산 — 정규화 불필요

```
이자율 모델 (InterestRateModel):
  utilization = totalBorrows / totalDeposits

  예: USDC 풀
    totalDeposits = 20,000 USDC
    totalBorrows  = 10,000 USDC
    utilization   = 10,000 / 20,000 = 50%

  → 같은 자산(USDC)끼리 나누기 → 단위가 상쇄됨
  → 가격 정보 불필요 ✅
```

---

## 담보 vs 부채 비교 — 정규화 필수!

```
LendingPool의 핵심 질문:
  "Alice의 ETH 담보가 USDC 대출을 커버할 수 있는가?"

  Alice:
    담보: 10 ETH
    대출: 10,000 USDC

  ETH와 USDC는 다른 자산 → 직접 비교 불가!
  → "같은 단위(USD)"로 환산해야 비교 가능
  → 이것이 오라클이 필요한 이유
```

---

## 왜 단순 환산이 아니라 "정규화"인가?

```
Chainlink 피드마다 decimals가 다를 수 있음:

  ETH/USD 피드: 8 decimals  → $2,000 = 2000_00000000
  WBTC/USD 피드: 8 decimals → $40,000 = 40000_00000000
  ETH/BTC 피드: 18 decimals → 0.05 = 50000000000000000

대부분의 USD 피드는 8 decimals이지만, 보장되지 않음.
피드를 교체하거나 새 자산을 추가할 때 decimals이 다를 수 있음.

만약 정규화 없이 8 dec 가격과 18 dec 가격을 섞으면:
  담보 가치 = amount × price_8dec   = 10 × 200000000000 = 2000000000000
  부채 가치 = amount × price_18dec  = 10 × 50000000000000000 = 500000000000000000
  → 단위가 안 맞으니 비교 결과가 의미 없음!
```

---

## 정규화 후

```
모든 가격을 18 decimals로 통일:

  getAssetPriceNormalized(ETH)  = 2000e18   (= $2,000)
  getAssetPriceNormalized(USDC) = 1e18      (= $1)
  getAssetPriceNormalized(WBTC) = 40000e18  (= $40,000)

LendingPool 계산:
  담보 USD 가치 = 10 ETH × 2000e18 = 20000e18 ($20,000)
  부채 USD 가치 = 10,000 USDC × 1e18 = 10000e18 ($10,000)

  Health Factor = 담보가치 × collateralFactor / 부채가치
                = $20,000 × 0.75 / $10,000
                = 1.5  (건강!)
```

---

## compound-v2-scenario.md 예시

```
Phase 3: Alice 대출 승인 여부 판단

  cETH 시장:
    cTokenBalance = 500 cETH
    exchangeRate  = 0.02
    oraclePrice   = $2,000      ← 여기에 가격 사용!
    collateralFactor = 0.75

    담보 가치 = 500 × 0.02 × $2,000 × 0.75 = $15,000

  cUSDC 시장:
    borrowAmount = 10,000 USDC
    oraclePrice  = $1.00        ← 여기에 가격 사용!

    부채 가치 = 10,000 × $1.00 = $10,000

  $15,000 > $10,000 → 대출 승인! ✓

→ 두 자산의 가격이 같은 단위(USD, 같은 decimals)여야 이 비교가 가능
```

---

## 정리

```
┌───────────────┬────────────────┬─────────────────┐
│ 기능           │ 가격 필요?     │ 정규화 필요?     │
├───────────────┼────────────────┼─────────────────┤
│ 이자율 계산    │ ❌ 불필요       │ ❌ 불필요        │
│ 사용률 계산    │ ❌ 불필요       │ ❌ 불필요        │
│ 대출 승인 판단 │ ✅ 필요         │ ✅ 필요          │
│ 청산 판단      │ ✅ 필요         │ ✅ 필요          │
│ HF 계산       │ ✅ 필요         │ ✅ 필요          │
└───────────────┴────────────────┴─────────────────┘

한 줄 요약:
  같은 자산 내 계산 → 가격 불필요
  서로 다른 자산 비교 → 같은 단위로 정규화 필수
```
