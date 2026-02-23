// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DebtToken — 부채 추적 토큰
/// @notice 사용자의 대출 부채를 추적하는 토큰 (Aave의 debtToken과 유사)
/// @notice Tracks user's borrow debt (similar to Aave's debtToken)
/// @dev 전송 불가능 — 부채는 양도할 수 없습니다
/// @dev Non-transferable — debt cannot be transferred to others

contract DebtToken is ERC20 {
    /// @notice 기초 자산 주소 / Underlying asset address
    address public immutable underlying;

    /// @notice 렌딩 풀 주소 (민팅/소각 권한) / Lending pool address (mint/burn authority)
    address public lendingPool;

    /// @notice 기초 자산의 소수점 자릿수 / Decimals of underlying asset
    uint8 private _decimals;

    modifier onlyPool() {
        require(msg.sender == lendingPool, "Only lending pool");
        _;
    }

    /// @param _name 토큰 이름 / Token name (e.g., "Debt USDC")
    /// @param _symbol 토큰 심볼 / Token symbol (e.g., "dUSDC")
    /// @param _underlying 기초 자산 주소 / Underlying asset address
    /// @param _underlyingDecimals 기초 자산 소수점 / Underlying asset decimals
    constructor(
        string memory _name,
        string memory _symbol,
        address _underlying,
        uint8 _underlyingDecimals
    ) ERC20(_name, _symbol) {
        underlying = _underlying;
        _decimals = _underlyingDecimals;
        lendingPool = msg.sender;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice 부채 토큰을 민팅합니다 (대출 시 호출)
    /// @notice Mint debt tokens (called on borrow)
    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }

    /// @notice 부채 토큰을 소각합니다 (상환 시 호출)
    /// @notice Burn debt tokens (called on repay)
    function burn(address from, uint256 amount) external onlyPool {
        _burn(from, amount);
    }

    /// @dev 전송을 금지합니다 — 부채는 양도 불가
    /// @dev Disable transfers — debt is non-transferable
    function transfer(address, uint256) public pure override returns (bool) {
        revert("DebtToken: transfer not allowed");
    }

    /// @dev 전송을 금지합니다 — 부채는 양도 불가
    /// @dev Disable transferFrom — debt is non-transferable
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("DebtToken: transfer not allowed");
    }

    /// @dev 승인을 금지합니다 — 부채는 양도 불가
    /// @dev Disable approve — debt is non-transferable
    function approve(address, uint256) public pure override returns (bool) {
        revert("DebtToken: approve not allowed");
    }
}
