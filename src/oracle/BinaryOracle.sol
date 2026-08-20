// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {DataTypes} from "./../types/DataTypes.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBinaryOracle} from "./../interfaces/IBinaryOracle.sol";
import {IPredictionMarket} from "./../interfaces/IPredictionMarket.sol";

/**
 * @title BinaryOracle
 * @notice Resolves a binary Conditional Tokens condition from a Chainlink price feed.
 */
contract BinaryOracle is Ownable, IBinaryOracle {
    error BinaryOracle__ZeroAddress();
    error BinaryOracle__InvalidQuestionId();
    error BinaryOracle__InvalidExpiry();
    error BinaryOracle__InvalidStrike();
    error BinaryOracle__InvalidSettlementDelay();
    error BinaryOracle__AlreadyResolved();
    error BinaryOracle__TooEarly();
    error BinaryOracle__InvalidPrice();
    error BinaryOracle__InvalidRound();
    error BinaryOracle__PreviousRoundInvalid();
    error BinaryOracle__PreviousRoundAfterExpiry();
    error BinaryOracle__CurrentRoundBeforeExpiry();
    error BinaryOracle__SettlementTooLate();
    error BinaryOracle__FeedRoundMismatch();
    error BinaryOracle__TimeoutNotReached();

    /// @notice Market data for each question.
    mapping(bytes32 => DataTypes.MarketData) sMarketData;

    /// @notice Resolution data for each question.
    mapping(bytes32 => DataTypes.ResolutionData) sResolutionData;

    /// @notice Emitted when a market is resolved.
    event MarketResolved(
        bytes32 indexed questionId, uint80 indexed roundId, int256 price, uint256 updatedAt, DataTypes.YesWins yesWins
    );

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Sets up a market for resolution.
     * @param questionId Unique identifier of the prediction-market question.
     * @param marketData Market data to set up the market.
     * @dev This function can only be called by the owner of the contract.
     */
    function setUpMarket(DataTypes.MarketData memory marketData, bytes32 questionId) external onlyOwner {
        if (questionId == bytes32(0)) revert BinaryOracle__InvalidQuestionId();
        if (marketData.market == address(0) || marketData.priceFeed == address(0)) revert BinaryOracle__ZeroAddress();
        // forge-lint: disable-next-line(block-timestamp)
        if (marketData.resolveTime <= block.timestamp) revert BinaryOracle__InvalidExpiry();
        if (marketData.strike <= 0) revert BinaryOracle__InvalidStrike();
        if (marketData.maxSettlementDelay == 0) revert BinaryOracle__InvalidSettlementDelay();

        sMarketData[questionId] = marketData;
    }

    /**
     * @notice Resolve the market using a Chainlink round. Anyone may call this function.
     * @param roundId The Chainlink round ID to use for settlement.
     * @dev The round must be the first round after expiry, and the previous round must be before expiry.
     *      The price must be valid and non-negative. The settlement round must not be too late after expiry.
     *      The market must not have already been resolved. The current timestamp must be after the expiry.
     */
    function resolve(bytes32 questionId, uint80 roundId) external {
        DataTypes.MarketData memory marketData = sMarketData[questionId];

        if (roundId == 0) revert BinaryOracle__InvalidRound();
        if (sResolutionData[questionId].resolved) revert BinaryOracle__AlreadyResolved();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < marketData.resolveTime) revert BinaryOracle__TooEarly();

        (uint80 returnedRoundId, int256 price,, uint256 updatedAt,) =
            AggregatorV3Interface(marketData.priceFeed).getRoundData(roundId);

        if (returnedRoundId != roundId) revert BinaryOracle__FeedRoundMismatch();
        if (price <= 0) revert BinaryOracle__InvalidPrice();
        if (updatedAt < marketData.resolveTime) revert BinaryOracle__CurrentRoundBeforeExpiry();
        if (updatedAt > marketData.resolveTime + marketData.maxSettlementDelay) {
            revert BinaryOracle__SettlementTooLate();
        }

        (uint80 previousRoundId,,, uint256 previousUpdatedAt,) =
            AggregatorV3Interface(marketData.priceFeed).getRoundData(roundId - 1);

        if (previousRoundId != roundId - 1) revert BinaryOracle__PreviousRoundInvalid();
        if (previousUpdatedAt >= marketData.resolveTime) revert BinaryOracle__PreviousRoundAfterExpiry();

        bool yes = price >= marketData.strike;

        sResolutionData[questionId] = DataTypes.ResolutionData({
            resolved: true,
            yesWins: yes ? DataTypes.YesWins.TRUE : DataTypes.YesWins.FALSE,
            settlementRoundId: roundId,
            settlementPrice: price,
            settlementTimestamp: updatedAt
        });

        emit MarketResolved(
            questionId, roundId, price, updatedAt, yes ? DataTypes.YesWins.TRUE : DataTypes.YesWins.FALSE
        );

        IPredictionMarket(marketData.market)
            .resolveMarket(questionId, yes ? DataTypes.YesWins.TRUE : DataTypes.YesWins.FALSE);
    }

    function resolveByTimeout(bytes32 questionId) external {
        DataTypes.MarketData storage marketData = sMarketData[questionId];

        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < marketData.resolveTime + marketData.maxSettlementDelay) {
            revert BinaryOracle__TimeoutNotReached();
        }
        if (sResolutionData[questionId].resolved) revert BinaryOracle__AlreadyResolved();

        sResolutionData[questionId] = DataTypes.ResolutionData({
            resolved: true,
            yesWins: DataTypes.YesWins.UNRESOLVED,
            settlementRoundId: 0,
            settlementPrice: 0,
            settlementTimestamp: 0
        });

        emit MarketResolved(questionId, 0, 0, 0, DataTypes.YesWins.UNRESOLVED);
        IPredictionMarket(marketData.market).resolveMarket(questionId, DataTypes.YesWins.UNRESOLVED);
    }

    /**
     * @notice Returns whether the market is currently resolvable.
     * This does not determine the settlement round.
     */
    function canResolve(bytes32 questionId) external view returns (bool) {
        // forge-lint: disable-next-line(block-timestamp)
        return !sResolutionData[questionId].resolved && block.timestamp >= sMarketData[questionId].resolveTime;
    }

    /**
     * @notice Returns the configured strike in chainlink native decimals.
     */
    function strikeWithDecimals(bytes32 questionId) external view returns (int256) {
        return sMarketData[questionId].strike;
    }

    function getMarketData(bytes32 questionId) external view returns (DataTypes.MarketData memory) {
        return sMarketData[questionId];
    }

    function getResolutionData(bytes32 questionId) external view returns (DataTypes.ResolutionData memory) {
        return sResolutionData[questionId];
    }
}
