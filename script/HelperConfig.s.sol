// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address asset;
        uint256 deployerKey;
    }

    struct MarketConfig {
        address priceFeed;
        bytes32 questionId;
        int256 strike;
        uint256 resolveTime;
        uint256 liquidityDeadline;
        uint256 maxSettlementDelay;
        uint256 initialLiquidityTarget;
        string lpTokenName;
        string lpTokenSymbol;
    }

    NetworkConfig public networkConfig;
    MarketConfig public marketConfig;

    string public question = "Will Ethereum (ETH) be at or above $5,000 USD at 11:59 PM UTC on December 31, 2026?";
    string public lpTokenName = "ETH at or above $5,000 USD 11:59 PM UTC December 31 2026";
    string public lpTokenSymbol = "ETH-$5,000-USD-11:59-PM-UTC-DEC-31-2026";

    int256 public constant STRIKE = 5000e18;
    uint256 public constant RESOLVE_TIME = 1798761599;
    uint256 public constant LIQUIDATION_DEADLINE = 1798675199;
    uint256 public constant MAX_SETTLEMENT_DELAY = 1 days;
    uint256 public constant INITIAL_LIQUIDITY_TARGET = 100000e18;

    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public constant SEPOLIA_CHAINID = 11155111;

    uint8 public constant FEED_DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;

    constructor() {
        if (block.chainid == SEPOLIA_CHAINID) {
            (networkConfig, marketConfig) = getSepoliaConfig();
        } else {
            (networkConfig, marketConfig) = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory netConfig, MarketConfig memory marConfig) {
        bytes32 questionId = keccak256(abi.encode(question, RESOLVE_TIME, block.chainid));

        netConfig = NetworkConfig({
            asset: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });

        marConfig = MarketConfig({
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            questionId: questionId,
            strike: STRIKE,
            resolveTime: RESOLVE_TIME,
            liquidityDeadline: LIQUIDATION_DEADLINE,
            maxSettlementDelay: MAX_SETTLEMENT_DELAY,
            initialLiquidityTarget: INITIAL_LIQUIDITY_TARGET,
            lpTokenName: lpTokenName,
            lpTokenSymbol: lpTokenSymbol
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory netConfig, MarketConfig memory marConfig) {
        if (networkConfig.asset != address(0)) {
            return (networkConfig, marketConfig);
        }

        bytes32 questionId = keccak256(abi.encode(question, RESOLVE_TIME, block.chainid));

        vm.startBroadcast();
        ERC20Mock asset = new ERC20Mock();
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(FEED_DECIMALS, ETH_USD_PRICE);
        vm.stopBroadcast();

        netConfig = NetworkConfig({asset: address(asset), deployerKey: DEFAULT_ANVIL_KEY});

        marConfig = MarketConfig({
            priceFeed: address(wethUsdPriceFeed),
            questionId: questionId,
            strike: STRIKE,
            resolveTime: RESOLVE_TIME,
            liquidityDeadline: LIQUIDATION_DEADLINE,
            maxSettlementDelay: MAX_SETTLEMENT_DELAY,
            initialLiquidityTarget: INITIAL_LIQUIDITY_TARGET,
            lpTokenName: lpTokenName,
            lpTokenSymbol: lpTokenSymbol
        });
    }

    function getNetworkConfig() external view returns (NetworkConfig memory) {
        return networkConfig;
    }

    function getMarketConfig() external view returns (MarketConfig memory) {
        return marketConfig;
    }
}
