// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title InterestRateModel — 렌딩 풀용 이자율 모델 (Practice)
/// @notice Kink(꺾임점) 기반 이자율 모델을 직접 구현해보는 연습 파일
///
/// ┌─────────────────────────────────────────────────────────┐
/// │ Kink Model 개념도                                        │
/// │                                                         │
/// │ 이자율                                                   │
/// │ │                        ╱ ← jumpMultiplier (급경사)     │
/// │ │                      ╱                                │
/// │ │                    ╱                                  │
/// │ │──────────────╱──── ← kink (최적 사용률, 보통 80%)     │
/// │ │            ╱  ← multiplier (완만한 경사)               │
/// │ │         ╱                                             │
/// │ │      ╱                                                │
/// │ │   ╱                                                   │
/// │ │╱ ← baseRate (기본 이자율)                              │
/// │ └───────────────────────────── 사용률(Utilization)       │
/// │ 0%              kink            100%                    │
/// └─────────────────────────────────────────────────────────┘
///
/// 공식 정리:
///   utilization = totalBorrows / totalDeposits
///   if utilization <= kink:
///     borrowRate = baseRate + (utilization × multiplier)
///   if utilization > kink:
///     borrowRate = baseRate + (kink × multiplier) + ((utilization - kink) × jumpMultiplier)

contract InterestRateModel {

    // ──────────────────────────────────────
    // 상수 (Constants)
    // ──────────────────────────────────────

    /// @dev 소수점 정밀도. Solidity에는 float이 없으므로 1e18을 곱해서 사용.
    ///      예: 80% = 0.8 → 0.8 * 1e18 = 8e17
    ///      모든 비율(rate) 계산에서 이 값으로 스케일링한다.
    uint256 public constant PRECISION = 1e18;

    /// @dev 1년을 초(seconds)로 환산한 값. 연간 이자율 → 초당 이자율 변환에 사용.
    ///      Solidity에서 `365 days`는 365 * 24 * 60 * 60 = 31,536,000
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // ──────────────────────────────────────
    // 상태 변수 (State Variables)
    // ──────────────────────────────────────
    // immutable = 생성자에서 한 번만 설정 가능, 이후 변경 불가 (gas 절약)
    // 이 4개 파라미터가 이자율 커브의 모양을 결정한다.

    /// @notice 기본 연간 이자율 (y절편)
    /// @dev 사용률이 0%일 때의 이자율. 예: 2% = 0.02e18
    ///      "아무도 빌려가지 않아도 이 정도는 기본으로 받겠다"
    uint256 public immutable baseRate;

    /// @notice kink 이하 구간의 기울기
    /// @dev 정상 구간에서 사용률 1% 증가당 이자율 증가분.
    ///      예: 10% = 0.1e18 → 사용률 50%일 때 추가 이자 = 50% × 10% = 5%
    uint256 public immutable multiplier;

    /// @notice kink 이상 구간의 기울기 (급격히 올라감)
    /// @dev 긴급 구간에서 사용률 1% 증가당 이자율 증가분.
    ///      예: 300% = 3e18 → kink 초과 10%마다 이자 30% 추가
    ///      "유동성이 부족하니 빨리 갚아라" 시그널
    uint256 public immutable jumpMultiplier;

    /// @notice 최적 사용률 (두 구간의 경계점)
    /// @dev 보통 80% (= 0.8e18). 이 지점에서 이자율 기울기가 꺾인다(jump).
    ///      프로토콜이 "이 정도까지는 건강한 상태"라고 판단하는 기준
    uint256 public immutable kink;

    // ──────────────────────────────────────
    // 생성자 (Constructor)
    // ──────────────────────────────────────

    /// @param _baseRate 기본 연간 이자율 (1e18 스케일)
    /// @param _multiplier kink 이하 기울기 (1e18 스케일)
    /// @param _jumpMultiplier kink 이상 기울기 (1e18 스케일)
    /// @param _kink 최적 사용률 (1e18 스케일)
    constructor(
        uint256 _baseRate,
        uint256 _multiplier,
        uint256 _jumpMultiplier,
        uint256 _kink
    ) {
        // TODO: 4개의 immutable 상태 변수에 생성자 인자를 할당하세요.
    }

    // ──────────────────────────────────────
    //  함수 1: getUtilization
    // ──────────────────────────────────────

    /// @notice 사용률(Utilization Rate) 계산
    /// @dev 전체 예치금 중 얼마나 빌려갔는지의 비율.
    ///      utilization = totalBorrows / totalDeposits
    ///
    ///      주의할 점:
    ///      - totalDeposits가 0이면? → 0 리턴 (빈 풀이므로 사용률 없음)
    ///      - totalBorrows가 0이면? → 0 리턴 (아무도 안 빌렸으므로)
    ///      - Solidity는 정수 나눗셈이므로 PRECISION을 곱해서 소수점 보존
    ///        계산: totalBorrows * PRECISION / totalDeposits
    ///        예: 800 * 1e18 / 1000 = 0.8e18 (80%)
    ///
    /// @param totalDeposits 전체 예치 금액 (raw amount)
    /// @param totalBorrows 전체 대출 금액 (raw amount)
    /// @return utilization 사용률 (1e18 스케일, 예: 80% = 0.8e18)
    function getUtilization(uint256 totalDeposits, uint256 totalBorrows)
        public
        pure
        returns (uint256)
    {
        // TODO: 구현하세요.
        // 힌트: 엣지 케이스(0 나누기) 먼저 처리하고, 비율 계산
    }

    // ──────────────────────────────────────
    //  함수 2: getBorrowRate
    // ──────────────────────────────────────

    /// @notice 연간 대출 이자율 계산 (Kink Model 핵심)
    /// @dev 사용률에 따라 두 가지 공식 중 하나를 적용:
    ///
    ///      [Case 1] utilization <= kink (정상 구간):
    ///        borrowRate = baseRate + (utilization × multiplier / PRECISION)
    ///        예: baseRate=2%, multiplier=10%, utilization=50%
    ///            → 2% + (50% × 10%) = 2% + 5% = 7%
    ///
    ///      [Case 2] utilization > kink (긴급 구간):
    ///        normalRate = baseRate + (kink × multiplier / PRECISION)  ← kink까지의 이자
    ///        excessUtil = utilization - kink                          ← kink 초과분
    ///        borrowRate = normalRate + (excessUtil × jumpMultiplier / PRECISION)
    ///        예: baseRate=2%, kink=80%, multiplier=10%, jumpMultiplier=300%, utilization=90%
    ///            normalRate = 2% + (80% × 10%) = 10%
    ///            excessUtil = 90% - 80% = 10%
    ///            → 10% + (10% × 300%) = 10% + 30% = 40%
    ///
    /// @param totalDeposits 전체 예치 금액
    /// @param totalBorrows 전체 대출 금액
    /// @return 연간 대출 이자율 (1e18 스케일)
    function getBorrowRate(uint256 totalDeposits, uint256 totalBorrows)
        public
        view
        returns (uint256)
    {
        // TODO: 구현하세요.
        // 힌트: 먼저 getUtilization()으로 사용률을 구하고,
        //       kink와 비교해서 Case 1 또는 Case 2 적용
    }

    // ──────────────────────────────────────
    //  함수 3: getBorrowRatePerSecond
    // ──────────────────────────────────────

    /// @notice 초당 대출 이자율 계산
    /// @dev LendingPool의 _accrueInterest()에서 사용.
    ///      블록마다 이자를 누적할 때, 연간 이자율을 초 단위로 쪼갠다.
    ///
    ///      공식: borrowRatePerSecond = borrowRate / SECONDS_PER_YEAR
    ///
    ///      예: 연간 10% = 0.1e18
    ///          → 0.1e18 / 31536000 ≈ 3.17e9 (초당)
    ///          → 이것을 경과 시간(초)만큼 곱하면 누적 이자
    ///
    /// @param totalDeposits 전체 예치 금액
    /// @param totalBorrows 전체 대출 금액
    /// @return 초당 대출 이자율 (1e18 스케일)
    function getBorrowRatePerSecond(uint256 totalDeposits, uint256 totalBorrows)
        external
        view
        returns (uint256)
    {
        // TODO: 구현하세요.
        // 힌트: getBorrowRate() 결과를 SECONDS_PER_YEAR로 나누기
    }

    // ──────────────────────────────────────
    //  함수 4: getSupplyRate
    // ──────────────────────────────────────

    /// @notice 연간 예치 이자율 계산 (예치자가 받는 이자)
    /// @dev 대출 이자가 모두 예치자에게 가는 게 아니라, 프로토콜이 일부를 떼감.
    ///      이것이 reserveFactor (준비금 비율)의 역할.
    ///
    ///      공식 분해:
    ///        ① borrowRate = getBorrowRate(...)          // 대출 이자율
    ///        ② utilization = getUtilization(...)        // 사용률
    ///        ③ rateToPool = borrowRate × utilization    // 풀에 들어오는 이자
    ///           → 사용률이 50%면, 예치금의 절반만 대출되므로 이자도 절반만 발생
    ///        ④ supplyRate = rateToPool × (1 - reserveFactor)
    ///           → reserveFactor=10%면, 이자의 90%만 예치자에게 분배
    ///
    ///      예: borrowRate=10%, utilization=80%, reserveFactor=10%
    ///          rateToPool = 10% × 80% = 8%
    ///          supplyRate = 8% × 90% = 7.2%
    ///          → 예치자는 연 7.2% 수익, 프로토콜은 0.8% 수수료
    ///
    /// @param totalDeposits 전체 예치 금액
    /// @param totalBorrows 전체 대출 금액
    /// @param reserveFactor 준비금 비율 (1e18 스케일, 예: 10% = 0.1e18)
    /// @return 연간 예치 이자율 (1e18 스케일)
    function getSupplyRate(
        uint256 totalDeposits,
        uint256 totalBorrows,
        uint256 reserveFactor
    ) external view returns (uint256) {
        // TODO: 구현하세요.
        // 힌트: 위의 ①②③④ 단계를 순서대로 계산
    }
}
