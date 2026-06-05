// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Thin wrapper around OZ ERC20 — identical constructor signature
/// to YulERC20 so both can be benchmarked with the same setup code.
contract OZToken is ERC20 {
    uint8 private _dec;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name_, symbol_) {
        _dec = decimals_;
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }
}