// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title JumpRateModel — 점프 이자율 모델
/// @notice 사용률(Utilization)에 따라 이자율을 계산하는 컨트랙트
/// @notice Calculates interest rates based on utilization rate with a "kink" jump point
/// @dev Day 2 학습: Compound V2의 이자율 모델을 기반으로 구현
/// @dev Day 2 learning: Based on Compound V2's interest rate model

contract JumpRateModel {
    /// @notice 기본 이자율 (연간, 1e18 = 100%)
    /// @notice Base interest rate per year (1e18 = 100%)
    uint256 public immutable baseRate;

    /// @notice kink 이하에서의 기울기 (사용률 대비 이자율 증가율)
    /// @notice Slope below kink (rate of interest increase per utilization)
    uint256 public immutable multiplier;

    /// @notice kink 이상에서의 급격한 기울기
    /// @notice Steep slope above kink (incentivizes liquidity return)
    uint256 public immutable jumpMultiplier;

    /// @notice 최적 사용률 (보통 80%, 1e18 = 100%)
    /// @notice Optimal utilization rate (typically 80%, 1e18 = 100%)
    uint256 public immutable kink;

    /// @notice 블록당 초 수 (이자 계산 참고용)
    /// @notice Seconds per year for rate conversion reference
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice 정밀도 상수
    /// @notice Precision constant
    uint256 public constant PRECISION = 1e18;

    /// @param _baseRate 기본 연간 이자율 / Base annual rate (1e18 scale)
    /// @param _multiplier kink 이하 기울기 / Slope below kink (1e18 scale)
    /// @param _jumpMultiplier kink 이상 기울기 / Slope above kink (1e18 scale)
    /// @param _kink 최적 사용률 / Optimal utilization (1e18 scale, e.g., 0.8e18 = 80%)
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

    /// @notice 사용률을 계산합니다
    /// @notice Calculate the utilization rate
    /// @param cash 풀에 남아있는 현금 / Cash remaining in pool
    /// @param borrows 총 대출금 / Total borrows outstanding
    /// @param reserves 프로토콜 준비금 / Protocol reserves
    /// @return 사용률 (1e18 스케일) / Utilization rate (1e18 scale)
    function getUtilization(uint256 cash, uint256 borrows, uint256 reserves)
        public
        pure
        returns (uint256)
    {
        // 대출이 없으면 사용률 0
        // If no borrows, utilization is 0
        if (borrows == 0) return 0;

        // 사용률 = 대출금 / (현금 + 대출금 - 준비금)
        // Utilization = borrows / (cash + borrows - reserves)
        uint256 totalLiquidity = cash + borrows - reserves;
        require(totalLiquidity > 0, "Total liquidity must be > 0");

        return borrows * PRECISION / totalLiquidity;
    }

    /// @notice 대출 이자율을 계산합니다 (연간)
    /// @notice Calculate the borrow interest rate per year
    /// @dev kink 이하: baseRate + utilization * multiplier
    /// @dev kink 이상: normalRate + (utilization - kink) * jumpMultiplier
    /// @dev Below kink: linear rate. Above kink: steep jump rate.
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves)
        public
        view
        returns (uint256)
    {
        uint256 utilization = getUtilization(cash, borrows, reserves);

        // kink 이하: 완만한 기울기
        // Below kink: gentle slope
        if (utilization <= kink) {
            return baseRate + (utilization * multiplier / PRECISION);
        }

        // kink 이상: 급격한 기울기 (유동성 복귀 유도)
        // Above kink: steep slope (incentivizes liquidity return)
        uint256 normalRate = baseRate + (kink * multiplier / PRECISION);
        uint256 excessUtil = utilization - kink;
        return normalRate + (excessUtil * jumpMultiplier / PRECISION);
    }

    /// @notice 예치 이자율을 계산합니다 (연간)
    /// @notice Calculate the supply interest rate per year
    /// @dev 예치 이자 = 대출 이자 × 사용률 × (1 - 준비금 비율)
    /// @dev Supply rate = borrow rate × utilization × (1 - reserve factor)
    /// @param reserveFactor 프로토콜 수수료 비율 / Protocol fee ratio (1e18 scale)
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactor
    ) public view returns (uint256) {
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 utilization = getUtilization(cash, borrows, reserves);

        // 예치 이자 = 대출이자 × 사용률 × (1 - 준비금비율)
        // Supply rate = borrow rate * utilization * (1 - reserve factor)
        uint256 rateToPool = borrowRate * utilization / PRECISION;
        return rateToPool * (PRECISION - reserveFactor) / PRECISION;
    }
}
