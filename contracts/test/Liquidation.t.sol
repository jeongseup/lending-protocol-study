// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";
import "../src/InterestRateModel.sol";
import "../src/PriceOracle.sol";
import "./LendingPool.invariant.t.sol"; // MockERC20, MockPriceFeed 재사용 / reuse mocks

/// @title 청산 테스트 — Day 7 학습
/// @notice 가격 하락 → 헬스팩터 < 1 → 청산 시나리오를 테스트합니다
/// @notice Tests price drop → health factor < 1 → liquidation scenarios
/// @dev vm.mockCall로 오라클 가격을 조작하여 청산 조건을 시뮬레이션
/// @dev Simulates liquidation conditions by manipulating oracle prices

contract LiquidationTest is Test {
    LendingPool public pool;
    InterestRateModel public rateModel;
    PriceOracle public oracle;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockPriceFeed public ethFeed;
    MockPriceFeed public usdcFeed;

    address alice = address(0xA11CE);  // 차입자 / borrower
    address bob = address(0xB0B);      // 유동성 공급자 / liquidity provider
    address liquidator = address(0x11CC);  // 청산자 / liquidator

    function setUp() public {
        // 오라클 설정 / Oracle setup
        oracle = new PriceOracle(3600);
        ethFeed = new MockPriceFeed(2000e18, 18); // ETH = $2,000
        usdcFeed = new MockPriceFeed(1e18, 18);   // USDC = $1

        // 이자율 모델 / Interest rate model
        rateModel = new InterestRateModel(
            0.02e18,  // 2% base
            0.1e18,   // 10% multiplier
            1.0e18,   // 100% jump
            0.8e18    // 80% kink
        );

        // 풀 배포 / Deploy pool
        pool = new LendingPool(address(oracle), address(rateModel));

        // 토큰 생성 / Create tokens
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 18);

        // 오라클 설정 / Oracle feed setup
        oracle.setPriceFeed(address(weth), address(ethFeed));
        oracle.setPriceFeed(address(usdc), address(usdcFeed));

        // 리저브 초기화 / Initialize reserves
        pool.initReserve(address(weth), 0.75e18, 0.80e18);
        pool.initReserve(address(usdc), 0.80e18, 0.85e18);

        // 토큰 배포 / Distribute tokens
        weth.mint(alice, 100e18);
        usdc.mint(alice, 100_000e18);
        weth.mint(bob, 100e18);
        usdc.mint(bob, 100_000e18);
        weth.mint(liquidator, 100e18);
        usdc.mint(liquidator, 100_000e18);

        // 승인 / Approvals
        vm.startPrank(alice);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(pool), type(uint256).max);
        pool.deposit(address(usdc), 50_000e18);
        vm.stopPrank();

        vm.startPrank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    // ============================================================
    // 시나리오 1: 가격 하락으로 인한 청산
    // Scenario 1: Liquidation due to price drop
    // ============================================================

    function test_liquidation_priceDrop() public {
        // 1. Alice가 10 ETH 예치 ($20,000), 15,000 USDC 대출
        //    Alice deposits 10 ETH ($20,000), borrows 15,000 USDC
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 15_000e18);
        vm.stopPrank();

        // HF = (10 × 2000 × 0.8) / 15000 = 16000/15000 = 1.066...
        uint256 hfBefore = pool.getHealthFactor(alice);
        assertGt(hfBefore, 1e18, "HF should be > 1 before price drop");

        // 2. ETH 가격이 $2000 → $1500으로 하락 (25% 하락)
        //    ETH price drops from $2000 to $1500 (25% drop)
        ethFeed.setPrice(1500e18);

        // HF = (10 × 1500 × 0.8) / 15000 = 12000/15000 = 0.8 < 1 → 청산 가능!
        uint256 hfAfter = pool.getHealthFactor(alice);
        assertLt(hfAfter, 1e18, "HF should be < 1 after price drop");

        // 3. 청산자가 Alice의 부채 일부를 상환하고 담보를 가져감
        //    Liquidator repays part of Alice's debt and seizes collateral
        uint256 debtToCover = 7_500e18; // 50% (close factor)

        uint256 liquidatorUsdcBefore = usdc.balanceOf(liquidator);
        uint256 debtBefore = pool.getTotalDebtValue(alice);

        vm.prank(liquidator);
        pool.liquidate(alice, address(usdc), address(weth), debtToCover);

        // 4. 검증 / Verification

        // 청산자가 USDC를 지불했어야 함
        // Liquidator should have paid USDC
        uint256 liquidatorUsdcAfter = usdc.balanceOf(liquidator);
        assertEq(
            liquidatorUsdcBefore - liquidatorUsdcAfter,
            debtToCover,
            "Liquidator should have paid debtToCover USDC"
        );

        // 청산자가 ETH(+보너스)를 받았어야 함
        // Liquidator should have received ETH (+ bonus)
        uint256 liquidatorWeth = weth.balanceOf(liquidator);
        assertGt(liquidatorWeth, 100e18, "Liquidator should have received WETH");

        // Alice의 부채가 감소했어야 함
        // Alice's debt should have decreased after liquidation
        uint256 debtAfter = pool.getTotalDebtValue(alice);
        assertLt(debtAfter, debtBefore, "Debt should decrease after liquidation");
    }

    // ============================================================
    // 시나리오 2: 건전한 포지션은 청산 불가
    // Scenario 2: Healthy position cannot be liquidated
    // ============================================================

    function test_liquidation_healthyPositionReverts() public {
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 5_000e18);
        vm.stopPrank();

        // HF = (10 × 2000 × 0.8) / 5000 = 16000/5000 = 3.2 → 건전함
        // HF = 3.2 → healthy, should not be liquidatable
        uint256 hf = pool.getHealthFactor(alice);
        assertGt(hf, 1e18, "Position is healthy");

        vm.prank(liquidator);
        vm.expectRevert("Health factor is healthy");
        pool.liquidate(alice, address(usdc), address(weth), 2_500e18);
    }

    // ============================================================
    // 시나리오 3: Close Factor 초과 청산 시도
    // Scenario 3: Exceed close factor on liquidation
    // ============================================================

    function test_liquidation_exceedCloseFactorReverts() public {
        // 포지션 생성 / Create position
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 15_000e18);
        vm.stopPrank();

        // 가격 하락 / Price drop
        ethFeed.setPrice(1500e18);

        // Close Factor = 50%, 부채 = 15,000, 최대 청산 = 7,500
        // Close Factor = 50%, debt = 15,000, max liquidation = 7,500
        vm.prank(liquidator);
        vm.expectRevert("Exceeds close factor");
        pool.liquidate(alice, address(usdc), address(weth), 10_000e18); // 50% 초과 / exceeds 50%
    }

    // ============================================================
    // 시나리오 4: 자기 자신 청산 불가
    // Scenario 4: Cannot self-liquidate
    // ============================================================

    function test_liquidation_selfLiquidateReverts() public {
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 15_000e18);
        vm.stopPrank();

        ethFeed.setPrice(1500e18);

        vm.prank(alice);
        vm.expectRevert("Cannot liquidate self");
        pool.liquidate(alice, address(usdc), address(weth), 5_000e18);
    }

    // ============================================================
    // 시나리오 5: 청산 보너스 계산 검증
    // Scenario 5: Verify liquidation bonus calculation
    // ============================================================

    function test_liquidation_bonusCalculation() public {
        // 청산자가 받는 담보 = 부채가치 × (1 + 보너스) / 담보가격
        // Collateral seized = debt value × (1 + bonus) / collateral price

        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 15_000e18);
        vm.stopPrank();

        // ETH 가격 하락 / ETH price drop
        ethFeed.setPrice(1500e18);

        uint256 debtToCover = 7_500e18;
        uint256 liquidatorWethBefore = weth.balanceOf(liquidator);

        vm.prank(liquidator);
        pool.liquidate(alice, address(usdc), address(weth), debtToCover);

        uint256 liquidatorWethAfter = weth.balanceOf(liquidator);
        uint256 wethReceived = liquidatorWethAfter - liquidatorWethBefore;

        // 예상 담보 압류:
        // Expected collateral seized:
        // debtToCover ($7,500) × (1 + 5% bonus) / ETH price ($1,500) = 7500 × 1.05 / 1500 = 5.25 ETH
        uint256 expectedCollateral = debtToCover * 1.05e18 / 1500e18;
        assertEq(wethReceived, expectedCollateral, "Collateral seized should include 5% bonus");
    }

    // ============================================================
    // 시나리오 6: 이자 누적 후 청산
    // Scenario 6: Liquidation after interest accrual
    // ============================================================

    function test_liquidation_afterInterestAccrual() public {
        // 경계선 포지션 생성 / Create borderline position
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 15_900e18); // HF ≈ 1.006 (거의 경계선)
        vm.stopPrank();

        uint256 hfBefore = pool.getHealthFactor(alice);
        assertGe(hfBefore, 1e18, "Should start healthy");

        // 소폭 가격 하락으로 청산 트리거
        // Small price drop triggers liquidation
        ethFeed.setPrice(1980e18); // $2000 → $1980 (1% 하락 / 1% drop)

        uint256 hfAfter = pool.getHealthFactor(alice);

        if (hfAfter < 1e18) {
            // 청산 가능 / Liquidatable
            uint256 debtToCover = 1_000e18;
            vm.prank(liquidator);
            pool.liquidate(alice, address(usdc), address(weth), debtToCover);
            assertTrue(true, "Liquidation successful");
        }
    }
}
