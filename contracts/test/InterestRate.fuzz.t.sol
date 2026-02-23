// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/JumpRateModel.sol";

/// @title 이자율 퍼즈 테스트 — Day 3 학습
/// @notice 퍼즈 테스팅으로 이자율 모델의 엣지 케이스를 발견합니다
/// @notice Discover edge cases in interest rate model via fuzz testing
/// @dev 랜덤 입력값으로 불변 조건(invariant)이 항상 유지되는지 확인
/// @dev Verify invariants always hold with random inputs

contract InterestRateFuzzTest is Test {
    JumpRateModel public model;

    uint256 constant BASE_RATE = 0.02e18;
    uint256 constant MULTIPLIER = 0.1e18;
    uint256 constant JUMP_MULTIPLIER = 1.0e18;
    uint256 constant KINK = 0.8e18;

    // 최대 이자율 한도 (연 1000% — 비현실적이지만 안전 한계)
    // Maximum rate cap (1000% annual — unrealistic but safety bound)
    uint256 constant MAX_RATE = 10e18;

    function setUp() public {
        model = new JumpRateModel(BASE_RATE, MULTIPLIER, JUMP_MULTIPLIER, KINK);
    }

    /// @notice 대출 이자율이 절대 최대값을 초과하지 않는지 퍼즈 테스트
    /// @notice Fuzz test that borrow rate never exceeds maximum
    function testFuzz_borrowRateNeverExceedsMax(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view {
        // 입력값을 현실적인 범위로 제한
        // Bound inputs to realistic ranges
        cash = bound(cash, 0, 1e30);
        borrows = bound(borrows, 0, cash + 1e30);
        reserves = bound(reserves, 0, cash);
        vm.assume(borrows == 0 || cash + borrows - reserves > 0); // 0 나누기 방지 / avoid div by zero

        uint256 rate = model.getBorrowRate(cash, borrows, reserves);
        assertLe(rate, MAX_RATE, "Rate exceeds maximum");
    }

    /// @notice 사용률이 0%~100% 범위 내인지 퍼즈 테스트
    /// @notice Fuzz test that utilization is always within 0-100% range
    function testFuzz_utilizationAlwaysBounded(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view {
        cash = bound(cash, 0, 1e30);
        borrows = bound(borrows, 0, 1e30);
        reserves = bound(reserves, 0, cash);
        vm.assume(borrows == 0 || cash + borrows - reserves > 0);

        uint256 utilization = model.getUtilization(cash, borrows, reserves);

        // 사용률은 0 이상 100% 이하
        // Utilization must be >= 0 and <= 100%
        assertGe(utilization, 0, "Utilization must be >= 0");
        assertLe(utilization, 1e18, "Utilization must be <= 100%");
    }

    /// @notice 이자율이 단조 증가하는지 퍼즈 테스트
    /// @notice Fuzz test that rate is monotonically increasing with utilization
    function testFuzz_rateMonotonicallyIncreasing(
        uint256 totalLiquidity,
        uint256 borrows1
    ) public view {
        // 총 유동성과 두 개의 대출 수준을 설정
        // Set up total liquidity and two borrow levels
        totalLiquidity = bound(totalLiquidity, 1e18, 1e30);
        borrows1 = bound(borrows1, 0, totalLiquidity - 1);

        uint256 borrows2 = borrows1 + 1; // borrows2 > borrows1
        vm.assume(borrows2 <= totalLiquidity);

        uint256 cash1 = totalLiquidity - borrows1;
        uint256 cash2 = totalLiquidity - borrows2;

        uint256 rate1 = model.getBorrowRate(cash1, borrows1, 0);
        uint256 rate2 = model.getBorrowRate(cash2, borrows2, 0);

        // 더 높은 사용률 → 더 높은 이자율
        // Higher utilization → higher rate
        assertGe(rate2, rate1, "Rate must increase with utilization");
    }

    /// @notice 예치 이자율이 항상 대출 이자율 이하인지 퍼즈 테스트
    /// @notice Fuzz test that supply rate is always <= borrow rate
    function testFuzz_supplyRateAlwaysLteBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactor
    ) public view {
        cash = bound(cash, 1, 1e27);
        borrows = bound(borrows, 1, 1e27);
        reserves = bound(reserves, 0, cash);
        reserveFactor = bound(reserveFactor, 0, 1e18);
        vm.assume(cash + borrows - reserves > 0);

        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        uint256 supplyRate = model.getSupplyRate(cash, borrows, reserves, reserveFactor);

        assertLe(supplyRate, borrowRate, "Supply rate must be <= borrow rate");
    }

    /// @notice 준비금 비율이 100%이면 예치 이자율이 0인지 퍼즈 테스트
    /// @notice Fuzz test: reserve factor = 100% → supply rate = 0
    function testFuzz_fullReserveFactorZeroesSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view {
        cash = bound(cash, 1, 1e27);
        borrows = bound(borrows, 1, 1e27);
        reserves = bound(reserves, 0, cash);
        vm.assume(cash + borrows - reserves > 0);

        // 준비금 비율 100%이면 예치자에게 돌아가는 이자 없음
        // Reserve factor 100% = no interest to depositors
        uint256 supplyRate = model.getSupplyRate(cash, borrows, reserves, 1e18);
        assertEq(supplyRate, 0, "Supply rate must be 0 with 100% reserve factor");
    }

    /// @notice kink 전후에서 이자율의 연속성을 퍼즈 테스트
    /// @notice Fuzz test: rate continuity around the kink
    function testFuzz_rateContinuityAtKink(uint256 delta) public view {
        // kink 근처에서 이자율이 급격히 변하지만 연속적이어야 함
        // Rate should be continuous (though slope changes) at kink
        delta = bound(delta, 1, 1e15); // 아주 작은 변화 / very small delta

        uint256 totalLiquidity = 1000e18;

        // kink 직전 / Just before kink
        uint256 borrowsBelow = KINK * totalLiquidity / 1e18 - delta;
        uint256 cashBelow = totalLiquidity - borrowsBelow;

        // kink 직후 / Just after kink
        uint256 borrowsAbove = KINK * totalLiquidity / 1e18 + delta;
        uint256 cashAbove = totalLiquidity - borrowsAbove;

        uint256 rateBelow = model.getBorrowRate(cashBelow, borrowsBelow, 0);
        uint256 rateAbove = model.getBorrowRate(cashAbove, borrowsAbove, 0);

        // kink 이후 이자율이 kink 이전보다 높아야 함
        // Rate after kink must be higher than rate before kink
        assertGt(rateAbove, rateBelow, "Rate above kink must be > rate below kink");
    }
}
