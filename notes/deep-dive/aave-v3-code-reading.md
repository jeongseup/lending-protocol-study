# Aave V3 코드 리딩 가이드
# Aave V3 Code Reading Guide

> 우리 코드(LendingPool.sol)와 비교하며 실제 Aave V3 코드를 읽는 가이드
> Guide to reading actual Aave V3 code, compared with our LendingPool.sol

> 소스: [aave-v3-origin](https://github.com/aave-dao/aave-v3-origin) (최신, aave-v3-core는 deprecated)
> 로컬 클론: ~/Workspace/temp/aave-v3-origin

---

## ⚠️ aave-v3-core → aave-v3-origin 변경 사항 (v3.2~v3.4)

```
aave-v3-core (deprecated)와 aave-v3-origin의 핵심 차이:

1. Stable Rate 완전 제거
   - StableDebtToken 삭제됨
   - InterestRateMode enum: NONE, __DEPRECATED, VARIABLE
   - swapBorrowRateMode(), rebalanceStableBorrowRate() 삭제됨
   → Variable Rate만 남음 (실제로도 stable은 거의 안 쓰였음)

2. InterestRateStrategy → Pool 레벨로 이동
   - 기존: reserve마다 개별 interestRateStrategyAddress
   - 변경: Pool 컨트랙트의 immutable RESERVE_INTEREST_RATE_STRATEGY
   - DefaultReserveInterestRateStrategyV2.sol 신규
   → reserve별 파라미터는 여전히 다르지만 컨트랙트 하나로 통합

3. Bad Debt (Deficit) 시스템 추가
   - ReserveData에 `deficit` 필드 추가 (구 stableBorrowRate 슬롯 재사용)
   - 청산 후 담보=0인데 부채 남으면 → deficit으로 기록
   - eliminateReserveDeficit(): Umbrella 컨트랙트가 deficit 해소
   - _burnBadDebt(): 청산 시 모든 부채를 한 번에 소각

4. Position Manager 추가
   - approvePositionManager(address, bool)
   - 승인된 매니저가 사용자 대신 담보 설정/eMode 변경 가능
   → DeFi 프로토콜 간 통합을 위한 기능

5. E-Mode 비트맵 방식 변경
   - 기존: eMode별 priceSource (오라클 오버라이드)
   - 변경: collateralBitmap + borrowableBitmap + ltvzeroBitmap
   - priceSource 삭제됨
   → 더 세밀한 자산별 eMode 설정 가능

6. virtualUnderlyingBalance 추가
   - aToken에 실제 보유 잔고와 프로토콜이 인식하는 잔고를 분리
   - 이자율 계산 시 virtual balance 사용

7. Multicall 상속
   - Pool이 OpenZeppelin Multicall 상속
   - 한 트랜잭션에서 여러 Pool 함수를 배치 호출 가능

8. 먼지(Dust) 방지 로직
   - MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD = $2,000
   - 청산 후 남은 담보/부채가 $1,000 미만이면 revert
   → 청산 봇이 가스 최적화로 소량만 남기는 것 방지

9. Liquidation Grace Period
   - reserve별 liquidationGracePeriodUntil 타임스탬프
   - 해당 기간 동안 청산 불가 (거버넌스가 설정)
```

---

## 읽는 순서 / Reading Order

```
① Pool.sol         — "얇은 라우터" (어디로 위임하는지 파악)
② SupplyLogic.sol  — 예치/출금 (우리 deposit/withdraw와 비교)
③ BorrowLogic.sol  — 대출/상환 (우리 borrow/repay와 비교)
④ LiquidationLogic.sol — 청산 (우리 liquidate와 비교)

보조 파일 (필요할 때 참조):
  - DataTypes.sol        — 모든 구조체 정의
  - ReserveLogic.sol     — 이자 인덱스 업데이트 (accrueInterest 역할)
  - ValidationLogic.sol  — 모든 검증 로직
  - GenericLogic.sol     — HF 계산 등 공용 로직
  - ReserveConfiguration.sol — 비트맵 설정 읽기/쓰기
  - TokenMath.sol        — 신규: scaled amount 변환 헬퍼
  - IsolationModeLogic.sol — Isolation mode 부채 관리

파일 경로:
  src/contracts/protocol/pool/Pool.sol
  src/contracts/protocol/libraries/logic/SupplyLogic.sol
  src/contracts/protocol/libraries/logic/BorrowLogic.sol
  src/contracts/protocol/libraries/logic/LiquidationLogic.sol
  src/contracts/protocol/libraries/types/DataTypes.sol
```

---

## 아키텍처 핵심: "왜 이렇게 분리했나?" / Why This Architecture?

```
Compound V2:
  CToken.sol = 2,000줄+ (자산보관 + 회계 + 로직 + 이자계산 전부)
  → 읽기 쉬움, 하지만 24KB 제한에 걸릴 수 있음

우리 코드 (LendingPool.sol):
  LendingPool.sol = 544줄 (모든 로직이 한 컨트랙트에)
  → 학습용으로 적합, 프로덕션에서는 너무 큼

Aave V3 (aave-v3-origin):
  Pool.sol = ~940줄 (abstract, 함수 시그니처 + library 위임)
  + SupplyLogic.sol, BorrowLogic.sol, ... (library로 분리)
  + PoolInstance.sol (concrete, 실제 배포되는 컨트랙트)
  → 24KB 제한 해결 + 모듈화

왜 library인가?
  - Solidity 컨트랙트 최대 크기 = 24KB (EIP-170)
  - delegatecall로 library 호출 → Pool의 storage를 직접 사용
  - library는 자체 상태 없음 → Pool의 _reserves mapping 등을 직접 읽고 씀
```

---

## ① Pool.sol — 얇은 라우터 / Thin Router

### 구조 / Structure

```solidity
// aave-v3-origin에서 Pool은 abstract contract!
// 실제 배포는 PoolInstance.sol이 담당

abstract contract Pool is VersionedInitializable, PoolStorage, IPool, Multicall {
    //       ↑                          ↑          ↑      ↑
    //  프록시 업그레이드     상태변수 정의  인터페이스  배치호출
    //  Proxy upgrade      State vars   Interface  Multicall

    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

    // v3.4 신규: 이자율 전략이 Pool 레벨 immutable로 이동!
    // (기존: reserve별로 interestRateStrategyAddress 저장)
    address public immutable RESERVE_INTEREST_RATE_STRATEGY;
```

### 핵심 상태변수 (PoolStorage에서 상속) / Key State Variables

```solidity
// PoolStorage.sol 실제 코드:

mapping(address => DataTypes.ReserveData) internal _reserves;
//  ↑ 우리 코드의 mapping(address => Market)과 동일한 역할
//    Aave는 "Reserve", 우리는 "Market"이라 부름

mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;
//  ↑ 사용자별 설정 (어떤 자산을 담보로 쓰는지 등)
//    비트맵으로 저장 → 가스 절약

mapping(uint256 => address) internal _reservesList;
//  ↑ 우리 코드의 address[] assetList와 동일한 역할
//    인덱스 → 주소 매핑

mapping(uint8 => DataTypes.EModeCategory) internal _eModeCategories;
mapping(address => uint8) internal _usersEModeCategory;

uint128 internal _flashLoanPremium;
//  ↑ v3.4: flashLoanPremiumToProtocol 삭제됨 (전액 treasury로)

uint16 internal _reservesCount;

// v3.4 신규: Position Manager
mapping(address user => mapping(address permittedPositionManager => bool))
    internal _positionManager;
```

### Pool.sol의 supply 함수 — 실제 코드 / Pool.supply Actual Code

```solidity
// ═══════════════════════════════════════════════════
// Aave V3 (aave-v3-origin): Pool.sol
// ═══════════════════════════════════════════════════

function supply(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
) public virtual override {
    SupplyLogic.executeSupply(
        _reserves,
        _reservesList,
        _eModeCategories,                              // ← eMode 카테고리도 전달
        _usersConfig[onBehalfOf],
        DataTypes.ExecuteSupplyParams({
            user: _msgSender(),                        // ← user와 onBehalfOf 분리
            asset: asset,
            interestRateStrategyAddress: RESERVE_INTEREST_RATE_STRATEGY,  // ← Pool 레벨!
            amount: amount,
            onBehalfOf: onBehalfOf,
            referralCode: referralCode,
            supplierEModeCategory: _usersEModeCategory[onBehalfOf]       // ← eMode 전달
        })
    );
}

// ═══════════════════════════════════════════════════
// 우리 코드: LendingPool.sol
// ═══════════════════════════════════════════════════

function deposit(address asset, uint256 amount)
    external
    marketExists(asset)
{
    require(amount > 0, "Amount must be > 0");
    _accrueInterest(asset);

    Market storage market = markets[asset];
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    uint256 mintAmount = _toMintAmount(asset, amount);
    market.lToken.mint(msg.sender, mintAmount);
    market.totalDeposits += amount;

    emit Deposit(msg.sender, asset, amount);
}

// ═══════════════════════════════════════════════════
// 차이점:
//   1. Aave: user(실행자)와 onBehalfOf(수혜자) 분리 → 대리 예치 가능
//      우리: msg.sender만 가능
//   2. Aave: interestRateStrategyAddress가 Pool immutable에서 전달
//      우리: interestRateModel이 LendingPool 상태변수
//   3. Aave: eMode 카테고리 정보도 함께 전달
//      우리: eMode 없음
//   4. Aave: 모든 로직이 SupplyLogic library에 위임
//      우리: 함수 안에 직접 작성
// ═══════════════════════════════════════════════════
```

### Pool.sol의 모든 사용자 함수 매핑 / All User Functions Mapped

```
┌──────────────────────────────────┬─────────────────────┬────────────────────┐
│ Aave V3 (Pool.sol)               │ Library 위임         │ 우리 코드           │
├──────────────────────────────────┼─────────────────────┼────────────────────┤
│ supply()                         │ SupplyLogic         │ deposit()          │
│ withdraw()                       │ SupplyLogic         │ withdraw()         │
│ borrow()                         │ BorrowLogic         │ borrow()           │
│ repay()                          │ BorrowLogic         │ repay()            │
│ liquidationCall()                │ LiquidationLogic    │ liquidate()        │
│ flashLoan() / flashLoanSimple()  │ FlashLoanLogic      │ ❌ 없음            │
│ setUserEMode()                   │ SupplyLogic         │ ❌ 없음            │
│ supplyWithPermit()               │ SupplyLogic         │ ❌ 없음            │
│ repayWithATokens()               │ BorrowLogic         │ ❌ 없음            │
│ eliminateReserveDeficit()        │ LiquidationLogic    │ ❌ 없음 (v3.4 신규) │
│ approvePositionManager()         │ (Pool 직접)          │ ❌ 없음 (v3.4 신규) │
│ setUserUseReserveAsCollateral()  │ SupplyLogic         │ (자동, 항상 담보)   │
├──────────────────────────────────┼─────────────────────┼────────────────────┤
│ ❌ swapBorrowRateMode() 삭제됨   │ -                   │ ❌ 없음            │
│ ❌ rebalanceStableBorrowRate() 삭│ -                   │ ❌ 없음            │
└──────────────────────────────────┴─────────────────────┴────────────────────┘

v3.4에서 삭제된 것들:
  - swapBorrowRateMode: Stable Rate 제거로 불필요
  - rebalanceStableBorrowRate: 위와 동일
  - mintUnbacked/backUnbacked: Portal 브릿지 제거

v3.4에서 추가된 것들:
  - eliminateReserveDeficit: Bad debt 해소 (Umbrella만 호출)
  - approvePositionManager: 대리 조작 승인
  - setUserUseReserveAsCollateralOnBehalfOf: Position Manager용
  - setUserEModeOnBehalfOf: Position Manager용
  - getFlashLoanLogic/getBorrowLogic/etc: Library 주소 조회
```

---

## ② SupplyLogic.sol — 예치/출금 로직 / Supply & Withdraw Logic

### executeSupply 실제 코드 / Actual Code

```solidity
// aave-v3-origin/src/contracts/protocol/libraries/logic/SupplyLogic.sol

function executeSupply(...) external {
    DataTypes.ReserveData storage reserve = reservesData[params.asset];
    DataTypes.ReserveCache memory reserveCache = reserve.cache();

    reserve.updateState(reserveCache);

    // v3.4 신규: TokenMath 라이브러리로 scaled amount 계산
    uint256 scaledAmount = params.amount.getATokenMintScaledAmount(
        reserveCache.nextLiquidityIndex
    );

    ValidationLogic.validateSupply(reserveCache, reserve, scaledAmount, params.onBehalfOf);

    // v3.4: updateInterestRatesAndVirtualBalance (virtualBalance도 함께 업데이트)
    reserve.updateInterestRatesAndVirtualBalance(
        reserveCache,
        params.asset,
        params.amount,    // liquidityAdded
        0,                // liquidityTaken
        params.interestRateStrategyAddress
    );

    // 자산을 aToken으로 전송 (Pool이 아니라!)
    IERC20(params.asset).safeTransferFrom(params.user, reserveCache.aTokenAddress, params.amount);

    // aToken 민팅 (scaledAmount 사용)
    bool isFirstSupply = IAToken(reserveCache.aTokenAddress).mint(
        params.user,
        params.onBehalfOf,
        scaledAmount,     // ← 정규화된 양 (amount / liquidityIndex)
        reserveCache.nextLiquidityIndex
    );

    // 첫 예치 시 자동 담보 활성화
    if (isFirstSupply) {
        if (ValidationLogic.validateAutomaticUseAsCollateral(
            reservesData, reservesList, eModeCategories, userConfig,
            reserveCache.reserveConfiguration,
            params.asset, params.supplierEModeCategory
        )) {
            userConfig.setUsingAsCollateral(reserve.id, params.asset, params.onBehalfOf, true);
        }
    }

    emit IPool.Supply(...);
}
```

### 우리 코드와 비교 / vs Our Code

```
우리 코드 (LendingPool.deposit):          Aave V3 (SupplyLogic.executeSupply):
─────────────────────────────             ──────────────────────────────────────

1. _accrueInterest(asset)           →    1. reserve.cache()
                                              ↑ ReserveData의 스냅샷 생성
                                         2. reserve.updateState(cache)
                                              ↑ 이자 인덱스 업데이트

                                         2.5 TokenMath.getATokenMintScaledAmount()
                                              ↑ 신규: scaled amount 미리 계산

2. (없음)                            →    3. ValidationLogic.validateSupply()

3. safeTransferFrom(                 →    4. updateInterestRatesAndVirtualBalance()
     user → pool)                           ↑ 이자율 재계산 + virtualBalance 업데이트

4. lToken.mint(user, amount)         →    5. IERC20.safeTransferFrom(user → aToken 주소)
                                              ↑ Pool이 아니라 aToken으로!

5. totalDeposits += amount           →    6. IAToken.mint(user, scaledAmount, index)
                                              ↑ 정규화된 양으로 민팅

                                         7. if isFirstSupply: 자동 담보 활성화
```

### 핵심 차이: 자산 보관 위치 / Key Difference: Asset Custody

```
우리 코드:
  IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
  //                                        ↑ LendingPool 자체에 보관
  // Pool 컨트랙트가 모든 자산을 직접 보유

Aave V3:
  IERC20(params.asset).safeTransferFrom(params.user, reserveCache.aTokenAddress, amount);
  //                                                  ↑ aToken 컨트랙트에 보관!
  // Pool은 로직만, 자산은 aToken이 보유

왜 분리?
  1. Pool 컨트랙트가 해킹되어도 자산은 aToken에 안전
     (Pool은 delegatecall 패턴이라 로직 교체 가능)
  2. aToken이 ERC-20이므로 다른 DeFi에서 직접 사용 가능
  3. 자산별 독립적인 보관 → 리스크 격리
```

### reserve.updateState() — 우리 _accrueInterest와 비교 / vs Our _accrueInterest

```solidity
// ═══════════════════════════════════════════════════
// Aave V3: ReserveLogic.sol — updateState()
// ═══════════════════════════════════════════════════

function updateState(
    DataTypes.ReserveData storage reserve,
    DataTypes.ReserveCache memory reserveCache
) internal {
    _updateIndexes(reserve, reserveCache);
    _accrueToTreasury(reserve, reserveCache);
}

// v3.4에서는 Stable Rate 관련 로직이 모두 삭제됨
// → Variable만 처리하면 되므로 더 단순해짐

// ═══════════════════════════════════════════════════
// 우리 코드: LendingPool._accrueInterest()
// ═══════════════════════════════════════════════════

function _accrueInterest(address asset) internal {
    Market storage market = markets[asset];
    uint256 timeElapsed = block.timestamp - market.lastUpdateTime;
    if (timeElapsed == 0) return;

    if (market.totalBorrows > 0) {
        uint256 borrowRatePerSecond = interestRateModel.getBorrowRatePerSecond(
            market.totalDeposits, market.totalBorrows
        );
        uint256 interestAccumulated = market.totalBorrows
            * borrowRatePerSecond * timeElapsed / PRECISION;

        uint256 reserveShare = interestAccumulated * RESERVE_FACTOR / PRECISION;
        market.totalReserves += reserveShare;
        market.totalBorrows += interestAccumulated;
        market.totalDeposits += interestAccumulated - reserveShare;
        market.borrowIndex += market.borrowIndex
            * borrowRatePerSecond * timeElapsed / PRECISION;
    }
    market.lastUpdateTime = block.timestamp;
}

// ═══════════════════════════════════════════════════
// 차이점:
//   1. Aave: 인덱스 2개 (liquidityIndex + variableBorrowIndex)
//      우리: 인덱스 1개 (borrowIndex만)
//   2. Aave: Ray 정밀도 (10^27), 우리: Mantissa (10^18)
//   3. Aave: 복리 (calculateCompoundedInterest)
//      우리: 단리 근사 (선형 계산)
//   4. Aave: treasury에 aToken 형태로 수수료 적립
//      우리: totalReserves에 숫자만 증가
//   5. Aave: cache 패턴 (SLOAD 1회 → MLOAD 여러 회)
//      우리: storage pointer 직접 접근
// ═══════════════════════════════════════════════════
```

### cache 패턴이란? / What is the Cache Pattern?

```solidity
// Aave V3는 함수 시작 시 reserve 데이터를 memory로 복사
// 이유: SLOAD (storage 읽기) = 2,100 gas, MLOAD (memory 읽기) = 3 gas

DataTypes.ReserveCache memory reserveCache = reserve.cache();

// ReserveCache 구조체 (v3.4 실제 코드):
struct ReserveCache {
    uint256 currScaledVariableDebt;
    uint256 nextScaledVariableDebt;
    uint256 currLiquidityIndex;
    uint256 nextLiquidityIndex;
    uint256 currVariableBorrowIndex;
    uint256 nextVariableBorrowIndex;
    uint256 currLiquidityRate;
    uint256 currVariableBorrowRate;
    uint256 reserveFactor;
    ReserveConfigurationMap reserveConfiguration;
    address aTokenAddress;
    address variableDebtTokenAddress;
    uint40 reserveLastUpdateTimestamp;
}
// ↑ StableDebt 관련 필드가 전부 삭제됨 (v3.2에서)

// 한 번 SLOAD로 읽어서 memory에 저장
// → 이후 여러 번 참조할 때 MLOAD만 사용 (가스 700배 절약!)
// → 함수 끝에서 변경된 값만 SSTORE로 다시 저장

// 우리 코드에서는 Market storage market = markets[asset]; 로
// storage pointer를 직접 사용 → 매 접근마다 SLOAD 발생
```

---

## ③ BorrowLogic.sol — 대출/상환 로직 / Borrow & Repay Logic

### executeBorrow 실제 코드 / Actual Code

```solidity
// v3.4에서 Stable Rate 관련 코드가 완전히 제거됨
// Variable만 남아서 코드가 훨씬 간결해짐

function executeBorrow(...) external {
    DataTypes.ReserveData storage reserve = reservesData[params.asset];
    DataTypes.ReserveCache memory reserveCache = reserve.cache();
    reserve.updateState(reserveCache);

    // v3.4: TokenMath로 scaled amount 미리 계산
    uint256 amountScaled = params.amount.getVTokenMintScaledAmount(
        reserveCache.nextVariableBorrowIndex
    );

    ValidationLogic.validateBorrow(...);

    // Variable 부채 토큰 민팅 (Stable은 더 이상 없음!)
    reserveCache.nextScaledVariableDebt = IVariableDebtToken(
        reserveCache.variableDebtTokenAddress
    ).mint(
        params.user,
        params.onBehalfOf,
        params.amount,
        amountScaled,                              // ← 정규화된 양
        reserveCache.nextVariableBorrowIndex
    );

    if (!userConfig.isBorrowing(reserve.id)) {
        userConfig.setBorrowing(reserve.id, true);
    }

    IsolationModeLogic.increaseIsolatedDebtIfIsolated(...);

    reserve.updateInterestRatesAndVirtualBalance(...);

    if (params.releaseUnderlying) {
        IAToken(reserveCache.aTokenAddress).transferUnderlyingTo(params.user, params.amount);
    }

    // v3.4: HF 검증이 borrow 이후에 수행됨!
    ValidationLogic.validateHFAndLtv(...);

    // v3.4: 이벤트에 항상 VARIABLE 모드
    emit IPool.Borrow(
        ..., DataTypes.InterestRateMode.VARIABLE, reserve.currentVariableBorrowRate, ...
    );
}
```

### 우리 코드와 비교 / vs Our Code

```
우리 코드 (LendingPool.borrow):         Aave V3 (BorrowLogic.executeBorrow):
────────────────────────────            ──────────────────────────────────────

1. _accrueInterest(asset)          →   1. reserve.cache() + updateState()

2. 유동성 확인                      →   2. TokenMath.getVTokenMintScaledAmount()
                                          ↑ 정규화된 부채량 미리 계산

3. (없음)                           →   3. ValidationLogic.validateBorrow()
                                          - reserve active/not paused/not frozen
                                          - 대출 활성화 여부
                                          - Isolation mode 부채 한도
                                          - eMode 호환성 (비트맵으로 확인)
                                          - Oracle sentinel (L2 시퀀서 다운타임)
                                          ⚠️ Stable Rate 검증 완전 삭제됨

4. debtToken.mint(user, amount)     →   4. IVariableDebtToken.mint(
                                            user, amount, amountScaled, index)
                                          ↑ scaledBalance = amount / variableBorrowIndex
                                          ⚠️ StableDebtToken 경로 완전 삭제됨

5. totalBorrows += amount           →   (debtToken.mint 내부에서 처리)

6. userBorrowIndex = borrowIndex    →   (scaledBalance 패턴으로 대체)

7. HF >= 1 확인                     →   5. validateHFAndLtv()
   ↑ 대출 후 확인                       ↑ 대출 후 확인 (v3.4에서 순서 변경!)

8. safeTransfer(user, amount)       →   6. IAToken.transferUnderlyingTo(user, amount)

                                    →   7. IsolationMode 부채 카운터 증가
                                    →   8. updateInterestRatesAndVirtualBalance()
```

### 핵심 차이: 부채 토큰화 / Key Difference: Debt Tokenization

```solidity
// ═══════════════════════════════════════════════════
// 우리 코드: 부채 = DebtToken (단순 ERC20)
// ═══════════════════════════════════════════════════

debtToken.mint(msg.sender, amount);           // 3,000 dUSDC 민팅
userBorrowIndex[msg.sender][asset] = borrowIndex;

uint256 debt = debtToken.balanceOf(user);     // 민팅한 그대로 3,000
// ⚠️ 이자가 반영되지 않음!

// ═══════════════════════════════════════════════════
// Aave V3: VariableDebtToken — 자동 이자 반영
// ═══════════════════════════════════════════════════

// 대출 시:
// scaledBalance = amount / variableBorrowIndex
// 예: 3,000 / 1.05 = 2,857.14

// 부채 조회 시 (TokenMath.getVTokenBalance 사용):
// debt = scaledBalance × variableBorrowIndex
// 2,857.14 × 1.08 = 3,085.71 ← 이자 자동 반영!

// 핵심: Aave의 debtToken.balanceOf()는 항상 "이자 포함 현재 부채"를 반환
// 우리 코드: debtToken.balanceOf()는 "원금"만 반환
```

---

## ④ LiquidationLogic.sol — 청산 로직 / Liquidation Logic

### v3.4 핵심 상수 / Key Constants

```solidity
uint256 internal constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 0.5e4;  // 50%
uint256 public constant CLOSE_FACTOR_HF_THRESHOLD = 0.95e18;

// v3.4 신규: 먼지 방지 임계값
uint256 public constant MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD = 2000e8;  // $2,000
uint256 public constant MIN_LEFTOVER_BASE = MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD / 2;  // $1,000

// Close Factor 로직 (v3.4에서 변경됨):
//   기본: maxLiquidatableDebt = 전체 부채 (100% 가능)
//   단, 담보와 부채 모두 $2,000 이상이고 HF > 0.95이면:
//     → maxLiquidatableDebt = 전체 부채의 50%
//   + 청산 후 남은 담보/부채가 $1,000 미만이면 revert
```

### executeLiquidationCall 실제 코드 / Actual Code

```solidity
function executeLiquidationCall(...) external {
    LiquidationCallLocalVars memory vars;

    // 1. 이자 정산 (담보 + 부채 모두)
    debtReserve.updateState(vars.debtReserveCache);
    collateralReserve.updateState(vars.collateralReserveCache);

    // 2. HF 계산
    (vars.totalCollateralInBaseCurrency, vars.totalDebtInBaseCurrency, , ,
     vars.healthFactor, ) = GenericLogic.calculateUserAccountData(...);

    // 3. 부채 잔고 조회 (Variable만!)
    vars.borrowerReserveDebt = IVariableDebtToken(...)
        .scaledBalanceOf(params.borrower)
        .getVTokenBalance(vars.debtReserveCache.nextVariableBorrowIndex);

    // 4. 검증
    ValidationLogic.validateLiquidationCall(...);

    // 5. eMode 보너스 확인 (비트맵 기반, priceSource 삭제됨)
    if (params.borrowerEModeCategory != 0 &&
        EModeConfiguration.isReserveEnabledOnBitmap(
            eModeCategories[params.borrowerEModeCategory].collateralBitmap,
            collateralReserve.id
        )) {
        vars.liquidationBonus = eModeCategories[...].liquidationBonus;
    } else {
        vars.liquidationBonus = collateralReserveConfig.getLiquidationBonus();
    }

    // 6. Close Factor 계산 (v3.4 변경)
    uint256 maxLiquidatableDebt = vars.borrowerReserveDebt;  // 기본: 100%
    if (
        vars.borrowerReserveCollateralInBaseCurrency >= MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD &&
        vars.borrowerReserveDebtInBaseCurrency >= MIN_BASE_MAX_CLOSE_FACTOR_THRESHOLD &&
        vars.healthFactor > CLOSE_FACTOR_HF_THRESHOLD
    ) {
        // 대형 포지션 + HF > 0.95 → 50%만 허용
        maxLiquidatableDebt = (totalDebt * 50%) 범위 내로 제한;
    }

    // 7. 담보 압류량 계산
    (vars.actualCollateralToLiquidate, vars.actualDebtToLiquidate,
     vars.liquidationProtocolFeeAmount, ...) =
        _calculateAvailableCollateralToLiquidate(...);

    // 8. 먼지 방지 검증 (v3.4 신규!)
    // 청산 후 남은 담보/부채가 $1,000 미만이면 revert
    require(
        isDebtMoreThanLeftoverThreshold && isCollateralMoreThanLeftoverThreshold,
        Errors.MustNotLeaveDust()
    );

    // 9. 부채 토큰 소각 (Variable만!)
    _burnDebtTokens(...)

    // 10. 담보 처리
    if (params.receiveAToken) {
        // aToken을 청산자에게 이전 (소각 안 함)
        IAToken(...).transferOnLiquidation(borrower, liquidator, amount, ...);
    } else {
        // aToken 소각 → underlying을 청산자에게 전송
        _burnCollateralATokens(...);
    }

    // 11. 프로토콜 수수료 → treasury
    if (vars.liquidationProtocolFeeAmount != 0) {
        IAToken(...).transferOnLiquidation(borrower, treasury, fee, ...);
    }

    // 12. v3.4 신규: Bad Debt 처리!
    // 담보가 0인데 다른 부채가 남아있으면 → deficit으로 기록
    if (hasNoCollateralLeft && borrowerConfig.isBorrowingAny()) {
        _burnBadDebt(reservesData, reservesList, borrowerConfig, params);
    }

    // 13. 청산자가 부채 상환
    IERC20(params.debtAsset).safeTransferFrom(
        params.liquidator, vars.debtReserveCache.aTokenAddress, vars.actualDebtToLiquidate
    );
}
```

### 우리 코드와 비교 / vs Our Code

```
우리 코드 (LendingPool.liquidate):       Aave V3 (aave-v3-origin):
──────────────────────────────           ─────────────────────────────

1. HF < 1 확인                      →   1. HF 계산 + validateLiquidationCall()
                                           + liquidationGracePeriod 확인 (v3.4)

2. Close Factor = 항상 50%          →   2. 동적 Close Factor (v3.4 변경):
                                           기본 100%, 대형 포지션+HF>0.95면 50%
                                           + 먼지 방지: 잔여 < $1,000이면 revert

3. 담보 압류량 계산                  →   3. _calculateAvailableCollateralToLiquidate()
                                           + liquidation protocol fee

4. 부채 소각                        →   4. _burnDebtTokens()
                                           Variable만! (Stable 삭제됨)

5. 담보 전송                        →   5. receiveAToken 선택 가능

(없음)                              →   6. Bad Debt 처리 (v3.4 신규)
                                           담보=0이고 부채 남으면:
                                           → deficit에 기록
                                           → _burnBadDebt()로 모든 부채 소각
```

### v3.4 신규: Bad Debt (Deficit) 시스템 / Bad Debt System

```
기존 (aave-v3-core):
  담보가 완전히 소진되어도 남은 부채가 그대로 남아있음
  → "좀비 포지션" 발생 (부채만 있고 담보 없는 상태)
  → 프로토콜 수익으로 충당해야 하는데 메커니즘 없었음

v3.4 (aave-v3-origin):
  1. 청산 후 담보=0이면 → 남은 모든 부채를 한 번에 소각
  2. 소각된 부채량 → reserve.deficit에 기록
  3. Umbrella 컨트랙트가 eliminateReserveDeficit() 호출
     → aToken을 태워서 deficit 해소
  4. emit DeficitCreated / DeficitCovered 이벤트

DevOps 관점:
  - deficit 모니터링 → 프로토콜 건전성 지표
  - Umbrella 컨트랙트 동작 확인
  - deficit이 누적되면 거버넌스 알림 필요
```

---

## DataTypes.sol — 핵심 구조체 / Key Data Structures

### ReserveData — 우리 Market과 비교 / vs Our Market Struct

```solidity
// ═══════════════════════════════════════════════════
// Aave V3 (aave-v3-origin): DataTypes.ReserveData
// ═══════════════════════════════════════════════════

struct ReserveData {
    ReserveConfigurationMap configuration;        // 비트맵
    uint128 liquidityIndex;                       // supply 이자 인덱스
    uint128 currentLiquidityRate;                 // 현재 supply 이자율
    uint128 variableBorrowIndex;                  // ← 우리 borrowIndex
    uint128 currentVariableBorrowRate;            // 현재 borrow 이자율
    uint128 deficit;                              // ← v3.4 신규! (구 stableBorrowRate 슬롯)
    uint40 lastUpdateTimestamp;                   // ← 우리 lastUpdateTime
    uint16 id;
    uint40 liquidationGracePeriodUntil;           // ← v3.4 신규!
    address aTokenAddress;                        // ← 우리 lToken
    address __deprecatedStableDebtTokenAddress;   // ← 삭제됨!
    address variableDebtTokenAddress;             // ← 우리 debtToken
    address __deprecatedInterestRateStrategyAddress; // ← Pool immutable로 이동!
    uint128 accruedToTreasury;
    uint128 virtualUnderlyingBalance;             // ← v3.4 신규!
    uint128 isolationModeTotalDebt;
}

// ═══════════════════════════════════════════════════
// 우리 코드: Market struct
// ═══════════════════════════════════════════════════

struct Market {
    LToken lToken;                    // → aTokenAddress
    DebtToken debtToken;              // → variableDebtTokenAddress
    uint256 collateralFactor;         // → configuration 비트맵 안
    uint256 liquidationThreshold;     // → configuration 비트맵 안
    uint256 totalDeposits;            // → aToken.totalSupply() × index로 계산
    uint256 totalBorrows;             // → debtToken.totalSupply() × index로 계산
    uint256 totalReserves;            // → accruedToTreasury
    uint256 borrowIndex;              // → variableBorrowIndex
    uint256 lastUpdateTime;           // → lastUpdateTimestamp
    bool isActive;                    // → configuration 비트맵 안
}
```

### Configuration 비트맵 (v3.4 업데이트) / Updated Bitmap

```
Aave V3 (aave-v3-origin)의 비트맵:

bit  0-15:  LTV
bit 16-31:  Liquidation threshold
bit 32-47:  Liquidation bonus
bit 48-55:  Decimals
bit 56:     Active flag
bit 57:     Frozen flag
bit 58:     Borrowing enabled
bit 59:     DEPRECATED (was: stable rate borrowing enabled)
bit 60:     Paused
bit 61:     Borrowable in isolation
bit 62:     Siloed borrowing enabled
bit 63:     Flashloaning enabled
bit 64-79:  Reserve factor
bit 80-115: Borrow cap (in whole tokens)
bit 116-151: Supply cap (in whole tokens)
bit 152-167: Liquidation protocol fee
bit 168-175: DEPRECATED (was: eMode category, moved to bitmap)
bit 176-211: DEPRECATED (was: unbacked mint cap)
bit 212-251: Debt ceiling (isolation mode)
bit 252:    DEPRECATED (was: virtual accounting enabled)
```

### EModeCategory (v3.4 변경) / E-Mode Changes

```solidity
// 기존 (aave-v3-core):
struct EModeCategory {
    uint16 ltv;
    uint16 liquidationThreshold;
    uint16 liquidationBonus;
    address priceSource;    // ← 커스텀 오라클 주소
    string label;
}

// 변경 (aave-v3-origin):
struct EModeCategory {
    uint16 ltv;
    uint16 liquidationThreshold;
    uint16 liquidationBonus;
    uint128 collateralBitmap;   // ← 어떤 자산이 이 eMode의 담보인지
    string label;
    uint128 borrowableBitmap;   // ← 어떤 자산이 이 eMode에서 빌릴 수 있는지
    uint128 ltvzeroBitmap;      // ← LTV=0으로 취급할 자산
}

// priceSource 삭제됨 → eMode별 커스텀 오라클 없음
// 대신 비트맵으로 자산별 세밀한 제어 가능
```

---

## 전체 콜 플로우 요약 / Complete Call Flow Summary

```
Alice가 Aave V3에 10 ETH 예치하는 전체 흐름 (aave-v3-origin):

Alice (EOA)
    │
    │ Pool.supply(WETH, 10e18, alice, 0)
    ▼
Pool.sol (abstract → PoolInstance.sol이 실제 배포)
    │
    │ SupplyLogic.executeSupply(
    │   _reserves,
    │   _reservesList,
    │   _eModeCategories,                    ← v3.4: eMode도 전달
    │   _usersConfig[alice],
    │   params { interestRateStrategyAddress: RESERVE_INTEREST_RATE_STRATEGY }
    │ )                                       ↑ v3.4: Pool immutable에서 전달
    ▼
SupplyLogic.sol (library)
    │
    ├─→ reserve.cache()
    │
    ├─→ reserve.updateState(cache)
    │     ├─→ _updateIndexes()
    │     └─→ _accrueToTreasury()
    │
    ├─→ TokenMath.getATokenMintScaledAmount()  ← v3.4: 신규 헬퍼
    │
    ├─→ ValidationLogic.validateSupply()
    │
    ├─→ reserve.updateInterestRatesAndVirtualBalance()
    │     └─→ DefaultReserveInterestRateStrategyV2   ← v3.4: V2로 변경
    │           .calculateInterestRates()
    │
    ├─→ IERC20(WETH).safeTransferFrom(alice → aWETH)
    │
    └─→ IAToken(aWETH).mint(alice, scaledAmount, index)
          │
          └─→ if isFirstSupply:
                validateAutomaticUseAsCollateral(... eMode 비트맵 확인)
                userConfig.setUsingAsCollateral(...)
```

---

## 코드 읽기 팁 / Code Reading Tips

```
1. Pool.sol부터 시작하되, 함수 본문은 무시해도 됨
   → 어떤 함수가 어떤 library로 위임되는지만 파악
   → "메뉴판"처럼 읽기
   → Pool.sol이 abstract인 것 주의! (PoolInstance.sol이 실제)

2. Library 읽을 때는 "우리 코드의 어떤 부분에 해당하는가?"를 생각
   → SupplyLogic.executeSupply ≈ 우리 deposit()
   → BorrowLogic.executeBorrow ≈ 우리 borrow()

3. DataTypes.sol을 먼저 훑어보기
   → ReserveData, ReserveCache, UserConfigurationMap 구조체 이해
   → __deprecated 필드들은 무시 (하위 호환용)

4. TokenMath.sol은 v3.4에서 추가된 헬퍼
   → getATokenMintScaledAmount, getVTokenBurnScaledAmount 등
   → scaled amount 변환을 표준화

5. Stable Rate 관련 코드는 모두 무시
   → __DEPRECATED, __deprecatedStableDebtTokenAddress 등
   → Variable만 보면 됨

6. 한 번에 다 읽으려 하지 말 것
   → supply 흐름만 완전히 따라가기 → borrow → liquidation
   → 각 흐름을 우리 코드와 1:1 대응시키기

7. 로컬에서 직접 탐색:
   → ~/Workspace/temp/aave-v3-origin 에 클론됨
   → forge build로 빌드 확인 가능
```

---

## Aave V3만의 고급 기능 / Aave V3 Advanced Features

### E-Mode (Efficiency Mode) — v3.4 업데이트

```
같은 카테고리의 상관 자산끼리는 높은 LTV를 허용

예시: ETH 카테고리
  - WETH, wstETH, cbETH, rETH 모두 collateralBitmap에 포함
  - 일반 LTV: 80%
  - E-Mode LTV: 93%
  - E-Mode liquidationThreshold: 95%

v3.4 변경사항:
  - priceSource 삭제 → eMode별 커스텀 오라클 없음
  - 비트맵으로 관리:
    collateralBitmap: 이 eMode에서 담보로 쓸 수 있는 자산들
    borrowableBitmap: 이 eMode에서 빌릴 수 있는 자산들
    ltvzeroBitmap: LTV=0으로 취급할 자산들
```

### Isolation Mode

```
신규/위험한 자산의 리스크를 격리

예시: 새로 추가된 TOKEN_X
  - isolation mode = true (debt ceiling 설정됨)
  - debt ceiling = $10M
  - TOKEN_X를 담보로 빌릴 수 있는 총 부채 = 최대 $10M
  - TOKEN_X 담보로는 "격리 허용된 자산"만 빌릴 수 있음

구현:
  ReserveData.isolationModeTotalDebt += newDebt
  → ceiling 초과 시 revert
```

### Flash Loan

```solidity
// 같은 트랜잭션 안에서 빌리고 갚기
pool.flashLoan(
    receiverAddress,
    assets,
    amounts,
    interestRateModes,  // 0=상환, 2=variable로 전환 (1=stable은 deprecated)
    onBehalfOf,
    params,
    referralCode
);

// v3.4 변경: flashLoan premium이 100% treasury로
// (기존: flashLoanPremiumTotal과 flashLoanPremiumToProtocol로 분리)
```

### Position Manager (v3.4 신규)

```solidity
// 사용자가 외부 컨트랙트를 "Position Manager"로 승인
pool.approvePositionManager(managerAddress, true);

// Manager가 사용자 대신:
pool.setUserUseReserveAsCollateralOnBehalfOf(asset, true, user);
pool.setUserEModeOnBehalfOf(categoryId, user);

// 활용: DeFi 프로토콜이 사용자 포지션을 자동 관리
// (예: 자동 리밸런싱, 자동 eMode 전환 등)
```

---

## 다음 단계 / Next Steps

```
코드 읽기 완료 후:
  1. 우리 LendingPool.sol에 빠진 기능 중 가장 중요한 것 식별
     → scaledBalance 패턴 (이자 자동 반영)
     → 동적 close factor
     → Bad debt (deficit) 관리
  2. Aave V3를 포크해서 로컬에서 테스트
     → cd ~/Workspace/temp/aave-v3-origin && forge test
  3. Go 모니터링 도구에서 Aave V3 연동
     → Pool.getUserAccountData() 호출
     → healthFactor 모니터링
     → deficit 모니터링 (v3.4 신규)
```
