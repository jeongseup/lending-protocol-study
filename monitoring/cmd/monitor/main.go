// 렌딩 프로토콜 헬스팩터 모니터 — Day 4 학습
// Lending protocol health factor monitor — Day 4 learning
//
// 이 프로그램은 Aave V3 포지션을 모니터링하고 낮은 헬스팩터를 감지합니다.
// This program monitors Aave V3 positions and detects low health factors.
//
// 실행 방법 / How to run:
//
//	go run ./cmd/monitor --rpc-url $ETH_RPC_URL --addresses 0x123...,0x456...
//
// DevOps 관점:
// - 노드 운영 경험의 RPC 연결 패턴을 활용합니다
// - Prometheus 메트릭으로 Grafana 대시보드와 연동합니다
// - 웹훅으로 Telegram/Slack 알림을 전송합니다
//
// DevOps perspective:
// - Leverages RPC connection patterns from node operations experience
// - Integrates with Grafana dashboards via Prometheus metrics
// - Sends Telegram/Slack alerts via webhooks
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/jeongseup/lending-monitor/internal/contracts"
	"github.com/jeongseup/lending-monitor/internal/metrics"
)

func main() {
	// CLI 플래그 설정 / CLI flag setup
	rpcURL := flag.String("rpc-url", "", "이더리움 RPC URL / Ethereum RPC URL (required)")
	addresses := flag.String("addresses", "", "모니터링할 주소 (쉼표 구분) / Addresses to monitor (comma-separated)")
	interval := flag.Duration("interval", 30*time.Second, "모니터링 주기 / Monitoring interval")
	metricsPort := flag.String("metrics-port", ":9090", "Prometheus 메트릭 포트 / Prometheus metrics port")
	webhookURL := flag.String("webhook-url", "", "알림 웹훅 URL / Alert webhook URL (optional)")
	flag.Parse()

	// 로거 설정 / Logger setup
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	if *rpcURL == "" {
		logger.Error("RPC URL이 필요합니다 / RPC URL is required")
		flag.Usage()
		os.Exit(1)
	}

	// 이더리움 클라이언트 연결 / Connect to Ethereum client
	// 노드 운영 경험 활용: 안정적인 RPC 연결 패턴
	// Leveraging node ops experience: reliable RPC connection pattern
	logger.Info("RPC 연결 중... / Connecting to RPC...", "url", *rpcURL)
	client, err := ethclient.Dial(*rpcURL)
	if err != nil {
		logger.Error("RPC 연결 실패 / Failed to connect to RPC", "error", err)
		os.Exit(1)
	}
	defer client.Close()

	// 체인 ID 확인 / Verify chain ID
	chainID, err := client.ChainID(context.Background())
	if err != nil {
		logger.Error("체인 ID 조회 실패 / Failed to get chain ID", "error", err)
		os.Exit(1)
	}
	logger.Info("연결 완료 / Connected", "chainID", chainID)

	// 모니터링 대상 주소 파싱 / Parse monitoring target addresses
	var monitorAddresses []common.Address
	if *addresses != "" {
		for _, addr := range strings.Split(*addresses, ",") {
			addr = strings.TrimSpace(addr)
			if common.IsHexAddress(addr) {
				monitorAddresses = append(monitorAddresses, common.HexToAddress(addr))
			} else {
				logger.Warn("잘못된 주소 무시 / Ignoring invalid address", "address", addr)
			}
		}
	}

	logger.Info("모니터링 설정 완료 / Monitor configured",
		"addresses", len(monitorAddresses),
		"interval", interval.String(),
	)

	// Aave Pool 클라이언트 생성 / Create Aave Pool client
	poolCaller := contracts.NewAavePoolCaller(client, contracts.AaveV3Pool)

	// Prometheus 메트릭 서버 시작 / Start Prometheus metrics server
	go func() {
		http.Handle("/metrics", promhttp.Handler())
		logger.Info("메트릭 서버 시작 / Metrics server started", "port", *metricsPort)
		if err := http.ListenAndServe(*metricsPort, nil); err != nil {
			logger.Error("메트릭 서버 오류 / Metrics server error", "error", err)
		}
	}()

	// 컨텍스트 설정 (graceful shutdown) / Context setup (graceful shutdown)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 시그널 핸들링 / Signal handling
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	// 모니터링 루프 / Monitoring loop
	ticker := time.NewTicker(*interval)
	defer ticker.Stop()

	logger.Info("모니터링 시작 / Starting monitoring loop...")

	// 첫 번째 실행 / First run
	monitorCycle(ctx, logger, poolCaller, monitorAddresses, *webhookURL)

	for {
		select {
		case <-ticker.C:
			monitorCycle(ctx, logger, poolCaller, monitorAddresses, *webhookURL)
		case sig := <-sigCh:
			logger.Info("종료 시그널 수신 / Received shutdown signal", "signal", sig)
			cancel()
			return
		case <-ctx.Done():
			return
		}
	}
}

// monitorCycle은 한 번의 모니터링 사이클을 실행합니다.
// monitorCycle executes one monitoring cycle.
func monitorCycle(
	ctx context.Context,
	logger *slog.Logger,
	poolCaller *contracts.AavePoolCaller,
	addresses []common.Address,
	webhookURL string,
) {
	start := time.Now()
	defer func() {
		duration := time.Since(start).Seconds()
		metrics.MonitorCycleDuration.Observe(duration)
		logger.Info("모니터링 사이클 완료 / Monitor cycle complete",
			"duration_ms", time.Since(start).Milliseconds(),
			"addresses_checked", len(addresses),
		)
	}()

	// 1e18을 big.Float로 변환 (헬스팩터 스케일링용)
	// Convert 1e18 to big.Float (for health factor scaling)
	scale := new(big.Float).SetFloat64(1e18)

	for _, addr := range addresses {
		// 사용자 계정 데이터 조회 / Get user account data
		data, err := poolCaller.GetUserAccountData(nil, addr)
		if err != nil {
			logger.Error("계정 데이터 조회 실패 / Failed to get account data",
				"address", addr.Hex(),
				"error", err,
			)
			continue
		}

		// 헬스팩터를 사람이 읽을 수 있는 형식으로 변환
		// Convert health factor to human-readable format
		// 헬스팩터는 18 소수점 (1e18 = 1.0)
		// Health factor has 18 decimals (1e18 = 1.0)
		hfFloat := new(big.Float).SetInt(data.HealthFactor)
		hfFloat.Quo(hfFloat, scale)
		hfValue, _ := hfFloat.Float64()

		// Prometheus 메트릭 업데이트 / Update Prometheus metrics
		metrics.HealthFactor.WithLabelValues("aave-v3", addr.Hex()).Set(hfValue)

		// 로깅 / Logging
		logger.Info("포지션 상태 / Position status",
			"address", addr.Hex(),
			"health_factor", fmt.Sprintf("%.4f", hfValue),
			"total_collateral", data.TotalCollateralBase.String(),
			"total_debt", data.TotalDebtBase.String(),
		)

		// 헬스팩터 알림 확인 / Check health factor alerts
		// < 1.0: 즉시 청산 가능 / immediately liquidatable
		// < 1.2: 경고 (곧 청산될 수 있음) / warning (may become liquidatable)
		if hfValue < 1.2 && hfValue > 0 && webhookURL != "" {
			logger.Warn("낮은 헬스팩터 감지! / Low health factor detected!",
				"address", addr.Hex(),
				"health_factor", hfValue,
			)
			// TODO: 웹훅 알림 전송 / Send webhook alert
			// alerter.AlertOnLowHealthFactor(ctx, addr.Hex(), hfFloat)
		}
	}
}
