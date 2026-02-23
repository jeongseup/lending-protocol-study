// 렌딩 프로토콜 알림 서비스 — Day 5 학습
// Lending protocol alert service — Day 5 learning
//
// 이 프로그램은 렌딩 프로토콜의 이상 징후를 감지하고 알림을 전송합니다.
// This program detects anomalies in lending protocols and sends alerts.
//
// 알림 시나리오 / Alert scenarios:
// 1. 헬스팩터 < 1.2 → 경고 / Health factor < 1.2 → warning
// 2. 헬스팩터 < 1.0 → 긴급 (청산 가능) / Health factor < 1.0 → critical (liquidatable)
// 3. 오라클 지연 > 1시간 → 경고 / Oracle staleness > 1 hour → warning
// 4. 사용률 > 90% → 경고 / Utilization > 90% → warning
// 5. 대규모 청산 이벤트 → 긴급 / Large liquidation event → critical
//
// DevOps 관점:
// - 인시던트 대응의 첫 번째 단계: 빠른 감지 + 알림
// - 스테이킹 인프라의 모니터링 패턴을 렌딩에 적용
//
// DevOps perspective:
// - First step of incident response: fast detection + alerting
// - Applies staking infrastructure monitoring patterns to lending
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"math/big"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"

	"github.com/jeongseup/lending-monitor/internal/alert"
	"github.com/jeongseup/lending-monitor/internal/contracts"
)

// 알림 임계값 / Alert thresholds
const (
	// HealthFactorWarning은 경고 헬스팩터 임계값입니다.
	// HealthFactorWarning is the warning health factor threshold.
	HealthFactorWarning = 1.2

	// HealthFactorCritical은 긴급 헬스팩터 임계값입니다.
	// HealthFactorCritical is the critical health factor threshold.
	HealthFactorCritical = 1.0

	// OracleMaxStaleness는 최대 허용 오라클 지연 시간입니다.
	// OracleMaxStaleness is the maximum allowed oracle staleness.
	OracleMaxStaleness = 1 * time.Hour

	// UtilizationWarning은 경고 사용률 임계값입니다.
	// UtilizationWarning is the warning utilization threshold.
	UtilizationWarning = 0.90
)

func main() {
	// CLI 플래그 / CLI flags
	rpcURL := flag.String("rpc-url", "", "이더리움 RPC URL / Ethereum RPC URL (required)")
	addresses := flag.String("addresses", "", "모니터링할 주소 / Addresses to monitor (comma-separated)")
	webhookURL := flag.String("webhook-url", "", "알림 웹훅 URL / Alert webhook URL (required)")
	interval := flag.Duration("interval", 1*time.Minute, "확인 주기 / Check interval")
	flag.Parse()

	// 로거 설정 / Logger setup
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	if *rpcURL == "" || *webhookURL == "" {
		logger.Error("RPC URL과 웹훅 URL이 필요합니다 / RPC URL and webhook URL are required")
		flag.Usage()
		os.Exit(1)
	}

	// 이더리움 클라이언트 연결 / Connect to Ethereum client
	client, err := ethclient.Dial(*rpcURL)
	if err != nil {
		logger.Error("RPC 연결 실패 / Failed to connect to RPC", "error", err)
		os.Exit(1)
	}
	defer client.Close()

	// 주소 파싱 / Parse addresses
	var monitorAddresses []common.Address
	if *addresses != "" {
		for _, addr := range strings.Split(*addresses, ",") {
			addr = strings.TrimSpace(addr)
			if common.IsHexAddress(addr) {
				monitorAddresses = append(monitorAddresses, common.HexToAddress(addr))
			}
		}
	}

	// Aave Pool 클라이언트 / Aave Pool client
	poolCaller := contracts.NewAavePoolCaller(client, contracts.AaveV3Pool)

	// 알림 전송기 / Alert sender
	alerter := alert.NewWebhookAlerter(*webhookURL, logger)

	// 컨텍스트 / Context
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 시그널 핸들링 / Signal handling
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	logger.Info("알림 서비스 시작 / Alert service started",
		"addresses", len(monitorAddresses),
		"interval", interval.String(),
		"webhook", *webhookURL,
	)

	// 모니터링 루프 / Monitoring loop
	ticker := time.NewTicker(*interval)
	defer ticker.Stop()

	// 첫 번째 실행 / First run
	checkAndAlert(ctx, logger, poolCaller, alerter, monitorAddresses)

	for {
		select {
		case <-ticker.C:
			checkAndAlert(ctx, logger, poolCaller, alerter, monitorAddresses)
		case sig := <-sigCh:
			logger.Info("종료 시그널 수신 / Received shutdown signal", "signal", sig)
			return
		case <-ctx.Done():
			return
		}
	}
}

// checkAndAlert는 포지션을 확인하고 필요시 알림을 전송합니다.
// checkAndAlert checks positions and sends alerts when needed.
func checkAndAlert(
	ctx context.Context,
	logger *slog.Logger,
	poolCaller *contracts.AavePoolCaller,
	alerter *alert.WebhookAlerter,
	addresses []common.Address,
) {
	scale := new(big.Float).SetFloat64(1e18)

	for _, addr := range addresses {
		data, err := poolCaller.GetUserAccountData(nil, addr)
		if err != nil {
			logger.Error("계정 데이터 조회 실패 / Failed to get account data",
				"address", addr.Hex(),
				"error", err,
			)
			continue
		}

		// 부채가 없으면 건너뛰기 / Skip if no debt
		if data.TotalDebtBase.Sign() == 0 {
			continue
		}

		// 헬스팩터 계산 / Calculate health factor
		hfFloat := new(big.Float).SetInt(data.HealthFactor)
		hfFloat.Quo(hfFloat, scale)
		hfValue, _ := hfFloat.Float64()

		// 알림 전송 / Send alerts
		if hfValue < HealthFactorCritical {
			logger.Error("긴급: 청산 가능 포지션! / CRITICAL: Liquidatable position!",
				"address", addr.Hex(),
				"health_factor", fmt.Sprintf("%.4f", hfValue),
			)
			if err := alerter.AlertOnLowHealthFactor(ctx, addr.Hex(), hfFloat); err != nil {
				logger.Error("알림 전송 실패 / Failed to send alert", "error", err)
			}
		} else if hfValue < HealthFactorWarning {
			logger.Warn("경고: 낮은 헬스팩터 / WARNING: Low health factor",
				"address", addr.Hex(),
				"health_factor", fmt.Sprintf("%.4f", hfValue),
			)
			if err := alerter.AlertOnLowHealthFactor(ctx, addr.Hex(), hfFloat); err != nil {
				logger.Error("알림 전송 실패 / Failed to send alert", "error", err)
			}
		}
	}
}
