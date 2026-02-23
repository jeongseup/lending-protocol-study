// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./LToken.sol";
import "./DebtToken.sol";
import "./InterestRateModel.sol";
import "./PriceOracle.sol";

/// @title LendingPool — 미니 렌딩 프로토콜 핵심 컨트랙트
/// @notice 예치, 대출, 상환, 청산의 핵심 로직을 구현합니다
/// @notice Implements core logic for deposit, borrow, repay, and liquidation
/// @dev Day 7 통합 프로젝트: 1주일 학습의 모든 개념을 통합
/// @dev Day 7 integration: Combines all concepts from the week's learning

contract LendingPool {
    using SafeERC20 for IERC20;

    // ============================================================
    // 상수 / Constants
    // ============================================================

    uint256 public constant PRECISION = 1e18;

    /// @notice 청산 보너스 (5%) — 청산자에게 주는 인센티브
    /// @notice Liquidation bonus (5%) — incentive for liquidators
    uint256 public constant LIQUIDATION_BONUS = 0.05e18;

    /// @notice 청산 시 최대 상환 비율 (50%) — Close Factor
    /// @notice Max repayable ratio per liquidation (50%) — Close Factor
    uint256 public constant CLOSE_FACTOR = 0.5e18;

    /// @notice 프로토콜 준비금 비율 (10%)
    /// @notice Protocol reserve factor (10%)
    uint256 public constant RESERVE_FACTOR = 0.1e18;

    // ============================================================
    // 상태 변수 / State Variables
    // ============================================================

    /// @notice 프로토콜 관리자 / Protocol admin
    address public owner;

    /// @notice 가격 오라클 / Price oracle
    PriceOracle public oracle;

    /// @notice 이자율 모델 / Interest rate model
    InterestRateModel public interestRateModel;

    /// @notice 자산별 시장 설정 / Per-asset market configuration
    struct Market {
        LToken lToken;           // 예치 영수증 토큰 / Deposit receipt token
        DebtToken debtToken;     // 부채 추적 토큰 / Debt tracking token
        uint256 collateralFactor; // 담보 인정 비율 (e.g., 0.75e18 = 75%) / Collateral factor
        uint256 liquidationThreshold; // 청산 기준 (e.g., 0.8e18 = 80%) / Liquidation threshold
        uint256 totalDeposits;   // 총 예치금 / Total deposits
        uint256 totalBorrows;    // 총 대출금 / Total borrows
        uint256 totalReserves;   // 총 준비금 / Total reserves
        uint256 borrowIndex;     // 누적 이자 인덱스 / Cumulative interest index
        uint256 lastUpdateTime;  // 마지막 이자 갱신 시간 / Last interest update time
        bool isActive;           // 시장 활성화 여부 / Market active flag
    }

    /// @notice 자산 주소 → 시장 정보 / Asset address → Market info
    mapping(address => Market) public markets;

    /// @notice 등록된 자산 목록 / List of registered assets
    address[] public assetList;

    /// @notice 사용자별 대출 인덱스 / Per-user borrow index snapshot
    mapping(address => mapping(address => uint256)) public userBorrowIndex;

    // ============================================================
    // 이벤트 / Events
    // ============================================================

    /// @notice 예치 이벤트 / Deposit event
    event Deposit(address indexed user, address indexed asset, uint256 amount);

    /// @notice 출금 이벤트 / Withdraw event
    event Withdraw(address indexed user, address indexed asset, uint256 amount);

    /// @notice 대출 이벤트 / Borrow event
    event Borrow(address indexed user, address indexed asset, uint256 amount);

    /// @notice 상환 이벤트 / Repay event
    event Repay(address indexed user, address indexed asset, uint256 amount);

    /// @notice 청산 이벤트 / Liquidation event
    event LiquidationCall(
        address indexed liquidator,
        address indexed borrower,
        address indexed debtAsset,
        address collateralAsset,
        uint256 debtCovered,
        uint256 collateralSeized
    );

    /// @notice 이자 갱신 이벤트 / Interest accrual event
    event InterestAccrued(address indexed asset, uint256 interestAccumulated, uint256 newBorrowIndex);

    /// @notice 시장 추가 이벤트 / Market added event
    event MarketAdded(address indexed asset, address lToken, address debtToken);

    // ============================================================
    // 수정자 / Modifiers
    // ============================================================

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier marketExists(address asset) {
        require(markets[asset].isActive, "Market not active");
        _;
    }

    // ============================================================
    // 생성자 / Constructor
    // ============================================================

    constructor(address _oracle, address _interestRateModel) {
        owner = msg.sender;
        oracle = PriceOracle(_oracle);
        interestRateModel = InterestRateModel(_interestRateModel);
    }

    // ============================================================
    // 관리자 함수 / Admin Functions
    // ============================================================

    /// @notice 새로운 자산 시장을 추가합니다
    /// @notice Add a new asset market
    /// @param asset 자산 주소 / Asset address
    /// @param collateralFactor 담보 인정 비율 / Collateral factor (1e18 scale)
    /// @param liquidationThreshold 청산 기준 / Liquidation threshold (1e18 scale)
    function addMarket(
        address asset,
        uint256 collateralFactor,
        uint256 liquidationThreshold
    ) external onlyOwner {
        require(!markets[asset].isActive, "Market already exists");
        require(collateralFactor <= PRECISION, "CF too high");
        require(liquidationThreshold <= PRECISION, "LT too high");
        require(collateralFactor <= liquidationThreshold, "CF must be <= LT");

        string memory name = string.concat("Lending ", ERC20(asset).name());
        string memory symbol = string.concat("l", ERC20(asset).symbol());
        uint8 assetDecimals = ERC20(asset).decimals();

        LToken lToken = new LToken(name, symbol, asset, assetDecimals);

        string memory debtName = string.concat("Debt ", ERC20(asset).name());
        string memory debtSymbol = string.concat("d", ERC20(asset).symbol());
        DebtToken debtToken = new DebtToken(debtName, debtSymbol, asset, assetDecimals);

        markets[asset] = Market({
            lToken: lToken,
            debtToken: debtToken,
            collateralFactor: collateralFactor,
            liquidationThreshold: liquidationThreshold,
            totalDeposits: 0,
            totalBorrows: 0,
            totalReserves: 0,
            borrowIndex: PRECISION, // 초기 인덱스 1.0 / Initial index 1.0
            lastUpdateTime: block.timestamp,
            isActive: true
        });

        assetList.push(asset);
        emit MarketAdded(asset, address(lToken), address(debtToken));
    }

    // ============================================================
    // 핵심 함수 / Core Functions
    // ============================================================

    /// @notice 자산을 예치합니다 → LToken을 받습니다
    /// @notice Deposit asset → Receive LToken
    /// @dev 예치 흐름: 사용자가 ERC20을 풀에 전송 → LToken 민팅
    /// @dev Deposit flow: User transfers ERC20 to pool → LToken minted
    function deposit(address asset, uint256 amount)
        external
        marketExists(asset)
    {
        require(amount > 0, "Amount must be > 0");

        // 이자 갱신 / Accrue interest
        _accrueInterest(asset);

        Market storage market = markets[asset];

        // 자산을 풀로 전송 / Transfer asset to pool
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // LToken 민팅 (1:1 비율, 단순화)
        // Mint LToken (1:1 ratio, simplified)
        // 실제 프로토콜에서는 환율을 적용합니다
        // In real protocols, exchange rate is applied
        uint256 mintAmount = _toMintAmount(asset, amount);
        market.lToken.mint(msg.sender, mintAmount);
        market.totalDeposits += amount;

        emit Deposit(msg.sender, asset, amount);
    }

    /// @notice 예치금을 출금합니다 → LToken을 소각합니다
    /// @notice Withdraw deposits → Burn LToken
    function withdraw(address asset, uint256 amount)
        external
        marketExists(asset)
    {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(asset);

        Market storage market = markets[asset];

        uint256 burnAmount = _toMintAmount(asset, amount);
        require(
            market.lToken.balanceOf(msg.sender) >= burnAmount,
            "Insufficient lToken balance"
        );

        // 출금 후 헬스팩터 확인 / Check health factor after withdrawal
        market.lToken.burn(msg.sender, burnAmount);
        market.totalDeposits -= amount;

        // 출금 후에도 건전성 유지 확인
        // Verify health factor remains healthy after withdrawal
        require(
            _getHealthFactor(msg.sender) >= PRECISION || _getTotalDebt(msg.sender) == 0,
            "Withdrawal would cause undercollateralization"
        );

        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, asset, amount);
    }

    /// @notice 담보를 기반으로 자산을 대출합니다
    /// @notice Borrow asset against collateral
    /// @dev 대출 흐름: 담보 가치 확인 → 대출 한도 계산 → DebtToken 민팅 → 자산 전송
    /// @dev Borrow flow: Check collateral → Calculate limit → Mint DebtToken → Transfer asset
    function borrow(address asset, uint256 amount)
        external
        marketExists(asset)
    {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(asset);

        Market storage market = markets[asset];
        require(market.totalDeposits - market.totalBorrows >= amount, "Insufficient liquidity");

        // DebtToken 민팅 / Mint debt token
        market.debtToken.mint(msg.sender, amount);
        market.totalBorrows += amount;

        // 사용자 대출 인덱스 스냅샷 저장
        // Save user's borrow index snapshot
        userBorrowIndex[msg.sender][asset] = market.borrowIndex;

        // 헬스팩터 확인 — 대출 후에도 건전해야 함
        // Check health factor — must remain healthy after borrow
        require(
            _getHealthFactor(msg.sender) >= PRECISION,
            "Insufficient collateral"
        );

        // 자산 전송 / Transfer asset to borrower
        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Borrow(msg.sender, asset, amount);
    }

    /// @notice 대출금을 상환합니다
    /// @notice Repay borrowed amount
    function repay(address asset, uint256 amount)
        external
        marketExists(asset)
    {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(asset);

        Market storage market = markets[asset];
        uint256 debt = market.debtToken.balanceOf(msg.sender);
        require(debt > 0, "No debt to repay");

        // 상환액이 부채보다 크면 부채만큼만 상환
        // If repay amount exceeds debt, only repay debt amount
        uint256 repayAmount = amount > debt ? debt : amount;

        // 자산을 풀로 전송 / Transfer asset back to pool
        IERC20(asset).safeTransferFrom(msg.sender, address(this), repayAmount);

        // DebtToken 소각 / Burn debt token
        market.debtToken.burn(msg.sender, repayAmount);
        market.totalBorrows -= repayAmount;

        emit Repay(msg.sender, asset, repayAmount);
    }

    /// @notice 청산 — 부채를 대신 상환하고 담보를 할인받아 가져갑니다
    /// @notice Liquidation — Repay debt on behalf, seize discounted collateral
    /// @dev 청산 흐름:
    /// @dev 1. 대상자의 HF < 1 확인
    /// @dev 2. 청산자가 부채 자산을 상환 (최대 50% = Close Factor)
    /// @dev 3. 청산자가 담보 자산을 보너스 포함하여 수령
    /// @dev Liquidation flow:
    /// @dev 1. Verify borrower's HF < 1
    /// @dev 2. Liquidator repays debt asset (max 50% = Close Factor)
    /// @dev 3. Liquidator receives collateral asset with bonus
    function liquidate(
        address borrower,
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover
    ) external marketExists(debtAsset) marketExists(collateralAsset) {
        require(borrower != msg.sender, "Cannot liquidate self");

        _accrueInterest(debtAsset);
        _accrueInterest(collateralAsset);

        // 1. 헬스팩터 확인 — 1 미만이어야 청산 가능
        // 1. Check health factor — must be < 1 for liquidation
        uint256 healthFactor = _getHealthFactor(borrower);
        require(healthFactor < PRECISION, "Health factor is healthy");

        // 2. Close Factor 적용 — 한 번에 최대 50%만 청산 가능
        // 2. Apply close factor — max 50% liquidatable per call
        Market storage debtMarket = markets[debtAsset];
        uint256 userDebt = debtMarket.debtToken.balanceOf(borrower);
        uint256 maxLiquidatable = userDebt * CLOSE_FACTOR / PRECISION;
        require(debtToCover <= maxLiquidatable, "Exceeds close factor");

        // 3. 담보 압류량 계산 (보너스 포함)
        // 3. Calculate collateral to seize (including bonus)
        uint256 debtPrice = oracle.getAssetPrice(debtAsset);
        uint256 collateralPrice = oracle.getAssetPrice(collateralAsset);

        // 압류 담보 = (부채 가치 × (1 + 보너스)) / 담보 가격
        // Collateral seized = (debt value × (1 + bonus)) / collateral price
        uint256 collateralToSeize = debtToCover
            * debtPrice
            * (PRECISION + LIQUIDATION_BONUS)
            / (collateralPrice * PRECISION);

        // 4. 청산자가 부채 상환 / Liquidator repays debt
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), debtToCover);
        debtMarket.debtToken.burn(borrower, debtToCover);
        debtMarket.totalBorrows -= debtToCover;

        // 5. 담보 LToken을 청산자에게 전송
        // 5. Transfer collateral LToken to liquidator
        Market storage collateralMarket = markets[collateralAsset];
        uint256 lTokenAmount = _toMintAmount(collateralAsset, collateralToSeize);
        require(
            collateralMarket.lToken.balanceOf(borrower) >= lTokenAmount,
            "Insufficient collateral"
        );

        // LToken을 대출자에서 소각하고 청산자에게 민팅
        // Burn LToken from borrower and mint to liquidator
        collateralMarket.lToken.burn(borrower, lTokenAmount);
        collateralMarket.totalDeposits -= collateralToSeize;

        // 청산자에게 담보 직접 전송
        // Transfer collateral directly to liquidator
        IERC20(collateralAsset).safeTransfer(msg.sender, collateralToSeize);

        emit LiquidationCall(
            msg.sender,
            borrower,
            debtAsset,
            collateralAsset,
            debtToCover,
            collateralToSeize
        );
    }

    // ============================================================
    // 조회 함수 / View Functions
    // ============================================================

    /// @notice 사용자의 헬스팩터를 조회합니다
    /// @notice Get user's health factor
    /// @dev HF = Σ(담보 × 가격 × 청산기준) / Σ(부채 × 가격)
    /// @dev HF = Σ(collateral × price × liquidationThreshold) / Σ(debt × price)
    /// @return healthFactor 헬스팩터 (1e18 스케일, < 1e18이면 청산 가능) / Health factor (1e18 scale, < 1e18 = liquidatable)
    function getHealthFactor(address user) external view returns (uint256 healthFactor) {
        return _getHealthFactor(user);
    }

    /// @notice 사용자의 총 담보 가치 (USD)
    /// @notice User's total collateral value in USD
    function getTotalCollateralValue(address user) external view returns (uint256) {
        return _getTotalCollateral(user);
    }

    /// @notice 사용자의 총 부채 가치 (USD)
    /// @notice User's total debt value in USD
    function getTotalDebtValue(address user) external view returns (uint256) {
        return _getTotalDebt(user);
    }

    /// @notice 자산의 현재 사용률
    /// @notice Current utilization rate of an asset
    function getUtilizationRate(address asset) external view returns (uint256) {
        Market storage market = markets[asset];
        return interestRateModel.getUtilization(market.totalDeposits, market.totalBorrows);
    }

    /// @notice 등록된 자산 수 / Number of registered assets
    function getAssetCount() external view returns (uint256) {
        return assetList.length;
    }

    // ============================================================
    // 내부 함수 / Internal Functions
    // ============================================================

    /// @dev 이자를 갱신합니다 (시간 경과에 따른 이자 누적)
    /// @dev Accrue interest (accumulate interest over time)
    /// @dev 스테이킹의 에포크 보상 계산과 유사한 개념
    /// @dev Similar concept to staking epoch reward calculation
    function _accrueInterest(address asset) internal {
        Market storage market = markets[asset];

        uint256 timeElapsed = block.timestamp - market.lastUpdateTime;
        if (timeElapsed == 0) return;

        if (market.totalBorrows > 0) {
            // 초당 이자율 계산 / Calculate per-second rate
            uint256 borrowRatePerSecond = interestRateModel.getBorrowRatePerSecond(
                market.totalDeposits,
                market.totalBorrows
            );

            // 누적 이자 계산 / Calculate accumulated interest
            uint256 interestAccumulated = market.totalBorrows
                * borrowRatePerSecond
                * timeElapsed
                / PRECISION;

            // 준비금 적립 / Allocate to reserves
            uint256 reserveShare = interestAccumulated * RESERVE_FACTOR / PRECISION;
            market.totalReserves += reserveShare;

            // 총 대출금 증가 (이자 누적) / Increase total borrows (interest accrual)
            market.totalBorrows += interestAccumulated;
            market.totalDeposits += interestAccumulated - reserveShare;

            // 대출 인덱스 갱신 / Update borrow index
            market.borrowIndex += market.borrowIndex * borrowRatePerSecond * timeElapsed / PRECISION;

            emit InterestAccrued(asset, interestAccumulated, market.borrowIndex);
        }

        market.lastUpdateTime = block.timestamp;
    }

    /// @dev 헬스팩터 계산 / Calculate health factor
    function _getHealthFactor(address user) internal view returns (uint256) {
        uint256 totalDebt = _getTotalDebt(user);
        if (totalDebt == 0) return type(uint256).max; // 부채 없으면 무한대 / No debt = infinite

        uint256 totalCollateralAdjusted = _getTotalCollateralAdjusted(user);
        return totalCollateralAdjusted * PRECISION / totalDebt;
    }

    /// @dev 청산 기준이 적용된 총 담보 가치 / Total collateral value adjusted by liquidation threshold
    function _getTotalCollateralAdjusted(address user) internal view returns (uint256) {
        uint256 totalValue = 0;

        for (uint256 i = 0; i < assetList.length; i++) {
            address asset = assetList[i];
            Market storage market = markets[asset];

            uint256 lTokenBalance = market.lToken.balanceOf(user);
            if (lTokenBalance > 0) {
                uint256 underlyingAmount = _toUnderlyingAmount(asset, lTokenBalance);
                uint256 price = oracle.getAssetPrice(asset);
                uint256 value = underlyingAmount * price / PRECISION;
                totalValue += value * market.liquidationThreshold / PRECISION;
            }
        }

        return totalValue;
    }

    /// @dev 총 담보 가치 (조정 없음) / Total collateral value (unadjusted)
    function _getTotalCollateral(address user) internal view returns (uint256) {
        uint256 totalValue = 0;

        for (uint256 i = 0; i < assetList.length; i++) {
            address asset = assetList[i];
            Market storage market = markets[asset];

            uint256 lTokenBalance = market.lToken.balanceOf(user);
            if (lTokenBalance > 0) {
                uint256 underlyingAmount = _toUnderlyingAmount(asset, lTokenBalance);
                uint256 price = oracle.getAssetPrice(asset);
                totalValue += underlyingAmount * price / PRECISION;
            }
        }

        return totalValue;
    }

    /// @dev 총 부채 가치 / Total debt value
    function _getTotalDebt(address user) internal view returns (uint256) {
        uint256 totalValue = 0;

        for (uint256 i = 0; i < assetList.length; i++) {
            address asset = assetList[i];
            Market storage market = markets[asset];

            uint256 debtBalance = market.debtToken.balanceOf(user);
            if (debtBalance > 0) {
                uint256 price = oracle.getAssetPrice(asset);
                totalValue += debtBalance * price / PRECISION;
            }
        }

        return totalValue;
    }

    /// @dev 기초 자산 → LToken 민팅량 변환 (단순화: 1:1)
    /// @dev Underlying → LToken mint amount conversion (simplified: 1:1)
    /// @dev 실제 프로토콜에서는 환율을 적용합니다 (cToken 모델)
    /// @dev Real protocols apply exchange rate (cToken model)
    function _toMintAmount(address, uint256 amount) internal pure returns (uint256) {
        return amount;
    }

    /// @dev LToken → 기초 자산 환산량 변환 (단순화: 1:1)
    /// @dev LToken → Underlying amount conversion (simplified: 1:1)
    function _toUnderlyingAmount(address, uint256 lTokenAmount) internal pure returns (uint256) {
        return lTokenAmount;
    }
}
