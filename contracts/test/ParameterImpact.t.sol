// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";
import "../src/InterestRateModel.sol";
import "../src/PriceOracle.sol";
import "./LendingPool.invariant.t.sol"; // MockERC20, MockPriceFeed

/// @title 파라미터 영향 테스트 — Day 3 파라미터 변경 분석
/// @notice 프로토콜 파라미터 변경이 계산 결과에 미치는 영향을 검증
/// @notice Verifies how parameter changes affect protocol calculations

contract ParameterImpactTest is Test {
    uint256 constant PRECISION = 1e18;
    uint256 constant SECONDS_PER_YEAR = 365 days;

    // 공유 인프라 / Shared infrastructure
    PriceOracle public oracle;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockPriceFeed public ethFeed;
    MockPriceFeed public usdcFeed;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        // 토큰 먼저 생성 (오라클에서 주소 필요) / Create tokens first
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 18);

        // 오라클 / Oracle
        oracle = new PriceOracle(3600);
        ethFeed = new MockPriceFeed(2000e18, 18); // ETH = $2,000
        usdcFeed = new MockPriceFeed(1e18, 18);   // USDC = $1
        oracle.setPriceFeed(address(weth), address(ethFeed));
        oracle.setPriceFeed(address(usdc), address(usdcFeed));
    }

    /// @notice 풀 생성 + 포지션 세팅 헬퍼 / Pool setup helper
    /// @dev Alice: 10 ETH 예치 + 10,000 USDC 대출, Bob: 50,000 USDC 유동성
    function _setupPool(InterestRateModel model, uint256 wethCF, uint256 wethLT)
        internal
        returns (LendingPool)
    {
        LendingPool p = new LendingPool(address(oracle), address(model));
        p.initReserve(address(weth), wethCF, wethLT);
        p.initReserve(address(usdc), 0.80e18, 0.85e18);

        // 토큰 발행 + 승인 / Mint + approve
        weth.mint(alice, 10e18);
        usdc.mint(bob, 50_000e18);

        vm.prank(alice);
        weth.approve(address(p), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(p), type(uint256).max);

        // Bob 유동성 공급 / Bob provides liquidity
        vm.prank(bob);
        p.deposit(address(usdc), 50_000e18);

        // Alice: 10 ETH 예치 + 10,000 USDC 대출
        vm.startPrank(alice);
        p.deposit(address(weth), 10e18);
        p.borrow(address(usdc), 10_000e18);
        vm.stopPrank();

        return p;
    }

    // ============================================================
    // 테스트 1: Kink 변경 → 이자율 곡선 변화
    // Test 1: Kink change → interest rate curve shift
    // ============================================================

    function test_impact_kinkChange() public {
        // 동일 파라미터, kink만 다름 / Same params, only kink differs
        InterestRateModel model80 = new InterestRateModel(0.02e18, 0.1e18, 1.0e18, 0.8e18);
        InterestRateModel model90 = new InterestRateModel(0.02e18, 0.1e18, 1.0e18, 0.9e18);

        // ── utilization = 85% 에서 비교 / Compare at util=85% ──

        // model80 (kink=80%): 85% > 80% → jump 구간
        //   normalRate = 2% + 80%×10% = 10%
        //   rate = 10% + (85%-80%)×100% = 15%
        uint256 rate80 = model80.getBorrowRate(100e18, 85e18);
        assertEq(rate80, 0.15e18, "kink=80%: util=85% -> rate=15%");

        // model90 (kink=90%): 85% < 90% → 선형 구간
        //   rate = 2% + 85%×10% = 10.5%
        uint256 rate90 = model90.getBorrowRate(100e18, 85e18);
        assertEq(rate90, 0.105e18, "kink=90%: util=85% -> rate=10.5%");

        // ── 차이 분석 / Difference analysis ──
        // kink 10% 올리면 → 이자율 15% → 10.5% (4.5%p 감소)
        uint256 rateDiff = rate80 - rate90;
        assertEq(rateDiff, 0.045e18, "kink impact: 4.5%p rate difference");

        // 30일간 10,000 USDC 대출 이자 차이 / 30-day interest difference
        uint256 time30d = 30 days;
        uint256 interest80 = 10_000e18 * (rate80 / SECONDS_PER_YEAR) * time30d / PRECISION;
        uint256 interest90 = 10_000e18 * (rate90 / SECONDS_PER_YEAR) * time30d / PRECISION;
        uint256 interestDiff = interest80 - interest90;

        // kink가 낮을수록 → jump 영역에 더 빨리 진입 → 높은 이자율
        // Lower kink → enters jump zone sooner → higher rates
        emit log_named_decimal_uint("  kink=80% rate", rate80, 18);
        emit log_named_decimal_uint("  kink=90% rate", rate90, 18);
        emit log_named_decimal_uint("  rate diff", rateDiff, 18);
        emit log_named_decimal_uint("  30d interest diff (USDC)", interestDiff, 18);
    }

    // ============================================================
    // 테스트 2: Liquidation Threshold 변경 → HF 변화
    // Test 2: LT change → Health Factor shift
    // ============================================================

    function test_impact_liquidationThreshold() public {
        InterestRateModel model = new InterestRateModel(0.02e18, 0.1e18, 1.0e18, 0.8e18);

        // ── Pool A: LT=80% ──
        LendingPool poolA = _setupPool(model, 0.75e18, 0.80e18);
        uint256 hfA = poolA.getHealthFactor(alice);
        // HF = (10 × 2000 × 0.80) / (10,000 × 1) = 16,000 / 10,000 = 1.6
        assertEq(hfA, 1.6e18, "LT=80%: HF=1.6");

        // ── Pool B: LT=60% ──
        LendingPool poolB = _setupPool(model, 0.55e18, 0.60e18);
        uint256 hfB = poolB.getHealthFactor(alice);
        // HF = (10 × 2000 × 0.60) / (10,000 × 1) = 12,000 / 10,000 = 1.2
        assertEq(hfB, 1.2e18, "LT=60%: HF=1.2");

        // ── 차이 분석 / Difference analysis ──
        // LT 20%p 감소 → HF 0.4 감소 (1.6 → 1.2)
        // 같은 포지션인데 LT만 다르면 청산까지의 여유 크게 달라짐
        assertEq(hfA - hfB, 0.4e18, "LT impact: HF diff = 0.4");

        // 최대 대출 한도 비교 (HF=1.0이 되는 지점)
        // Max borrow at HF=1.0 threshold
        // LT=80%: max = 10×2000×0.80 = $16,000
        // LT=60%: max = 10×2000×0.60 = $12,000
        uint256 maxBorrowA = 10e18 * 2000e18 / PRECISION * 0.80e18 / PRECISION;
        uint256 maxBorrowB = 10e18 * 2000e18 / PRECISION * 0.60e18 / PRECISION;
        assertEq(maxBorrowA, 16_000e18, "LT=80%: maxBorrow = $16,000");
        assertEq(maxBorrowB, 12_000e18, "LT=60%: maxBorrow = $12,000");

        emit log_named_decimal_uint("  LT=80% HF", hfA, 18);
        emit log_named_decimal_uint("  LT=60% HF", hfB, 18);
        emit log_named_uint("  LT=80% maxBorrow ($)", maxBorrowA / 1e18);
        emit log_named_uint("  LT=60% maxBorrow ($)", maxBorrowB / 1e18);
    }

    // ============================================================
    // 테스트 3: Reserve Factor 변경 → Supply APY 변화
    // Test 3: RF change → Supply APY shift
    // ============================================================

    function test_impact_reserveFactor() public {
        InterestRateModel model = new InterestRateModel(0.02e18, 0.1e18, 1.0e18, 0.8e18);

        // 조건: totalDeposits=100, totalBorrows=50 → util=50%
        uint256 totalDeposits = 100e18;
        uint256 totalBorrows = 50e18;

        uint256 borrowRate = model.getBorrowRate(totalDeposits, totalBorrows);
        assertEq(borrowRate, 0.07e18, "borrowRate = 7%");

        uint256 utilization = model.getUtilization(totalDeposits, totalBorrows);
        assertEq(utilization, 0.5e18, "utilization = 50%");

        // rateToPool = borrowRate × utilization = 7% × 50% = 3.5%
        uint256 rateToPool = borrowRate * utilization / PRECISION;
        assertEq(rateToPool, 0.035e18, "rateToPool = 3.5%");

        // ── RF=10%: supplyRate = 3.5% × (1 - 10%) = 3.15% ──
        uint256 supplyRate10 = model.getSupplyRate(totalDeposits, totalBorrows, 0.10e18);
        assertEq(supplyRate10, 0.0315e18, "RF=10%: supplyRate = 3.15%");

        // ── RF=30%: supplyRate = 3.5% × (1 - 30%) = 2.45% ──
        uint256 supplyRate30 = model.getSupplyRate(totalDeposits, totalBorrows, 0.30e18);
        assertEq(supplyRate30, 0.0245e18, "RF=30%: supplyRate = 2.45%");

        // ── 차이 분석 / Difference analysis ──
        // RF 10%→30% → supplyRate 3.15%→2.45% (0.7%p 감소)
        uint256 supplyDiff = supplyRate10 - supplyRate30;
        assertEq(supplyDiff, 0.007e18, "RF impact: 0.7%p supply rate decrease");

        // 프로토콜 수익 비교 / Protocol revenue comparison
        uint256 protocolRevenue10 = rateToPool * 0.10e18 / PRECISION; // 0.35%
        uint256 protocolRevenue30 = rateToPool * 0.30e18 / PRECISION; // 1.05%
        assertEq(protocolRevenue10, 0.0035e18, "RF=10%: protocol revenue = 0.35%");
        assertEq(protocolRevenue30, 0.0105e18, "RF=30%: protocol revenue = 1.05%");

        // 프로토콜 수익은 3배 증가 (10% → 30%)
        assertEq(protocolRevenue30 / protocolRevenue10, 3, "RF 3x -> protocol revenue 3x");

        // RF↑ → 프로토콜 수익↑, 예치자 수익↓ (트레이드오프)
        // Higher RF → more protocol revenue, less depositor yield
        emit log_named_decimal_uint("  RF=10% supplyRate", supplyRate10, 18);
        emit log_named_decimal_uint("  RF=30% supplyRate", supplyRate30, 18);
        emit log_named_decimal_uint("  RF=10% protocol revenue", protocolRevenue10, 18);
        emit log_named_decimal_uint("  RF=30% protocol revenue", protocolRevenue30, 18);
    }

    // ============================================================
    // 테스트 4: Liquidation Bonus 변경 → 청산자 수익 / 차입자 손실
    // Test 4: Bonus change → liquidator profit / borrower loss
    // ============================================================

    function test_impact_liquidationBonus() public pure {
        // 청산 시나리오 / Liquidation scenario:
        // Alice: 10 ETH, ETH=$1,500 (하락 후), 15,000 USDC 부채
        // Liquidator covers 7,500 USDC (50% close factor)
        uint256 debtToCover = 7_500e18;
        uint256 collateralPrice = 1500e18; // ETH after price drop
        uint256 debtPrice = 1e18;          // USDC

        // ── Bonus = 5% ──
        uint256 bonus5 = 0.05e18;
        uint256 seized5 = debtToCover * debtPrice * (PRECISION + bonus5)
            / (collateralPrice * PRECISION);
        // = 7,500 × 1 × 1.05 / 1,500 = 5.25 ETH
        assertEq(seized5, 5.25e18, "bonus=5%: seized = 5.25 ETH");

        uint256 profit5 = seized5 * collateralPrice / PRECISION - debtToCover;
        // = 5.25 × $1,500 - $7,500 = $375
        assertEq(profit5, 375e18, "bonus=5%: profit = $375");

        // ── Bonus = 10% ──
        uint256 bonus10 = 0.10e18;
        uint256 seized10 = debtToCover * debtPrice * (PRECISION + bonus10)
            / (collateralPrice * PRECISION);
        // = 7,500 × 1 × 1.10 / 1,500 = 5.50 ETH
        assertEq(seized10, 5.50e18, "bonus=10%: seized = 5.50 ETH");

        uint256 profit10 = seized10 * collateralPrice / PRECISION - debtToCover;
        // = 5.50 × $1,500 - $7,500 = $750
        assertEq(profit10, 750e18, "bonus=10%: profit = $750");

        // ── 차이 분석 / Difference analysis ──
        // bonus 5%p 증가 → 청산자 수익 $375 → $750 (2배)
        assertEq(profit10 - profit5, 375e18, "bonus impact: $375 more profit");
        assertEq(profit10 / profit5, 2, "bonus impact: profit doubles");

        // 차입자 관점: 더 많은 담보 손실 / Borrower perspective: more collateral lost
        uint256 aliceRemaining5 = 10e18 - seized5;   // 4.75 ETH
        uint256 aliceRemaining10 = 10e18 - seized10;  // 4.50 ETH
        assertEq(aliceRemaining5, 4.75e18, "bonus=5%: Alice keeps 4.75 ETH");
        assertEq(aliceRemaining10, 4.50e18, "bonus=10%: Alice keeps 4.50 ETH");

        // bonus↑ → 청산자 인센티브↑, 차입자 손실↑ (트레이드오프)
        // Higher bonus → more liquidator incentive, more borrower loss
    }
}
