# Day 1 Review — 오늘 배운 것 정리

> 2026-02-23 (일) 학습 리뷰

---

## 완료한 항목 / Completed

- [x] `defi-lending-protocol-guide.md` 섹션 1-3 읽기
- [x] Finematics: DeFi Lending Explained 영상 시청
- [x] Finematics: Flash Loans Explained 영상 시청
- [x] ~~SpeedRunEthereum 렌딩 챌린지~~ — 이미 LendingPool.sol로 더 완전하게 구현함
- [x] Compound V2 코드 리딩 → 가이드 문서화

---

## 핵심 개념 요약 / Key Concepts Learned

### 1. 렌딩 프로토콜의 5대 파라미터

```
① LTV (Loan-to-Value)       — 얼마까지 빌릴 수 있나 (보통 75-80%)
② Health Factor              — 내 포지션이 안전한가 (HF < 1이면 청산)
③ Utilization Rate           — 풀의 돈이 얼마나 빌려졌나 (이자율 결정)
④ Reserve Factor             — 프로토콜이 이자에서 얼마를 떼가나 (10-35%)
⑤ Collateral Factor          — 자산의 담보 가치를 얼마나 인정하나
```

### 2. 외워야 할 공식 3개

```
① HF = LT / LTV
② 최대 하락률 = 1 - (LTV / LT)
③ Supply APY = Borrow APR × Utilization × (1 - Reserve Factor)
```

### 3. 과담보인 이유

```
블록체인 = 익명 → 신용평가 불가 → 담보로만 판단 → 과담보 필수
```

---

## Q&A 정리 / Questions & Answers

### Q1. Jump Rate Model은 모든 프로토콜이 쓰는 표준인가?

```
A: 아니다. DEX의 CPMM(x·y=k)처럼 "원조 모델"이지 "유일한 모델"은 아님.

  Compound V2: Jump Rate Model (원조)
  Aave V3:     Variable Rate Strategy (비슷하지만 파라미터 구조 다름)
  MakerDAO:    거버넌스가 직접 이자율 설정 (알고리즘 아님!)
  Euler V2:    모듈형 — 풀 생성자가 이자율 모델 직접 선택
  Fraxlend:    시간 가중 모델 (사용률 기반 아님)

  공통점: 사용률 올라가면 이자율도 올라가는 구조
  차이점: 곡선 모양, 파라미터 수, 결정 방식이 다름
```

> 상세: [deep-dive/interest-rates.md](deep-dive/interest-rates.md) — 프로토콜별 모델 비교

---

### Q2. Borrow APR은 항상 Supply APY보다 높은가?

```
A: 기본 이자(Layer 1)에서는 수학적으로 무조건 그렇다.

  Supply = Borrow × Utilization × (1 - RF)
         = Borrow × (1보다 작은 수) × (1보다 작은 수)
         → 항상 Borrow보다 작음

  이유:
  ① 풀의 돈이 100% 빌려진 게 아님 → 안 빌린 돈은 이자 안 벌음
  ② 프로토콜이 Reserve Factor만큼 떼감

  단, 토큰 인센티브(Layer 2) 포함하면 역전 가능:
  2020 DeFi Summer: COMP 보상 > 대출 이자 → "빌리면 돈 버는" 상황
```

> 상세: [deep-dive/deposit-tokens.md](deep-dive/deposit-tokens.md) — Borrow APR vs Supply APY

---

### Q3. Compound는 Variable인데 Aave는 Stable인가?

```
A: Aave는 Variable + Stable 두 가지를 모두 제공했었다.

  Compound: Variable Rate만
  Aave:     Variable Rate + Stable Rate (고정금리 옵션)

  하지만 Stable Rate는 사실상 사라지는 추세:
  ① 악용 가능: 낮은 고정금리로 빌린 뒤 시장 이자율 오르면 이득
  ② 복잡성: 두 개 관리 → 코드/감사 비용 증가
  ③ DeFi 사용자 대부분 단기 차입 → 변동금리 선호

  Aave V3: 대부분 자산에서 Stable Rate 비활성화
  업계 전체: Variable Rate로 수렴하는 추세
```

> 상세: [deep-dive/deposit-tokens.md](deep-dive/deposit-tokens.md) — Variable Rate vs Stable Rate

---

### Q4. cToken과 aToken은 뭐가 다른가?

```
A: 이자를 반영하는 방식이 다르다. "언제 곱하느냐"의 차이.

  cToken (Compound): 토큰 수량 고정, 교환비율이 올라감
    예치: 1,000 USDC → 50,000 cUSDC (비율 0.02)
    1년후: 50,000 cUSDC 그대로, 비율 0.025
    인출: 50,000 × 0.025 = 1,250 USDC

  aToken (Aave): 토큰 수량이 자동으로 늘어남 (rebase)
    예치: 1,000 USDC → 1,000 aUSDC (1:1)
    1년후: 지갑에 1,050 aUSDC로 늘어남
    인출: 1,050 aUSDC → 1,050 USDC

  UX: aToken이 직관적 (잔고 = 실제 가치)
  호환성: cToken이 유리 (표준 ERC20, DeFi 조합 가능)

  수학적으로 동일:
    cToken: amount = shares × exchangeRate     (인출할 때 곱셈)
    aToken: balance = scaledBalance × index    (조회할 때 곱셈)
```

> 상세: [deep-dive/deposit-tokens.md](deep-dive/deposit-tokens.md) — 전체 비교

---

### Q5. cToken 구조가 Walrus 스테이킹과 같은 패턴 아닌가?

```
A: 정확히 같다. "Share-Based Accounting" (지분 기반 회계).

  Compound cToken:
    exchange_rate = (totalCash + totalBorrows - totalReserves) / totalSupply
    deposit:  shares = amount / exchange_rate
    withdraw: amount = shares × exchange_rate

  Walrus StakingPool:
    exchange_rate = total_wal / total_shares
    stake:    shares = principal × total_shares / total_wal
    withdraw: amount = shares × total_wal / total_shares

  → 같은 공식, 변수명만 다름!

  이 패턴을 쓰는 곳들:
    DeFi: Compound cToken, ERC-4626
    Liquid Staking: Lido wstETH, Rocket Pool rETH, Walrus StakingPool
```

> 상세: [deep-dive/deposit-tokens.md](deep-dive/deposit-tokens.md) — Walrus 비교

---

### Q6. Scaled Balance가 뭐고, 왜 가스비를 절약하나?

```
A: 예치 시점의 index로 나눈 정규화된 값. SSTORE를 없애서 가스 절약.

  Scaled Balance = 예치금 / 예치 시점의 liquidityIndex
  예: 1,000 USDC / 1.02 = 980.39 (이 값은 안 바뀜!)

  V1 (순진한 방식): 이자 발생 시 모든 사용자 잔고 업데이트
    → 사용자 1,000명 × SSTORE(5,000 gas) = 5,000,000 gas ≈ $630

  V2 (scaled balance): 전역 index 1개만 업데이트
    → SSTORE 1번 = 5,000 gas ≈ $2.70
    → 99.6% 절약!

  EVM 핵심:
    SSTORE = 5,000 gas (쓰기) — Merkle Trie 재계산 + 전 노드 영구 저장
    SLOAD  = 2,100 gas (읽기) — 트리 탐색만
    MUL    =     5 gas (계산)

  balanceOf()는 view 함수 → 외부 호출 시 가스비 0
  → "계산을 읽기 시점으로 미룬다" = "쓰기를 없앤다"
```

> 상세: [deep-dive/deposit-tokens.md](deep-dive/deposit-tokens.md) — Scaled Balance 심화

---

### Q7. cToken의 borrowIndex도 Scaled Balance 아닌가?

```
A: 맞다. cToken도 대출자 쪽에서는 scaled balance를 쓴다.

  cToken에는 두 가지 회계가 공존:
    예치자: exchangeRate 방식 (cToken이라는 ERC20을 발행하니까)
    대출자: borrowIndex 방식 (= scaled balance, 별도 토큰이 없으니까)

  Aave는 양쪽 다 scaled balance:
    예치자: aToken의 scaledBalance × liquidityIndex
    대출자: debtToken의 scaledBalance × variableBorrowIndex

  "Scaled Balance"는 특정 프로토콜 전유물이 아니라 가스 절약 패턴.
```

---

### Q8. 우리 프로젝트는 Aave 방식인가 Compound 방식인가?

```
A: Aave 방식이다.

  우리:      사용자 → LendingPool.deposit() → LToken.mint()
  Aave:     사용자 → Pool.deposit()        → aToken.mint()
  Compound: 사용자 → CToken.mint()          (CToken이 풀 겸 토큰)

  구조적 차이:
    Compound: CToken이 풀 역할까지 겸함 (monolithic)
    Aave/우리: Pool이 중심, 토큰은 영수증일 뿐 (분리된 구조)

  단, 이자 반영(rebase/scaledBalance)은 단순화해서 빠져 있음.
  핵심 흐름(deposit → borrow → repay → liquidate)은 Aave V3와 동일.
```

---

### Q9. Compound V2 코드는 어디서부터 봐야 하나?

```
A: 핵심 3개 파일, 5개 함수만 보면 된다.

  ① CToken.sol — 핵심 5개 함수:
     accrueInterest()  → 이자 누적 (borrowIndex = scaled balance 패턴!)
     mintFresh()        → 예치 (= 우리 deposit)
     borrowFresh()      → 대출 (= 우리 borrow)
     repayBorrowFresh() → 상환 (= 우리 repay)
     liquidateBorrowFresh() → 청산 (= 우리 liquidate)

  ② Comptroller.sol — 핵심 1개 함수:
     getHypotheticalAccountLiquidityInternal()
     → Health Factor 계산의 핵심
     → sumCollateral vs sumBorrowPlusEffects

  ③ BaseJumpRateModelV2.sol — 우리 JumpRateModel.sol과 동일

  나머지 (Governance, Lens, Timelock 등)는 전부 무시.
```

> 상세: [deep-dive/compound-v2-code-reading.md](deep-dive/compound-v2-code-reading.md) — 전체 코드 리딩 가이드

---

## 오늘의 핵심 인사이트 / Key Insights

```
1. 렌딩의 본질은 "풀 기반 중개"
   → 예치자와 대출자를 직접 매칭하지 않고, 풀을 통해 간접 매칭
   → 스테이킹 풀과 동일한 패턴

2. Share-Based Accounting은 DeFi의 범용 패턴
   → cToken, ERC-4626, wstETH, rETH, Walrus 전부 같은 원리
   → "지분으로 변환 → 전역 비율만 업데이트 → 인출 시 역변환"

3. 가스 최적화의 핵심: "쓰기를 읽기로 바꾸기"
   → SSTORE(쓰기)는 SLOAD(읽기)보다 2.4배, 계산보다 1,000배 비쌈
   → Scaled Balance = 전역 index 1개만 쓰기, 나머지는 읽기 시 계산
   → 이게 Merkle Patricia Trie 재계산 비용 때문

4. Compound와 Aave의 아키텍처 차이
   → Compound: CToken이 풀 겸 토큰 (monolithic)
   → Aave: Pool과 토큰 분리 (modular)
   → 우리 프로젝트는 Aave 구조

5. 이자율은 3개 레이어
   → Layer 1: 기본 이자 (Jump Rate Model)
   → Layer 2: 토큰 인센티브 (COMP, AAVE)
   → Layer 3: 포인트/에어드랍 (Blast, EigenLayer)
   → Layer 2,3까지 포함하면 "빌리면 돈 버는" 상황도 가능
```

---

## 생성된 심화 문서 / Deep Dive Documents Created

| 문서 | 핵심 내용 |
|------|----------|
| [health-factor.md](deep-dive/health-factor.md) | BTC $100K 예제, LTV별 HF 비교, 간편 공식 |
| [interest-rates.md](deep-dive/interest-rates.md) | 이자 계산, RF 비교, 3 Layers, 프로토콜별 모델 비교, APR vs APY |
| [deposit-tokens.md](deep-dive/deposit-tokens.md) | cToken vs aToken, Scaled Balance + EVM 가스, Walrus 비교, Variable vs Stable |
| [compound-v2-code-reading.md](deep-dive/compound-v2-code-reading.md) | CToken/Comptroller/JumpRateModel 핵심 코드 + 우리 코드 매핑 |

---

## 내일 할 것 / Tomorrow (Day 2)

```
Day 2: Interest Rate Models + Solidity Deep Dive

  오전: Aave V3 아키텍처 읽기
    - Pool.sol, SupplyLogic.sol, BorrowLogic.sol, LiquidationLogic.sol
    - 우리 코드와 비교하며 읽기

  오후: 테스트 심화
    - Fork Testing (Aave V3 메인넷 포크)
    - Fuzz Testing (이자율 엣지 케이스)
    - Invariant Testing (풀 불변성)

  참고: defi-lending-protocol-guide.md 섹션 5 (Interest Rate Models)
```
