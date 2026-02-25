// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PriceOracle — 가격 오라클 컨트랙트 (Practice)
/// @notice Chainlink 가격 피드를 통해 자산의 USD 가격을 제공하는 오라클
///
/// ┌─────────────────────────────────────────────────────────────────┐
/// │ 오라클의 역할 — 왜 렌딩 프로토콜에 필수인가?                      │
/// │                                                                 │
/// │  LendingPool이 알아야 하는 것:                                   │
/// │    "Alice의 ETH 담보가 USDC 대출을 커버할 수 있는가?"             │
/// │                                                                 │
/// │  이를 위해 필요한 정보:                                          │
/// │    ETH 가격 = $2,000  ← 어디서 가져오나? → 오라클!               │
/// │    USDC 가격 = $1.00  ← 어디서 가져오나? → 오라클!               │
/// │                                                                 │
/// │  오라클 없이는 담보 가치 계산, 청산 판단이 불가능                   │
/// └─────────────────────────────────────────────────────────────────┘
///
/// ┌─────────────────────────────────────────────────────────────────┐
/// │ Chainlink 가격 피드 구조                                        │
/// │                                                                 │
/// │  Chainlink은 오프체인 노드 네트워크가 실제 시장 가격을             │
/// │  주기적으로 온체인에 업데이트하는 구조:                            │
/// │                                                                 │
/// │  [Binance/Coinbase/...] → [Chainlink 노드들] → [온체인 컨트랙트]  │
/// │       실제 가격              합의/집계           latestRoundData()│
/// │                                                                 │
/// │  latestRoundData() 리턴값:                                       │
/// │    roundId          — 라운드 번호 (업데이트마다 증가)              │
/// │    answer           — 가격 (int256, 보통 8 decimals)             │
/// │    startedAt        — 라운드 시작 시간                            │
/// │    updatedAt        — 마지막 업데이트 시간 ← staleness 체크에 핵심 │
/// │    answeredInRound  — 답변이 완료된 라운드                        │
/// └─────────────────────────────────────────────────────────────────┘

// ──────────────────────────────────────
// Step 1: Chainlink 인터페이스 정의
// ──────────────────────────────────────

/// @notice Chainlink AggregatorV3Interface의 간소화 버전
/// @dev 실제 Chainlink은 더 많은 함수가 있지만, 우리가 필요한 건 이 2개뿐
///
///      Q: 왜 인터페이스를 직접 정의하는가?
///      A: Chainlink 전체 패키지를 의존성에 추가하지 않기 위해.
///         실제 프로덕션에서는 chainlink/contracts를 import하기도 함.
interface IPriceFeed {
    /// @notice 최신 가격 데이터를 조회
    /// @dev Chainlink 노드들이 합의한 최신 가격
    /// @return roundId 라운드 번호
    /// @return answer 가격 (int256! — 음수도 이론적으로 가능하기에)
    /// @return startedAt 라운드 시작 timestamp (보통 사용 안 함)
    /// @return updatedAt 가격이 마지막으로 업데이트된 timestamp ← 핵심!
    /// @return answeredInRound 답변이 기록된 라운드 번호
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice 이 피드의 소수점 자릿수
    /// @dev 대부분의 USD 피드는 8 decimals (예: ETH = 2000_00000000)
    ///      일부 피드는 18 decimals (ETH/BTC 같은 쌍)
    function decimals() external view returns (uint8);
}

// ──────────────────────────────────────
// Step 2: PriceOracle 컨트랙트
// ──────────────────────────────────────

contract PriceOracle {
    // ──────────────────────────────────────
    // 상태 변수
    // ──────────────────────────────────────

    /// @notice 자산 주소 → Chainlink 가격 피드 주소 매핑
    /// @dev 예: WETH(0x...) → ETH/USD 피드(0x...)
    ///      LendingPool에 등록된 모든 자산에 대해 피드가 설정되어야 함
    mapping(address => address) public priceFeeds;

    /// @notice 최대 허용 지연 시간 (초)
    /// @dev Chainlink이 가격을 얼마나 오래 업데이트 안 하면 "오래됐다"고 판단할지
    ///      예: 3600 = 1시간. 1시간 넘게 업데이트 없으면 가격 조회 거부
    ///      왜 필요? → 오라클이 죽거나 멈추면 오래된 가격으로 청산이 발생할 수 있음
    uint256 public maxStaleness;

    /// @notice 관리자 주소 — 피드 설정 권한
    address public owner;

    /// @notice 가격 피드 설정 이벤트
    event PriceFeedSet(address indexed asset, address indexed feed);

    /// @notice 오라클 지연 감지 이벤트 (모니터링 봇이 감지)
    event OracleStale(address indexed asset, uint256 updatedAt, uint256 currentTime);

    /// @dev owner만 호출 가능한 함수에 붙이는 접근 제어
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // ──────────────────────────────────────
    // 생성자
    // ──────────────────────────────────────

    /// @param _maxStaleness 최대 허용 지연 시간 (초). 예: 3600 = 1시간
    constructor(uint256 _maxStaleness) {
        // TODO: owner를 배포자(msg.sender)로, maxStaleness를 설정하세요.
        owner = msg.sender;
        maxStaleness = _maxStaleness;
    }

    // ──────────────────────────────────────
    //  함수 1: setPriceFeed
    // ──────────────────────────────────────

    /// @notice 특정 자산의 Chainlink 가격 피드를 등록/변경
    /// @dev owner만 호출 가능. 자산과 피드 주소가 유효해야 함 (address(0) 불가)
    ///
    ///      사용 예시:
    ///        oracle.setPriceFeed(WETH_ADDRESS, CHAINLINK_ETH_USD_FEED);
    ///        oracle.setPriceFeed(USDC_ADDRESS, CHAINLINK_USDC_USD_FEED);
    ///
    /// @param asset 자산 토큰 주소 (예: WETH, USDC)
    /// @param feed Chainlink 가격 피드 컨트랙트 주소
    function setPriceFeed(address asset, address feed) external onlyOwner {
        // TODO: 구현하세요.
        // 힌트: require로 address(0) 체크, mapping에 저장, 이벤트 발생
        require(asset != address(0), "Invalid asset");
        require(feed != address(0), "Invalid feed");
        priceFeeds[asset] = feed;
        emit PriceFeedSet(asset, feed);
    }

    // ──────────────────────────────────────
    //  함수 2: getAssetPrice (핵심!)
    // ──────────────────────────────────────

    /// @notice 자산의 USD 가격을 조회 (Chainlink 피드의 원본 decimals 그대로)
    /// @dev 이 함수가 오라클의 핵심. 3가지 안전 검증을 수행:
    ///
    ///      ① 가격이 양수인가? (answer > 0)
    ///         → Chainlink이 음수를 리턴하면 뭔가 잘못된 것
    ///
    ///      ② 라운드가 완료되었는가? (updatedAt > 0)
    ///         → updatedAt이 0이면 아직 노드들이 합의를 안 한 것
    ///
    ///      ③ 오래된 라운드가 아닌가? (answeredInRound >= roundId)
    ///         → answeredInRound < roundId면 이전 라운드의 답변을 쓰고 있는 것
    ///
    ///      ④ 데이터가 신선한가? (block.timestamp - updatedAt <= maxStaleness)
    ///         → 마지막 업데이트로부터 너무 오래 지났으면 거부
    ///         → 이것이 "staleness check" — DevOps 모니터링의 핵심
    ///
    ///      예: ETH/USD 피드, 8 decimals → 리턴값 200000000000 = $2,000.00
    ///
    /// @param asset 자산 토큰 주소
    /// @return 자산의 USD 가격 (피드의 decimals, 보통 8)
    function getAssetPrice(address asset) public view returns (uint256) {
        // TODO: 구현하세요.
        // 순서:
        // 1. priceFeeds에서 피드 주소 가져오기 (없으면 revert)
        address feed = priceFeeds[asset];
        require(feed != address(0), "No price feed");
        // 2. IPriceFeed(feed).latestRoundData() 호출
        (uint256 roundId, int256 answer,, uint256 updatedAt, uint256 answeredInRound) =
            IPriceFeed(feed).latestRoundData();

        // 3. answer > 0 체크
        require(answer > 0, "Invalid price");
        // 4. updatedAt > 0 체크
        require(updatedAt > 0, "Invalid updatedAt");
        // 5. answeredInRound >= roundId 체크
        require(answeredInRound >= roundId, "Invalid answeredInRound");
        // 6. block.timestamp - updatedAt <= maxStaleness 체크
        require(block.timestamp - updatedAt <= maxStaleness, "Oracle data is stale");
        // 7. uint256(answer) 리턴
        return uint256(answer);
    }

    // ──────────────────────────────────────
    //  함수 3: getAssetPriceNormalized
    // ──────────────────────────────────────

    /// @notice 자산 가격을 18 decimals로 정규화하여 리턴
    /// @dev Chainlink 피드마다 decimals가 다를 수 있음:
    ///        ETH/USD = 8 decimals → 2000_00000000
    ///        ETH/BTC = 18 decimals → 0.05e18
    ///
    ///      LendingPool은 모든 가격을 통일된 형식으로 받아야 하므로
    ///      18 decimals로 맞춰주는 것:
    ///
    ///        feedDecimals < 18 → 10^(18 - feedDecimals)를 곱함 (스케일 업)
    ///        feedDecimals > 18 → 10^(feedDecimals - 18)로 나눔 (스케일 다운)
    ///        feedDecimals = 18 → 그대로
    ///
    ///      예: ETH $2,000 (8 decimals)
    ///          200000000000 × 10^(18-8) = 200000000000 × 10^10 = 2000e18
    ///
    /// @param asset 자산 토큰 주소
    /// @return 자산의 USD 가격 (18 decimals)
    function getAssetPriceNormalized(address asset) external view returns (uint256) {
        // TODO: 구현하세요.
        // 힌트: getAssetPrice()로 가격, IPriceFeed.decimals()로 자릿수 확인 후 스케일링
        address feed = priceFeeds[asset];
        require(feed != address(0), "No price feed");

        uint256 price = getAssetPrice(asset);
        uint8 feedDecimals = IPriceFeed(feed).decimals();

        if (feedDecimals < 18) {
            return price * 10 ** (18 - feedDecimals);
        } else if (feedDecimals > 18) {
            return price / 10 ** (feedDecimals - 18);
        }
        return price;
    }

    // ──────────────────────────────────────
    //  함수 4: checkStaleness (모니터링용)
    // ──────────────────────────────────────

    /// @notice 오라클 데이터의 지연 상태를 확인 (DevOps 모니터링용)
    /// @dev getAssetPrice()와 달리 revert하지 않고 상태만 리턴
    ///      모니터링 봇이 주기적으로 호출해서 알림을 보내는 용도
    ///
    ///      사용 시나리오:
    ///        (bool isStale, uint256 staleness) = oracle.checkStaleness(WETH);
    ///        if (isStale) {
    ///            sendAlert("ETH oracle stale for " + staleness + " seconds!");
    ///        }
    ///
    /// @param asset 자산 토큰 주소
    /// @return isStale 지연 여부 (true = 오래됨)
    /// @return staleness 마지막 업데이트 이후 경과 시간 (초)
    function checkStaleness(address asset) external view returns (bool isStale, uint256 staleness) {
        // TODO: 구현하세요.
        // 힌트: latestRoundData()에서 updatedAt만 필요,
        //       block.timestamp - updatedAt로 경과 시간 계산
        address feed = priceFeeds[asset];
        require(feed != address(0), "No price feed");

        (,,, uint256 updatedAt,) = IPriceFeed(feed).latestRoundData();
        staleness = block.timestamp - updatedAt;
        isStale = staleness > maxStaleness;
    }
}
