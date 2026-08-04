// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "./../libraries/Math.sol";

/**
 * @title FeeLogic
 * @author Rajib Kumar Pradhan
 * @notice Handles fee calculation, fee indexing, and LP fee debt accounting.
 */
abstract contract FeeLogic {
    error FeeLogic__InvalidFee();

    using Math for uint256;

    /// @dev The current fee rate in 18-decimal precision.
    uint256 feeRate = 5e16;

    /// @dev The global fee index, used to track accumulated fees for LPs.
    uint256 feeIndex;

    /// @dev Mapping of user addresses to their fee debt,
    /// representing the amount of fees they have already claimed.
    mapping(address => uint256) feeDebt;

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
     * @notice Adds newly collected fees to the global fee index.
     * @param feeAmount The amount of fees collected.
     * @param totalLPSupply The total LP token supply.
     */
    function addFee(uint256 feeAmount, uint256 totalLPSupply) internal {
        if (totalLPSupply > 0) {
            feeIndex += feeAmount.div(totalLPSupply);
        }
    }

    /**
     * @notice Updates a user's fee debt.
     * @param user The user's address.
     * @param lpBalance The user's LP token balance.
     */
    function updateUser(address user, uint256 lpBalance) internal {
        feeDebt[user] = lpBalance.mul(feeIndex);
    }

    /**
     * @notice Returns the user's claimable fees and updates their fee debt.
     * @param user The user's address.
     * @param lpBalance The user's LP token balance.
     * @return amount The claimable fee amount.
     */
    function getClaimableAndUpdateFeeDebt(address user, uint256 lpBalance) internal returns (uint256 amount) {
        uint256 accumulated = lpBalance.mul(feeIndex);
        amount = accumulated - feeDebt[user];

        feeDebt[user] += amount;
    }
}
