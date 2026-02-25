// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/// @title Solidity 정수 연산과 PRECISION 스케일링 이해
/// @dev `forge test --match-contract MathTest -vvv`로 실행하면 console.log 출력 확인 가능
contract MathTest is Test {
    uint256 constant PRECISION = 1e18;

    /// @notice 기본 나눗셈 — 소수점이 버려지는 문제
    function test_01_IntegerDivision() public pure {
        // Solidity: 변수끼리 정수 나눗셈 → 소수점 이하 버림!
        // (리터럴 800/1000은 컴파일 타임에 소수로 평가되어서 uint에 안 들어감)
        // 그래서 변수에 넣어서 "런타임 나눗셈"으로 만들어야 함
        uint256 a = 800;
        uint256 b = 1000;
        uint256 result = a / b;
        console.log("[raw] 800 / 1000 =", result); // → 0 (소수점 날아감!)

        uint256 c = 1;
        uint256 d = 3;
        uint256 result2 = c / d;
        console.log("[raw] 1 / 3 =", result2); // → 0
    }

    /// @notice PRECISION 스케일링 — 소수점 보존 방법
    function test_02_PrecisionScaling() public pure {
        // 해결: 나누기 전에 PRECISION(1e18)을 곱한다
        uint256 a = 800;
        uint256 b = 1000;
        uint256 result = a * PRECISION / b;
        console.log("[scaled] 800 * 1e18 / 1000 =", result);
        // → 800000000000000000 = 0.8e18 = 80%

        assertEq(result, 0.8e18, "80% should be 0.8e18");

        // 1/3도 보존됨
        uint256 c = 1;
        uint256 d = 3;
        uint256 oneThird = c * PRECISION / d;
        console.log("[scaled] 1 * 1e18 / 3 =", oneThird);
        // → 333333333333333333 ≈ 0.333...e18

        assertEq(oneThird, 333333333333333333, "1/3 precision");
    }

    /// @notice 곱셈 시 PRECISION 처리 — 나눠줘야 스케일 유지
    function test_03_MultiplicationWithPrecision() public pure {
        uint256 utilization = 0.8e18; // 80%
        uint256 multiplier_ = 0.1e18; // 10%

        // ❌ 잘못된 방법: 그냥 곱하면 스케일이 1e36이 됨
        uint256 wrong = utilization * multiplier_;
        console.log("[wrong] 0.8e18 * 0.1e18 =", wrong);
        // → 80000000000000000000000000000000000 (1e34, 의미없는 값)

        // ✅ 올바른 방법: 곱한 후 PRECISION으로 나눠서 스케일 맞추기
        uint256 correct = utilization * multiplier_ / PRECISION;
        console.log("[correct] 0.8e18 * 0.1e18 / 1e18 =", correct);
        // → 80000000000000000 = 0.08e18 = 8%

        assertEq(correct, 0.08e18, "80% * 10% = 8%");
    }

    /// @notice getUtilization 실제 계산 확인
    function test_04_UtilizationCalculation() public pure {
        // 시나리오: 1000 USDC 예치, 800 USDC 대출
        uint256 totalDeposits = 1000e18; // 1000 USDC (18 decimals)
        uint256 totalBorrows = 800e18; // 800 USDC

        uint256 utilization = totalBorrows * PRECISION / totalDeposits;
        console.log("utilization =", utilization);
        // → 800000000000000000 = 0.8e18 = 80%

        assertEq(utilization, 0.8e18, "800/1000 = 80%");

        // 엣지: 50 USDC 예치, 1 USDC 대출
        uint256 smallDeposits = 50e18;
        uint256 smallBorrows = 1e18;
        uint256 lowUtil = smallBorrows * PRECISION / smallDeposits;
        console.log("low utilization =", lowUtil);
        // → 20000000000000000 = 0.02e18 = 2%

        assertEq(lowUtil, 0.02e18, "1/50 = 2%");
    }

    /// @notice getBorrowRate 계산 시뮬레이션
    function test_05_BorrowRateSimulation() public pure {
        uint256 baseRate = 0.02e18; // 2%
        uint256 multiplier_ = 0.1e18; // 10%
        uint256 jumpMultiplier_ = 3e18; // 300%
        uint256 kink_ = 0.8e18; // 80%

        // Case 1: utilization = 50% (kink 이하, 정상 구간)
        uint256 util50 = 0.5e18;
        uint256 rate50 = baseRate + (util50 * multiplier_ / PRECISION);
        console.log("borrowRate at 50%% util =", rate50);
        // = 2% + (50% * 10%) = 2% + 5% = 7%
        assertEq(rate50, 0.07e18, "50% util -> 7% rate");

        // Case 2: utilization = 90% (kink 초과, 긴급 구간)
        uint256 util90 = 0.9e18;
        uint256 normalRate = baseRate + (kink_ * multiplier_ / PRECISION);
        uint256 excessUtil = util90 - kink_; // 10%
        uint256 rate90 = normalRate + (excessUtil * jumpMultiplier_ / PRECISION);
        console.log("borrowRate at 90%% util =", rate90);
        // = (2% + 8%) + (10% * 300%) = 10% + 30% = 40%
        assertEq(rate90, 0.4e18, "90% util -> 40% rate");
    }

    /// @notice 정밀도 손실(precision loss) 체험 — 곱셈 순서가 중요!
    function test_06_PrecisionLoss() public pure {
        // 매우 작은 값의 나눗셈 → 정밀도 손실
        uint256 tiny = 1; // 1 wei
        uint256 big = 3;

        // 1 / 3 = 0 (완전 손실)
        uint256 raw = tiny / big;
        console.log("[raw] 1 / 3 =", raw); // 0

        // ✅ 곱하기 먼저 → 정밀도 보존
        uint256 mulFirst = tiny * PRECISION / big;
        console.log("[mul first] 1 * 1e18 / 3 =", mulFirst); // 333333333333333333

        // ❌ 나누기 먼저 → 정밀도 손실
        uint256 divFirst = tiny / big * PRECISION;
        console.log("[div first] 1 / 3 * 1e18 =", divFirst); // 0 (이미 0이 됨)

        // 교훈: Solidity에서는 항상 곱하기를 먼저!
        assertTrue(mulFirst > divFirst, "multiply first preserves precision");
    }
}
