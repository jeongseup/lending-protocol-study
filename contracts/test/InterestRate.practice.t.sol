// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../practice/InterestRateModel.sol";

/// @title InterestRateModel Practice 테스트
/// @dev compound-v2-scenario.md의 시뮬레이션 숫자를 기반으로 검증
///      `cd contracts && forge test --match-contract InterestRatePracticeTest -vvv`
contract InterestRatePracticeTest is Test {
    InterestRateModel model;

    // Compound V2 시나리오와 동일한 파라미터
    uint256 constant BASE_RATE = 0.02e18; // 2%
    uint256 constant MULTIPLIER = 0.1e18; // 10%
    uint256 constant JUMP_MULTIPLIER = 3e18; // 300%
    uint256 constant KINK = 0.8e18; // 80%
    uint256 constant RESERVE_FACTOR = 0.1e18; // 10%

    function setUp() public {
        model = new InterestRateModel(BASE_RATE, MULTIPLIER, JUMP_MULTIPLIER, KINK);
    }

    // ──────────────────────────────────────
    // getUtilization 테스트
    // ──────────────────────────────────────

    function test_utilization_zeroDeposits() public view {
        // 예치금 0 → 사용률 0 (0 나누기 방지)
        assertEq(model.getUtilization(0, 100), 0);
    }

    function test_utilization_zeroBorrows() public view {
        // 대출 0 → 사용률 0
        assertEq(model.getUtilization(1000e18, 0), 0);
    }

    function test_utilization_50percent() public view {
        // compound-v2-scenario.md Phase 3:
        // "U = totalBorrows / (cash + totalBorrows) = 10,000 / 20,000 = 50%"
        // 우리 모델은 U = totalBorrows / totalDeposits 로 단순화
        uint256 util = model.getUtilization(20_000e18, 10_000e18);
        assertEq(util, 0.5e18, "10K/20K = 50%");
        console.log("utilization(20K, 10K) =", util, "= 50%");
    }

    function test_utilization_80percent_kink() public view {
        uint256 util = model.getUtilization(10_000e18, 8_000e18);
        assertEq(util, 0.8e18, "8K/10K = 80% (kink)");
    }

    function test_utilization_100percent() public view {
        uint256 util = model.getUtilization(10_000e18, 10_000e18);
        assertEq(util, 1e18, "10K/10K = 100%");
    }

    // ──────────────────────────────────────
    // getBorrowRate 테스트
    // compound-v2-scenario.md의 시뮬레이션 표 검증
    // ──────────────────────────────────────

    function test_borrowRate_0percent() public view {
        // 사용률 0% → baseRate만 적용
        // 표: 0% → Borrow APR = 2.0%
        uint256 rate = model.getBorrowRate(10_000e18, 0);
        // borrows=0이면 util=0, rate = baseRate + 0 = baseRate
        // 하지만 getUtilization이 borrows=0이면 0을 리턴하므로:
        assertEq(rate, BASE_RATE, "0% util -> 2% baseRate");
        console.log("borrowRate at 0%  =", rate, "= 2%");
    }

    function test_borrowRate_50percent() public view {
        // compound-v2-scenario.md Phase 4 Step 3:
        // "APR = 2% + 50% × 10% = 2% + 5% = 7%"
        uint256 rate = model.getBorrowRate(20_000e18, 10_000e18);
        assertEq(rate, 0.07e18, "50% util -> 7% borrow rate");
        console.log("borrowRate at 50%% =", rate, "= 7%%");
    }

    function test_borrowRate_80percent_kink() public view {
        // 표: 80% → 2% + 80% × 10% = 10.0%
        uint256 rate = model.getBorrowRate(10_000e18, 8_000e18);
        assertEq(rate, 0.1e18, "80% util (kink) -> 10% borrow rate");
        console.log("borrowRate at 80%% =", rate, "= 10%%");
    }

    function test_borrowRate_90percent_jump() public view {
        // compound-v2-scenario.md Kink 설명 — kink 초과 시 2단계로 계산:
        //
        // [상황] 10,000 예치, 9,000 대출 → utilization = 90%
        //        kink = 80%이므로, 90% > 80% → "긴급 구간" 진입
        //
        // [Step 1] normalRate: kink(80%)까지의 이자율 계산 (정상 구간 공식 그대로)
        //   normalRate = baseRate + (kink * multiplier / PRECISION)
        //              = 2%      + (80%  * 10%        / 1)
        //              = 2%      + 8%
        //              = 10%
        //   → "80%까지는 정상 구간이었으니, 거기까지의 이자율은 10%"
        //
        // [Step 2] excessUtil: kink을 초과한 사용률 부분만 따로 뽑기
        //   excessUtil = utilization - kink
        //              = 90%         - 80%
        //              = 10%
        //   → "80%를 넘은 건 10%p만큼"
        //
        // [Step 3] 초과 구간에 jumpMultiplier(300%) 적용
        //   jumpPart = excessUtil * jumpMultiplier / PRECISION
        //            = 10%        * 300%           / 1
        //            = 30%
        //   → "10%p 초과에 대해 300% 기울기 → 이자 30% 추가"
        //
        // [최종] borrowRate = normalRate + jumpPart = 10% + 30% = 40%
        //
        // 비교: kink 이하에서 80% → 10%였는데
        //       kink 초과 10%p만 더 올라갔을 뿐인데 10% → 40%로 4배 급등!
        //       이것이 "Jump" Rate의 핵심 — 유동성 부족 시 급격한 이자로 상환 유도
        uint256 rate = model.getBorrowRate(10_000e18, 9_000e18);
        assertEq(rate, 0.4e18, "90% util -> 40% borrow rate (jump!)");
        console.log("borrowRate at 90%% =", rate, "= 40%% (JUMP!)");
    }

    function test_borrowRate_100percent() public view {
        // 표: 100% → 10% + 20% × 300% = 70.0%
        uint256 rate = model.getBorrowRate(10_000e18, 10_000e18);
        assertEq(rate, 0.7e18, "100% util -> 70% borrow rate");
        console.log("borrowRate at 100%% =", rate, "= 70%%");
    }

    // ──────────────────────────────────────
    // getBorrowRatePerSecond 테스트
    // ──────────────────────────────────────

    function test_borrowRatePerSecond() public view {
        // 연간 7% → 초당
        uint256 ratePerSec = model.getBorrowRatePerSecond(20_000e18, 10_000e18);
        uint256 annualRate = 0.07e18;
        uint256 expectedPerSec = annualRate / 365 days;
        assertEq(ratePerSec, expectedPerSec, "7% APR / seconds_per_year");
        console.log("borrowRatePerSecond at 50%% =", ratePerSec);

        // 역산 검증: 초당 x 1년 -> 원래 연간 이자율
        uint256 backToAnnual = ratePerSec * 365 days;
        // 정수 나눗셈 때문에 약간의 오차 발생 가능
        console.log("back to annual =", backToAnnual, "(expected: 70000000000000000)");
    }

    // ──────────────────────────────────────
    // getSupplyRate 테스트 — 핵심!
    // ──────────────────────────────────────

    /// @notice Supply Rate 공식이 왜 이렇게 되는가?
    /// @dev compound-v2-scenario.md Line 487~494에서 검증:
    ///
    ///   Supply APY = Borrow APR × Utilization × (1 - ReserveFactor)
    ///
    ///   이유를 돈의 흐름으로 이해하면:
    ///   ┌──────────────────────────────────────────────────────────┐
    ///   │ 전체 예치금: 20,000 USDC (Bob이 넣었음)                   │
    ///   │ 대출금:      10,000 USDC (Alice가 빌려감, 50% 사용률)     │
    ///   │ 남은 현금:   10,000 USDC (풀에 남아있음)                   │
    ///   └──────────────────────────────────────────────────────────┘
    ///
    ///   ① borrowRate = 7% → Alice가 내는 이자 = 10,000 × 7% = 700 USDC/년
    ///   ② 이 700 USDC가 이자 수입의 전부 (남은 10,000은 이자 안 냄)
    ///   ③ 프로토콜이 10% 떼감 → 700 × 10% = 70 USDC (reserve)
    ///   ④ 예치자에게 돌아감: 700 - 70 = 630 USDC
    ///   ⑤ supplyRate = 630 / 20,000 = 3.15%
    ///
    ///   공식으로 정리하면:
    ///     supplyRate = (borrowRate × totalBorrows × (1 - RF)) / totalDeposits
    ///                = borrowRate × (totalBorrows/totalDeposits) × (1 - RF)
    ///                = borrowRate × utilization × (1 - RF)
    ///                = 7% × 50% × 90% = 3.15% ✓
    function test_supplyRate_50percent() public view {
        // compound-v2-scenario.md: "Supply APY = 7% × 50% × 90% = 3.15%"
        uint256 rate = model.getSupplyRate(20_000e18, 10_000e18, RESERVE_FACTOR);
        assertEq(rate, 0.0315e18, "50% util, 10% RF -> 3.15% supply rate");
        console.log("supplyRate at 50%% util =", rate, "= 3.15%%");
    }

    function test_supplyRate_80percent() public view {
        // 표: 80% → Borrow 10%, Supply = 10% × 80% × 90% = 7.20%
        uint256 rate = model.getSupplyRate(10_000e18, 8_000e18, RESERVE_FACTOR);
        assertEq(rate, 0.072e18, "80% util -> 7.2% supply rate");
        console.log("supplyRate at 80%% util =", rate, "= 7.2%%");
    }

    function test_supplyRate_90percent_jump() public view {
        // 표: 90% → Borrow 40%, Supply = 40% × 90% × 90% = 32.40%
        uint256 rate = model.getSupplyRate(10_000e18, 9_000e18, RESERVE_FACTOR);
        assertEq(rate, 0.324e18, "90% util -> 32.4% supply rate");
        console.log("supplyRate at 90%% util =", rate, "= 32.4%%");
    }

    function test_supplyRate_zeroReserveFactor() public view {
        // RF=0이면 이자 전부 예치자에게
        // supplyRate = 7% × 50% × 100% = 3.5%
        uint256 rate = model.getSupplyRate(20_000e18, 10_000e18, 0);
        assertEq(rate, 0.035e18, "RF=0 -> supply rate = borrow x util");
        console.log("supplyRate (RF=0) =", rate, "= 3.5%%");
    }

    // ──────────────────────────────────────
    // compound-v2-scenario.md 전체 시뮬레이션 표 검증
    // ──────────────────────────────────────

    function test_fullSimulationTable() public view {
        console.log("=== Full Simulation Table ===");
        console.log("Util%% | Borrow APR | Supply APY");
        console.log("-------|------------|----------");

        uint256[8] memory utilizations = [uint256(0), 0.2e18, 0.4e18, 0.5e18, 0.6e18, 0.8e18, 0.9e18, 1e18];
        uint256[8] memory expectedBorrow =
            [uint256(0.02e18), 0.04e18, 0.06e18, 0.07e18, 0.08e18, 0.1e18, 0.4e18, 0.7e18];

        for (uint256 i = 0; i < utilizations.length; i++) {
            uint256 deposits = 10_000e18;
            uint256 borrows = deposits * utilizations[i] / 1e18;
            uint256 borrowRate = model.getBorrowRate(deposits, borrows);
            uint256 supplyRate = model.getSupplyRate(deposits, borrows, RESERVE_FACTOR);

            assertEq(borrowRate, expectedBorrow[i], "Borrow rate mismatch");
            console.log("util:", utilizations[i] * 100 / 1e18, "borrow:", borrowRate);
            console.log("  supply:", supplyRate);
        }
    }
}
