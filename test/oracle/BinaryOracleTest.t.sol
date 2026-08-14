// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test, console} from "forge-std/Test.sol";
import {BinaryOracle} from "../../src/oracle/BinaryOracle.sol";
import {PredictionMarket} from "../../src/market/PredictionMarket.sol";
import {MarketManager} from "../../src/market/MarketManager.sol";
import {LPToken} from "../../src/tokens/LPToken.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployCore} from "../../script/DeployCore.s.sol";
import {DeployMarket} from "../../script/DeployMarket.s.sol";
import {DataTypes} from "../../src/types/DataTypes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20DecimalsMock} from "./../mocks/ERC20DecimalsMock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

contract BinaryOracleTest is Test {
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

    event MarketResolved(
        bytes32 indexed questionId, uint80 indexed roundId, int256 price, uint256 updatedAt, DataTypes.YesWins yesWins
    );

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

    function testSetUpMarketRevertsIfNotOwnerQuestionIdOrAddressOrStrikeOrMaxSetlDelayAreZeroOrResolveTimeIsLessThanCurrTime()
        public
    {
        DataTypes.MarketData memory data = DataTypes.MarketData({
            market: address(market),
            priceFeed: marketConfig.priceFeed,
            strike: marketConfig.strike,
            resolveTime: marketConfig.resolveTime,
            maxSettlementDelay: marketConfig.maxSettlementDelay
        });

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        oracle.setUpMarket(data, marketConfig.questionId);

        vm.startPrank(address(manager));
        vm.expectRevert(BinaryOracle.BinaryOracle__InvalidQuestionId.selector);
        oracle.setUpMarket(data, bytes32(0));

        data.market = address(0);

        vm.expectRevert(BinaryOracle.BinaryOracle__ZeroAddress.selector);
        oracle.setUpMarket(data, marketConfig.questionId);

        data.market = address(market);
        data.priceFeed = address(0);

        vm.expectRevert(BinaryOracle.BinaryOracle__ZeroAddress.selector);
        oracle.setUpMarket(data, marketConfig.questionId);

        data.priceFeed = marketConfig.priceFeed;
        data.resolveTime = 0;

        vm.expectRevert(BinaryOracle.BinaryOracle__InvalidExpiry.selector);
        oracle.setUpMarket(data, marketConfig.questionId);

        data.resolveTime = marketConfig.resolveTime;
        data.strike = 0;

        vm.expectRevert(BinaryOracle.BinaryOracle__InvalidStrike.selector);
        oracle.setUpMarket(data, marketConfig.questionId);

        data.strike = marketConfig.strike;
        data.maxSettlementDelay = 0;

        vm.expectRevert(BinaryOracle.BinaryOracle__InvalidSettlementDelay.selector);
        oracle.setUpMarket(data, marketConfig.questionId);
        vm.stopPrank();
    }

    function testSetUpMarket() public {
        DataTypes.MarketData memory data = DataTypes.MarketData({
            market: address(market),
            priceFeed: marketConfig.priceFeed,
            strike: marketConfig.strike,
            resolveTime: marketConfig.resolveTime,
            maxSettlementDelay: marketConfig.maxSettlementDelay
        });

        vm.prank(address(manager));
        oracle.setUpMarket(data, marketConfig.questionId);

        DataTypes.MarketData memory storedData = oracle.getMarketData(marketConfig.questionId);

        assertEq(data.market, storedData.market);
        assertEq(data.priceFeed, storedData.priceFeed);
        assertEq(data.strike, storedData.strike);
        assertEq(data.resolveTime, storedData.resolveTime);
        assertEq(data.maxSettlementDelay, storedData.maxSettlementDelay);
    }

    function testResolveRevertsIfRoundIdIsZeroOrCurrTimeIsLessThanResolveTimeOrAlreadyResolved() public {
        vm.expectRevert(BinaryOracle.BinaryOracle__InvalidRound.selector);
        oracle.resolve(marketConfig.questionId, 0);

        vm.expectRevert(BinaryOracle.BinaryOracle__TooEarly.selector);
        oracle.resolve(marketConfig.questionId, 1);

        vm.startPrank(user);
        ERC20DecimalsMock(networkConfig.asset).mint(user, marketConfig.initialLiquidityTarget);
        ERC20DecimalsMock(networkConfig.asset).approve(address(market), marketConfig.initialLiquidityTarget);
        market.addInitialLiquidity(marketConfig.initialLiquidityTarget);
        vm.stopPrank();

        vm.warp(marketConfig.resolveTime);
        MockV3Aggregator(marketConfig.priceFeed).updateRoundData(2, 5000e18, block.timestamp, block.timestamp);
        oracle.resolve(marketConfig.questionId, 2);

        vm.expectRevert(BinaryOracle.BinaryOracle__AlreadyResolved.selector);
        oracle.resolve(marketConfig.questionId, 2);
    }

    function testResolveRevertsIfPriceIsNotPosiOrUpdatedIsLessThanResolveTimeOrMoreMaxTimeOrPreviousUpdatedWasMoreThanResolveTime()
        public
    {
        vm.startPrank(user);
        ERC20DecimalsMock(networkConfig.asset).mint(user, marketConfig.initialLiquidityTarget);
        ERC20DecimalsMock(networkConfig.asset).approve(address(market), marketConfig.initialLiquidityTarget);
        market.addInitialLiquidity(marketConfig.initialLiquidityTarget);
        vm.stopPrank();

        vm.warp(marketConfig.resolveTime);
        MockV3Aggregator(marketConfig.priceFeed).updateRoundData(2, 0, block.timestamp, block.timestamp);

        vm.expectRevert(BinaryOracle.BinaryOracle__InvalidPrice.selector);
        oracle.resolve(marketConfig.questionId, 2);

        MockV3Aggregator(marketConfig.priceFeed).updateRoundData(2, 5000e18, block.timestamp - 1, block.timestamp - 1);

        vm.expectRevert(BinaryOracle.BinaryOracle__CurrentRoundBeforeExpiry.selector);
        oracle.resolve(marketConfig.questionId, 2);

        vm.warp(block.timestamp + marketConfig.maxSettlementDelay + 1);
        MockV3Aggregator(marketConfig.priceFeed).updateRoundData(2, 5000e18, block.timestamp, block.timestamp);

        vm.expectRevert(BinaryOracle.BinaryOracle__SettlementTooLate.selector);
        oracle.resolve(marketConfig.questionId, 2);

        MockV3Aggregator(marketConfig.priceFeed).updateRoundData(2, 5000e18, block.timestamp - 10, block.timestamp - 10);
        MockV3Aggregator(marketConfig.priceFeed).updateRoundData(3, 5000e18, block.timestamp - 1, block.timestamp - 1);

        vm.expectRevert(BinaryOracle.BinaryOracle__PreviousRoundAfterExpiry.selector);
        oracle.resolve(marketConfig.questionId, 3);
    }

    function testResolve() public {
        vm.startPrank(user);
        ERC20DecimalsMock(networkConfig.asset).mint(user, marketConfig.initialLiquidityTarget);
        ERC20DecimalsMock(networkConfig.asset).approve(address(market), marketConfig.initialLiquidityTarget);
        market.addInitialLiquidity(marketConfig.initialLiquidityTarget);
        vm.stopPrank();

        vm.warp(marketConfig.resolveTime);
        MockV3Aggregator(marketConfig.priceFeed).updateRoundData(2, 5000e18, block.timestamp, block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit MarketResolved(marketConfig.questionId, 2, 5000e18, block.timestamp, DataTypes.YesWins.TRUE);
        oracle.resolve(marketConfig.questionId, 2);

        DataTypes.ResolutionData memory resolutionData = oracle.getResolutionData(marketConfig.questionId);

        assertEq(resolutionData.resolved, true);
        assertEq(uint256(resolutionData.yesWins), uint256(DataTypes.YesWins.TRUE));
        assertEq(resolutionData.settlementRoundId, 2);
        assertEq(resolutionData.settlementPrice, 5000e18);
        assertEq(resolutionData.settlementTimestamp, block.timestamp);
    }

    function testResolveByTimeoutRevertsIfCurrTimeIsLessThanMaxSettlementTimeOrAlreadyResolved() public {
        vm.expectRevert(BinaryOracle.BinaryOracle__TimeoutNotReached.selector);
        oracle.resolveByTimeout(marketConfig.questionId);

        vm.startPrank(user);
        ERC20DecimalsMock(networkConfig.asset).mint(user, marketConfig.initialLiquidityTarget);
        ERC20DecimalsMock(networkConfig.asset).approve(address(market), marketConfig.initialLiquidityTarget);
        market.addInitialLiquidity(marketConfig.initialLiquidityTarget);
        vm.stopPrank();

        vm.warp(marketConfig.resolveTime);
        MockV3Aggregator(marketConfig.priceFeed).updateRoundData(2, 5000e18, block.timestamp, block.timestamp);
        oracle.resolve(marketConfig.questionId, 2);

        vm.warp(block.timestamp + marketConfig.maxSettlementDelay + 1);

        vm.expectRevert(BinaryOracle.BinaryOracle__AlreadyResolved.selector);
        oracle.resolveByTimeout(marketConfig.questionId);
    }

    function testResolveByTimeout() public {
        vm.startPrank(user);
        ERC20DecimalsMock(networkConfig.asset).mint(user, marketConfig.initialLiquidityTarget);
        ERC20DecimalsMock(networkConfig.asset).approve(address(market), marketConfig.initialLiquidityTarget);
        market.addInitialLiquidity(marketConfig.initialLiquidityTarget);
        vm.stopPrank();

        vm.warp(marketConfig.resolveTime + marketConfig.maxSettlementDelay + 1);

        vm.expectEmit(true, true, true, true);
        emit MarketResolved(marketConfig.questionId, 0, 0, 0, DataTypes.YesWins.UNRESOLVED);
        oracle.resolveByTimeout(marketConfig.questionId);

        DataTypes.ResolutionData memory resolutionData = oracle.getResolutionData(marketConfig.questionId);

        assertEq(resolutionData.resolved, true);
        assertEq(uint256(resolutionData.yesWins), uint256(DataTypes.YesWins.UNRESOLVED));
        assertEq(resolutionData.settlementRoundId, 0);
        assertEq(resolutionData.settlementPrice, 0);
        assertEq(resolutionData.settlementTimestamp, 0);
    }

    function testCanResolve() public {
        assertEq(oracle.canResolve(marketConfig.questionId), false);

        vm.warp(marketConfig.resolveTime);

        assertEq(oracle.canResolve(marketConfig.questionId), true);
    }

    function testStrikeWithDecimals() public view {
        assertEq(oracle.strikeWithDecimals(marketConfig.questionId), marketConfig.strike);
    }
}
