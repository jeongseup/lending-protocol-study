# Lending Protocol Study

DeFi 렌딩 프로토콜을 1주일 만에 학습하기 위한 실전 프로젝트입니다.
Solidity 스마트 컨트랙트 구현부터 Go 모니터링 도구까지, 렌딩 프로토콜 DevOps 엔지니어가 되기 위한 전 과정을 다룹니다.

A hands-on project to learn DeFi lending protocols in one week.
Covers everything from Solidity smart contracts to Go monitoring tools — a full path to becoming a lending protocol DevOps engineer.

## Who Is This For? / 대상

- Solidity/DeFi에 입문하려는 백엔드 개발자
- 노드 오퍼레이터/스테이킹에서 렌딩 DevOps로 전환하려는 엔지니어
- 렌딩 프로토콜의 작동 원리를 코드 레벨에서 이해하고 싶은 사람

## What You'll Learn / 학습 내용

### Core Concepts / 핵심 개념
- **Overcollateralized Lending** — 과담보 대출의 원리와 이유
- **Health Factor & Liquidation** — 청산 메커니즘과 헬스팩터 계산
- **Interest Rate Model** — Jump Rate Model을 통한 이자율 결정 구조
- **Reserve Factor** — 프로토콜 수수료와 이자 분배 메커니즘
- **Token Incentives** — COMP/AAVE 토큰 인센티브와 Yield Farming

### Smart Contracts / 스마트 컨트랙트 (Solidity)
- 6개의 핵심 컨트랙트를 직접 구현
- Foundry 기반 테스트 (unit, fuzz, invariant, fork, scenario)

### Monitoring Tools / 모니터링 도구 (Go)
- Health Factor 실시간 모니터
- 온체인 이벤트 인덱서
- 알림 서비스 (Slack/Discord webhook)

## Project Structure / 프로젝트 구조

```
LendingProtocolStudy/
├── contracts/                          # Foundry project (Solidity)
│   ├── src/
│   │   ├── LendingPool.sol            # 핵심 렌딩 풀 (deposit/borrow/repay/liquidate)
│   │   ├── JumpRateModel.sol          # 이자율 모델 (kink 기반 Jump Rate)
│   │   ├── InterestRateModel.sol      # LendingPool 통합 이자율 모델
│   │   ├── PriceOracle.sol            # Chainlink 오라클 연동
│   │   ├── LToken.sol                 # 예치 영수증 토큰 (aToken 유사)
│   │   └── DebtToken.sol              # 부채 추적 토큰 (양도 불가)
│   ├── test/
│   │   ├── JumpRateModel.t.sol        # 이자율 모델 단위 테스트
│   │   ├── LendingPool.t.sol          # 전체 흐름 테스트 (14 tests)
│   │   ├── Liquidation.t.sol          # 청산 시나리오 테스트
│   │   ├── Oracle.t.sol               # 오라클 테스트 (staleness 등)
│   │   ├── InterestRate.fuzz.t.sol    # 퍼즈 테스트 (엣지 케이스)
│   │   ├── LendingPool.invariant.t.sol# 불변성 테스트
│   │   └── AaveFork.t.sol             # 메인넷 포크 테스트
│   └── script/
│       └── Deploy.s.sol               # 배포 스크립트
│
├── monitoring/                         # Go monitoring tools
│   ├── cmd/
│   │   ├── monitor/                   # Health Factor 모니터 + Prometheus
│   │   ├── indexer/                    # 온체인 이벤트 인덱서
│   │   └── alerter/                   # 알림 서비스 (webhook)
│   └── internal/
│       ├── contracts/                  # ABI 바인딩
│       ├── metrics/                    # Prometheus 메트릭 정의
│       └── alert/                      # 알림 로직
│
├── notes/                              # 일별 학습 노트 (한/영 이중 언어)
│   ├── day1-core-concepts.md          # 핵심 개념 + 예제
│   ├── day2-interest-rates.md         # 이자율 모델 심화
│   ├── day3-liquidation.md            # 청산 메커니즘
│   ├── day4-monitoring.md             # 모니터링 & DevOps
│   ├── day5-security.md               # 보안 & 감사
│   ├── day6-cross-chain.md            # 크로스체인
│   └── day7-integration.md            # 통합 프로젝트
│
└── defi-lending-protocol-guide.md      # 전체 학습 가이드
```

## 1-Week Curriculum / 1주일 커리큘럼

| Day | Topic / 주제 | Output / 산출물 |
|-----|-------------|----------------|
| 1 | Core Concepts — LTV, Health Factor, Utilization Rate | 핵심 개념 정리 노트 |
| 2 | Interest Rate Models — Jump Rate, Reserve Factor | `JumpRateModel.sol` 구현 + 테스트 |
| 3 | Testing & Security — Fuzz, Invariant, Fork Testing | 고급 테스트 작성 |
| 4 | Monitoring & DevOps — Go 모니터링 도구 | Health Factor 모니터 |
| 5 | Security & Auditing — Oracle, Reentrancy, Flash Loan | 보안 체크리스트 |
| 6 | Cross-chain & Advanced — 브릿지, 거버넌스 | 크로스체인 분석 |
| 7 | Integration — 전체 시스템 통합 | `LendingPool.sol` + 전체 테스트 |

## Quick Start / 빠른 시작

### Prerequisites / 사전 준비

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- [Go 1.21+](https://go.dev/dl/)

### Setup / 설정

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/jeongseup/LendingProtocolStudy.git
cd LendingProtocolStudy

# If already cloned without submodules
git submodule update --init --recursive
```

### Build & Test Contracts / 컨트랙트 빌드 & 테스트

```bash
cd contracts

# Build
forge build

# Run all tests (61 tests)
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/LendingPool.t.sol

# Run fuzz tests
forge test --match-path test/InterestRate.fuzz.t.sol

# Run fork tests (requires RPC URL)
FORK_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY forge test --match-path test/AaveFork.t.sol
```

### Build Monitoring Tools / 모니터링 도구 빌드

```bash
cd monitoring

# Build all
go build ./...

# Run health factor monitor
go run ./cmd/monitor --rpc-url ws://localhost:8545 --pool-address 0x...

# Run event indexer
go run ./cmd/indexer --rpc-url ws://localhost:8545 --pool-address 0x...

# Run alerter
go run ./cmd/alerter --rpc-url ws://localhost:8545 --pool-address 0x... --webhook-url https://hooks.slack.com/...
```

## Key Formulas / 핵심 공식

```
Health Factor = Σ(담보 × 가격 × 청산기준) / Σ(부채 × 가격)
             = Σ(collateral × price × liquidation_threshold) / Σ(debt × price)

Quick: HF = LT / LTV
Max Price Drop = 1 - (LTV / LT)

Borrow Rate (below kink) = baseRate + (utilization × multiplier)
Borrow Rate (above kink) = baseRate + (kink × multiplier) + ((util - kink) × jumpMultiplier)

Supply APY = Borrow APR × Utilization × (1 - Reserve Factor)
```

## Study Notes Highlights / 학습 노트 하이라이트

학습 노트는 한국어와 영어로 작성되어 있으며, 실제 숫자 예제가 포함되어 있습니다.

- **BTC $100K 예제**: $100 담보, LTV 80%일 때 BTC 6% 하락만으로 청산
- **이자율 계산**: Jump Rate Model로 사용률 80% 초과 시 이자율 4배 급등
- **이자 흐름**: Borrower → Protocol (RF 10%) → Depositor
- **3 Layers**: Base Interest + Token Incentives + Points/Airdrops

## Test Results / 테스트 결과

```
Ran 7 test suites: 61 tests passed, 0 failed, 2 skipped (63 total tests)
```

| Test Suite | Tests | Description |
|-----------|-------|-------------|
| JumpRateModel.t.sol | 18 | 이자율 모델 단위 + 퍼즈 테스트 |
| LendingPool.t.sol | 14 | deposit/borrow/repay/withdraw 전체 흐름 |
| Oracle.t.sol | 13 | 오라클 staleness, 가격 검증 |
| Liquidation.t.sol | 6 | 청산 시나리오 |
| InterestRate.fuzz.t.sol | 6 | 이자율 엣지 케이스 퍼즈 |
| LendingPool.invariant.t.sol | 2 | 풀 불변성 (solvency, debt consistency) |
| AaveFork.t.sol | 2 (skipped) | 메인넷 포크 (RPC URL 필요) |

## References / 참고 자료

- [Aave V3 Documentation](https://docs.aave.com/)
- [Compound V2 Whitepaper](https://compound.finance/documents/Compound.Whitepaper.pdf)
- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)

## License

MIT
