// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {DataTypes} from "./../types/DataTypes.sol";

interface IPredictionMarket {
    function updateFeeRate(uint256 newRate) external;

    function buyYes(uint256 collateralAmount, uint256 minOutcomeTokens) external;

    function buyNo(uint256 collateralAmount, uint256 minOutcomeTokens) external;

    function sellYes(uint256 collateralAmount, uint256 maxOutcomeTokens) external;

    function sellNo(uint256 collateralAmount, uint256 maxOutcomeTokens) external;

    function addInitialLiquidity(uint256 collateralAmount) external;

    function addLiquidity(uint256 collateralAmount) external;

    function removeLiquidity(uint256 sharesToBurn) external;

    function refundLiquidity() external;

    function transferLiquidityToken(address to, uint256 amount) external;

    function claimFees() external;

    function resolveMarket(bytes32 resovingQuestionId, DataTypes.YesWins yesWins) external;

    function redeem() external;
}
