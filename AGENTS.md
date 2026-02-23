# AGENTS.md — AI Assistant Guide for Lending Protocol Study
# AI 어시스턴트 가이드 — 렌딩 프로토콜 학습 프로젝트

## Project Purpose / 프로젝트 목적

This is a 1-week intensive learning project for DeFi lending protocols.
The learner is an experienced Go developer and node operator transitioning to lending protocol DevOps.

이 프로젝트는 DeFi 렌딩 프로토콜을 1주일 집중 학습하기 위한 프로젝트입니다.
학습자는 Go 개발자이자 노드 오퍼레이터로서, 렌딩 프로토콜 DevOps로 전환 중입니다.

## Language Rule / 언어 규칙

**모든 설명은 한국어와 영어 모두 제공합니다.**
**All explanations must be provided in both Korean and English.**

- Code comments: Korean explanation first, then English
- Documentation: Bilingual (Korean + English)
- Variable names and function names: English only (standard convention)

```solidity
// 예치금에 대한 이자율을 계산합니다
// Calculate the interest rate for deposits
function getSupplyRate(...) external view returns (uint256) { ... }
```

## Directory Structure / 디렉토리 구조

```
LendingProtocolStudy/
├── AGENTS.md                          # This file / 이 파일
├── defi-lending-protocol-guide.md     # Core study guide / 핵심 학습 가이드
│
├── contracts/                         # Foundry project / Foundry 프로젝트
│   ├── foundry.toml                   # Foundry config
│   ├── src/
│   │   ├── JumpRateModel.sol          # Day 2: Interest rate model / 이자율 모델
│   │   ├── LendingPool.sol            # Day 7: Core lending pool / 핵심 렌딩 풀
│   │   ├── InterestRateModel.sol      # Day 7: Integrated rate model / 통합 이자율 모델
│   │   ├── PriceOracle.sol            # Day 7: Chainlink oracle / 체인링크 오라클
│   │   ├── LToken.sol                 # Day 7: Deposit receipt token / 예치 영수증 토큰
│   │   └── DebtToken.sol              # Day 7: Debt tracking token / 부채 추적 토큰
│   ├── test/
│   │   ├── JumpRateModel.t.sol        # Day 2: Rate model tests / 이자율 모델 테스트
│   │   ├── AaveFork.t.sol             # Day 3: Mainnet fork tests / 메인넷 포크 테스트
│   │   ├── InterestRate.fuzz.t.sol    # Day 3: Fuzz tests / 퍼즈 테스트
│   │   ├── LendingPool.invariant.t.sol# Day 3: Invariant tests / 불변성 테스트
│   │   ├── LendingPool.t.sol          # Day 7: Full flow tests / 전체 흐름 테스트
│   │   ├── Liquidation.t.sol          # Day 7: Liquidation tests / 청산 테스트
│   │   └── Oracle.t.sol               # Day 7: Oracle tests / 오라클 테스트
│   └── script/
│       └── Deploy.s.sol               # Deployment script / 배포 스크립트
│
├── monitoring/                        # Go monitoring tools / Go 모니터링 도구
│   ├── go.mod
│   ├── go.sum
│   ├── cmd/
│   │   ├── monitor/main.go            # Health factor monitor / 헬스팩터 모니터
│   │   ├── indexer/main.go            # Event indexer / 이벤트 인덱서
│   │   └── alerter/main.go           # Alert service / 알림 서비스
│   └── internal/
│       ├── contracts/                 # ABI bindings / ABI 바인딩
│       │   └── aave_pool.go
│       ├── metrics/                   # Prometheus metrics / 프로메테우스 메트릭
│       │   └── metrics.go
│       └── alert/                     # Alert integrations / 알림 통합
│           └── webhook.go
│
└── notes/                             # Study notes / 학습 노트
    ├── day1-core-concepts.md
    ├── day2-interest-rates.md
    ├── day3-liquidation.md
    ├── day4-monitoring.md
    ├── day5-security.md
    ├── day6-cross-chain.md
    └── day7-integration.md
```

## Conventions / 컨벤션

### Solidity / Foundry

- Solidity version: `^0.8.20`
- Use Foundry for all Solidity development (compile, test, deploy)
- Test file naming: `*.t.sol` for tests, `*.s.sol` for scripts
- Use `forge fmt` for formatting
- Import OpenZeppelin contracts via `@openzeppelin/`
- Import Chainlink contracts via `@chainlink/`

### Go Monitoring Tool

- Go version: 1.21+
- Use `go-ethereum` (geth) for Ethereum interaction
- Expose Prometheus metrics on `:9090/metrics`
- Use structured logging (`log/slog`)
- Follow standard Go project layout

### Testing

- **Foundry-first**: All smart contract testing via `forge test`
- Fork testing: Use `vm.createSelectFork()` for mainnet interaction
- Fuzz testing: Use `testFuzz_` prefix with `bound()` for input ranges
- Invariant testing: Use `invariant_` prefix
- Go testing: Standard `go test` with table-driven tests

## Key Concepts Reference / 핵심 개념 참조

| Concept / 개념 | Description / 설명 |
|---|---|
| LTV (Loan-to-Value) | 담보 대비 대출 비율 / Ratio of loan to collateral value |
| Health Factor | 청산 기준 지표 (< 1이면 청산 가능) / Liquidation threshold indicator (< 1 = liquidatable) |
| Utilization Rate | 풀 사용률 = 대출금 / 예치금 / Pool usage = borrows / deposits |
| Collateral Factor | 담보로 인정되는 비율 / Percentage of collateral recognized |
| Liquidation Bonus | 청산자에게 주는 보너스 (보통 5-10%) / Bonus given to liquidator (typically 5-10%) |
| Kink | 이자율 급등 지점 (보통 80%) / Interest rate jump point (typically 80%) |

## Staking → Lending Mental Model / 스테이킹 → 렌딩 멘탈 모델

| Staking (You Know) / 스테이킹 (아는 것) | Lending Equivalent / 렌딩 대응 개념 |
|---|---|
| Validator effective balance / 검증자 유효 잔액 | Health Factor / 헬스 팩터 |
| Slashing / 슬래싱 | Liquidation / 청산 |
| Attestation rewards / 증명 보상 | Supply APY / 공급 이자율 |
| Staking APR / 스테이킹 연이율 | Borrow APR / 대출 이자율 |
| Validator queue / 검증자 큐 | Utilization rate / 사용률 |
| Beacon chain state / 비콘 체인 상태 | Pool accounting / 풀 회계 |
| Node monitoring / 노드 모니터링 | Protocol monitoring / 프로토콜 모니터링 |
| Chain sync status / 체인 동기화 상태 | Oracle staleness / 오라클 지연 |
