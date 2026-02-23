// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";
import "../src/InterestRateModel.sol";
import "../src/PriceOracle.sol";
import "./LendingPool.invariant.t.sol"; // MockERC20, MockPriceFeed 재사용 / reuse mocks

/// @title LendingPool 전체 흐름 테스트 — Day 7 학습
/// @notice 예치 → 대출 → 이자 누적 → 상환 → 청산 전체 흐름을 테스트합니다
/// @notice Tests complete flows: deposit → borrow → interest → repay → liquidation

contract LendingPoolTest is Test {
    // 이벤트 재선언 (expectEmit 사용을 위해) / Re-declare events for expectEmit
    event Deposit(address indexed user, address indexed asset, uint256 amount);

    LendingPool public pool;
    InterestRateModel public rateModel;
    PriceOracle public oracle;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockPriceFeed public ethFeed;
    MockPriceFeed public usdcFeed;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address liquidator = address(0x11CC);

    function setUp() public {
        // 오라클 설정 / Oracle setup
        oracle = new PriceOracle(3600);
        ethFeed = new MockPriceFeed(2000e18, 18); // ETH = $2000
        usdcFeed = new MockPriceFeed(1e18, 18);   // USDC = $1

        // 이자율 모델 / Interest rate model
        rateModel = new InterestRateModel(
            0.02e18,  // 2% base rate
            0.1e18,   // 10% multiplier
            1.0e18,   // 100% jump multiplier
            0.8e18    // 80% kink
        );

        // 렌딩 풀 / Lending pool
        pool = new LendingPool(address(oracle), address(rateModel));

        // 토큰 생성 / Create tokens
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 18); // 테스트 편의상 18 decimals

        // 오라클 피드 설정 / Set oracle feeds
        oracle.setPriceFeed(address(weth), address(ethFeed));
        oracle.setPriceFeed(address(usdc), address(usdcFeed));

        // 시장 추가 / Add markets
        // ETH: 75% 담보 인정, 80% 청산 기준
        // ETH: 75% collateral factor, 80% liquidation threshold
        pool.addMarket(address(weth), 0.75e18, 0.80e18);
        // USDC: 80% 담보 인정, 85% 청산 기준
        // USDC: 80% collateral factor, 85% liquidation threshold
        pool.addMarket(address(usdc), 0.80e18, 0.85e18);

        // 토큰 배포 / Distribute tokens
        weth.mint(alice, 100e18);
        usdc.mint(alice, 100_000e18);
        weth.mint(bob, 100e18);
        usdc.mint(bob, 100_000e18);
        weth.mint(liquidator, 100e18);
        usdc.mint(liquidator, 100_000e18);

        // 풀에 유동성 공급 (bob이 USDC를 예치)
        // Provide liquidity (bob deposits USDC)
        vm.startPrank(bob);
        usdc.approve(address(pool), type(uint256).max);
        pool.deposit(address(usdc), 50_000e18);
        vm.stopPrank();

        // Alice와 liquidator 승인 / Alice and liquidator approvals
        vm.startPrank(alice);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidator);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    // ============================================================
    // 예치 테스트 / Deposit Tests
    // ============================================================

    function test_deposit() public {
        // Alice가 10 ETH를 예치합니다
        // Alice deposits 10 ETH
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        vm.stopPrank();

        // LToken 잔액 확인 / Verify LToken balance
        (LToken lToken,,,,,,,,, ) = pool.markets(address(weth));
        assertEq(lToken.balanceOf(alice), 10e18, "Should have 10 lWETH");

        // 시장 상태 확인 / Verify market state
        (,,,,uint256 totalDeposits,,,,, ) = pool.markets(address(weth));
        assertEq(totalDeposits, 10e18, "Total deposits should be 10 ETH");
    }

    function test_deposit_emitsEvent() public {
        // 예치 시 이벤트가 발생해야 함
        // Deposit should emit event
        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true);
        emit Deposit(alice, address(weth), 10e18);
        pool.deposit(address(weth), 10e18);
        vm.stopPrank();
    }

    function test_deposit_zeroAmountReverts() public {
        vm.startPrank(alice);
        vm.expectRevert("Amount must be > 0");
        pool.deposit(address(weth), 0);
        vm.stopPrank();
    }

    // ============================================================
    // 대출 테스트 / Borrow Tests
    // ============================================================

    function test_borrow() public {
        // 1. Alice가 10 ETH 예치 ($20,000 가치)
        // 1. Alice deposits 10 ETH ($20,000 value)
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);

        // 2. Alice가 $12,000 USDC 대출 (LTV = 60%, 한도 75% 이내)
        // 2. Alice borrows $12,000 USDC (LTV = 60%, within 75% limit)
        pool.borrow(address(usdc), 12_000e18);
        vm.stopPrank();

        // USDC 잔액 확인 / Verify USDC balance
        assertEq(usdc.balanceOf(alice), 100_000e18 + 12_000e18, "Should have received USDC");

        // 헬스팩터 확인 (1.0 이상이어야 함)
        // Verify health factor (must be >= 1.0)
        uint256 hf = pool.getHealthFactor(alice);
        assertGe(hf, 1e18, "Health factor must be >= 1.0");
    }

    function test_borrow_insufficientCollateralReverts() public {
        // 담보 없이 대출 시도 → 실패해야 함
        // Attempt to borrow without collateral → should fail
        vm.startPrank(alice);
        vm.expectRevert();
        pool.borrow(address(usdc), 1000e18);
        vm.stopPrank();
    }

    function test_borrow_exceedingCollateralReverts() public {
        // 담보 한도를 초과하는 대출 시도 → 실패해야 함
        // Attempt to borrow beyond collateral limit → should fail
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);

        // 10 ETH × $2000 × 80% LT = $16,000 한도
        // 10 ETH × $2000 × 80% LT = $16,000 limit
        vm.expectRevert("Insufficient collateral");
        pool.borrow(address(usdc), 20_000e18);
        vm.stopPrank();
    }

    // ============================================================
    // 상환 테스트 / Repay Tests
    // ============================================================

    function test_repay() public {
        // 예치 → 대출 → 상환
        // Deposit → Borrow → Repay
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 5_000e18);

        // 전액 상환 / Full repayment
        pool.repay(address(usdc), 5_000e18);
        vm.stopPrank();

        // 부채 토큰 잔액 0 확인 / Verify debt token balance is 0
        (, DebtToken debtToken,,,,,,,,) = pool.markets(address(usdc));
        assertEq(debtToken.balanceOf(alice), 0, "Debt should be fully repaid");
    }

    function test_repay_partial() public {
        // 부분 상환 / Partial repayment
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 5_000e18);

        // 절반만 상환 / Repay half
        pool.repay(address(usdc), 2_500e18);
        vm.stopPrank();

        (, DebtToken debtToken,,,,,,,,) = pool.markets(address(usdc));
        assertEq(debtToken.balanceOf(alice), 2_500e18, "Half debt should remain");
    }

    // ============================================================
    // 출금 테스트 / Withdraw Tests
    // ============================================================

    function test_withdraw() public {
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);

        // 출금 / Withdraw
        pool.withdraw(address(weth), 10e18);
        vm.stopPrank();

        (LToken lToken,,,,,,,,, ) = pool.markets(address(weth));
        assertEq(lToken.balanceOf(alice), 0, "LToken balance should be 0");
        assertEq(weth.balanceOf(alice), 100e18, "Should have original WETH back");
    }

    function test_withdraw_wouldUndercollateralizeReverts() public {
        // 대출이 있는 상태에서 전액 출금 시도 → 실패
        // Attempt full withdrawal with outstanding debt → should fail
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 5_000e18);

        vm.expectRevert("Withdrawal would cause undercollateralization");
        pool.withdraw(address(weth), 10e18);
        vm.stopPrank();
    }

    // ============================================================
    // 이자 누적 테스트 / Interest Accrual Tests
    // ============================================================

    function test_interestAccrual() public {
        // 예치 → 대출 → 시간 경과 → 이자 누적 확인
        // Deposit → Borrow → Time passes → Verify interest accrual
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 5_000e18);
        vm.stopPrank();

        // 1년 경과 / 1 year passes
        vm.warp(block.timestamp + 365 days);

        // 상환 시 이자가 반영됨 / Interest reflected on repay
        (,,,,, uint256 totalBorrowsBefore,,,,) = pool.markets(address(usdc));

        // 상호작용을 통해 이자 갱신 트리거
        // Trigger interest update through interaction
        vm.startPrank(alice);
        pool.repay(address(usdc), 1); // 최소 상환으로 이자 갱신 / Minimal repay to trigger interest
        vm.stopPrank();

        (,,,,, uint256 totalBorrowsAfter,,,,) = pool.markets(address(usdc));

        // 총 대출금이 증가했어야 함 (이자 누적)
        // Total borrows should have increased (interest accrued)
        assertGt(totalBorrowsAfter, totalBorrowsBefore - 1, "Interest should have accrued");
    }

    // ============================================================
    // 전체 수명주기 테스트 / Full Lifecycle Test
    // ============================================================

    function test_fullLifecycle_depositBorrowRepayWithdraw() public {
        // 전체 흐름: 예치 → 대출 → 시간 경과 → 상환 → 출금
        // Full flow: Deposit → Borrow → Time passes → Repay → Withdraw

        // 1. Alice가 10 ETH 예치
        // 1. Alice deposits 10 ETH
        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);

        // 2. Alice가 5,000 USDC 대출
        // 2. Alice borrows 5,000 USDC
        pool.borrow(address(usdc), 5_000e18);

        // 3. 30일 경과
        // 3. 30 days pass
        vm.warp(block.timestamp + 30 days);

        // 4. Alice가 USDC 전액 상환 (이자 포함 여유분)
        // 4. Alice repays all USDC (with extra for interest)
        pool.repay(address(usdc), 6_000e18); // 여유롭게 / with buffer

        // 5. Alice가 ETH 출금
        // 5. Alice withdraws ETH
        pool.withdraw(address(weth), 10e18);
        vm.stopPrank();

        // 최종 확인 / Final verification
        (LToken lToken,,,,,,,,, ) = pool.markets(address(weth));
        assertEq(lToken.balanceOf(alice), 0, "No lTokens remaining");

        uint256 hf = pool.getHealthFactor(alice);
        assertEq(hf, type(uint256).max, "HF should be max (no debt)");
    }

    // ============================================================
    // 헬스팩터 테스트 / Health Factor Tests
    // ============================================================

    function test_healthFactor_noDebt() public view {
        // 부채 없으면 헬스팩터 = 무한대 (type(uint256).max)
        // No debt = infinite health factor
        uint256 hf = pool.getHealthFactor(alice);
        assertEq(hf, type(uint256).max);
    }

    function test_healthFactor_calculation() public {
        // 헬스팩터 계산 검증
        // Health factor calculation verification
        // 10 ETH × $2000 × 80% LT = $16,000 담보 / adjusted collateral
        // 10,000 USDC × $1 = $10,000 부채 / debt
        // HF = 16,000 / 10,000 = 1.6

        vm.startPrank(alice);
        pool.deposit(address(weth), 10e18);
        pool.borrow(address(usdc), 10_000e18);
        vm.stopPrank();

        uint256 hf = pool.getHealthFactor(alice);
        assertEq(hf, 1.6e18, "Health factor should be 1.6");
    }
}
