// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";
import "../src/InterestRateModel.sol";
import "../src/PriceOracle.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title 불변성 테스트 — Day 3 학습
/// @notice 프로토콜 불변 조건이 항상 유지되는지 확인합니다
/// @notice Verify protocol invariants always hold
/// @dev 불변성 테스트는 랜덤 함수 호출 시퀀스 후에도 조건이 유지되는지 검증
/// @dev Invariant tests verify conditions hold after random function call sequences

/// @notice 테스트용 ERC20 토큰 / Test ERC20 token
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 dec) ERC20(name, symbol) {
        _decimals = dec;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice 테스트용 가격 피드 / Mock price feed for testing
contract MockPriceFeed {
    int256 private _price;
    uint8 private _decimals;
    uint256 private _updatedAt;

    constructor(int256 price, uint8 dec) {
        _price = price;
        _decimals = dec;
        _updatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, _price, block.timestamp, _updatedAt, 1);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function setPrice(int256 price) external {
        _price = price;
        _updatedAt = block.timestamp;
    }
}

/// @title 렌딩 풀 핸들러 — 불변성 테스트용 행위 정의
/// @notice Defines actions for invariant testing
contract LendingPoolHandler is Test {
    LendingPool public pool;
    MockERC20 public weth;
    MockERC20 public usdc;
    address[] public actors;

    constructor(LendingPool _pool, MockERC20 _weth, MockERC20 _usdc) {
        pool = _pool;
        weth = _weth;
        usdc = _usdc;

        // 테스트 사용자 생성 / Create test users
        for (uint256 i = 0; i < 3; i++) {
            address actor = address(uint160(0x1000 + i));
            actors.push(actor);
            // 토큰 지급 / Give tokens
            weth.mint(actor, 100e18);
            usdc.mint(actor, 100_000e6);
            // 승인 / Approve
            vm.startPrank(actor);
            weth.approve(address(pool), type(uint256).max);
            usdc.approve(address(pool), type(uint256).max);
            vm.stopPrank();
        }
    }

    /// @notice 랜덤 사용자가 예치합니다 / Random user deposits
    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e15, 10e18);

        if (weth.balanceOf(actor) < amount) return;

        vm.prank(actor);
        pool.deposit(address(weth), amount);
    }

    /// @notice 랜덤 사용자가 대출합니다 / Random user borrows
    function borrow(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e4, 1000e6);

        vm.prank(actor);
        try pool.borrow(address(usdc), amount) {} catch {}
    }

    /// @notice 랜덤 사용자가 상환합니다 / Random user repays
    function repay(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e4, 1000e6);

        if (usdc.balanceOf(actor) < amount) return;

        vm.prank(actor);
        try pool.repay(address(usdc), amount) {} catch {}
    }

    /// @notice 시간을 앞으로 진행합니다 (이자 누적)
    /// @notice Advance time (interest accrual)
    function warpTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1, 365 days);
        vm.warp(block.timestamp + seconds_);
    }
}

contract LendingPoolInvariantTest is Test {
    LendingPool public pool;
    InterestRateModel public rateModel;
    PriceOracle public oracle;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockPriceFeed public ethFeed;
    MockPriceFeed public usdcFeed;
    LendingPoolHandler public handler;

    function setUp() public {
        // 오라클 설정 / Oracle setup
        oracle = new PriceOracle(3600);
        ethFeed = new MockPriceFeed(2000e8, 8); // ETH = $2000
        usdcFeed = new MockPriceFeed(1e8, 8);   // USDC = $1

        // 이자율 모델 / Interest rate model
        rateModel = new InterestRateModel(
            0.02e18,  // 2% base rate
            0.1e18,   // 10% multiplier
            1.0e18,   // 100% jump multiplier
            0.8e18    // 80% kink
        );

        // 렌딩 풀 배포 / Deploy lending pool
        pool = new LendingPool(address(oracle), address(rateModel));

        // 토큰 생성 / Create tokens
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // 오라클 설정 / Setup oracle feeds
        oracle.setPriceFeed(address(weth), address(ethFeed));
        oracle.setPriceFeed(address(usdc), address(usdcFeed));

        // 시장 추가 / Add markets
        pool.addMarket(address(weth), 0.75e18, 0.80e18);  // 75% CF, 80% LT
        pool.addMarket(address(usdc), 0.80e18, 0.85e18);  // 80% CF, 85% LT

        // 풀에 초기 유동성 공급 / Provide initial liquidity
        usdc.mint(address(this), 1_000_000e6);
        usdc.approve(address(pool), type(uint256).max);
        pool.deposit(address(usdc), 1_000_000e6);

        // 핸들러 설정 / Setup handler
        handler = new LendingPoolHandler(pool, weth, usdc);
        targetContract(address(handler));
    }

    /// @notice 불변성: 총 예치금은 항상 총 대출금 이상이어야 함
    /// @notice Invariant: total deposits must always >= total borrows
    function invariant_totalDepositsGteTotalBorrows() public view {
        (,,,,uint256 wethDeposits, uint256 wethBorrows,,,,) = pool.markets(address(weth));
        (,,,,uint256 usdcDeposits, uint256 usdcBorrows,,,,) = pool.markets(address(usdc));

        assertGe(
            wethDeposits,
            wethBorrows,
            "WETH: deposits must be >= borrows"
        );
        assertGe(
            usdcDeposits,
            usdcBorrows,
            "USDC: deposits must be >= borrows"
        );
    }

    /// @notice 불변성: 대출 인덱스는 항상 1.0(1e18) 이상이어야 함
    /// @notice Invariant: borrow index must always be >= 1.0 (1e18)
    function invariant_borrowIndexGteOne() public view {
        (,,,,,,,uint256 wethIndex,,) = pool.markets(address(weth));
        (,,,,,,,uint256 usdcIndex,,) = pool.markets(address(usdc));

        assertGe(wethIndex, 1e18, "WETH borrow index must be >= 1e18");
        assertGe(usdcIndex, 1e18, "USDC borrow index must be >= 1e18");
    }
}
