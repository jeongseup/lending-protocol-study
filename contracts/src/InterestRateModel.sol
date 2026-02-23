// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title InterestRateModel — 렌딩 풀용 이자율 모델
/// @notice LendingPool에 통합되는 이자율 계산 컨트랙트
/// @notice Interest rate calculator integrated into LendingPool
/// @dev JumpRateModel과 동일한 로직이지만, LendingPool에서 사용하기 편하게 리팩토링
/// @dev Same logic as JumpRateModel, refactored for LendingPool integration

contract InterestRateModel {
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice 기본 연간 이자율 / Base annual rate
    uint256 public immutable baseRate;

    /// @notice kink 이하 기울기 / Slope below kink
    uint256 public immutable multiplier;

    /// @notice kink 이상 기울기 / Slope above kink
    uint256 public immutable jumpMultiplier;

    /// @notice 최적 사용률 / Optimal utilization
    uint256 public immutable kink;

    constructor(
        uint256 _baseRate,
        uint256 _multiplier,
        uint256 _jumpMultiplier,
        uint256 _kink
    ) {
        baseRate = _baseRate;
        multiplier = _multiplier;
        jumpMultiplier = _jumpMultiplier;
        kink = _kink;
    }

    /// @notice 사용률 계산 / Calculate utilization rate
    function getUtilization(uint256 totalDeposits, uint256 totalBorrows)
        public
        pure
        returns (uint256)
    {
        if (totalDeposits == 0) return 0;
        if (totalBorrows == 0) return 0;
        return totalBorrows * PRECISION / totalDeposits;
    }

    /// @notice 연간 대출 이자율 / Annual borrow rate
    function getBorrowRate(uint256 totalDeposits, uint256 totalBorrows)
        public
        view
        returns (uint256)
    {
        uint256 utilization = getUtilization(totalDeposits, totalBorrows);

        if (utilization <= kink) {
            return baseRate + (utilization * multiplier / PRECISION);
        }

        uint256 normalRate = baseRate + (kink * multiplier / PRECISION);
        uint256 excessUtil = utilization - kink;
        return normalRate + (excessUtil * jumpMultiplier / PRECISION);
    }

    /// @notice 초당 대출 이자율 / Per-second borrow rate
    function getBorrowRatePerSecond(uint256 totalDeposits, uint256 totalBorrows)
        external
        view
        returns (uint256)
    {
        return getBorrowRate(totalDeposits, totalBorrows) / SECONDS_PER_YEAR;
    }

    /// @notice 연간 예치 이자율 / Annual supply rate
    function getSupplyRate(
        uint256 totalDeposits,
        uint256 totalBorrows,
        uint256 reserveFactor
    ) external view returns (uint256) {
        uint256 borrowRate = getBorrowRate(totalDeposits, totalBorrows);
        uint256 utilization = getUtilization(totalDeposits, totalBorrows);
        uint256 rateToPool = borrowRate * utilization / PRECISION;
        return rateToPool * (PRECISION - reserveFactor) / PRECISION;
    }
}
