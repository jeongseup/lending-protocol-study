# 렌딩 프로토콜 유형 비교

# Lending Protocol Types Comparison

> Alberto Cuesta Cañada의 아티클 기반 — Pool-based vs CDP vs Fixed-rate 구조적 차이 정리
> Based on Alberto Cuesta Cañada's article — Structural differences between protocol types

> 참고: [How to Design a Lending Protocol on Ethereum](https://alcueca.medium.com/how-to-design-a-lending-protocol-on-ethereum-18ba5849aaf0)

---

## 핵심 질문: "돈을 어디서 가져오는가?" / "Where does the borrowed money come from?"

```
이 한 가지 질문이 세 가지 유형을 나눈다:
This single question separates the three types:

  Pool-based (Compound, Aave, Euler):
    → 다른 사용자가 예치한 돈을 빌림
    → Borrow money deposited by other users

  CDP-based (MakerDAO):
    → 프로토콜이 새로운 돈(DAI)을 찍어냄
    → Protocol mints new money (DAI)

  Fixed-rate (Yield):
    → 프로토콜이 미래 가치가 있는 토큰(fyToken)을 발행
    → Protocol issues tokens representing future value (fyToken)
```

---

## 1. Pool-based: Compound, Aave, Euler

### 구조 / Architecture

```
           예치자 (Lender)                    차입자 (Borrower)
               │                                  │
               │ deposit 1,000 USDC                │ deposit 2 ETH (담보)
               ▼                                  ▼
         ┌──────────────────────────────────────────┐
         │              Lending Pool               │
         │                                          │
         │   USDC Pool: 10,000 USDC (유동성)        │
         │   ETH Pool:  100 ETH (담보)              │
         │                                          │
         │   이자율 = f(사용률)                      │
         │   Rate = f(utilization)                  │
         └──────────────────────────────────────────┘
               │                                  │
               │ 이자 수익 (Supply APY)             │ 800 USDC 대출
               ▼                                  ▼
         cUSDC/aUSDC 수령                     USDC 수령 + 이자 부담

핵심: 예치자의 돈 → 풀 → 차입자에게 전달
Key: Lender's money → Pool → Delivered to borrower
```

### 작동 원리 / How It Works

```
1. Alice가 1,000 USDC 예치
   → 풀에 USDC 추가, Alice에게 cUSDC/aUSDC 발급

2. Bob이 2 ETH 담보로 넣고 800 USDC 대출
   → 풀에서 800 USDC가 Bob에게 전달
   → 풀의 USDC 잔고: 10,000 → 9,200

3. 이자율 자동 조절
   → 사용률 = 800 / 10,000 = 8%
   → 사용률이 높아지면 이자율 자동으로 올라감 (수요-공급)
   → Bob이 내는 이자 → Alice에게 분배

핵심 특징:
  - 변동 금리 (사용률에 따라 실시간 변동)
  - 예치자와 차입자가 같은 풀을 공유
  - 이자율은 알고리즘이 결정 (거버넌스 아님)
```

### 프로토콜별 차이 / Protocol Differences

```
              Compound V2        Aave V2           Euler
              ──────────         ──────            ─────
자산 관리      CToken별 분산       Pool 하나에 통합    Storage 하나에 통합
(Treasury)    (per-asset)        (centralized)     (monolithic)

리스크 관리    Comptroller        Pool              RiskManager 모듈
(Risk)        (중앙 컨트랙트)     (통합)             (별도 모듈)

유저 진입점    CToken 직접 호출    Pool 직접 호출      Proxy를 통해 호출
(Entry)       mint()/borrow()   supply()/borrow()  (Diamond-like)

포지션 토큰    cToken만           aToken + vToken    eToken + dToken
(Position)    (대출만 토큰화)      (대출 + 부채 토큰화)  (대출 + 부채 토큰화)

가스 효율      보통               보통               최고 (단일 스토리지)
(Gas)         (컨트랙트간 호출)    (라이브러리 호출)    (내부 호출만)
```

---

## 2. CDP-based: MakerDAO

### 구조 / Architecture

```
                   사용자 (User)
                      │
                      │ deposit 2 ETH (담보)
                      ▼
              ┌───────────────┐
              │   Join (ETH)  │ ← 자산별 금고
              │   Asset Vault │
              └───────┬───────┘
                      │
                      ▼
              ┌───────────────┐
              │   Vat.sol     │ ← 중앙 회계 장부
              │   Accounting  │    (담보, 부채, 비율 관리)
              │               │
              │   "2 ETH 담보  │
              │    있으니      │
              │    DAI 발행"   │
              └───────┬───────┘
                      │
                      │ 🪙 DAI 새로 발행 (mint)
                      ▼
                 사용자에게 DAI 전달

핵심: 예치자 없음! 프로토콜이 직접 DAI를 "찍어냄"
Key: No depositors! Protocol directly "mints" DAI
```

### 작동 원리 / How It Works

```
1. Bob이 2 ETH를 담보로 Vault에 넣음
   → ETH Join 컨트랙트에 ETH 잠김
   → Vat에 "Bob: 2 ETH 담보" 기록

2. Bob이 DAI 발행 요청 (예: 2,000 DAI)
   → Vat 확인: 2 ETH × $2,000 = $4,000 담보가치
   → LTV 50% 적용: 최대 2,000 DAI 발행 가능
   → DAI가 새로 생성(mint)되어 Bob에게 전달

3. Bob이 DAI 상환
   → DAI가 소각(burn)됨
   → ETH 담보 반환

4. ETH 가격 하락 시
   → 담보가치 < 부채 → 청산
   → Keeper가 담보를 경매(auction)에 올림

핵심 차이:
  - Pool-based: 이자율 = f(사용률) → 알고리즘
  - CDP-based: 이자율 = Stability Fee → 거버넌스가 결정!
  - Pool-based: 기존 토큰을 빌림 (USDC, ETH)
  - CDP-based: 새로운 토큰을 발행 (DAI만 가능)
```

### Pool-based와의 핵심 차이 / Key Differences from Pool-based

```
┌──────────────────┬─────────────────────┬──────────────────────┐
│                  │ Pool-based          │ CDP-based            │
│                  │ (Compound/Aave)     │ (MakerDAO)           │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 빌리는 자산       │ 풀에 있는 아무 토큰   │ DAI만 가능            │
│ Borrowed asset   │ Any token in pool   │ Only DAI             │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 돈의 출처         │ 예치자가 넣은 돈      │ 프로토콜이 새로 발행   │
│ Source of funds  │ Depositors' money   │ Protocol mints       │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 예치자 필요?      │ ✅ 필수             │ ❌ 없음              │
│ Need depositors? │ Yes, required       │ No                   │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 이자율 결정       │ 사용률 알고리즘       │ 거버넌스 투표          │
│ Rate setting     │ Utilization algo    │ Governance vote      │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 유동성 위험       │ 있음 (bank run)      │ 없음 (민팅이니까)      │
│ Liquidity risk   │ Yes (bank run)      │ No (minting)         │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 청산 방식         │ 직접 매수            │ 경매 (auction)        │
│ Liquidation      │ Direct purchase     │ Auction              │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 복잡도           │ 중간                 │ 높음                  │
│ Complexity       │ Medium              │ High                 │
└──────────────────┴─────────────────────┴──────────────────────┘
```

---

## 3. Fixed-rate: Yield Protocol

### 구조 / Architecture

```
                 사용자 (User)
                    │
                    │ deposit 2 ETH (담보)
                    ▼
            ┌───────────────┐
            │   Join (ETH)  │ ← 자산별 금고 (MakerDAO와 유사)
            │   Asset Vault │
            └───────┬───────┘
                    │
                    ▼
            ┌───────────────┐
            │  Cauldron.sol │ ← 중앙 회계 (Vat과 유사)
            │  Accounting   │
            └───────┬───────┘
                    │
                    │ fyDAI 발행 (만기일 있음!)
                    ▼
            ┌───────────────┐
            │    Ladle.sol  │ ← 라우터 (사용자 진입점)
            │    Router     │    유저 → Ladle → Cauldron/Join
            └───────┬───────┘
                    │
                    ▼
               fyDAI 수령
          (2025-12-31에 1 DAI로 교환 가능)

핵심: "미래에 1 DAI가 될 토큰"을 지금 할인된 가격에 판매
Key: Selling a "token worth 1 DAI in the future" at a discount now
```

### 작동 원리 / How It Works

```
fyToken = "Fixed Yield Token"
  → 만기일이 있는 토큰
  → 만기일에 정확히 1:1로 underlying 자산과 교환

시나리오: Bob이 고정 금리로 대출받기

1. Bob이 2 ETH 담보로 넣음

2. Bob이 fyDAI 발행 (만기: 2025-12-31)
   → 1,000 fyDAI 수령
   → 각 fyDAI는 만기일에 1 DAI의 가치

3. Bob이 fyDAI를 시장에서 DAI로 교환
   → 현재 가격: 1 fyDAI = 0.95 DAI (5% 할인)
   → 1,000 fyDAI → 950 DAI 수령

4. 만기일에 Bob이 상환
   → 1,000 DAI를 갚아야 함 (fyDAI 발행량)
   → 실질 이자: 1,000 - 950 = 50 DAI (≈5.26%)

핵심 차이:
  - Pool-based: 이자율이 매 블록 변동 (변동 금리)
  - Fixed-rate: 이자율이 발행 시점에 확정 (고정 금리)
  - 고정 금리 = fyToken의 할인율로 결정됨
```

### 고정 금리의 원리 / How Fixed Rate Works

```
오늘 날짜: 2025-01-01
만기일:   2025-12-31 (1년 후)

fyDAI 가격 결정:
  현재 가격 0.95 DAI  → 연 이자율 ≈ 5.26%
  현재 가격 0.90 DAI  → 연 이자율 ≈ 11.1%
  현재 가격 0.80 DAI  → 연 이자율 ≈ 25.0%

가격이 낮을수록 → 이자율이 높다 (더 많은 할인)

차입자 입장:
  "지금 950 DAI 받고, 1년 후에 1,000 DAI 갚으면 돼"
  → 이자율 확정! 변동 없음!

대출자 입장:
  "지금 950 DAI로 fyDAI 1,000개 사면"
  → 1년 후 1,000 DAI 받음 → 확정 수익 5.26%
```

---

## 세 가지 유형 종합 비교 / Comprehensive Comparison

```
┌──────────────┬──────────────────┬──────────────────┬──────────────────┐
│              │ Pool-based       │ CDP-based        │ Fixed-rate       │
│              │ Compound/Aave   │ MakerDAO         │ Yield            │
├──────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 빌리는 것     │ 기존 토큰         │ 새로 발행한 DAI   │ fyToken          │
│ What you     │ Existing tokens  │ Newly minted DAI │ (할인된 미래토큰)   │
│ borrow       │                  │                  │ (discounted)     │
├──────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 이자율 유형    │ 변동 (Variable)  │ 반고정            │ 고정 (Fixed)      │
│ Rate type    │ Changes per block│ (Stability Fee)  │ Set at issuance  │
│              │ 매 블록 변동       │ 거버넌스가 변경    │ 발행시 확정        │
├──────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 이자율 결정    │ 사용률 알고리즘    │ 거버넌스 투표      │ 시장 가격         │
│ Rate decided │ Utilization algo │ Governance vote  │ Market price     │
│ by           │                  │                  │ (fyToken 할인율)  │
├──────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 만기일        │ 없음 (언제든 상환) │ 없음              │ 있음!            │
│ Maturity     │ None (repay any) │ None             │ Yes!             │
├──────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 예치자 필요    │ ✅ 필수          │ ❌               │ ❌               │
│ Depositors   │ Required         │ Not needed       │ Not needed       │
├──────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 유동성 위험    │ 높음 (bank run)  │ 없음              │ 없음              │
│ Liq. risk    │ High             │ None             │ None             │
├──────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 대표 예시     │ Compound, Aave  │ MakerDAO, Liquity│ Yield, Notional  │
│ Examples     │ Euler            │                  │                  │
├──────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 핵심 혁신     │ 풀 공유 + 자동이자 │ 스테이블코인 발행  │ 고정 금리 DeFi    │
│ Key          │ Shared pool +    │ Stablecoin       │ Fixed rates in   │
│ innovation   │ auto interest    │ issuance         │ DeFi             │
└──────────────┴──────────────────┴──────────────────┴──────────────────┘
```

---

## 아키텍처 진화 요약 / Architecture Evolution Summary

```
MakerDAO (2017)
  │  "안전 최우선, 가스비 비싸도 OK"
  │  "Safety first, gas costs secondary"
  │
  │  설계: Vat 중앙회계 + Join 분산금고 + 경매 청산
  │  Design: Vat accounting + Join vaults + Auction liquidation
  │
  ├──→ Compound V2 (2019)
  │      "cToken으로 조합성(composability) 확보!"
  │      "cTokens enable composability!"
  │
  │      혁신: 예치 포지션 토큰화 (cToken = ERC-20)
  │      Innovation: Tokenized lending positions
  │      → 다른 DeFi에서 cToken을 담보로 사용 가능
  │
  ├──→ Aave V2 (2020)
  │      "부채도 토큰화하자! + 단일 Pool로 통합"
  │      "Tokenize debt too! + Single Pool"
  │
  │      혁신: aToken (예치) + vToken (부채) 토큰화
  │      → 부채 포지션도 거래 가능 (theoretically)
  │      → Flash Loan 도입
  │
  ├──→ Yield V2 (2021)
  │      "MakerDAO 구조 + 가스 최적화 + 고정금리"
  │      "MakerDAO structure + gas optimization + fixed rates"
  │
  │      혁신: Ladle 라우터 패턴 + fyToken 고정금리
  │      → 사용자는 Ladle 하나만 호출
  │      → 오라클 방향 반전: push → pull
  │
  └──→ Euler (2022)
         "전부 하나의 스토리지에 넣자 (Diamond 패턴)"
         "Put everything in one storage (Diamond pattern)"

         혁신: 단일 스토리지 + 모듈 프록시
         → 가스 최소화 (컨트랙트간 호출 제거)
         → 모듈 독립 업그레이드 가능

  ──→ Compound V3 (2022)
         "다시 단순하게: 시장별 독립 컨트랙트"
         "Back to simple: separate contract per market"

         ⚠️ 방향 반전: 복잡한 통합 → 단순한 분리
         → 오라클 공격 후 안전성 재우선
```

---

## DevOps 관점에서의 차이 / DevOps Perspective

```
모니터링 포인트가 프로토콜 유형에 따라 다르다:

Pool-based (Compound/Aave):
  - 사용률(utilization) 모니터링 → 이자율 급등 감지
  - Bank run 위험: 예치금 < 대출금이면 인출 불가
  - Health Factor 모니터링 → 청산 기회 감지
  - 풀별 유동성 추적

CDP-based (MakerDAO):
  - Stability Fee 변경 거버넌스 추적
  - DAI peg ($1 유지) 모니터링
  - 경매(auction) 시스템 모니터링 → Keeper 봇 운영
  - Vault별 담보비율 추적

Fixed-rate (Yield):
  - 만기일 관리 → 시리즈별 만기 추적
  - fyToken 가격 모니터링 → 내재 금리 계산
  - 만기 도래 시 정산 프로세스 모니터링
  - 롤오버(만기 연장) 이벤트 추적
```

---

## 비유로 이해하기 / Analogy

```
Pool-based (Compound/Aave):
  = 은행 (Bank)
  → 예금자가 돈을 맡기면, 은행이 대출자에게 빌려줌
  → 이자율은 수요-공급으로 결정

CDP-based (MakerDAO):
  = 중앙은행 (Central Bank)
  → 담보를 맡기면 새로운 화폐(DAI)를 발행
  → 이자율은 통화정책(거버넌스)으로 결정

Fixed-rate (Yield):
  = 채권 시장 (Bond Market)
  → "1년 후 100만원" 짜리 채권을 지금 95만원에 거래
  → 이자율은 채권 가격(시장)으로 결정
```
