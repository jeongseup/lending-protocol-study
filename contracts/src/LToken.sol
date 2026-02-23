// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title LToken — 예치 영수증 토큰
/// @notice 사용자가 렌딩 풀에 예치하면 받는 토큰 (Aave의 aToken과 유사)
/// @notice Receipt token received when depositing to lending pool (similar to Aave's aToken)
/// @dev Compound의 cToken 모델: 환율이 시간에 따라 증가
/// @dev Uses Compound's cToken model: exchange rate grows over time
/// @dev 사용자의 LToken 잔액 × 환율 = 실제 예치금 + 이자
/// @dev User's LToken balance × exchange rate = actual deposit + interest

contract LToken is ERC20 {
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

    /// @param _name 토큰 이름 / Token name (e.g., "Lending ETH")
    /// @param _symbol 토큰 심볼 / Token symbol (e.g., "lETH")
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

    /// @notice LToken을 민팅합니다 (예치 시 호출)
    /// @notice Mint LTokens (called on deposit)
    /// @param to 수령자 주소 / Recipient address
    /// @param amount 민팅할 양 / Amount to mint
    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }

    /// @notice LToken을 소각합니다 (출금 시 호출)
    /// @notice Burn LTokens (called on withdraw)
    /// @param from 소각 대상 주소 / Address to burn from
    /// @param amount 소각할 양 / Amount to burn
    function burn(address from, uint256 amount) external onlyPool {
        _burn(from, amount);
    }
}
