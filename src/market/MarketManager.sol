// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DataTypes} from "./../types/DataTypes.sol";
import {IPredictionMarket} from "./../interfaces/IPredictionMarket.sol";
import {IBinaryOracle} from "./../interfaces/IBinaryOracle.sol";

/**
 * @title MarketManager
 * @notice Central management and registry contract for prediction markets.
 * @dev This contract does not deploy prediction markets. Markets and their associated LP tokens are
 * deployed through a deployment script, and then registered through register market function.
 */
contract MarketManager is Ownable {
    error MarketManager__MarketAlreadyExists();
    error MarketManager__InvalidAddress();
    error MarketManager__MarketNotFound();

    /// @notice Canonical market address for each question.
    mapping(bytes32 => address) internal sMarkets;

    /// @notice Emitted when a market is registered.
    event MarketCreated(address indexed market, bytes32 indexed questionId);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Registers an already-deployed prediction market.
     * @dev The deployment script deploys PredictionMarket and LPToken first,
     *      then calls this function to make the market official.
     * @param data MarketData struct containing market parameters.
     * @param questionId Unique identifier of the prediction-market question.
     * @param oracle Address of the oracle that will resolve the market.
     */
    function registerMarket(DataTypes.MarketData memory data, bytes32 questionId, address oracle) external onlyOwner {
        if (questionId == bytes32(0)) revert MarketManager__InvalidAddress();
        if (sMarkets[questionId] != address(0)) revert MarketManager__MarketAlreadyExists();

        sMarkets[questionId] = data.market;
        IBinaryOracle(oracle).setUpMarket(data, questionId);
        emit MarketCreated(data.market, questionId);
    }

    /**
     * @notice Updates the trading fee of a registered market.
     * @dev The market must have been registered through this factory.
     * @param newFee New trading fee expressed in 18-decimal precision.
     * @param questionId Identifier of the registered market.
     */
    function updateFactoryFee(uint256 newFee, bytes32 questionId) external onlyOwner {
        address market = sMarkets[questionId];
        if (market == address(0)) revert MarketManager__MarketNotFound();

        IPredictionMarket(market).updateFeeRate(newFee);
    }

    /**
     * @notice Returns whether a market is registered.
     * @param questionId Identifier of the registered market.
     */
    function isRegisteredMarket(bytes32 questionId) external view returns (bool) {
        return sMarkets[questionId] != address(0);
    }
}
