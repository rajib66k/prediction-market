// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ILPToken} from "./../interfaces/ILPToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LPToken
 * @author Rajib Kumar Pradhan
 * @notice Token representing a user's supplied liquidity position.
 */
contract LPToken is ILPToken, ERC20, Ownable {
    error LPToken__NotZeroAddress();
    error LPToken__MustBeMoreThanZero();

    constructor(string memory tokenName, string memory symbol) Ownable(msg.sender) ERC20(tokenName, symbol) {}

    /**
     * @notice Mints LP tokens to a user.
     * @param to The address receiving the LP tokens.
     * @param amount The amount to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert LPToken__NotZeroAddress();
        if (amount == 0) revert LPToken__MustBeMoreThanZero();

        _mint(to, amount);
    }

    /**
     * @notice Burns LP tokens from a user.
     * @param from The address whose LP tokens are burned.
     * @param amount The amount to burn.
     */
    function burn(address from, uint256 amount) external onlyOwner {
        if (from == address(0)) revert LPToken__NotZeroAddress();
        if (amount == 0) revert LPToken__MustBeMoreThanZero();

        _burn(from, amount);
    }
}
