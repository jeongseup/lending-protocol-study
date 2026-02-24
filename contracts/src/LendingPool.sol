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
/// @dev Aave V3 origin의 PoolStorage 패턴을 적용한 리팩토링 버전
/// @dev Refactored version applying Aave V3 origin's PoolStorage pattern

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
    // 구조체 / Structs (Aave V3 PoolStorage 스타일)
    // ============================================================

    /// @notice 사용자별 담보/대출 설정 비트맵 (Aave V3: UserConfigurationMap)
    /// @notice Per-user collateral/borrow configuration bitmap
    /// @dev 비트 쌍으로 구성: bit 2*reserveId = 담보 여부, bit 2*reserveId+1 = 대출 여부
    /// @dev Arranged in bit pairs: bit 2*reserveId = isCollateral, bit 2*reserveId+1 = isBorrowing
    struct UserConfigurationMap {
        uint256 data;
    }

    /// @notice 자산별 리저브 데이터 (Aave V3: ReserveData)
    /// @notice Per-asset reserve data (Aave V3: ReserveData)
    struct ReserveData {
        LToken lToken;                // 예치 영수증 토큰 / Deposit receipt token
        DebtToken debtToken;          // 부채 추적 토큰 / Debt tracking token
        uint256 collateralFactor;     // 담보 인정 비율 / Collateral factor
        uint256 liquidationThreshold; // 청산 기준 / Liquidation threshold
        uint256 totalDeposits;        // 총 예치금 / Total deposits
        uint256 totalBorrows;         // 총 대출금 / Total borrows
        uint256 totalReserves;        // 총 준비금 / Total reserves
        uint256 borrowIndex;          // 누적 이자 인덱스 / Cumulative interest index
        uint256 lastUpdateTime;       // 마지막 이자 갱신 시간 / Last interest update time
        uint16 id;                    // 리저브 ID (Aave V3 스타일) / Reserve ID
        bool isActive;                // 리저브 활성화 여부 / Reserve active flag
    }

    // ============================================================
    // 상태 변수 / State Variables (Aave V3 PoolStorage 패턴)
    // ============================================================

    /// @notice 프로토콜 관리자 / Protocol admin
    address public owner;

    /// @notice 가격 오라클 / Price oracle
    PriceOracle public oracle;

    /// @notice 이자율 모델 / Interest rate model
    InterestRateModel public interestRateModel;

    /// @notice 자산 주소 → 리저브 데이터 (Aave V3: mapping(address => DataTypes.ReserveData) _reserves)
    /// @notice Asset address → Reserve data
    mapping(address => ReserveData) public reserves;

    /// @notice 사용자별 담보/대출 설정 비트맵 (Aave V3: mapping(address => DataTypes.UserConfigurationMap) _usersConfig)
    /// @notice Per-user configuration bitmap tracking collateral & borrow positions
    mapping(address => UserConfigurationMap) internal _usersConfig;

    /// @notice 리저브 ID → 자산 주소 매핑 (Aave V3: mapping(uint256 => address) _reservesList)
    /// @notice Reserve ID → Asset address mapping
    /// @dev 배열 대신 매핑 사용 → 가스 절약 (Aave V3와 동일한 이유)
    /// @dev Mapping instead of array → gas savings (same reason as Aave V3)
    mapping(uint256 => address) public reservesList;

    /// @notice 활성 리저브 수 (Aave V3: uint16 _reservesCount)
    /// @notice Number of active reserves, upper bound of reservesList
    uint16 public reservesCount;

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

    /// @notice 리저브 초기화 이벤트 (Aave V3: ReserveInitialized)
    /// @notice Reserve initialized event
    event ReserveInitialized(address indexed asset, address lToken, address debtToken, uint16 reserveId);

    // ============================================================
    // 수정자 / Modifiers
    // ============================================================

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier reserveActive(address asset) {
        require(reserves[asset].isActive, "Reserve not active");
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

    /// @notice 새로운 리저브를 초기화합니다 (Aave V3: initReserve)
    /// @notice Initialize a new reserve
    /// @param asset 자산 주소 / Asset address
    /// @param collateralFactor 담보 인정 비율 / Collateral factor (1e18 scale)
    /// @param liquidationThreshold 청산 기준 / Liquidation threshold (1e18 scale)
    function initReserve(
        address asset,
        uint256 collateralFactor,
        uint256 liquidationThreshold
    ) external onlyOwner {
        require(!reserves[asset].isActive, "Reserve already exists");
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

        // Aave V3 패턴: reserveId를 순차적으로 할당
        // Aave V3 pattern: assign reserveId sequentially
        uint16 reserveId = reservesCount;

        reserves[asset] = ReserveData({
            lToken: lToken,
            debtToken: debtToken,
            collateralFactor: collateralFactor,
            liquidationThreshold: liquidationThreshold,
            totalDeposits: 0,
            totalBorrows: 0,
            totalReserves: 0,
            borrowIndex: PRECISION, // 초기 인덱스 1.0 / Initial index 1.0
            lastUpdateTime: block.timestamp,
            id: reserveId,
            isActive: true
        });

        // Aave V3 패턴: reserveId → asset 주소를 매핑에 저장 (배열 대신)
        // Aave V3 pattern: store reserveId → asset in mapping (instead of array)
        reservesList[reserveId] = asset;
        reservesCount++;

        emit ReserveInitialized(asset, address(lToken), address(debtToken), reserveId);
    }

    // ============================================================
    // 핵심 함수 / Core Functions
    // ============================================================

    /// @notice 자산을 예치합니다 → LToken을 받습니다
    /// @notice Deposit asset → Receive LToken
    function deposit(address asset, uint256 amount)
        external
        reserveActive(asset)
    {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(asset);

        ReserveData storage reserve = reserves[asset];

        // Aave V3 패턴: 첫 예치 여부를 미리 확인 (민팅 전)
        // Aave V3 pattern: check if first supply before minting
        bool isFirstSupply = reserve.lToken.balanceOf(msg.sender) == 0;

        // 자산을 풀로 전송 / Transfer asset to pool
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // LToken 민팅 / Mint LToken
        uint256 mintAmount = _toMintAmount(asset, amount);
        reserve.lToken.mint(msg.sender, mintAmount);
        reserve.totalDeposits += amount;

        // Aave V3 패턴: 첫 예치 시 UserConfigurationMap에 담보 비트 자동 설정
        // Aave V3 pattern: automatically set collateral bit on first supply
        if (isFirstSupply) {
            _setUsingAsCollateral(_usersConfig[msg.sender], reserve.id, true);
        }

        emit Deposit(msg.sender, asset, amount);
    }

    /// @notice 예치금을 출금합니다 → LToken을 소각합니다
    /// @notice Withdraw deposits → Burn LToken
    function withdraw(address asset, uint256 amount)
        external
        reserveActive(asset)
    {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(asset);

        ReserveData storage reserve = reserves[asset];

        uint256 burnAmount = _toMintAmount(asset, amount);
        require(
            reserve.lToken.balanceOf(msg.sender) >= burnAmount,
            "Insufficient lToken balance"
        );

        // LToken 소각 / Burn LToken
        reserve.lToken.burn(msg.sender, burnAmount);
        reserve.totalDeposits -= amount;

        // Aave V3 패턴: 잔액이 0이 되면 담보 비트 해제
        // Aave V3 pattern: unset collateral bit when balance becomes zero
        if (reserve.lToken.balanceOf(msg.sender) == 0) {
            _setUsingAsCollateral(_usersConfig[msg.sender], reserve.id, false);
        }

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
    function borrow(address asset, uint256 amount)
        external
        reserveActive(asset)
    {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(asset);

        ReserveData storage reserve = reserves[asset];
        require(reserve.totalDeposits - reserve.totalBorrows >= amount, "Insufficient liquidity");

        // DebtToken 민팅 / Mint debt token
        reserve.debtToken.mint(msg.sender, amount);
        reserve.totalBorrows += amount;

        // 사용자 대출 인덱스 스냅샷 저장
        // Save user's borrow index snapshot
        userBorrowIndex[msg.sender][asset] = reserve.borrowIndex;

        // Aave V3 패턴: UserConfigurationMap에 대출 비트 설정
        // Aave V3 pattern: set borrowing bit in UserConfigurationMap
        _setBorrowing(_usersConfig[msg.sender], reserve.id, true);

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
        reserveActive(asset)
    {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(asset);

        ReserveData storage reserve = reserves[asset];
        uint256 debt = reserve.debtToken.balanceOf(msg.sender);
        require(debt > 0, "No debt to repay");

        // 상환액이 부채보다 크면 부채만큼만 상환
        // If repay amount exceeds debt, only repay debt amount
        uint256 repayAmount = amount > debt ? debt : amount;

        // 자산을 풀로 전송 / Transfer asset back to pool
        IERC20(asset).safeTransferFrom(msg.sender, address(this), repayAmount);

        // DebtToken 소각 / Burn debt token
        reserve.debtToken.burn(msg.sender, repayAmount);
        reserve.totalBorrows -= repayAmount;

        // Aave V3 패턴: 부채 완전 상환 시 대출 비트 해제
        // Aave V3 pattern: unset borrowing bit when debt fully repaid
        if (reserve.debtToken.balanceOf(msg.sender) == 0) {
            _setBorrowing(_usersConfig[msg.sender], reserve.id, false);
        }

        emit Repay(msg.sender, asset, repayAmount);
    }

    /// @notice 청산 — 부채를 대신 상환하고 담보를 할인받아 가져갑니다
    /// @notice Liquidation — Repay debt on behalf, seize discounted collateral
    function liquidate(
        address borrower,
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover
    ) external reserveActive(debtAsset) reserveActive(collateralAsset) {
        require(borrower != msg.sender, "Cannot liquidate self");

        _accrueInterest(debtAsset);
        _accrueInterest(collateralAsset);

        // 1. 헬스팩터 확인 — 1 미만이어야 청산 가능
        // 1. Check health factor — must be < 1 for liquidation
        uint256 healthFactor = _getHealthFactor(borrower);
        require(healthFactor < PRECISION, "Health factor is healthy");

        // 2. Close Factor 적용 — 한 번에 최대 50%만 청산 가능
        // 2. Apply close factor — max 50% liquidatable per call
        ReserveData storage debtReserve = reserves[debtAsset];
        uint256 userDebt = debtReserve.debtToken.balanceOf(borrower);
        uint256 maxLiquidatable = userDebt * CLOSE_FACTOR / PRECISION;
        require(debtToCover <= maxLiquidatable, "Exceeds close factor");

        // 3. 담보 압류량 계산 (보너스 포함)
        // 3. Calculate collateral to seize (including bonus)
        uint256 debtPrice = oracle.getAssetPrice(debtAsset);
        uint256 collateralPrice = oracle.getAssetPrice(collateralAsset);

        uint256 collateralToSeize = debtToCover
            * debtPrice
            * (PRECISION + LIQUIDATION_BONUS)
            / (collateralPrice * PRECISION);

        // 4. 청산자가 부채 상환 / Liquidator repays debt
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), debtToCover);
        debtReserve.debtToken.burn(borrower, debtToCover);
        debtReserve.totalBorrows -= debtToCover;

        // Aave V3 패턴: 부채 완전 소각 시 대출 비트 해제
        // Aave V3 pattern: unset borrowing bit if debt fully cleared
        if (debtReserve.debtToken.balanceOf(borrower) == 0) {
            _setBorrowing(_usersConfig[borrower], debtReserve.id, false);
        }

        // 5. 담보 LToken을 청산자에게 전송
        // 5. Transfer collateral LToken to liquidator
        ReserveData storage collateralReserve = reserves[collateralAsset];
        uint256 lTokenAmount = _toMintAmount(collateralAsset, collateralToSeize);
        require(
            collateralReserve.lToken.balanceOf(borrower) >= lTokenAmount,
            "Insufficient collateral"
        );

        collateralReserve.lToken.burn(borrower, lTokenAmount);
        collateralReserve.totalDeposits -= collateralToSeize;

        // Aave V3 패턴: 담보 잔액 0이면 담보 비트 해제
        // Aave V3 pattern: unset collateral bit if balance becomes zero
        if (collateralReserve.lToken.balanceOf(borrower) == 0) {
            _setUsingAsCollateral(_usersConfig[borrower], collateralReserve.id, false);
        }

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
        ReserveData storage reserve = reserves[asset];
        return interestRateModel.getUtilization(reserve.totalDeposits, reserve.totalBorrows);
    }

    /// @notice 리저브 수 조회 / Number of reserves
    function getReserveCount() external view returns (uint256) {
        return reservesCount;
    }

    /// @notice 사용자 설정 비트맵 조회 (Aave V3: getUserConfiguration)
    /// @notice Get user configuration bitmap
    function getUserConfiguration(address user) external view returns (uint256) {
        return _usersConfig[user].data;
    }

    /// @notice 사용자가 특정 자산을 담보로 사용 중인지 조회
    /// @notice Check if user is using asset as collateral
    function isUsingAsCollateral(address user, address asset) external view returns (bool) {
        return _isUsingAsCollateral(_usersConfig[user], reserves[asset].id);
    }

    /// @notice 사용자가 특정 자산을 대출 중인지 조회
    /// @notice Check if user is borrowing asset
    function isBorrowing(address user, address asset) external view returns (bool) {
        return _isBorrowing(_usersConfig[user], reserves[asset].id);
    }

    // ============================================================
    // 비트맵 헬퍼 함수 / Bitmap Helper Functions
    // (Aave V3: UserConfiguration library)
    // ============================================================

    /// @dev 사용자가 특정 리저브를 담보로 사용 중인지 확인
    /// @dev Check if user is using reserve as collateral
    /// @dev 비트 위치: 2 * reserveId (짝수 비트)
    /// @dev Bit position: 2 * reserveId (even bits)
    function _isUsingAsCollateral(UserConfigurationMap memory self, uint16 reserveId) internal pure returns (bool) {
        return (self.data >> (reserveId * 2)) & 1 != 0;
    }

    /// @dev 사용자가 특정 리저브에서 대출 중인지 확인
    /// @dev Check if user is borrowing from reserve
    /// @dev 비트 위치: 2 * reserveId + 1 (홀수 비트)
    /// @dev Bit position: 2 * reserveId + 1 (odd bits)
    function _isBorrowing(UserConfigurationMap memory self, uint16 reserveId) internal pure returns (bool) {
        return (self.data >> (reserveId * 2 + 1)) & 1 != 0;
    }

    /// @dev 담보 사용 비트 설정/해제
    /// @dev Set/unset collateral usage bit
    function _setUsingAsCollateral(UserConfigurationMap storage self, uint16 reserveId, bool value) internal {
        if (value) {
            self.data = self.data | (1 << (reserveId * 2));
        } else {
            self.data = self.data & ~(1 << (reserveId * 2));
        }
    }

    /// @dev 대출 비트 설정/해제
    /// @dev Set/unset borrowing bit
    function _setBorrowing(UserConfigurationMap storage self, uint16 reserveId, bool value) internal {
        if (value) {
            self.data = self.data | (1 << (reserveId * 2 + 1));
        } else {
            self.data = self.data & ~(1 << (reserveId * 2 + 1));
        }
    }

    // ============================================================
    // 내부 함수 / Internal Functions
    // ============================================================

    /// @dev 이자를 갱신합니다 (시간 경과에 따른 이자 누적)
    /// @dev Accrue interest (accumulate interest over time)
    function _accrueInterest(address asset) internal {
        ReserveData storage reserve = reserves[asset];

        uint256 timeElapsed = block.timestamp - reserve.lastUpdateTime;
        if (timeElapsed == 0) return;

        if (reserve.totalBorrows > 0) {
            // 초당 이자율 계산 / Calculate per-second rate
            uint256 borrowRatePerSecond = interestRateModel.getBorrowRatePerSecond(
                reserve.totalDeposits,
                reserve.totalBorrows
            );

            // 누적 이자 계산 / Calculate accumulated interest
            uint256 interestAccumulated = reserve.totalBorrows
                * borrowRatePerSecond
                * timeElapsed
                / PRECISION;

            // 준비금 적립 / Allocate to reserves
            uint256 reserveShare = interestAccumulated * RESERVE_FACTOR / PRECISION;
            reserve.totalReserves += reserveShare;

            // 총 대출금 증가 (이자 누적) / Increase total borrows
            reserve.totalBorrows += interestAccumulated;
            reserve.totalDeposits += interestAccumulated - reserveShare;

            // 대출 인덱스 갱신 / Update borrow index
            reserve.borrowIndex += reserve.borrowIndex * borrowRatePerSecond * timeElapsed / PRECISION;

            emit InterestAccrued(asset, interestAccumulated, reserve.borrowIndex);
        }

        reserve.lastUpdateTime = block.timestamp;
    }

    /// @dev 헬스팩터 계산 / Calculate health factor
    function _getHealthFactor(address user) internal view returns (uint256) {
        uint256 totalDebt = _getTotalDebt(user);
        if (totalDebt == 0) return type(uint256).max; // 부채 없으면 무한대 / No debt = infinite

        uint256 totalCollateralAdjusted = _getTotalCollateralAdjusted(user);
        return totalCollateralAdjusted * PRECISION / totalDebt;
    }

    /// @dev 청산 기준이 적용된 총 담보 가치 / Total collateral adjusted by liquidation threshold
    /// @dev Aave V3 패턴: UserConfigurationMap 비트맵으로 포지션 있는 리저브만 순회
    /// @dev Aave V3 pattern: use bitmap to skip reserves without positions
    function _getTotalCollateralAdjusted(address user) internal view returns (uint256) {
        uint256 totalValue = 0;
        UserConfigurationMap memory userConfig = _usersConfig[user];

        for (uint256 i = 0; i < reservesCount; i++) {
            // Aave V3 최적화: 비트맵으로 담보 여부 확인 → 없으면 스킵
            // Aave V3 optimization: check bitmap → skip if not collateral
            if (!_isUsingAsCollateral(userConfig, uint16(i))) continue;

            address asset = reservesList[i];
            ReserveData storage reserve = reserves[asset];

            uint256 lTokenBalance = reserve.lToken.balanceOf(user);
            if (lTokenBalance > 0) {
                uint256 underlyingAmount = _toUnderlyingAmount(asset, lTokenBalance);
                uint256 price = oracle.getAssetPrice(asset);
                uint256 value = underlyingAmount * price / PRECISION;
                totalValue += value * reserve.liquidationThreshold / PRECISION;
            }
        }

        return totalValue;
    }

    /// @dev 총 담보 가치 (조정 없음) / Total collateral value (unadjusted)
    function _getTotalCollateral(address user) internal view returns (uint256) {
        uint256 totalValue = 0;
        UserConfigurationMap memory userConfig = _usersConfig[user];

        for (uint256 i = 0; i < reservesCount; i++) {
            if (!_isUsingAsCollateral(userConfig, uint16(i))) continue;

            address asset = reservesList[i];
            ReserveData storage reserve = reserves[asset];

            uint256 lTokenBalance = reserve.lToken.balanceOf(user);
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
        UserConfigurationMap memory userConfig = _usersConfig[user];

        for (uint256 i = 0; i < reservesCount; i++) {
            // Aave V3 최적화: 비트맵으로 대출 여부 확인 → 없으면 스킵
            // Aave V3 optimization: check bitmap → skip if not borrowing
            if (!_isBorrowing(userConfig, uint16(i))) continue;

            address asset = reservesList[i];
            ReserveData storage reserve = reserves[asset];

            uint256 debtBalance = reserve.debtToken.balanceOf(user);
            if (debtBalance > 0) {
                uint256 price = oracle.getAssetPrice(asset);
                totalValue += debtBalance * price / PRECISION;
            }
        }

        return totalValue;
    }

    /// @dev 기초 자산 → LToken 민팅량 변환 (단순화: 1:1)
    /// @dev Underlying → LToken mint amount conversion (simplified: 1:1)
    function _toMintAmount(address, uint256 amount) internal pure returns (uint256) {
        return amount;
    }

    /// @dev LToken → 기초 자산 환산량 변환 (단순화: 1:1)
    /// @dev LToken → Underlying amount conversion (simplified: 1:1)
    function _toUnderlyingAmount(address, uint256 lTokenAmount) internal pure returns (uint256) {
        return lTokenAmount;
    }
}
