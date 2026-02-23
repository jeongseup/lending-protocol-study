# Day 4: Go 모니터링 도구 + 오라클
# Day 4: Go Monitoring Tool + Oracles

## Go 모니터링 도구 / Go Monitoring Tool

### 구조 / Structure
```
monitoring/
├── cmd/
│   ├── monitor/    # 헬스팩터 모니터 / Health factor monitor
│   ├── indexer/    # 이벤트 인덱서 / Event indexer
│   └── alerter/    # 알림 서비스 / Alert service
└── internal/
    ├── contracts/  # ABI 바인딩 / ABI bindings
    ├── metrics/    # Prometheus 메트릭 / Prometheus metrics
    └── alert/      # 웹훅 알림 / Webhook alerts
```

### 핵심 Prometheus 메트릭 / Key Prometheus Metrics
```
lending_health_factor{protocol="aave",user="0x..."}     1.45
lending_utilization_rate{protocol="aave",asset="USDC"}   0.82
lending_oracle_staleness_seconds{feed="ETH/USD"}         120
lending_total_borrows{protocol="aave",asset="WETH"}      15000.5
lending_liquidation_events_total{protocol="aave"}        42
lending_tvl{protocol="aave"}                             12000000000
```

## 오라클 모니터링 / Oracle Monitoring

### Chainlink 가격 피드 / Chainlink Price Feeds
- `latestRoundData()` 호출로 가격 조회
- `updatedAt` 확인 → 지연(staleness) 감지
- 여러 소스 비교 (Chainlink vs DEX TWAP)

### 지연 감지 기준 / Staleness Detection Criteria
- ETH/USD: 1시간 / 1 hour
- 스테이블코인: 24시간 / 24 hours
- 소형 자산: 30분 / 30 minutes

## 할 일 / TODO
- [ ] 가이드 섹션 7 읽기 / Read guide Section 7
- [ ] Chainlink 문서 읽기 / Read Chainlink docs
- [ ] Go 모니터링 도구 빌드 / Build Go monitoring tool
- [ ] 실제 RPC로 헬스팩터 조회 테스트 / Test health factor query with real RPC
