// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";
import "../src/InterestRateModel.sol";
import "../src/PriceOracle.sol";
import "./LendingPool.invariant.t.sol"; // MockERC20, MockPriceFeed 재사용

/// @title 시나리오 테스트 — Day 3 정밀 계산 검증
/// @notice 중간 계산을 추적하고 정확한 값을 assert (Walrus calculate_rewards 스타일)
/// @notice Traces intermediate calculations and asserts exact values

contract ScenarioTest is Test {
    LendingPool public pool;
    InterestRateModel public rateModel;
    PriceOracle public oracle;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockPriceFeed public ethFeed;
    MockPriceFeed public usdcFeed;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address liquidator = address(0x11CC);

    // 상수 재선언 (계산 검증용) / Re-declare constants for verification
    uint256 constant PRECISION = 1e18;
    uint256 constant SECONDS_PER_YEAR = 365 days; // 31,536,000
    uint256 constant RESERVE_FACTOR = 0.1e18;
    uint256 constant LIQUIDATION_BONUS = 0.05e18;
    uint256 constant CLOSE_FACTOR = 0.5e18;

    function setUp() public {
        // 오라클 / Oracle
        oracle = new PriceOracle(3600);
        ethFeed = new MockPriceFeed(2000e18, 18); // ETH = $2,000
        usdcFeed = new MockPriceFeed(1e18, 18);   // USDC = $1

        // 이자율 모델: base=2%, multiplier=10%, jump=100%, kink=80%
        rateModel = new InterestRateModel(0.02e18, 0.1e18, 1.0e18, 0.8e18);

        // 풀 / Pool
        pool = new LendingPool(address(oracle), address(rateModel));

        // 토큰 / Tokens
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 18);

        // 오라클 피드 / Oracle feeds
        oracle.setPriceFeed(address(weth), address(ethFeed));
        oracle.setPriceFeed(address(usdc), address(usdcFeed));

        // WETH: CF=75%, LT=80%
        pool.initReserve(address(weth), 0.75e18, 0.80e18);
        // USDC: CF=80%, LT=85%
        pool.initReserve(address(usdc), 0.80e18, 0.85e18);

        // 토큰 발행 / Mint tokens
        weth.mint(alice, 100e18);
        usdc.mint(alice, 200_000e18);
        weth.mint(bob, 100e18);
        usdc.mint(bob, 200_000e18);
        weth.mint(liquidator, 100e18);
        usdc.mint(liquidator, 200_000e18);

        // 승인 / Approvals
        vm.startPrank(alice);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidator);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    // ============================================================
    // 시나리오 1: Deposit → Borrow → 30일 → Interest → Repay → Withdraw
    // Scenario 1: Full lifecycle with precise interest verification
    // ============================================================

    function test_scenario1_fullLifecycle_preciseInterest() public {
        // ── Phase 1: Bob이 50,000 USDC 예치 (유동성 공급) ──
        // ── Phase 1: Bob deposits 50,000 USDC (liquidity) ──
        vm.prank(bob);
        pool.deposit(address(usdc), 50_000e18);

        (,,,,uint256 usdcDeposits,,,,,,) = pool.reserves(address(usdc));
        assertEq(usdcDeposits, 50_000e18, "Phase1: USDC totalDeposits = 50,000");

        // ── Phase 2: Alice가 10 ETH 예치 ──
        // ── Phase 2: Alice deposits 10 ETH ──
        vm.prank(alice);
        pool.deposit(address(weth), 10e18);

        (LToken lWeth,,,,uint256 wethDeposits,,,,,,) = pool.reserves(address(weth));
        assertEq(lWeth.balanceOf(alice), 10e18, "Phase2: Alice lWETH = 10");
        assertEq(wethDeposits, 10e18, "Phase2: WETH totalDeposits = 10");
        assertTrue(pool.isUsingAsCollateral(alice, address(weth)), "Phase2: collateral bit set");

        // 담보 가치 = 10 × $2,000 = $20,000
        assertEq(pool.getTotalCollateralValue(alice), 20_000e18, "Phase2: collateral = $20,000");

        // ── Phase 3: Alice가 10,000 USDC 대출 ──
        // ── Phase 3: Alice borrows 10,000 USDC ──
        vm.prank(alice);
        pool.borrow(address(usdc), 10_000e18);

        (, DebtToken dUsdc,,,uint256 usdcDepositsPost, uint256 usdcBorrows,,,,,) =
            pool.reserves(address(usdc));
        assertEq(dUsdc.balanceOf(alice), 10_000e18, "Phase3: debtToken = 10,000");
        assertEq(usdcBorrows, 10_000e18, "Phase3: totalBorrows = 10,000");
        assertTrue(pool.isBorrowing(alice, address(usdc)), "Phase3: borrow bit set");

        // 사용률 = 10,000 / 50,000 = 20%
        uint256 utilization = pool.getUtilizationRate(address(usdc));
        assertEq(utilization, 0.2e18, "Phase3: utilization = 20%");

        // 이자율 = baseRate + util × multiplier = 2% + 20% × 10% = 4%
        uint256 expectedBorrowRate = 0.02e18 + (0.2e18 * 0.1e18 / PRECISION);
        assertEq(expectedBorrowRate, 0.04e18, "Phase3: borrowRate = 4%");

        uint256 actualBorrowRate = rateModel.getBorrowRate(usdcDepositsPost, usdcBorrows);
        assertEq(actualBorrowRate, expectedBorrowRate, "Phase3: model confirms 4%");

        // HF = (10 × 2000 × 0.80) / (10,000 × 1) = 16,000 / 10,000 = 1.6
        assertEq(pool.getHealthFactor(alice), 1.6e18, "Phase3: HF = 1.6");

        // ── Phase 4: 30일 경과 → 이자 누적 ──
        // ── Phase 4: 30 days → interest accrual ──
        uint256 timeElapsed = 30 days; // 2,592,000 seconds
        vm.warp(block.timestamp + timeElapsed);

        // 예상 이자 수동 계산 / Manual interest calculation
        // borrowRatePerSecond = 4% annual / 31,536,000 sec
        uint256 borrowRatePerSecond = expectedBorrowRate / SECONDS_PER_YEAR;
        // interestAccumulated = totalBorrows × ratePerSec × time / PRECISION
        uint256 expectedInterest = 10_000e18 * borrowRatePerSecond * timeElapsed / PRECISION;
        // reserveShare = interest × RF(10%) / PRECISION
        uint256 expectedReserveShare = expectedInterest * RESERVE_FACTOR / PRECISION;

        // 이자 누적 트리거 (1 wei 상환) / Trigger accrual via minimal repay
        vm.prank(alice);
        pool.repay(address(usdc), 1);

        // 리저브 상태 검증 / Verify reserve state
        (,,,,uint256 newDeposits, uint256 newBorrows, uint256 newReserves, uint256 newIndex,,,) =
            pool.reserves(address(usdc));

        // totalBorrows = 원래 10,000 + 이자 - 상환(1 wei)
        assertEq(
            newBorrows,
            10_000e18 + expectedInterest - 1,
            "Phase4: totalBorrows = principal + interest - 1"
        );

        // totalReserves = 이자 × 10%
        assertEq(newReserves, expectedReserveShare, "Phase4: totalReserves = interest * 10%");

        // totalDeposits = 50,000 + (이자 - reserveShare)
        // 예치자는 이자에서 프로토콜 몫을 제외한 나머지를 받음
        assertEq(
            newDeposits,
            50_000e18 + expectedInterest - expectedReserveShare,
            "Phase4: totalDeposits = 50,000 + interest - reserveShare"
        );

        // borrowIndex = 1e18 + 1e18 × ratePerSec × time / 1e18
        uint256 expectedIndex = PRECISION + PRECISION * borrowRatePerSecond * timeElapsed / PRECISION;
        assertEq(newIndex, expectedIndex, "Phase4: borrowIndex precise");

        // 로그 / Logs
        emit log_named_uint("  borrowRatePerSecond", borrowRatePerSecond);
        emit log_named_uint("  interestAccumulated (wei)", expectedInterest);
        emit log_named_uint("  reserveShare (wei)", expectedReserveShare);
        emit log_named_uint("  newBorrowIndex", newIndex);

        // ── Phase 5: Alice 전액 상환 ──
        // ── Phase 5: Alice repays full debt ──
        // debtToken은 원금만 추적 (이자 미반영) — 현재 구현의 단순화
        // debtToken tracks principal only (no interest) — simplification
        uint256 aliceDebt = dUsdc.balanceOf(alice);
        assertEq(aliceDebt, 10_000e18 - 1, "Phase5: debtToken = principal - 1 repaid");

        vm.prank(alice);
        pool.repay(address(usdc), aliceDebt);

        assertEq(dUsdc.balanceOf(alice), 0, "Phase5: debt fully repaid");
        assertFalse(pool.isBorrowing(alice, address(usdc)), "Phase5: borrow bit cleared");

        // ── Phase 6: Alice 10 ETH 출금 ──
        // ── Phase 6: Alice withdraws 10 ETH ──
        vm.prank(alice);
        pool.withdraw(address(weth), 10e18);

        assertEq(weth.balanceOf(alice), 100e18, "Phase6: original ETH back");
        assertFalse(pool.isUsingAsCollateral(alice, address(weth)), "Phase6: collateral bit cleared");
        assertEq(pool.getUserConfiguration(alice), 0, "Phase6: bitmap clean");
        assertEq(pool.getHealthFactor(alice), type(uint256).max, "Phase6: HF = max (no debt)");
    }

    // ============================================================
    // 시나리오 2: 가격 하락 → 청산 — 정밀 계산
    // Scenario 2: Price drop → Liquidation — precise calculation
    // ============================================================

    function test_scenario2_liquidation_preciseCalculation() public {
        // ── Phase 1: 포지션 생성 ──
        // ── Phase 1: Create position ──
        vm.prank(bob);
        pool.deposit(address(usdc), 50_000e18);

        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 15_000e18);
        vm.stopPrank();

        // ── Phase 2: 초기 상태 검증 ──
        // ── Phase 2: Verify initial state ──

        // 담보 = 10 × $2,000 = $20,000
        assertEq(pool.getTotalCollateralValue(alice), 20_000e18, "Phase2: collateral = $20,000");
        // 부채 = 15,000 × $1 = $15,000
        assertEq(pool.getTotalDebtValue(alice), 15_000e18, "Phase2: debt = $15,000");

        // HF = (10 × 2000 × 0.80) / 15,000 = 16,000 / 15,000
        uint256 expectedHF = 16_000e18 * PRECISION / 15_000e18;
        assertEq(pool.getHealthFactor(alice), expectedHF, "Phase2: HF = 16000/15000");
        assertGt(pool.getHealthFactor(alice), PRECISION, "Phase2: HF > 1 (healthy)");

        // ── Phase 3: ETH 가격 $2,000 → $1,500 (25% 하락) ──
        // ── Phase 3: ETH price $2,000 → $1,500 (25% drop) ──
        ethFeed.setPrice(1500e18);

        // 새 담보 = 10 × $1,500 = $15,000
        assertEq(pool.getTotalCollateralValue(alice), 15_000e18, "Phase3: collateral = $15,000");

        // 새 HF = (10 × 1500 × 0.80) / 15,000 = 12,000 / 15,000 = 0.8
        assertEq(pool.getHealthFactor(alice), 0.8e18, "Phase3: HF = 0.8");
        assertLt(pool.getHealthFactor(alice), PRECISION, "Phase3: HF < 1 (liquidatable)");

        // ── Phase 4: 청산 실행 ──
        // ── Phase 4: Execute liquidation ──
        uint256 debtToCover = 7_500e18; // Close Factor 50% of 15,000

        // Close Factor 검증 / Verify close factor
        uint256 maxLiquidatable = 15_000e18 * CLOSE_FACTOR / PRECISION;
        assertEq(maxLiquidatable, debtToCover, "Phase4: debtToCover = maxLiquidatable");

        // 담보 압류 예측 / Predict collateral seized
        // collateralToSeize = debtToCover × debtPrice × (1 + bonus) / (collateralPrice × PRECISION)
        // = 7,500 × $1 × 1.05 / $1,500 = 5.25 ETH
        uint256 expectedSeized = debtToCover
            * 1e18  // debtPrice (USDC = $1)
            * (PRECISION + LIQUIDATION_BONUS) // 1.05e18
            / (1500e18 * PRECISION); // collateralPrice × PRECISION
        assertEq(expectedSeized, 5.25e18, "Phase4: expected seized = 5.25 ETH");

        // 잔액 스냅샷 / Balance snapshot
        uint256 liqUsdcBefore = usdc.balanceOf(liquidator);
        uint256 liqWethBefore = weth.balanceOf(liquidator);

        // 청산! / Liquidate!
        vm.prank(liquidator);
        pool.liquidate(alice, address(usdc), address(weth), debtToCover);

        // ── Phase 5: 결과 검증 ──
        // ── Phase 5: Verify results ──

        // 청산자: USDC 지불 / Liquidator paid USDC
        assertEq(
            liqUsdcBefore - usdc.balanceOf(liquidator),
            debtToCover,
            "Phase5: liquidator paid 7,500 USDC"
        );

        // 청산자: WETH 수령 (5.25 ETH) / Liquidator received WETH
        assertEq(
            weth.balanceOf(liquidator) - liqWethBefore,
            expectedSeized,
            "Phase5: liquidator received 5.25 WETH"
        );

        // 청산자 순이익 = 5.25 × $1,500 - $7,500 = $7,875 - $7,500 = $375
        // Liquidator profit = $375 (5% bonus)
        uint256 profit = expectedSeized * 1500e18 / PRECISION - debtToCover;
        assertEq(profit, 375e18, "Phase5: liquidator profit = $375");

        // Alice 잔여 담보 = 10 - 5.25 = 4.75 ETH
        (LToken lWeth2,,,,,,,,,,) = pool.reserves(address(weth));
        assertEq(lWeth2.balanceOf(alice), 4.75e18, "Phase5: Alice lWETH = 4.75");

        // Alice 잔여 부채 = 15,000 - 7,500 = 7,500 USDC
        (, DebtToken dUsdc2,,,,,,,,,) = pool.reserves(address(usdc));
        assertEq(dUsdc2.balanceOf(alice), 7_500e18, "Phase5: Alice debt = 7,500");

        // 청산 후 HF = (4.75 × 1500 × 0.80) / 7,500 = 5,700 / 7,500 = 0.76
        uint256 postLiqHF = pool.getHealthFactor(alice);
        assertEq(postLiqHF, 5_700e18 * PRECISION / 7_500e18, "Phase5: HF formula check");
        assertEq(postLiqHF, 0.76e18, "Phase5: HF = 0.76");

        emit log_named_decimal_uint("  collateralSeized (ETH)", expectedSeized, 18);
        emit log_named_decimal_uint("  liquidator profit ($)", profit, 18);
        emit log_named_decimal_uint("  post-liquidation HF", postLiqHF, 18);
    }

    // ============================================================
    // 시나리오 3: 이자율 곡선 — kink 전후 기울기 검증
    // Scenario 3: Interest rate curve — slope verification around kink
    // ============================================================

    function test_scenario3_interestRateCurve_kinkBehavior() public view {
        // ── kink 이하 (선형 구간) / Below kink (linear) ──
        // rate = baseRate + util × multiplier = 2% + util × 10%

        // util=20%: rate = 2% + 20%×10% = 4%
        assertEq(rateModel.getBorrowRate(100e18, 20e18), 0.04e18, "util=20%: rate=4%");

        // util=50%: rate = 2% + 50%×10% = 7%
        assertEq(rateModel.getBorrowRate(100e18, 50e18), 0.07e18, "util=50%: rate=7%");

        // util=80% (kink 지점): rate = 2% + 80%×10% = 10%
        assertEq(rateModel.getBorrowRate(100e18, 80e18), 0.10e18, "util=80% (kink): rate=10%");

        // ── kink 이상 (가파른 구간) / Above kink (steep) ──
        // normalRate = 10%, rate = 10% + (util - 80%) × 100%

        // util=85%: rate = 10% + 5%×100% = 15%
        assertEq(rateModel.getBorrowRate(100e18, 85e18), 0.15e18, "util=85%: rate=15%");

        // util=90%: rate = 10% + 10%×100% = 20%
        assertEq(rateModel.getBorrowRate(100e18, 90e18), 0.20e18, "util=90%: rate=20%");

        // util=100%: rate = 10% + 20%×100% = 30%
        assertEq(rateModel.getBorrowRate(100e18, 100e18), 0.30e18, "util=100%: rate=30%");

        // ── 기울기 비교 / Slope comparison ──
        // kink 이하: 30% util 변화 → 3% rate 변화 (기울기 = 0.1)
        uint256 rate20 = rateModel.getBorrowRate(100e18, 20e18);
        uint256 rate50 = rateModel.getBorrowRate(100e18, 50e18);
        assertEq(rate50 - rate20, 0.03e18, "Below kink: 30% util diff -> 3% rate diff");

        // kink 이상: 5% util 변화 → 5% rate 변화 (기울기 = 1.0)
        uint256 rate85 = rateModel.getBorrowRate(100e18, 85e18);
        uint256 rate90 = rateModel.getBorrowRate(100e18, 90e18);
        assertEq(rate90 - rate85, 0.05e18, "Above kink: 5% util diff -> 5% rate diff");

        // 기울기 비: jump(1.0) / normal(0.1) = 10배
        // 같은 5% utilization 변화에 대한 이자율 변화 비교
        uint256 rate55 = rateModel.getBorrowRate(100e18, 55e18);
        uint256 belowKinkDelta = rate55 - rate50; // 0.5% (5% util × 0.1 slope)
        uint256 aboveKinkDelta = rate90 - rate85;  // 5.0% (5% util × 1.0 slope)
        assertEq(aboveKinkDelta / belowKinkDelta, 10, "Jump slope is 10x steeper");
    }
}
