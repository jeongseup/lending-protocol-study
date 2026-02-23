// 렌딩 프로토콜 이벤트 인덱서 — Day 5 학습
// Lending protocol event indexer — Day 5 learning
//
// 이 프로그램은 렌딩 프로토콜의 온체인 이벤트를 수집하여 인덱싱합니다.
// This program collects and indexes on-chain events from lending protocols.
//
// 수집하는 이벤트 / Events collected:
// - Deposit: 예치 이벤트 / Deposit events
// - Borrow: 대출 이벤트 / Borrow events
// - Repay: 상환 이벤트 / Repay events
// - LiquidationCall: 청산 이벤트 / Liquidation events
//
// DevOps 관점:
// - 스테이킹 모니터링의 이벤트 수집 패턴을 활용합니다
// - 기존 Go 이벤트 리스너 패턴을 렌딩 프로토콜에 적용합니다
//
// DevOps perspective:
// - Leverages event collection patterns from staking monitoring
// - Applies existing Go event listener patterns to lending protocols
package main

import (
	"context"
	"flag"
	"log/slog"
	"math/big"
	"os"
	"os/signal"
	"syscall"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

// Aave V3 이벤트 시그니처 / Aave V3 event signatures
// 이벤트 토픽 = keccak256(이벤트 시그니처)
// Event topic = keccak256(event signature)
var (
	// Supply(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount, uint16 indexed referralCode)
	supplyEventSig = crypto.Keccak256Hash([]byte("Supply(address,address,address,uint256,uint16)"))

	// Borrow(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount, uint8 interestRateMode, uint256 borrowRate, uint16 indexed referralCode)
	borrowEventSig = crypto.Keccak256Hash([]byte("Borrow(address,address,address,uint256,uint8,uint256,uint16)"))

	// Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount, bool useATokens)
	repayEventSig = crypto.Keccak256Hash([]byte("Repay(address,address,address,uint256,bool)"))

	// LiquidationCall(address indexed collateralAsset, address indexed debtAsset, address indexed user, uint256 debtToCover, uint256 liquidatedCollateralAmount, address liquidator, bool receiveAToken)
	liquidationEventSig = crypto.Keccak256Hash([]byte("LiquidationCall(address,address,address,uint256,uint256,address,bool)"))
)

func main() {
	// CLI 플래그 / CLI flags
	rpcURL := flag.String("rpc-url", "", "이더리움 RPC URL (WebSocket 권장) / Ethereum RPC URL (WebSocket recommended)")
	fromBlock := flag.Uint64("from-block", 0, "시작 블록 번호 / Starting block number (0 = latest)")
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
	logger.Info("RPC 연결 중... / Connecting to RPC...", "url", *rpcURL)
	client, err := ethclient.Dial(*rpcURL)
	if err != nil {
		logger.Error("RPC 연결 실패 / Failed to connect to RPC", "error", err)
		os.Exit(1)
	}
	defer client.Close()

	// 컨텍스트 및 시그널 핸들링 / Context and signal handling
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	// Aave V3 Pool 주소 / Aave V3 Pool address
	poolAddress := common.HexToAddress("0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2")

	// 이벤트 필터 설정 / Event filter setup
	// 관심 있는 이벤트 토픽만 필터링합니다
	// Only filter for events we're interested in
	topics := [][]common.Hash{{
		supplyEventSig,
		borrowEventSig,
		repayEventSig,
		liquidationEventSig,
	}}

	// 시작 블록 설정 / Set starting block
	var startBlock *big.Int
	if *fromBlock > 0 {
		startBlock = new(big.Int).SetUint64(*fromBlock)
	}

	// 이벤트 구독 쿼리 / Event subscription query
	query := ethereum.FilterQuery{
		FromBlock: startBlock,
		Addresses: []common.Address{poolAddress},
		Topics:    topics,
	}

	logger.Info("이벤트 인덱싱 시작 / Starting event indexing...",
		"pool", poolAddress.Hex(),
		"from_block", *fromBlock,
	)

	// 방법 1: 과거 로그 조회 (백필) / Method 1: Historical log query (backfill)
	if startBlock != nil {
		logs, err := client.FilterLogs(ctx, query)
		if err != nil {
			logger.Error("과거 로그 조회 실패 / Failed to query historical logs", "error", err)
		} else {
			logger.Info("과거 로그 조회 완료 / Historical logs retrieved", "count", len(logs))
			for _, vLog := range logs {
				processLog(logger, vLog)
			}
		}
	}

	// 방법 2: 실시간 이벤트 구독 / Method 2: Real-time event subscription
	// WebSocket 연결이 필요합니다 / Requires WebSocket connection
	logCh := make(chan types.Log)
	sub, err := client.SubscribeFilterLogs(ctx, query, logCh)
	if err != nil {
		logger.Warn("실시간 구독 실패 (HTTP RPC?) / Real-time subscription failed (HTTP RPC?)",
			"error", err,
			"hint", "WebSocket RPC를 사용하세요 (ws:// 또는 wss://) / Use WebSocket RPC (ws:// or wss://)",
		)
		// HTTP RPC인 경우 폴링 방식으로 대체 가능
		// Can fallback to polling for HTTP RPC
		<-sigCh
		return
	}
	defer sub.Unsubscribe()

	logger.Info("실시간 이벤트 구독 시작 / Real-time event subscription started")

	for {
		select {
		case vLog := <-logCh:
			processLog(logger, vLog)
		case err := <-sub.Err():
			logger.Error("구독 오류 / Subscription error", "error", err)
			return
		case sig := <-sigCh:
			logger.Info("종료 시그널 수신 / Received shutdown signal", "signal", sig)
			return
		case <-ctx.Done():
			return
		}
	}
}

// processLog는 수신된 이벤트 로그를 처리합니다.
// processLog processes a received event log.
func processLog(logger *slog.Logger, vLog types.Log) {
	if len(vLog.Topics) == 0 {
		return
	}

	switch vLog.Topics[0] {
	case supplyEventSig:
		// Supply 이벤트 처리 / Process Supply event
		logger.Info("Supply 이벤트 감지 / Supply event detected",
			"block", vLog.BlockNumber,
			"tx", vLog.TxHash.Hex(),
			"reserve", common.BytesToAddress(vLog.Topics[1].Bytes()).Hex(),
		)

	case borrowEventSig:
		// Borrow 이벤트 처리 / Process Borrow event
		logger.Info("Borrow 이벤트 감지 / Borrow event detected",
			"block", vLog.BlockNumber,
			"tx", vLog.TxHash.Hex(),
			"reserve", common.BytesToAddress(vLog.Topics[1].Bytes()).Hex(),
		)

	case repayEventSig:
		// Repay 이벤트 처리 / Process Repay event
		logger.Info("Repay 이벤트 감지 / Repay event detected",
			"block", vLog.BlockNumber,
			"tx", vLog.TxHash.Hex(),
			"reserve", common.BytesToAddress(vLog.Topics[1].Bytes()).Hex(),
		)

	case liquidationEventSig:
		// LiquidationCall 이벤트 처리 — 가장 중요한 이벤트!
		// Process LiquidationCall event — the most important event!
		logger.Warn("청산 이벤트 감지! / Liquidation event detected!",
			"block", vLog.BlockNumber,
			"tx", vLog.TxHash.Hex(),
			"collateral_asset", common.BytesToAddress(vLog.Topics[1].Bytes()).Hex(),
			"debt_asset", common.BytesToAddress(vLog.Topics[2].Bytes()).Hex(),
			"user", common.BytesToAddress(vLog.Topics[3].Bytes()).Hex(),
		)

		// TODO: 청산 이벤트를 데이터베이스에 저장
		// TODO: Store liquidation event in database
		// TODO: Prometheus 카운터 증가
		// TODO: Increment Prometheus counter
		// metrics.LiquidationEventsTotal.WithLabelValues("aave-v3").Inc()

	default:
		logger.Debug("알 수 없는 이벤트 / Unknown event",
			"topic", vLog.Topics[0].Hex(),
		)
	}
}
