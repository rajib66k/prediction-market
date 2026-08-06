// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "./../libraries/Math.sol";

/**
 * @title FeeLogic
 * @author Rajib Kumar Pradhan
 * @notice Handles fee calculation and fee rate management for pools where
 * fees are added directly to the liquidity reserves.
 */
abstract contract FeeLogic {
    error FeeLogic__InvalidFee();

    using Math for uint256;

    /// @dev The current fee rate in 18-decimal precision.
    uint256 feeRate = 5e16;

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
}
