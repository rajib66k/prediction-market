// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "./../libraries/Math.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FeeLogic
 * @author Rajib Kumar Pradhan
 * @notice Handles fee calculation and fee rate management for pools where
 * fees are added directly to the liquidity reserves.
 */
abstract contract FeeLogic {
    error FeeLogic__InvalidFee();
    error FeeLogic__NoClaimableAmountLeft();

    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @dev The current fee rate in 18-decimal precision.
    uint256 feeRate;

    /// @dev The global fee index, used to track accumulated fees for LPs.
    uint256 feeIndex;

    /// @dev Mapping of user addresses to their fee debt,
    /// representing the amount of fees they have already claimed.
    mapping(address => uint256) feeDebt;

    /// @dev Claimable fees stored for LPs.
    mapping(address => uint256) internal pendingFees;

    uint256 internal constant MAX_FEE = 1e18;

    /// @notice Emitted when the fee rate is updated.
    event FeeUpdated(uint256 oldRate, uint256 newRate);

    /**
     * @notice Updates the protocol fee rate.
     * @param rate The new fee rate in 18-decimal precision.
     */
    function updateFee(uint256 rate) internal {
        if (rate > MAX_FEE) revert FeeLogic__InvalidFee();

        uint256 oldRate = feeRate;

        feeRate = rate;
        emit FeeUpdated(oldRate, rate);
    }

    /**
     * @notice Calculates the fee for a given amount.
     * @param amount The amount to calculate the fee on.
     * @return The calculated fee.
     */
    function calculateFee(uint256 amount) internal view returns (uint256) {
        return amount.mul(feeRate);
    }

    /**
     * @notice Calculates the fee required for a desired net output amount.
     * @dev Returns the fee that must be added so the recipient receives amount exactly after fees.
     * @param amount Desired net output amount.
     * @return The fee amount.
     */
    function calculateFeeFromNet(uint256 amount) internal view returns (uint256) {
        return amount.integerMulDivCeil(feeRate, Math.PRECISION - feeRate);
    }

    /**
     * @notice Updates a user's fee debt.
     * @param user The user's address.
     * @param lpBalance The user's LP token balance.
     */
    function updateUser(address user, uint256 lpBalance) internal {
        feeDebt[user] = lpBalance.mulFloor(feeIndex);
    }

    /**
     * @notice Adds newly collected fees to the global fee index.
     * @param feeAmount The amount of fees collected.
     * @param totalLPSupply The total LP token supply.
     */
    function addFee(uint256 feeAmount, uint256 totalLPSupply) internal {
        feeIndex += feeAmount.divFloor(totalLPSupply);
    }

    /**
     * @dev Updates a user's pending fees before balance changes.
     * @param user The user's address.
     * @param lpToken The LP token address associated with the fees.
     */
    function updatePendingFee(address user, address lpToken) internal {
        uint256 balance = IERC20(lpToken).balanceOf(user);
        uint256 accumulated = balance.mulFloor(feeIndex);

        if (accumulated > feeDebt[user]) {
            pendingFees[user] += accumulated - feeDebt[user];
        }

        feeDebt[user] = accumulated;
    }

    /**
     * @dev Updates the user's pending fees and transfers them to the user.
     * @param lpToken The LP token address associated with the fees.
     * @param collateral The collateral token address to transfer fees in.
     */
    function claimFeesUser(address lpToken, address collateral) internal {
        updatePendingFee(msg.sender, lpToken);

        uint256 amount = pendingFees[msg.sender];
        if (amount == 0) revert FeeLogic__NoClaimableAmountLeft();

        pendingFees[msg.sender] = 0;
        IERC20(collateral).safeTransfer(msg.sender, amount);
    }
}
