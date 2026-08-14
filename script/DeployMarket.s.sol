// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {LPToken} from "./../src/tokens/LPToken.sol";
import {PredictionMarket} from "./../src/market/PredictionMarket.sol";
import {MarketManager} from "./../src/market/MarketManager.sol";
import {DataTypes} from "./../src/types/DataTypes.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMarket is Script {
    function run() external returns (address market, address lpToken) {
        HelperConfig config = new HelperConfig();
        HelperConfig.NetworkConfig memory netConfig = config.getNetworkConfig();
        HelperConfig.MarketConfig memory marketConfig = config.getMarketConfig();

        string memory corePath = string.concat("deployments/", vm.toString(block.chainid), "/core.json");
        string memory coreJson = vm.readFile(corePath);

        address manager = vm.parseJsonAddress(coreJson, ".manager");

        DataTypes.MarketInitParams memory params = DataTypes.MarketInitParams({
            questionId: marketConfig.questionId,
            resolveTime: marketConfig.resolveTime,
            liquidityDeadline: marketConfig.liquidityDeadline,
            initialLiquidityTarget: marketConfig.initialLiquidityTarget
        });

        DataTypes.MarketData memory data = DataTypes.MarketData({
            market: address(0),
            priceFeed: marketConfig.priceFeed,
            strike: marketConfig.strike,
            resolveTime: marketConfig.resolveTime,
            maxSettlementDelay: marketConfig.maxSettlementDelay
        });

        vm.startBroadcast(netConfig.deployerKey);
        (market, lpToken) = MarketManager(manager)
            .cloneAndRegisterMarket(params, data, marketConfig.lpTokenName, marketConfig.lpTokenName);
        vm.stopBroadcast();

        _saveMarket(market, lpToken);
    }

    function _saveMarket(address market, address lpToken) internal {
        string memory path = string.concat(
            "deployments/", vm.toString(block.chainid), "/markets/", vm.toString(block.timestamp), ".json"
        );
        string memory obj = "market";
        vm.serializeAddress(obj, "market", market);
        string memory json = vm.serializeAddress(obj, "lpToken", lpToken);
        vm.writeJson(json, path);
    }
}
