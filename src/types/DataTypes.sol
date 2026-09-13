// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/**
 * @title DataTypes
 * @author Rajib Kumar Pradhan
 * @notice Collection data types used throughout the prediction market.
 */
library DataTypes {
    enum YesWins {
        TRUE,
        FALSE,
        UNRESOLVED
    }

    struct MarketInitParams {
        string question;
        bytes32 questionId;
        uint256 resolveTime;
        uint256 liquidityDeadline;
        uint256 initialLiquidityTarget;
    }

    struct MarketData {
        address market;
        address priceFeed;
        int256 strike;
        uint256 resolveTime;
        uint256 maxSettlementDelay;
    }

    struct ResolutionData {
        bool resolved;
        YesWins yesWins;
        uint80 settlementRoundId;
        int256 settlementPrice;
        uint256 settlementTimestamp;
    }
}
