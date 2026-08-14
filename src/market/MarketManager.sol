// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DataTypes} from "./../types/DataTypes.sol";
import {IPredictionMarket} from "./../interfaces/IPredictionMarket.sol";
import {IBinaryOracle} from "./../interfaces/IBinaryOracle.sol";
import {ILPToken} from "./../interfaces/ILPToken.sol";

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

    using Clones for address;

    /// @notice Address of the market implementation used for cloning new markets.
    address public immutable marketImplementation;

    /// @notice Address of the LP token implementation used for cloning new LP tokens.
    address public immutable lpTokenImplementation;

    /// @notice Address of the oracle used for market resolution.
    address public immutable oracle;

    /// @notice Canonical market address for each question.
    mapping(bytes32 => address) internal sMarkets;

    /// @notice Emitted when a market is registered.
    event MarketCreated(address indexed market, address lpToken, bytes32 questionId);

    constructor(address marketAddress, address lpTokenAddress, address oracleAddress) Ownable(msg.sender) {
        if (marketAddress == address(0) || lpTokenAddress == address(0) || oracleAddress == address(0)) {
            revert MarketManager__InvalidAddress();
        }

        marketImplementation = marketAddress;
        lpTokenImplementation = lpTokenAddress;
        oracle = oracleAddress;
    }

    /**
     * @notice Deploy and registers new prediction market from existing implementations.
     * @param params MarketInitParams struct containing market initialization parameters.
     * @param data MarketData struct containing market data for oracle.
     * @param lpTokenName Name of the LP token.
     * @param lpTokenSymbol Symbol of the LP token.
     * @return market Address of the registered market.
     * @return lpToken Address of the associated LP token.
     * @dev This function deploys a new market and LP token using the provided parameters,
     *      and registers them in the manager.
     */
    function cloneAndRegisterMarket(
        DataTypes.MarketInitParams calldata params,
        DataTypes.MarketData calldata data,
        string calldata lpTokenName,
        string calldata lpTokenSymbol
    ) external onlyOwner returns (address market, address lpToken) {
        bytes32 questionId = params.questionId;
        if (sMarkets[questionId] != address(0)) revert MarketManager__MarketAlreadyExists();

        DataTypes.MarketData memory newData = data;

        market = marketImplementation.clone();
        lpToken = lpTokenImplementation.clone();

        newData.market = market;
        sMarkets[questionId] = market;

        ILPToken(lpToken).initialize(market, lpTokenName, lpTokenSymbol);
        IPredictionMarket(market).initialize(params, lpToken);
        IBinaryOracle(oracle).setUpMarket(newData, questionId);

        emit MarketCreated(market, lpToken, questionId);
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

    function getMarket(bytes32 questionId) external view returns (address) {
        return sMarkets[questionId];
    }

    function getMarketImplementation() external view returns (address) {
        return marketImplementation;
    }

    function getLPTokenImplementation() external view returns (address) {
        return lpTokenImplementation;
    }

    function getOracle() external view returns (address) {
        return oracle;
    }
}
