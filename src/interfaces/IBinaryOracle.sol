// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {DataTypes} from "./../types/DataTypes.sol";

interface IBinaryOracle {
    function setUpMarket(DataTypes.MarketData calldata marketData, bytes32 questionId) external;

    function resolve(bytes32 questionId, uint80 roundId) external;

    function resolveByTimeout(bytes32 questionId) external;

    function canResolve(bytes32 questionId) external view returns (bool);

    function strikeWithDecimals(bytes32 questionId) external view returns (int256);
}
