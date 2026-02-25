// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../practice/PriceOracle.sol";

/// @title PriceOracle Practice 테스트
/// @dev `cd contracts && forge test --match-contract PriceOraclePracticeTest -vvv`
///
/// ┌─────────────────────────────────────────────────────────────────────┐
/// │ 외부 의존성(Chainlink) 테스트는 어떻게 하나?                         │
/// │                                                                     │
/// │ 문제: 로컬에서 테스트할 때 Chainlink 컨트랙트가 없다.                  │
/// │       메인넷 포크하면 가능하지만, 느리고 네트워크 필요.                 │
/// │                                                                     │
/// │ 해결: "Mock(가짜) 컨트랙트"를 만든다.                                │
/// │                                                                     │
/// │   실제 Chainlink:                                                    │
/// │     [오프체인 노드] → [AggregatorV3 컨트랙트] → latestRoundData()     │
/// │                                                                     │
/// │   테스트용 Mock:                                                     │
/// │     [없음] → [MockChainlinkFeed 컨트랙트] → latestRoundData()        │
/// │                  ↑ 우리가 직접 가격을 설정                             │
/// │                                                                     │
/// │   핵심: PriceOracle은 "IPriceFeed 인터페이스"만 알면 되고,             │
/// │         그 뒤에 진짜 Chainlink이든 Mock이든 상관없다.                  │
/// │         이것이 "인터페이스를 통한 의존성 주입" 패턴.                    │
/// │                                                                     │
/// │   다른 테스트 방법:                                                   │
/// │     1. Mock (지금 이 방식) — 빠르고 완전 통제 가능                     │
/// │     2. Fork test (forge test --fork-url $RPC) — 실제 데이터로 테스트   │
/// │     3. Foundry vm.mockCall — 코드 없이 리턴값만 가짜로 설정           │
/// └─────────────────────────────────────────────────────────────────────┘

// ──────────────────────────────────────
// Mock 컨트랙트 — Chainlink 피드를 흉내내는 가짜 컨트랙트
// ──────────────────────────────────────

/// @notice 테스트용 Chainlink 가격 피드
/// @dev IPriceFeed 인터페이스를 구현하되, 가격을 자유롭게 조작 가능
///
///      왜 Mock이 필요한가?
///      - 로컬 테스트에서 Chainlink 실제 컨트랙트 접근 불가
///      - 특수 케이스 (음수 가격, 오래된 데이터 등) 재현 가능
///      - 빠른 실행 (네트워크 없이 즉시)
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

    /// @notice IPriceFeed.latestRoundData() 구현
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, price, block.timestamp, updatedAt, answeredInRound);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    // ── 테스트 헬퍼 함수들 (실제 Chainlink에는 없음) ──

    /// @notice 정상 가격 업데이트
    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
        roundId++;
        answeredInRound = roundId;
    }

    /// @notice 의도적으로 오래된 가격 설정 (staleness 테스트용)
    function setStalePrice(int256 _price, uint256 _updatedAt) external {
        price = _price;
        updatedAt = _updatedAt; // ← 과거 시간으로 설정!
        roundId++;
        answeredInRound = roundId;
    }

    /// @notice 라운드 불일치 설정 (stale round 테스트용)
    function setInvalidRound(uint80 _roundId, uint80 _answeredInRound) external {
        roundId = _roundId;
        answeredInRound = _answeredInRound; // ← roundId보다 작게!
    }

    /// @notice 음수 가격 설정
    function setNegativePrice() external {
        price = -1;
        updatedAt = block.timestamp;
    }
}

// ──────────────────────────────────────
// 테스트 컨트랙트
// ──────────────────────────────────────

contract PriceOraclePracticeTest is Test {
    PriceOracle oracle;
    MockChainlinkFeed ethFeed;
    MockChainlinkFeed usdcFeed;
    MockChainlinkFeed btcFeed;

    // 가짜 토큰 주소 (실제 주소가 아니어도 테스트에서는 상관없음)
    address constant WETH = address(0x1);
    address constant USDC = address(0x2);
    address constant WBTC = address(0x3);

    uint256 constant MAX_STALENESS = 3600; // 1시간

    function setUp() public {
        // 오라클 배포
        oracle = new PriceOracle(MAX_STALENESS);

        // Mock 가격 피드 배포 (Chainlink은 8 decimals가 표준)
        // $2,000 = 2000_00000000 (8 decimals)
        ethFeed = new MockChainlinkFeed(2000_00000000, 8);
        usdcFeed = new MockChainlinkFeed(1_00000000, 8); // $1
        btcFeed = new MockChainlinkFeed(40000_00000000, 8); // $40,000

        // 오라클에 피드 등록
        oracle.setPriceFeed(WETH, address(ethFeed));
        oracle.setPriceFeed(USDC, address(usdcFeed));
        oracle.setPriceFeed(WBTC, address(btcFeed));
    }

    // ═══════════════════════════════════
    // 기본 가격 조회
    // ═══════════════════════════════════

    function test_getAssetPrice_ETH() public view {
        uint256 price = oracle.getAssetPrice(WETH);
        assertEq(price, 2000_00000000, "ETH = $2,000");
        console.log("ETH price (8 dec):", price);
    }

    function test_getAssetPrice_allAssets() public view {
        assertEq(oracle.getAssetPrice(WETH), 2000_00000000, "ETH");
        assertEq(oracle.getAssetPrice(USDC), 1_00000000, "USDC");
        assertEq(oracle.getAssetPrice(WBTC), 40000_00000000, "BTC");
    }

    // ═══════════════════════════════════
    // 18 decimals 정규화
    // ═══════════════════════════════════

    function test_getAssetPriceNormalized() public view {
        uint256 price = oracle.getAssetPriceNormalized(WETH);
        // 2000_00000000 * 10^(18-8) = 2000e18
        assertEq(price, 2000e18, "ETH normalized = 2000e18");
        console.log("ETH normalized:", price);
    }

    // ═══════════════════════════════════
    // Staleness (지연) 테스트 — 핵심!
    // ═══════════════════════════════════

    /// @notice vm.warp — Foundry의 시간 조작 치트코드
    /// @dev vm.warp(timestamp)는 block.timestamp를 원하는 값으로 설정
    ///      이것이 "시간이 흐른 것처럼" 시뮬레이션하는 방법
    function test_staleOracle_reverts() public {
        // 1시간 + 1초 경과 시뮬레이션
        vm.warp(block.timestamp + MAX_STALENESS + 1);

        vm.expectRevert("Oracle data is stale");
        oracle.getAssetPrice(WETH);
    }

    function test_freshOracle_succeeds() public view {
        // Mock 생성 시 updatedAt = block.timestamp이므로 바로 조회 가능
        uint256 price = oracle.getAssetPrice(WETH);
        assertEq(price, 2000_00000000);
    }

    function test_checkStaleness_monitoring() public {
        // 즉시 → 지연 아님
        (bool isStale, uint256 staleness) = oracle.checkStaleness(WETH);
        assertFalse(isStale);
        assertEq(staleness, 0);

        // 30분 경과
        vm.warp(block.timestamp + 1800);
        (isStale, staleness) = oracle.checkStaleness(WETH);
        assertFalse(isStale, "30min: not stale");
        assertEq(staleness, 1800);

        // 1시간 1초 경과 → 지연!
        vm.warp(block.timestamp + 1801);
        (isStale, staleness) = oracle.checkStaleness(WETH);
        assertTrue(isStale, "1h1s: stale!");
    }

    // ═══════════════════════════════════
    // 가격 검증 — 잘못된 데이터 거부
    // ═══════════════════════════════════

    function test_negativePrice_reverts() public {
        ethFeed.setNegativePrice();
        vm.expectRevert("Invalid price");
        oracle.getAssetPrice(WETH);
    }

    function test_staleRound_reverts() public {
        // answeredInRound(3) < roundId(5) → 이전 라운드 답변
        ethFeed.setInvalidRound(5, 3);
        vm.expectRevert("Stale round");
        oracle.getAssetPrice(WETH);
    }

    // ═══════════════════════════════════
    // 접근 제어
    // ═══════════════════════════════════

    function test_setPriceFeed_onlyOwner() public {
        // vm.prank — 다음 호출의 msg.sender를 변경하는 치트코드
        vm.prank(address(0xBEEF));
        vm.expectRevert("Only owner");
        oracle.setPriceFeed(address(0x4), address(0x5));
    }

    function test_getPrice_unknownAsset_reverts() public {
        vm.expectRevert("No price feed");
        oracle.getAssetPrice(address(0x999));
    }

    function test_setPriceFeed_zeroAddress_reverts() public {
        vm.expectRevert("Invalid asset");
        oracle.setPriceFeed(address(0), address(0x5));
    }

    // ═══════════════════════════════════
    // 가격 업데이트 시나리오
    // ═══════════════════════════════════

    function test_priceUpdate_scenario() public {
        // ETH $2,000 → $1,500 하락
        ethFeed.setPrice(1500_00000000);
        assertEq(oracle.getAssetPrice(WETH), 1500_00000000, "ETH dropped to $1,500");

        // 이어서 $2,500 상승
        ethFeed.setPrice(2500_00000000);
        assertEq(oracle.getAssetPrice(WETH), 2500_00000000, "ETH rose to $2,500");
    }
}
