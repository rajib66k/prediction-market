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
     * @notice Redeems winning conditional tokens after resolution.
     */
    function redeemPositions(address conditionalTokens, address collateralToken, bytes32 conditionId) internal {
        IConditionalTokens(conditionalTokens)
            .redeemPositions(IERC20(collateralToken), COLLECTION_ID, conditionId, partition());
    }

    /**
     * @notice Reports the winning outcome to the Conditional Tokens contract.
     * @param conditionalTokens The Conditional Tokens contract.
     * @param questionId The question identifier.
     * @param yesWins True if the YES outcome wins, false if NO wins.
     */
    function reportPayouts(address conditionalTokens, bytes32 questionId, bool yesWins) internal {
        uint256[] memory payouts = new uint256[](2);

        if (yesWins) {
            payouts[0] = 1;
        } else {
            payouts[1] = 1;
        }

        IConditionalTokens(conditionalTokens).reportPayouts(questionId, payouts);
    }

    /**
     * @notice Returns the balance of a position token.
     */
    function balanceOf(address conditionalTokens, address account, uint256 positionId) internal view returns (uint256) {
        return IERC1155(conditionalTokens).balanceOf(account, positionId);
    }

    /**
     * @dev Transfers a position token from one address to another.
     * @param conditionalToken The address of the Conditional Tokens contract.
     * @param from The sender.
     * @param to The recipient.
     * @param tokenId The ID of the token to transfer.
     * @param amount The amount to transfer.
     */
    function transferPositionFrom(address conditionalToken, address from, address to, uint256 tokenId, uint256 amount)
        internal
    {
        IERC1155(conditionalToken).safeTransferFrom(from, to, tokenId, amount, "");
    }

    /**
     * @dev Transfers YES and NO position tokens from the pool.
     * @param conditionalTokens The address of the Conditional Tokens contract.
     * @param to The recipient.
     * @param yesPositionId The ID of the YES position.
     * @param noPositionId The ID of the NO position.
     * @param yesAmount The amount of YES tokens to transfer.
     * @param noAmount The amount of NO tokens to transfer.
     */
    function transferPositions(
        address conditionalTokens,
        address to,
        uint256 yesPositionId,
        uint256 noPositionId,
        uint256 yesAmount,
        uint256 noAmount
    ) internal {
        IERC1155(conditionalTokens)
            .safeBatchTransferFrom(
                address(this), to, positionIds(yesPositionId, noPositionId), amounts(yesAmount, noAmount), ""
            );
    }

    /**
     * @dev Creates the position ID array for batch operations.
     * @param yesPositionId The ID of the yes position.
     * @param noPositionId The ID of the no position.
     * @return ids The array of position IDs.
     */
    function positionIds(uint256 yesPositionId, uint256 noPositionId) private pure returns (uint256[] memory ids) {
        ids = new uint256[](2);
        ids[0] = yesPositionId;
        ids[1] = noPositionId;
    }

    /**
     * @dev Creates the amount array for batch operations.
     * @param yesAmount The amount of YES tokens.
     * @param noAmount The amount of NO tokens.
     * @return values The array of amounts.
     */
    function amounts(uint256 yesAmount, uint256 noAmount) private pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = yesAmount;
        values[1] = noAmount;
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
