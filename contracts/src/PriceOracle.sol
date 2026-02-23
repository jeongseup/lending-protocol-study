// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IPriceFeed — Chainlink 가격 피드 인터페이스
/// @notice Chainlink AggregatorV3Interface의 간소화 버전
/// @notice Simplified version of Chainlink's AggregatorV3Interface
interface IPriceFeed {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function decimals() external view returns (uint8);
}

/// @title PriceOracle — 가격 오라클 컨트랙트
/// @notice 여러 자산의 USD 가격을 Chainlink을 통해 제공합니다
/// @notice Provides USD prices for multiple assets via Chainlink price feeds
/// @dev Day 4-7 학습: 오라클 통합 및 지연 모니터링
/// @dev Day 4-7 learning: Oracle integration and staleness monitoring

contract PriceOracle {
    /// @notice 자산별 Chainlink 가격 피드 매핑
    /// @notice Mapping of asset address to Chainlink price feed
    mapping(address => address) public priceFeeds;

    /// @notice 최대 허용 지연 시간 (초)
    /// @notice Maximum allowed staleness in seconds
    uint256 public maxStaleness;

    /// @notice 프로토콜 관리자
    /// @notice Protocol admin
    address public owner;

    /// @notice 가격 피드 설정 이벤트 / Price feed set event
    event PriceFeedSet(address indexed asset, address indexed feed);

    /// @notice 오라클 지연 감지 이벤트 / Oracle staleness detected event
    event OracleStale(address indexed asset, uint256 updatedAt, uint256 currentTime);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    /// @param _maxStaleness 최대 허용 지연 시간 / Max staleness in seconds (e.g., 3600 = 1 hour)
    constructor(uint256 _maxStaleness) {
        owner = msg.sender;
        maxStaleness = _maxStaleness;
    }

    /// @notice 자산의 가격 피드를 설정합니다
    /// @notice Set the price feed for an asset
    function setPriceFeed(address asset, address feed) external onlyOwner {
        require(asset != address(0), "Invalid asset");
        require(feed != address(0), "Invalid feed");
        priceFeeds[asset] = feed;
        emit PriceFeedSet(asset, feed);
    }

    /// @notice 자산의 USD 가격을 조회합니다 (8자리 소수점)
    /// @notice Get the USD price of an asset (8 decimals)
    /// @dev 지연된 오라클 데이터는 거부합니다
    /// @dev Rejects stale oracle data
    function getAssetPrice(address asset) public view returns (uint256) {
        address feed = priceFeeds[asset];
        require(feed != address(0), "No price feed");

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = IPriceFeed(feed).latestRoundData();

        // 가격이 유효한지 확인
        // Validate price data
        require(answer > 0, "Invalid price");
        require(updatedAt > 0, "Round not complete");
        require(answeredInRound >= roundId, "Stale round");

        // 오라클 지연 확인 (DevOps 모니터링 핵심!)
        // Check oracle staleness (key DevOps monitoring point!)
        require(
            block.timestamp - updatedAt <= maxStaleness,
            "Oracle data is stale"
        );

        return uint256(answer);
    }

    /// @notice 자산 가격을 18자리 소수점으로 정규화하여 반환
    /// @notice Get asset price normalized to 18 decimals
    function getAssetPriceNormalized(address asset) external view returns (uint256) {
        address feed = priceFeeds[asset];
        require(feed != address(0), "No price feed");

        uint256 price = getAssetPrice(asset);
        uint8 feedDecimals = IPriceFeed(feed).decimals();

        // 18자리 소수점으로 스케일링
        // Scale to 18 decimals
        if (feedDecimals < 18) {
            return price * 10 ** (18 - feedDecimals);
        } else if (feedDecimals > 18) {
            return price / 10 ** (feedDecimals - 18);
        }
        return price;
    }

    /// @notice 오라클 지연 여부를 확인합니다 (모니터링용)
    /// @notice Check if oracle is stale (for monitoring purposes)
    /// @return isStale 지연 여부 / Whether oracle is stale
    /// @return staleness 지연 시간 (초) / Staleness in seconds
    function checkStaleness(address asset) external view returns (bool isStale, uint256 staleness) {
        address feed = priceFeeds[asset];
        require(feed != address(0), "No price feed");

        (, , , uint256 updatedAt, ) = IPriceFeed(feed).latestRoundData();
        staleness = block.timestamp - updatedAt;
        isStale = staleness > maxStaleness;
    }
}
