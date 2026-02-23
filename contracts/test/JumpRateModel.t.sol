// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/JumpRateModel.sol";

/// @title JumpRateModel 테스트 — Day 2 학습
/// @notice 다양한 사용률에서의 이자율 계산을 검증합니다
/// @notice Verifies interest rate calculations at various utilization levels
/// @dev 퍼즈 테스트 포함 — 엣지 케이스 발견을 위해
/// @dev Includes fuzz tests — for discovering edge cases

contract JumpRateModelTest is Test {
    JumpRateModel public model;

    // 파라미터 설정 (일반적인 값)
    // Parameter setup (typical values)
    uint256 constant BASE_RATE = 0.02e18;        // 2% 기본 이자율 / 2% base rate
    uint256 constant MULTIPLIER = 0.1e18;         // kink 이하 기울기 / slope below kink
    uint256 constant JUMP_MULTIPLIER = 1.0e18;    // kink 이상 급격한 기울기 / steep slope above kink
    uint256 constant KINK = 0.8e18;               // 80% 최적 사용률 / 80% optimal utilization

    function setUp() public {
        model = new JumpRateModel(BASE_RATE, MULTIPLIER, JUMP_MULTIPLIER, KINK);
    }

    // ============================================================
    // 기본 파라미터 테스트 / Basic Parameter Tests
    // ============================================================

    function test_parameters() public view {
        // 생성자 파라미터가 올바르게 설정되었는지 확인
        // Verify constructor parameters are set correctly
        assertEq(model.baseRate(), BASE_RATE);
        assertEq(model.multiplier(), MULTIPLIER);
        assertEq(model.jumpMultiplier(), JUMP_MULTIPLIER);
        assertEq(model.kink(), KINK);
    }

    // ============================================================
    // 사용률 테스트 / Utilization Tests
    // ============================================================

    function test_utilization_zeroBorrows() public view {
        // 대출이 없으면 사용률 0%
        // Zero borrows = 0% utilization
        uint256 utilization = model.getUtilization(1000e18, 0, 0);
        assertEq(utilization, 0);
    }

    function test_utilization_50percent() public view {
        // 50% 사용률: 현금 500, 대출 500, 준비금 0
        // 50% utilization: cash 500, borrows 500, reserves 0
        uint256 utilization = model.getUtilization(500e18, 500e18, 0);
        assertEq(utilization, 0.5e18);
    }

    function test_utilization_80percent() public view {
        // 80% 사용률 (kink 지점)
        // 80% utilization (kink point)
        uint256 utilization = model.getUtilization(200e18, 800e18, 0);
        assertEq(utilization, 0.8e18);
    }

    function test_utilization_100percent() public view {
        // 100% 사용률 (모든 자산이 대출됨)
        // 100% utilization (all assets borrowed)
        uint256 utilization = model.getUtilization(0, 1000e18, 0);
        assertEq(utilization, 1e18);
    }

    function test_utilization_withReserves() public view {
        // 준비금이 있는 경우 사용률 계산
        // Utilization calculation with reserves
        // cash=400, borrows=500, reserves=100 → util = 500/(400+500-100) = 500/800 = 62.5%
        uint256 utilization = model.getUtilization(400e18, 500e18, 100e18);
        assertEq(utilization, 0.625e18);
    }

    // ============================================================
    // 대출 이자율 테스트 / Borrow Rate Tests
    // ============================================================

    function test_borrowRate_at0percent() public view {
        // 0% 사용률에서의 대출 이자율 = baseRate = 2%
        // Borrow rate at 0% utilization = baseRate = 2%
        uint256 rate = model.getBorrowRate(1000e18, 0, 0);
        assertEq(rate, BASE_RATE, "At 0% util, rate should equal base rate");
    }

    function test_borrowRate_at50percent() public view {
        // 50% 사용률: 2% + 50% × 10% = 2% + 5% = 7%
        // At 50% util: 2% + 50% × 10% = 2% + 5% = 7%
        uint256 rate = model.getBorrowRate(500e18, 500e18, 0);
        uint256 expected = BASE_RATE + (0.5e18 * MULTIPLIER / 1e18);
        assertEq(rate, expected, "At 50% util, rate should be 7%");
        assertEq(rate, 0.07e18);
    }

    function test_borrowRate_atKink() public view {
        // kink (80%) 에서: 2% + 80% × 10% = 2% + 8% = 10%
        // At kink (80%): 2% + 80% × 10% = 2% + 8% = 10%
        uint256 rate = model.getBorrowRate(200e18, 800e18, 0);
        uint256 expected = BASE_RATE + (KINK * MULTIPLIER / 1e18);
        assertEq(rate, expected, "At kink, rate should be 10%");
        assertEq(rate, 0.10e18);
    }

    function test_borrowRate_at90percent() public view {
        // 90% 사용률 (kink 이상): 10% + (90%-80%) × 100% = 10% + 10% = 20%
        // At 90% (above kink): 10% + (90%-80%) × 100% = 10% + 10% = 20%
        uint256 rate = model.getBorrowRate(100e18, 900e18, 0);
        uint256 normalRate = BASE_RATE + (KINK * MULTIPLIER / 1e18); // 10%
        uint256 excessUtil = 0.9e18 - KINK; // 10%
        uint256 expected = normalRate + (excessUtil * JUMP_MULTIPLIER / 1e18);
        assertEq(rate, expected, "At 90% util, rate should be 20%");
        assertEq(rate, 0.20e18);
    }

    function test_borrowRate_at100percent() public view {
        // 100% 사용률: 10% + (100%-80%) × 100% = 10% + 20% = 30%
        // At 100%: 10% + (100%-80%) × 100% = 10% + 20% = 30%
        uint256 rate = model.getBorrowRate(0, 1000e18, 0);
        uint256 normalRate = BASE_RATE + (KINK * MULTIPLIER / 1e18); // 10%
        uint256 excessUtil = 1e18 - KINK; // 20%
        uint256 expected = normalRate + (excessUtil * JUMP_MULTIPLIER / 1e18);
        assertEq(rate, expected, "At 100% util, rate should be 30%");
        assertEq(rate, 0.30e18);
    }

    // ============================================================
    // 예치 이자율 테스트 / Supply Rate Tests
    // ============================================================

    function test_supplyRate_at50percent() public view {
        // 예치 이자 = 대출이자 × 사용률 × (1 - 준비금비율)
        // Supply rate = borrow rate × utilization × (1 - reserve factor)
        // reserveFactor = 10%
        uint256 reserveFactor = 0.1e18;
        uint256 supplyRate = model.getSupplyRate(500e18, 500e18, 0, reserveFactor);

        // 대출이자 7% × 사용률 50% × (1 - 10%) = 7% × 50% × 90% = 3.15%
        // Borrow rate 7% × utilization 50% × (1 - 10%) = 7% × 50% × 90% = 3.15%
        uint256 borrowRate = 0.07e18;
        uint256 utilization = 0.5e18;
        uint256 expected = borrowRate * utilization / 1e18 * (1e18 - reserveFactor) / 1e18;
        assertEq(supplyRate, expected, "Supply rate should be ~3.15%");
    }

    function test_supplyRate_alwaysLessThanBorrowRate() public view {
        // 예치 이자율은 항상 대출 이자율보다 낮아야 함
        // Supply rate must always be less than borrow rate
        uint256 reserveFactor = 0.1e18;

        uint256 borrowRate = model.getBorrowRate(500e18, 500e18, 0);
        uint256 supplyRate = model.getSupplyRate(500e18, 500e18, 0, reserveFactor);
        assertLt(supplyRate, borrowRate, "Supply rate must be < borrow rate");
    }

    // ============================================================
    // 이자율 곡선 단조 증가 테스트 / Rate Curve Monotonicity Test
    // ============================================================

    function test_borrowRate_increasesWithUtilization() public view {
        // 사용률이 증가하면 대출 이자율도 증가해야 함
        // Borrow rate must increase as utilization increases
        uint256 rate0 = model.getBorrowRate(1000e18, 0, 0);        // 0%
        uint256 rate50 = model.getBorrowRate(500e18, 500e18, 0);   // 50%
        uint256 rate80 = model.getBorrowRate(200e18, 800e18, 0);   // 80%
        uint256 rate90 = model.getBorrowRate(100e18, 900e18, 0);   // 90%
        uint256 rate100 = model.getBorrowRate(0, 1000e18, 0);      // 100%

        assertLt(rate0, rate50, "Rate at 0% < Rate at 50%");
        assertLt(rate50, rate80, "Rate at 50% < Rate at 80%");
        assertLt(rate80, rate90, "Rate at 80% < Rate at 90%");
        assertLt(rate90, rate100, "Rate at 90% < Rate at 100%");
    }

    function test_borrowRate_jumpAtKink() public view {
        // kink 이전과 이후의 기울기 차이를 확인
        // Verify slope difference before and after kink
        uint256 rateAt79 = model.getBorrowRate(210e18, 790e18, 0); // ~79%
        uint256 rateAt80 = model.getBorrowRate(200e18, 800e18, 0); // 80% (kink)
        uint256 rateAt81 = model.getBorrowRate(190e18, 810e18, 0); // ~81%

        // kink 전후의 기울기: kink 이후가 더 급격해야 함
        // Slope before/after kink: slope after should be steeper
        uint256 slopeBefore = rateAt80 - rateAt79;
        uint256 slopeAfter = rateAt81 - rateAt80;
        assertGt(slopeAfter, slopeBefore, "Slope after kink should be steeper");
    }

    // ============================================================
    // 퍼즈 테스트 / Fuzz Tests
    // ============================================================

    function testFuzz_borrowRateNeverNegative(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view {
        // 입력값을 현실적인 범위로 제한
        // Bound inputs to realistic ranges
        cash = bound(cash, 0, 1e30);
        borrows = bound(borrows, 0, 1e30);
        reserves = bound(reserves, 0, cash + borrows);
        vm.assume(borrows == 0 || cash + borrows - reserves > 0);

        uint256 rate = model.getBorrowRate(cash, borrows, reserves);
        // 이자율은 항상 baseRate 이상이어야 함
        // Rate must always be >= baseRate
        assertGe(rate, BASE_RATE, "Rate must be >= base rate");
    }

    function testFuzz_utilizationBounded(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view {
        // 사용률은 0과 1e18 사이여야 함
        // Utilization must be between 0 and 1e18
        cash = bound(cash, 0, 1e30);
        borrows = bound(borrows, 0, 1e30);
        // 준비금은 현금보다 작아야 함 (현실적 제약)
        // Reserves must be less than cash (realistic constraint)
        reserves = bound(reserves, 0, cash);
        vm.assume(borrows == 0 || cash + borrows - reserves > 0);

        uint256 utilization = model.getUtilization(cash, borrows, reserves);
        assertLe(utilization, 1e18, "Utilization must be <= 100%");
    }

    function testFuzz_supplyRateLessThanBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactor
    ) public view {
        // 예치 이자율은 항상 대출 이자율 이하
        // Supply rate must always be <= borrow rate
        cash = bound(cash, 1, 1e27);
        borrows = bound(borrows, 1, 1e27);
        // 준비금은 현금보다 작아야 함 (현실적 제약)
        // Reserves must be less than cash (realistic constraint)
        reserves = bound(reserves, 0, cash);
        reserveFactor = bound(reserveFactor, 0, 1e18);
        vm.assume(cash + borrows - reserves > 0);

        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        uint256 supplyRate = model.getSupplyRate(cash, borrows, reserves, reserveFactor);
        assertLe(supplyRate, borrowRate, "Supply rate must be <= borrow rate");
    }
}
