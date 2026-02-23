// Package metrics는 렌딩 프로토콜 모니터링을 위한 Prometheus 메트릭을 정의합니다.
// Package metrics defines Prometheus metrics for lending protocol monitoring.
package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// 렌딩 프로토콜 모니터링 메트릭 / Lending protocol monitoring metrics
//
// DevOps 관점에서 모니터링해야 할 핵심 메트릭:
// Key metrics to monitor from DevOps perspective:
// 1. 헬스팩터 — 청산 위험 감지 / Health factor — liquidation risk detection
// 2. 사용률 — 유동성 부족 감지 / Utilization — liquidity shortage detection
// 3. 오라클 지연 — 가격 데이터 신뢰성 / Oracle staleness — price data reliability
// 4. TVL — 프로토콜 전체 건전성 / TVL — overall protocol health
// 5. 청산 이벤트 수 — 시장 변동성 지표 / Liquidation events — market volatility indicator

var (
	// HealthFactor는 사용자별 헬스팩터를 추적합니다.
	// HealthFactor tracks health factor per user.
	// < 1.0이면 청산 가능! 알림 필요!
	// < 1.0 means liquidatable! Alert needed!
	HealthFactor = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "lending",
			Name:      "health_factor",
			Help:      "사용자의 헬스팩터 (1.0 미만이면 청산 가능) / User's health factor (< 1.0 = liquidatable)",
		},
		[]string{"protocol", "user"},
	)

	// UtilizationRate는 자산별 사용률을 추적합니다.
	// UtilizationRate tracks utilization rate per asset.
	// 높은 사용률 = 대출 이자율 급증 = 출금 어려움
	// High utilization = borrow rate spike = withdrawal difficulty
	UtilizationRate = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "lending",
			Name:      "utilization_rate",
			Help:      "자산별 사용률 (0.0-1.0) / Asset utilization rate (0.0-1.0)",
		},
		[]string{"protocol", "asset"},
	)

	// OracleStalenessSeconds는 오라클 가격 데이터의 지연 시간(초)입니다.
	// OracleStalenessSeconds is the oracle price data staleness in seconds.
	// 지연이 길면 가격이 부정확할 수 있음!
	// Long staleness means prices may be inaccurate!
	OracleStalenessSeconds = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "lending",
			Name:      "oracle_staleness_seconds",
			Help:      "오라클 가격 데이터 지연 시간 (초) / Oracle price data staleness in seconds",
		},
		[]string{"feed"},
	)

	// TotalBorrows는 자산별 총 대출금입니다.
	// TotalBorrows is total borrows per asset.
	TotalBorrows = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "lending",
			Name:      "total_borrows",
			Help:      "자산별 총 대출금 / Total borrows per asset",
		},
		[]string{"protocol", "asset"},
	)

	// TotalDeposits는 자산별 총 예치금입니다.
	// TotalDeposits is total deposits per asset.
	TotalDeposits = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "lending",
			Name:      "total_deposits",
			Help:      "자산별 총 예치금 / Total deposits per asset",
		},
		[]string{"protocol", "asset"},
	)

	// TVL은 프로토콜 전체 잠금 자산 가치입니다.
	// TVL is total value locked in the protocol.
	TVL = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "lending",
			Name:      "tvl",
			Help:      "프로토콜 전체 TVL (USD) / Total value locked in USD",
		},
		[]string{"protocol"},
	)

	// LiquidationEventsTotal은 청산 이벤트 총 수입니다.
	// LiquidationEventsTotal is total number of liquidation events.
	LiquidationEventsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Namespace: "lending",
			Name:      "liquidation_events_total",
			Help:      "청산 이벤트 총 수 / Total liquidation events",
		},
		[]string{"protocol"},
	)

	// BorrowRateAPY는 자산별 대출 이자율입니다.
	// BorrowRateAPY is borrow APY per asset.
	BorrowRateAPY = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "lending",
			Name:      "borrow_rate_apy",
			Help:      "자산별 대출 이자율 (APY) / Borrow rate APY per asset",
		},
		[]string{"protocol", "asset"},
	)

	// SupplyRateAPY는 자산별 예치 이자율입니다.
	// SupplyRateAPY is supply APY per asset.
	SupplyRateAPY = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "lending",
			Name:      "supply_rate_apy",
			Help:      "자산별 예치 이자율 (APY) / Supply rate APY per asset",
		},
		[]string{"protocol", "asset"},
	)

	// OraclePrice는 오라클에서 조회한 자산 가격입니다.
	// OraclePrice is asset price from oracle.
	OraclePrice = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "lending",
			Name:      "oracle_price_usd",
			Help:      "오라클 자산 가격 (USD) / Oracle asset price in USD",
		},
		[]string{"asset"},
	)

	// MonitorCycleDuration은 모니터링 사이클 소요 시간입니다.
	// MonitorCycleDuration is the duration of a monitoring cycle.
	MonitorCycleDuration = promauto.NewHistogram(
		prometheus.HistogramOpts{
			Namespace: "lending",
			Name:      "monitor_cycle_duration_seconds",
			Help:      "모니터링 사이클 소요 시간 (초) / Monitoring cycle duration in seconds",
			Buckets:   prometheus.DefBuckets,
		},
	)
)
