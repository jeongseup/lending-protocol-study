# Day 5: 보안 + 배포 패턴
# Day 5: Security + Deployment Patterns

## 프록시 패턴 / Proxy Patterns

### TransparentProxy (Aave V3 사용)
- 관리자 ↔ 사용자 호출 분리
- Admin ↔ User call separation
- OpenZeppelin 구현 사용

### UUPS (최신 프로토콜)
- 업그레이드 로직이 구현 컨트랙트에 존재
- Upgrade logic lives in implementation contract

### Diamond Pattern (EIP-2535)
- 여러 구현(Facet)을 하나의 프록시에 연결
- Multiple implementations (Facets) connected to one proxy

## 주요 DeFi 해킹 사례 / Major DeFi Hacks

### 1. Euler Finance ($200M) — Donation Attack
- **원인**: donate 함수에서 헬스팩터 체크 누락
- **교훈**: 모든 상태 변경 후 HF 확인 필수

### 2. Cream Finance ($130M) — Flash Loan + Oracle Manipulation
- **원인**: 단일 오라클 의존 + 플래시 론 공격
- **교훈**: 다중 오라클 + TWAP 사용

### 3. Radiant Capital ($50M) — Multisig Compromise
- **원인**: 멀티시그 키 탈취
- **교훈**: 하드웨어 월렛 + 타임락 필수

## 할 일 / TODO
- [ ] 가이드 섹션 9 읽기 / Read guide Section 9
- [ ] Rekt News 해킹 사후 분석 읽기 / Read Rekt News post-mortems
- [ ] 업그레이더블 컨트랙트 테스트넷 배포 / Deploy upgradeable contract to testnet
- [ ] 모니터링 대시보드 설계 / Design monitoring dashboard
