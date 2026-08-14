// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {LPToken} from "./../src/tokens/LPToken.sol";
import {PredictionMarket} from "./../src/market/PredictionMarket.sol";
import {MarketManager} from "./../src/market/MarketManager.sol";
import {BinaryOracle} from "./../src/oracle/BinaryOracle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployCore is Script {
    function run()
        external
        returns (
            address conditionalTokens,
            MarketManager manager,
            BinaryOracle oracle,
            PredictionMarket market,
            LPToken lpToken,
            HelperConfig.NetworkConfig memory netConfig
        )
    {
        HelperConfig config = new HelperConfig();
        netConfig = config.getNetworkConfig();

        vm.startBroadcast(netConfig.deployerKey);
        conditionalTokens = vm.deployCode("artifacts/ConditionalTokens.json");
        oracle = new BinaryOracle();
        lpToken = new LPToken();
        market = new PredictionMarket(netConfig.asset, conditionalTokens, address(oracle));
        manager = new MarketManager(address(market), address(lpToken), address(oracle));
        lpToken.transferOwnership(address(manager));
        market.transferOwnership(address(manager));
        oracle.transferOwnership(address(manager));
        vm.stopBroadcast();

        _saveCore(address(conditionalTokens), address(manager), address(oracle), address(market), address(lpToken));
    }

    function _saveCore(address condToken, address manager, address oracle, address market, address lpToken) internal {
        string memory basePath = string.concat("deployments/", vm.toString(block.chainid));
        vm.createDir(string.concat(basePath, "/markets"), true);

        string memory obj = "core";

        vm.serializeAddress(obj, "manager", manager);
        vm.serializeAddress(obj, "conditionalTokens", condToken);
        vm.serializeAddress(obj, "oracle", oracle);
        vm.serializeAddress(obj, "market", market);
        string memory json = vm.serializeAddress(obj, "lpToken", lpToken);

        vm.writeJson(json, string.concat(basePath, "/core.json"));
    }
}
