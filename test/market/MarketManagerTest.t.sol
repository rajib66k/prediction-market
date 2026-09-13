// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {MarketManager} from "../../src/market/MarketManager.sol";
import {PredictionMarket} from "../../src/market/PredictionMarket.sol";
import {LPToken} from "../../src/tokens/LPToken.sol";
import {BinaryOracle} from "../../src/oracle/BinaryOracle.sol";
import {DataTypes} from "../../src/types/DataTypes.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployCore} from "../../script/DeployCore.s.sol";
import {DeployMarket} from "../../script/DeployMarket.s.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract MarketManagerTest is Test {
    HelperConfig.NetworkConfig public networkConfig;
    HelperConfig.MarketConfig public marketConfig;

    PredictionMarket public marketImpl;
    LPToken public lpTokenImpl;

    address public ct;

    MarketManager public manager;
    BinaryOracle public oracle;

    PredictionMarket public market;
    LPToken public lpToken;

    address public user = makeAddr("user");

    address public constant ANVIL_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    event MarketCreated(address indexed market, address lpToken, bytes32 questionId);

    function setUp() public {
        DeployCore deployCore = new DeployCore();
        DeployMarket deployMarket = new DeployMarket();

        address marketAddress;
        address lpTokenAddress;

        (ct, manager, oracle, marketImpl, lpTokenImpl, networkConfig) = deployCore.run();
        (marketAddress, lpTokenAddress, marketConfig) = deployMarket.run();

        market = PredictionMarket(marketAddress);
        lpToken = LPToken(lpTokenAddress);
    }

    function testConstructorRevertsIfZeroAddress() public {
        vm.expectRevert(MarketManager.MarketManager__InvalidAddress.selector);
        new MarketManager(address(0), address(lpToken), address(oracle));

        vm.expectRevert(MarketManager.MarketManager__InvalidAddress.selector);
        new MarketManager(address(marketImpl), address(0), address(oracle));

        vm.expectRevert(MarketManager.MarketManager__InvalidAddress.selector);
        new MarketManager(address(marketImpl), address(marketImpl), address(0));
    }

    function testConstructor() public {
        MarketManager localManager = new MarketManager(address(marketImpl), address(lpToken), address(oracle));

        assertEq(address(marketImpl), localManager.getMarketImplementation());
        assertEq(address(lpToken), localManager.getLPTokenImplementation());
        assertEq(address(oracle), localManager.getOracle());
    }

    function testCloneAndRegisterMarketRevertsIfNotOwnerOrMarketAlreadyExist() public {
        DataTypes.MarketInitParams memory params = DataTypes.MarketInitParams({
            question: marketConfig.question,
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

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        manager.cloneAndRegisterMarket(params, data, marketConfig.lpTokenName, marketConfig.lpTokenName);

        vm.prank(ANVIL_ADDRESS);
        vm.expectRevert(MarketManager.MarketManager__MarketAlreadyExists.selector);
        manager.cloneAndRegisterMarket(params, data, marketConfig.lpTokenName, marketConfig.lpTokenName);
    }

    function testCloneAndRegisterMarket() public {
        bytes32 questionId = keccak256(abi.encode("New Question", marketConfig.resolveTime, block.chainid));

        DataTypes.MarketInitParams memory params = DataTypes.MarketInitParams({
            question: marketConfig.question,
            questionId: questionId,
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

        vm.prank(ANVIL_ADDRESS);
        vm.expectEmit(false, false, false, false);
        emit MarketCreated(address(0), address(0), questionId);
        (address marketAddress, address lpTokenAddress) =
            manager.cloneAndRegisterMarket(params, data, marketConfig.lpTokenName, marketConfig.lpTokenName);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        PredictionMarket(marketAddress).initialize(params, lpTokenAddress);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        LPToken(lpTokenAddress).initialize(marketAddress, marketConfig.lpTokenName, marketConfig.lpTokenSymbol);

        DataTypes.MarketData memory storedData = oracle.getMarketData(questionId);

        assertEq(marketAddress, storedData.market);
        assertEq(data.priceFeed, storedData.priceFeed);
        assertEq(data.strike, storedData.strike);
        assertEq(data.resolveTime, storedData.resolveTime);
        assertEq(data.maxSettlementDelay, storedData.maxSettlementDelay);
        assertEq(marketAddress, manager.getMarket(questionId));
    }

    function testUpdateFactoryFeeRevertsIfNotOwnerOrMarketAddressIsZero() public {
        uint256 newFee = 2e16;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        manager.updateFactoryFee(newFee, marketConfig.questionId);

        vm.prank(ANVIL_ADDRESS);
        vm.expectRevert(MarketManager.MarketManager__MarketNotFound.selector);
        manager.updateFactoryFee(newFee, bytes32(0));
    }

    function testUpdateFactoryFee() public {
        uint256 newFee = 2e16;

        vm.prank(ANVIL_ADDRESS);
        manager.updateFactoryFee(newFee, marketConfig.questionId);

        assertEq(newFee, market.getCurrentFee());
    }

    function testIsRegisteredMarket() public view {
        assertTrue(manager.isRegisteredMarket(marketConfig.questionId));
        assertFalse(manager.isRegisteredMarket(bytes32(0)));
    }
}
