// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title ConditionalTokensOperator
 * @author Rajib Kumar Pradhan
 * @notice Provides helper functions for managing conditional token positions.
 */
library ConditionalTokensOperator {
    bytes32 internal constant COLLECTION_ID = bytes32(0);

    /**
     * @dev Returns the balances of the yes and no positions.
     * @param yesPositionId The ID of the yes position.
     * @param noPositionId The ID of the no position.
     * @return yesBalance The balance of the yes position.
     * @return noBalance The balance of the no position.
     */
    function getPoolBalances(address conditionalTokens, uint256 yesPositionId, uint256 noPositionId)
        internal
        view
        returns (uint256 yesBalance, uint256 noBalance)
    {
        yesBalance = (IERC1155(conditionalTokens)).balanceOf(address(this), yesPositionId);
        noBalance = (IERC1155(conditionalTokens)).balanceOf(address(this), noPositionId);
    }

    /**
     * @dev Splits a position into two separate positions.
     * @param conditionalTokens The address of the conditional tokens contract.
     * @param collateralToken The address of the collateral token.
     * @param conditionId The ID of the condition.
     * @param amount The amount to split.
     */
    function splitPosition(address conditionalTokens, address collateralToken, bytes32 conditionId, uint256 amount)
        internal
    {
        IConditionalTokens(conditionalTokens)
            .splitPosition(IERC20(collateralToken), COLLECTION_ID, conditionId, partition(), amount);
    }

    /**
     * @dev Merges two positions into one.
     * @param conditionalTokens The address of the conditional tokens contract.
     * @param collateralToken The address of the collateral token.
     * @param conditionId The ID of the condition.
     * @param amount The amount to merge.
     */
    function mergePosition(address conditionalTokens, address collateralToken, bytes32 conditionId, uint256 amount)
        internal
    {
        IConditionalTokens(conditionalTokens)
            .mergePositions(IERC20(collateralToken), COLLECTION_ID, conditionId, partition(), amount);
    }

    /**
     * @notice Returns the partition for splitting and merging positions.
     * @return partitionArray The partition array.
     */
    function partition() private pure returns (uint256[] memory partitionArray) {
        partitionArray = new uint256[](2);
        partitionArray[0] = 1;
        partitionArray[1] = 2;
    }
}
