// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PriceOracle.sol";

/// @title 오라클 테스트 — Day 4-7 학습
/// @notice 오라클 통합, 지연 감지, 가격 검증을 테스트합니다
/// @notice Tests oracle integration, staleness detection, and price validation
/// @dev DevOps 관점: 오라클 모니터링은 프로토콜 안전의 핵심
/// @dev DevOps perspective: Oracle monitoring is core to protocol safety

/// @notice 테스트용 가격 피드 / Mock price feed for testing
contract MockChainlinkFeed {
    int256 public price;
    uint8 public _decimals;
    uint256 public updatedAt;
    uint80 public roundId;
    uint80 public answeredInRound;

    constructor(int256 _price, uint8 decimals_) {
        price = _price;
        _decimals = decimals_;
        updatedAt = block.timestamp;
        roundId = 1;
        answeredInRound = 1;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, price, block.timestamp, updatedAt, answeredInRound);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    /// @notice 가격 업데이트 / Update price
    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
        roundId++;
        answeredInRound = roundId;
    }

    /// @notice 지연된 가격 설정 (지연 테스트용) / Set stale price (for staleness testing)
    function setStalePrice(int256 _price, uint256 _updatedAt) external {
        price = _price;
        updatedAt = _updatedAt;
        roundId++;
        answeredInRound = roundId;
    }

    /// @notice 잘못된 라운드 설정 (무효 데이터 테스트용) / Set invalid round
    function setInvalidRound(uint80 _roundId, uint80 _answeredInRound) external {
        roundId = _roundId;
        answeredInRound = _answeredInRound;
    }

    /// @notice 음수 가격 설정 / Set negative price
    function setNegativePrice() external {
        price = -1;
        updatedAt = block.timestamp;
    }
}

contract OracleTest is Test {
    PriceOracle public oracle;
    MockChainlinkFeed public ethFeed;
    MockChainlinkFeed public usdcFeed;
    MockChainlinkFeed public btcFeed;

    address constant WETH = address(0x1);
    address constant USDC = address(0x2);
    address constant WBTC = address(0x3);

    // 최대 지연 허용: 1시간 / Max staleness: 1 hour
    uint256 constant MAX_STALENESS = 3600;

    function setUp() public {
        oracle = new PriceOracle(MAX_STALENESS);

        // 가격 피드 생성 (8 decimals, Chainlink 표준)
        // Create price feeds (8 decimals, Chainlink standard)
        ethFeed = new MockChainlinkFeed(2000_00000000, 8);   // $2,000
        usdcFeed = new MockChainlinkFeed(1_00000000, 8);     // $1
        btcFeed = new MockChainlinkFeed(40000_00000000, 8);  // $40,000

        // 오라클에 피드 등록 / Register feeds with oracle
        oracle.setPriceFeed(WETH, address(ethFeed));
        oracle.setPriceFeed(USDC, address(usdcFeed));
        oracle.setPriceFeed(WBTC, address(btcFeed));
    }

    // ============================================================
    // 기본 가격 조회 테스트 / Basic Price Query Tests
    // ============================================================

    function test_getAssetPrice() public view {
        uint256 ethPrice = oracle.getAssetPrice(WETH);
        assertEq(ethPrice, 2000_00000000, "ETH price should be $2,000");

        uint256 usdcPrice = oracle.getAssetPrice(USDC);
        assertEq(usdcPrice, 1_00000000, "USDC price should be $1");

        uint256 btcPrice = oracle.getAssetPrice(WBTC);
        assertEq(btcPrice, 40000_00000000, "BTC price should be $40,000");
    }

    function test_getAssetPriceNormalized() public view {
        // 18 소수점으로 정규화 / Normalize to 18 decimals
        uint256 ethPrice = oracle.getAssetPriceNormalized(WETH);
        // 2000_00000000 × 10^(18-8) = 2000e18
        assertEq(ethPrice, 2000e18, "Normalized ETH price should be 2000e18");
    }

    // ============================================================
    // 오라클 지연(Staleness) 테스트 / Oracle Staleness Tests
    // ============================================================

    function test_staleOracleReverts() public {
        // 1시간 + 1초 경과 → 지연된 것으로 판단
        // 1 hour + 1 second elapsed → considered stale
        vm.warp(block.timestamp + MAX_STALENESS + 1);

        vm.expectRevert("Oracle data is stale");
        oracle.getAssetPrice(WETH);
    }

    function test_freshOracleSucceeds() public {
        // 지연 시간 이내 → 정상
        // Within staleness period → OK
        vm.warp(block.timestamp + MAX_STALENESS - 1);
        uint256 price = oracle.getAssetPrice(WETH);
        assertEq(price, 2000_00000000);
    }

    function test_checkStaleness() public {
        // 지연 확인 함수 테스트 / Test staleness check function

        // 바로 확인 → 지연 아님
        // Check immediately → not stale
        (bool isStale, uint256 staleness) = oracle.checkStaleness(WETH);
        assertFalse(isStale, "Should not be stale initially");
        assertEq(staleness, 0, "Staleness should be 0");

        // 30분 경과 / 30 minutes pass
        vm.warp(block.timestamp + 1800);
        (isStale, staleness) = oracle.checkStaleness(WETH);
        assertFalse(isStale, "Should not be stale at 30min");
        assertEq(staleness, 1800, "Staleness should be 1800s");

        // 1시간 + 1초 경과 → 지연!
        // 1 hour + 1 second → stale!
        vm.warp(block.timestamp + 1801);
        (isStale, staleness) = oracle.checkStaleness(WETH);
        assertTrue(isStale, "Should be stale after 1h");
    }

    // ============================================================
    // 가격 검증 테스트 / Price Validation Tests
    // ============================================================

    function test_negativePriceReverts() public {
        // 음수 가격 → 거부
        // Negative price → rejected
        ethFeed.setNegativePrice();

        vm.expectRevert("Invalid price");
        oracle.getAssetPrice(WETH);
    }

    function test_staleRoundReverts() public {
        // answeredInRound < roundId → 오래된 라운드
        // answeredInRound < roundId → stale round
        ethFeed.setInvalidRound(5, 3);

        vm.expectRevert("Stale round");
        oracle.getAssetPrice(WETH);
    }

    // ============================================================
    // 피드 관리 테스트 / Feed Management Tests
    // ============================================================

    function test_setPriceFeed() public {
        address newAsset = address(0x4);
        MockChainlinkFeed newFeed = new MockChainlinkFeed(100_00000000, 8);

        oracle.setPriceFeed(newAsset, address(newFeed));
        uint256 price = oracle.getAssetPrice(newAsset);
        assertEq(price, 100_00000000);
    }

    function test_setPriceFeed_onlyOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("Only owner");
        oracle.setPriceFeed(address(0x4), address(0x5));
    }

    function test_getPrice_noPriceFeedReverts() public {
        address unknownAsset = address(0x999);
        vm.expectRevert("No price feed");
        oracle.getAssetPrice(unknownAsset);
    }

    function test_setPriceFeed_zeroAddressReverts() public {
        vm.expectRevert("Invalid asset");
        oracle.setPriceFeed(address(0), address(0x5));
    }

    // ============================================================
    // DevOps 모니터링 시나리오 / DevOps Monitoring Scenarios
    // ============================================================

    function test_scenario_oracleFailureDuringVolatility() public {
        // 시나리오: 시장 급변 시 오라클이 업데이트되지 않는 경우
        // Scenario: Oracle fails to update during market volatility
        //
        // DevOps 대응:
        // 1. checkStaleness()로 지연 감지
        // 2. 알림 발송 (Telegram/Slack)
        // 3. 필요시 긴급 오라클 교체 또는 프로토콜 일시 중지
        //
        // DevOps response:
        // 1. Detect staleness via checkStaleness()
        // 2. Send alerts (Telegram/Slack)
        // 3. Emergency oracle swap or protocol pause if needed

        // 1시간 30분 경과, 오라클 업데이트 없음
        // 1.5 hours pass, no oracle update
        vm.warp(block.timestamp + 5400);

        (bool isStale, uint256 staleness) = oracle.checkStaleness(WETH);
        assertTrue(isStale, "Oracle should be stale");
        assertGt(staleness, MAX_STALENESS, "Staleness exceeds max");

        // 프로토콜 작업이 실패해야 함 (안전 장치)
        // Protocol operations should fail (safety mechanism)
        vm.expectRevert("Oracle data is stale");
        oracle.getAssetPrice(WETH);
    }

    function test_scenario_priceManipulationDetection() public view {
        // 시나리오: 가격 조작 감지
        // Scenario: Price manipulation detection
        //
        // DevOps 모니터링 포인트:
        // 1. 여러 소스의 가격 비교 (Chainlink vs DEX TWAP)
        // 2. 급격한 가격 변동 감지 (±20% in 1 block)
        // 3. 비정상적인 가격 스프레드 감지
        //
        // DevOps monitoring points:
        // 1. Compare prices across sources (Chainlink vs DEX TWAP)
        // 2. Detect sudden price changes (±20% in 1 block)
        // 3. Detect abnormal price spreads

        uint256 ethPrice = oracle.getAssetPrice(WETH);
        uint256 usdcPrice = oracle.getAssetPrice(USDC);

        // 기본 상식 검증: ETH가 USDC보다 비싸야 함
        // Sanity check: ETH should be more expensive than USDC
        assertGt(ethPrice, usdcPrice);
    }
}
