// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "./Math.sol";

/**
 * @title Pricing
 * @author Rajib Kumar Pradhan
 * @notice Library for pricing trades in a two-outcome constant-product market maker.
 */
library Pricing {
    error Pricing__InsufficientLiquidity();

    using Math for uint256;

    /**
     * @notice Calculates the outcome tokens received for a fee-adjusted collateral input.
     * @dev Computes the trade amount while preserving the constant-product invariant. Intermediate calculations
     *      use fixed-point precision to minimize rounding error before the final ceiling division.
     * @param buyReserve Current reserve of the outcome being purchased.
     * @param otherReserve Current reserve of the opposite outcome.
     * @param collateralInMinusFee Collateral amount after deducting trading fees.
     * @return amountOut The amount of outcome tokens received.
     */
    function buyAmount(uint256 buyReserve, uint256 otherReserve, uint256 collateralInMinusFee)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (buyReserve == 0 || otherReserve == 0) revert Pricing__InsufficientLiquidity();
        uint256 endingReserve = Math.integerMulDivCeil(buyReserve, otherReserve, otherReserve + collateralInMinusFee);

        amountOut = buyReserve + collateralInMinusFee - endingReserve;
    }

    /**
     * @notice Calculates the outcome tokens required to receive a desired collateral amount.
     * @dev Computes the trade amount while preserving the constant-product invariant. Intermediate calculations
     *      use fixed-point precision to minimize rounding error before the final ceiling division.
     * @param sellReserve Current reserve of the outcome being sold.
     * @param otherReserve Current reserve of the opposite outcome.
     * @param collateralOutPlusFee Collateral amount including the trading fee adjustment.
     * @return amountIn The amount of outcome tokens required to receive the desired collateral.
     */
    function sellAmount(uint256 sellReserve, uint256 otherReserve, uint256 collateralOutPlusFee)
        internal
        pure
        returns (uint256 amountIn)
    {
        if (sellReserve == 0 || otherReserve == 0 || collateralOutPlusFee >= otherReserve) {
            revert Pricing__InsufficientLiquidity();
        }

        uint256 endingReserve = Math.integerMulDivCeil(sellReserve, otherReserve, otherReserve - collateralOutPlusFee);

        amountIn = collateralOutPlusFee + endingReserve - sellReserve;
    }
}
