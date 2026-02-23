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
- 심화: [deep-dive/health-factor.md](deep-dive/health-factor.md)

#### Utilization Rate — 사용률

- U = 총 대출금 / 총 예치금
- U = Total Borrows / Total Deposits
- 높을수록 → 이자율 높아짐 (유동성 복귀 유도)
- Higher → interest rates increase (incentivizes liquidity return)
- **스테이킹 비유**: 검증자 큐와 유사 — 수요가 많으면 진입이 어려움

#### Interest Rate Model — 이자율 모델

- Jump Rate Model: Compound V2 원조, kink 기반 이자율 급등 구조
- 사용률 ≤ kink: 완만한 증가 / Gradual increase
- 사용률 > kink: 급격한 증가 / Steep increase (incentivizes liquidity return)
- 심화: [deep-dive/interest-rates.md](deep-dive/interest-rates.md)

#### Reserve Factor — 프로토콜 수수료

- 대출자 이자의 일부를 프로토콜 금고에 적립
- 보통 10~35% (프로토콜별 상이)
- 심화: [deep-dive/interest-rates.md](deep-dive/interest-rates.md)

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

### 간편 공식 / Quick Formulas

```
HF = LT / LTV
최대 하락률 = 1 - (LTV / LT)
Supply APY = Borrow APR × Utilization × (1 - Reserve Factor)
```

---

## 심화 학습 / Deep Dive

학습 중 발생한 Q&A와 상세 예제는 별도 파일에 정리:

| 주제 / Topic   | 파일 / File                                                | 내용 / Contents                                                  |
| -------------- | ---------------------------------------------------------- | ---------------------------------------------------------------- |
| Health Factor  | [deep-dive/health-factor.md](deep-dive/health-factor.md)   | BTC $100K 예제, LTV별 비교, HF 간편 공식                         |
| Interest Rates | [deep-dive/interest-rates.md](deep-dive/interest-rates.md) | 이자 계산 예제, RF 프로토콜 비교, 3 Layers, 프로토콜별 모델 비교 |

---

## 할 일 / TODO

- [x] [`defi-lending-protocol-guide.md`](../defi-lending-protocol-guide.md) 섹션 1-3 읽기 / Read Sections 1-3
- [x] [Finematics: DeFi Lending Explained](https://www.youtube.com/watch?v=aTp9er6S73M) 영상 시청
- [x] [Finematics: Flash Loans Explained](https://www.youtube.com/watch?v=mCJUhnXQ76s) 영상 시청
- [x] ~~[SpeedRunEthereum 렌딩 챌린지](https://speedrunethereum.com/challenge/over-collateralized-lending)~~ — 이미 LendingPool.sol로 더 완전하게 구현함
- [ ] [Compound V2 코드](https://github.com/compound-finance/compound-protocol) 읽기
