// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/**
 * @title DataTypes
 * @author Rajib Kumar Pradhan
 * @notice Collection data types used throughout the prediction market.
 */
library DataTypes {
    struct MarketInitParams {
        address oracle;
        address collateral;
        address conditionalToken;
        address lpToken;

        bytes32 questionId;

        uint256 resolveTime;
        uint256 liquidityDeadline;
        uint256 initialLiquidityTarget;
    }
}
