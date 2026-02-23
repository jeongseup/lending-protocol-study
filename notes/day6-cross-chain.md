# Day 6: 크로스체인 + 고급 주제
# Day 6: Cross-Chain + Advanced Topics

## 크로스체인 렌딩 / Cross-Chain Lending

### 메시징 레이어 비교 / Messaging Layer Comparison
| 특성 | LayerZero | Chainlink CCIP |
|------|-----------|----------------|
| 아키텍처 | Ultra Light Node | DON 기반 |
| DeFi 채택 | 높음 | 성장 중 |
| 보안 | 오라클+릴레이어 | 엔터프라이즈급 |
| Architecture | Ultra Light Nodes | DON-based |
| DeFi Adoption | High | Growing |
| Security | Oracle+Relayer | Enterprise grade |

### DevOps 과제 / DevOps Challenges
- 메시지 최종성 지연 (소스 체인 리오그 시?)
- Message finality delays (source chain reorg?)
- 릴레이어/오라클 인프라 운영
- Relayer/Oracle infrastructure operation
- 크로스체인 헬스팩터 동기화
- Cross-chain health factor synchronization

## Aave V3 고급 기능 / Aave V3 Advanced Features

### Isolation Mode — 격리 모드
- 위험한 새 자산을 격리하여 추가
- Sandbox new risky assets in isolation

### E-Mode (Efficiency Mode) — 효율 모드
- 상관 자산에 높은 LTV 허용 (예: stETH/ETH)
- Higher LTV for correlated assets (e.g., stETH/ETH)

### Portal — 크로스체인 유동성 브리징
- 체인 간 유동성 이동
- Cross-chain liquidity bridging

### Supply/Borrow Caps — 공급/대출 상한
- DevOps가 관리하는 리스크 파라미터
- Risk parameters managed by DevOps

## 할 일 / TODO
- [ ] 가이드 섹션 8 읽기 / Read guide Section 8
- [ ] CCIP DeFi 렌딩 데모 배포 / Deploy CCIP DeFi lending demo
- [ ] Aave V3 고급 기능 노트 / Notes on Aave V3 advanced features
