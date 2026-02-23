# Health Factor & Liquidation 심화
# Health Factor & Liquidation Deep Dive

> Day 1 학습 중 발생한 Q&A를 정리한 심화 노트입니다.
> Deep-dive notes from Day 1 Q&A sessions.

---

## 왜 과담보(Overcollateralized)인가?

```
블록체인에는 신원 확인 없음 → 신용점수 불가
No identity on blockchain → no credit scores possible
따라서 대출금보다 더 많은 담보를 요구
Therefore require more collateral than loan amount

현실 세계: 은행이 내 신용을 보고 무담보 대출 가능
DeFi:     누구인지 모르니까 담보로만 판단 → 과담보 필수
```

---

## BTC $100K 예제 — HF 계산

**조건: 0.001 BTC ($100) 담보, LTV 80%, Liquidation Threshold 85%**

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
```

---

## LTV별 안전 비교

```
안전한 대출 vs 위험한 대출 / Safe vs Risky borrowing:
보수적 LTV 50%: $100 담보 → $50 대출 → HF=1.70 → BTC 41% 하락까지 버팀
보통   LTV 65%: $100 담보 → $65 대출 → HF=1.31 → BTC 24% 하락까지 버팀
공격적 LTV 80%: $100 담보 → $80 대출 → HF=1.06 → BTC  6% 하락에 청산!

Conservative LTV 50%: $100 → borrow $50 → HF=1.70 → survives 41% BTC drop
Moderate     LTV 65%: $100 → borrow $65 → HF=1.31 → survives 24% BTC drop
Aggressive   LTV 80%: $100 → borrow $80 → HF=1.06 → liquidated at 6% drop!
```

---

## 간편 공식 — HF & 최대 하락률

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
