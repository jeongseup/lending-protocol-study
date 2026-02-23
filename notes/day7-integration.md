# Day 7: 통합 + 미니 렌딩 프로토콜 구축
# Day 7: Integration + Build Mini Lending Protocol

## 미니 렌딩 프로토콜 / Mini Lending Protocol

### 구현된 컨트랙트 / Implemented Contracts
| 파일 | 역할 |
|------|------|
| `LendingPool.sol` | 핵심 예치/대출/상환/청산 로직 / Core deposit/borrow/repay/liquidate |
| `InterestRateModel.sol` | Jump Rate 이자율 모델 / Jump Rate interest model |
| `PriceOracle.sol` | Chainlink 가격 피드 통합 / Chainlink price feed integration |
| `LToken.sol` | 예치 영수증 토큰 (aToken 유사) / Deposit receipt token |
| `DebtToken.sol` | 부채 추적 토큰 (전송 불가) / Debt tracking token (non-transferable) |

### 핵심 흐름 / Core Flows
1. **예치 (Deposit)**: 사용자 → ERC20 전송 → LToken 민팅
2. **대출 (Borrow)**: 담보 확인 → DebtToken 민팅 → 자산 전송
3. **이자 누적 (Interest)**: 시간 경과 → borrowIndex 증가 → totalBorrows 증가
4. **상환 (Repay)**: ERC20 전송 → DebtToken 소각
5. **청산 (Liquidation)**: HF < 1 → 부채 상환 → 담보 + 보너스 수령

### 테스트 결과 / Test Results
- JumpRateModel: 18 tests (including 3 fuzz tests) ✅
- Oracle: 13 tests ✅
- LendingPool: 14 tests ✅
- Liquidation: 6 tests ✅
- InterestRate Fuzz: 6 tests ✅
- Invariant: 2 tests ✅
- AaveFork: 2 pass, 2 skipped (need fork URL)

## Go 모니터링 스위트 / Go Monitoring Suite
- `cmd/monitor/` — 헬스팩터 + 사용률 모니터링
- `cmd/indexer/` — 이벤트 인덱서 (Deposit, Borrow, Liquidation)
- `cmd/alerter/` — 청산 가능 포지션 알림

## 학습 성과 확인 / Verification
- [x] LTV, Health Factor, Utilization Rate, Liquidation 설명 가능
- [ ] Aave V3 스마트 컨트랙트 코드 이해
- [x] 기본 렌딩 프로토콜 테스트넷 배포 가능
- [x] Go 모니터링 도구 빌드 가능
- [ ] Chainlink 오라클 작동 방식 + 모니터링 방법 설명
- [ ] 크로스체인 렌딩 아키텍처 이해
- [ ] 3개 이상 DeFi 해킹 사례 및 원인 설명
- [ ] 렌딩 프로토콜용 모니터링/알림 시스템 설계
