// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ILPToken} from "./../interfaces/ILPToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LPToken
 * @author Rajib Kumar Pradhan
 * @notice Token representing a user's supplied liquidity position.
 */
contract LPToken is ILPToken, ERC20, Ownable {
    error LPToken__NotZeroAddress();
    error LPToken__MustBeMoreThanZero();
    error LPToken__OperationNotSupported();

    constructor(string memory tokenName, string memory symbol) Ownable(msg.sender) ERC20(tokenName, symbol) {}

    /**
     * @notice Mints LP tokens to a user.
     * @param to The address receiving the LP tokens.
     * @param amount The amount to mint.
     */
    function mint(address to, uint256 amount) external override onlyOwner {
        if (to == address(0)) revert LPToken__NotZeroAddress();
        if (amount == 0) revert LPToken__MustBeMoreThanZero();

        _mint(to, amount);
    }

    /**
     * @notice Burns LP tokens from a user.
     * @param from The address whose LP tokens are burned.
     * @param amount The amount to burn.
     */
    function burn(address from, uint256 amount) external override onlyOwner {
        if (from == address(0)) revert LPToken__NotZeroAddress();
        if (amount == 0) revert LPToken__MustBeMoreThanZero();

        _burn(from, amount);
    }

    /**
     * @notice Transfers lp tokens on behalf of a user.
     * @dev user can call this function through market.
     * @param from The address tokens are transferred from.
     * @param to The address receiving the tokens.
     * @param amount The amount to transfer.
     * @return True after successful transfer.
     */
    function transferOnBehalf(address from, address to, uint256 amount) external override onlyOwner returns (bool) {
        if (amount == 0) revert LPToken__MustBeMoreThanZero();

        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Lp tokens cannot be transferred directly.
     */
    function transfer(address, uint256) public virtual override(ERC20, IERC20) returns (bool) {
        revert LPToken__OperationNotSupported();
    }

    /**
     * @dev LP tokens cannot be transferred using allowances.
     */
    function transferFrom(address, address, uint256) public virtual override(ERC20, IERC20) returns (bool) {
        revert LPToken__OperationNotSupported();
    }

    /**
     * @dev LP tokens do not support approvals.
     */
    function approve(address, uint256) public virtual override(ERC20, IERC20) returns (bool) {
        revert LPToken__OperationNotSupported();
    }

    /**
     * @notice Returns zero since allowances are not supported.
     */
    function allowance(address, address) public view virtual override(ERC20, IERC20) returns (uint256) {
        return 0;
    }
}
