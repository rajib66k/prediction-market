// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {PredictionMarket} from "../../src/market/PredictionMarket.sol";
import {MarketManager} from "../../src/market/MarketManager.sol";
import {LPToken} from "../../src/tokens/LPToken.sol";
import {IConditionalTokens} from "../../src/interfaces/IConditionalTokens.sol";
import {BinaryOracle} from "../../src/oracle/BinaryOracle.sol";
import {DataTypes} from "../../src/types/DataTypes.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployCore} from "../../script/DeployCore.s.sol";
import {DeployMarket} from "../../script/DeployMarket.s.sol";
import {ERC20DecimalsMock} from "./../mocks/ERC20DecimalsMock.sol";
import {ConditionalTokensOperator} from "../../src/libraries/ConditionalTokensOperator.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PredictionMarketTest is Test {
    using ConditionalTokensOperator for address;

    HelperConfig.NetworkConfig public networkConfig;
    HelperConfig.MarketConfig public marketConfig;

    PredictionMarket public marketImpl;
    LPToken public lpTokenImpl;

    IConditionalTokens public ct;

    MarketManager public manager;
    BinaryOracle public oracle;

    PredictionMarket public market;
    LPToken public lpToken;

    address public user = makeAddr("user");
    address public constant ANVIL_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    event LiquidityAdded(address indexed provider, uint256 collateralAmount, uint256 lpTokensMinted);

    event LiquidityRefunded(address indexed provider, uint256 lpTokensBurned, uint256 collateralAmount);

    event MarketStateChanged(PredictionMarket.MarketState marketState);

    event LiquidityRemoved(address indexed provider, uint256 lpTokensBurned, uint256 yesAmount, uint256 noAmount);

    function setUp() public {
        DeployCore deployCore = new DeployCore();
        DeployMarket deployMarket = new DeployMarket();

        address marketAddress;
        address lpTokenAddress;
        address ctAddress;

        (ctAddress, manager, oracle, marketImpl, lpTokenImpl, networkConfig) = deployCore.run();
        (marketAddress, lpTokenAddress, marketConfig) = deployMarket.run();

        market = PredictionMarket(marketAddress);
        lpToken = LPToken(lpTokenAddress);
        ct = IConditionalTokens(ctAddress);
    }

    /////////////
    // Helpers //
    /////////////
    function mintAndApprove(address userAddress, uint256 amount) internal {
        ERC20DecimalsMock(networkConfig.asset).mint(userAddress, amount);
        ERC20DecimalsMock(networkConfig.asset).approve(address(market), amount);
    }

    function openMarketWithInitalSupply() internal {
        mintAndApprove(user, marketConfig.initialLiquidityTarget);
        market.addInitialLiquidity(marketConfig.initialLiquidityTarget);
    }

    ////////////////////////////////////
    // Constructor & Initialize Tests //
    ////////////////////////////////////
    function testConstructorRevertsIfZeroAddress() public {
        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidAddress.selector);
        new PredictionMarket(address(0), address(ct), address(oracle));

        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidAddress.selector);
        new PredictionMarket(networkConfig.asset, address(0), address(oracle));

        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidAddress.selector);
        new PredictionMarket(networkConfig.asset, address(ct), address(0));
    }

    function testConstructor() public {
        PredictionMarket implementation = new PredictionMarket(networkConfig.asset, address(ct), address(oracle));

        assertEq(networkConfig.asset, implementation.getCollateralToken());
        assertEq(address(ct), implementation.getConditionalToken());
        assertEq(address(oracle), implementation.getOracle());
    }

    function testImplementationRevertsIfInitialize() public {
        PredictionMarket implementation = new PredictionMarket(networkConfig.asset, address(ct), address(oracle));

        DataTypes.MarketInitParams memory params = DataTypes.MarketInitParams({
            questionId: marketConfig.questionId,
            resolveTime: marketConfig.resolveTime,
            liquidityDeadline: marketConfig.liquidityDeadline,
            initialLiquidityTarget: marketConfig.initialLiquidityTarget
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(params, address(lpToken));
    }

    function testInitializeRevertsIfLiquidityTargetIsZeroOrDeadlineIsLessThanCurrTimeOrResoveTimeIsLessThanDeadline()
        public
    {
        DataTypes.MarketInitParams memory params = DataTypes.MarketInitParams({
            questionId: marketConfig.questionId,
            resolveTime: marketConfig.resolveTime,
            liquidityDeadline: marketConfig.liquidityDeadline,
            initialLiquidityTarget: 0
        });

        address clone = Clones.clone(address(marketImpl));

        vm.expectRevert(PredictionMarket.PredictionMarket__IntialLiquidityMustBeMoreThanZero.selector);
        PredictionMarket(clone).initialize(params, marketConfig.priceFeed);

        params.initialLiquidityTarget = marketConfig.initialLiquidityTarget;
        params.liquidityDeadline = 0;

        vm.expectRevert(PredictionMarket.PredictionMarket__LiquidityDeadlineMustBeMoreThanCurrTimestamp.selector);
        PredictionMarket(clone).initialize(params, marketConfig.priceFeed);

        params.liquidityDeadline = marketConfig.liquidityDeadline;
        params.resolveTime = 0;

        vm.expectRevert(PredictionMarket.PredictionMarket__ResolveTimeMustBeMoreThanLiquidityDeadline.selector);
        PredictionMarket(clone).initialize(params, marketConfig.priceFeed);
    }

    function testCloneCanBeInitialized() public {
        address clone = Clones.clone(address(marketImpl));

        address previousOwner = PredictionMarket(clone).owner();

        DataTypes.MarketInitParams memory params = DataTypes.MarketInitParams({
            questionId: marketConfig.questionId,
            resolveTime: marketConfig.resolveTime,
            liquidityDeadline: marketConfig.liquidityDeadline,
            initialLiquidityTarget: marketConfig.initialLiquidityTarget
        });

        vm.prank(user);
        PredictionMarket(clone).initialize(params, address(lpToken));

        address newOwner = PredictionMarket(clone).owner();

        (bytes32 questionId, uint256 resolveTime, uint256 liquidityDeadline, uint256 initialLiquidityTarget) =
            PredictionMarket(clone).getMarketData();

        (bytes32 conditionId, uint256 yesTokenId, uint256 noTokenId) = PredictionMarket(clone).getConditionAndTokenIds();

        bytes32 expectedConditionId = ct.getConditionId(clone, params.questionId, 2);
        uint256 expectedYesTokenId =
            ct.getPositionId(IERC20(networkConfig.asset), ct.getCollectionId(bytes32(0), expectedConditionId, 1));
        uint256 expectedNoTokenId =
            ct.getPositionId(IERC20(networkConfig.asset), ct.getCollectionId(bytes32(0), expectedConditionId, 2));

        assertEq(PredictionMarket(clone).getLPToken(), address(lpToken));
        assertEq(marketConfig.questionId, questionId);
        assertEq(marketConfig.resolveTime, resolveTime);
        assertEq(marketConfig.liquidityDeadline, liquidityDeadline);
        assertEq(marketConfig.initialLiquidityTarget, initialLiquidityTarget);
        assertEq(expectedConditionId, conditionId);
        assertEq(expectedYesTokenId, yesTokenId);
        assertEq(expectedNoTokenId, noTokenId);

        assertEq(address(0), previousOwner);
        assertEq(user, newOwner);
        assertTrue(PredictionMarket(clone).hasRole(keccak256("RESOLUTION_ROLE"), address(oracle)));
    }

    function testCloneCannotBeInitializedTwice() public {
        address clone = Clones.clone(address(marketImpl));

        DataTypes.MarketInitParams memory params = DataTypes.MarketInitParams({
            questionId: marketConfig.questionId,
            resolveTime: marketConfig.resolveTime,
            liquidityDeadline: marketConfig.liquidityDeadline,
            initialLiquidityTarget: marketConfig.initialLiquidityTarget
        });

        PredictionMarket(clone).initialize(params, address(lpToken));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        PredictionMarket(clone).initialize(params, address(lpToken));
    }

    ///////////////////////////////////////
    // Add Initial & Add Liquidity Tests //
    ///////////////////////////////////////
    function testAddInitialLiquidityRevertsIfNotPendingOrCurrTimeIsMoreThanDeadlineNotPending(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint96).max);

        vm.startPrank(user);
        mintAndApprove(user, 1e6);
        market.addInitialLiquidity(1e6);

        vm.warp(marketConfig.liquidityDeadline);

        vm.expectRevert(PredictionMarket.PredictionMarket__LiquidityPeriodEnded.selector);
        market.addInitialLiquidity(amount);

        vm.warp(marketConfig.liquidityDeadline - 1);

        openMarketWithInitalSupply();

        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotPending.selector);
        market.addInitialLiquidity(amount);
        vm.stopPrank();
    }

    function teatAddInitialLiquidity(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint96).max);

        vm.startPrank(user);
        mintAndApprove(user, amount);

        vm.expectEmit(true, true, true, true);
        emit LiquidityAdded(user, amount, amount);
        market.addInitialLiquidity(amount);
        vm.stopPrank();

        (, uint256 yesTokenId, uint256 noTokenId) = market.getConditionAndTokenIds();
        (uint256 yesReserve, uint256 noReserve) = address(ct).getPoolBalances(yesTokenId, noTokenId);

        assertEq(yesReserve, noReserve);
    }

    function teatAddInitialLiquidityOpensMarketIfEnoughLiquidity() public {
        vm.startPrank(user);
        ERC20DecimalsMock(networkConfig.asset).mint(user, marketConfig.initialLiquidityTarget);
        ERC20DecimalsMock(networkConfig.asset).approve(address(market), marketConfig.initialLiquidityTarget);

        vm.expectEmit(true, true, true, true);
        emit LiquidityAdded(user, marketConfig.initialLiquidityTarget, marketConfig.initialLiquidityTarget);
        market.addInitialLiquidity(marketConfig.initialLiquidityTarget);
        vm.stopPrank();

        (, uint256 yesTokenId, uint256 noTokenId) = market.getConditionAndTokenIds();
        (uint256 yesReserve, uint256 noReserve) = address(ct).getPoolBalances(yesTokenId, noTokenId);

        assertEq(yesReserve, noReserve);
        assertEq(uint256(market.getMarketState()), uint256(PredictionMarket.MarketState.OPEN));
    }

    function testAddLiquidityRevertsIfNotOpenOrLpShareIsZero(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint96).max);

        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotOpen.selector);
        market.addLiquidity(amount);

        vm.startPrank(user);
        openMarketWithInitalSupply();
        vm.stopPrank();

        vm.expectRevert(PredictionMarket.PredictionMarket__NeedMoreThanZero.selector);
        market.addLiquidity(0);
    }

    function testAddLiquidity(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint96).max);

        vm.startPrank(user);
        openMarketWithInitalSupply();

        mintAndApprove(user, amount);

        vm.expectEmit(true, true, true, true);
        emit LiquidityAdded(user, amount, amount);
        market.addLiquidity(amount);
        vm.stopPrank();

        (, uint256 yesTokenId, uint256 noTokenId) = market.getConditionAndTokenIds();
        (uint256 yesReserve, uint256 noReserve) = address(ct).getPoolBalances(yesTokenId, noTokenId);

        assertEq(LPToken(lpToken).balanceOf(user), marketConfig.initialLiquidityTarget + amount);
        assertEq(IERC20(networkConfig.asset).balanceOf(address(ct)), marketConfig.initialLiquidityTarget + amount);
        assertEq(yesReserve, noReserve);
        assertEq(uint256(market.getMarketState()), uint256(PredictionMarket.MarketState.OPEN));
        assertEq(market.getUserFeeDebt(user), 0);
        assertEq(market.getClaimableFee(user), 0);
        assertEq(market.getFeeIndex(), 0);
    }

    //////////////////////////////////////////////////////
    // Cancel Market, Remove and Refund Liquidity Tests //
    //////////////////////////////////////////////////////
    function testCancelMarketRevertsIfCurrTimeIsLessThanDeadlineOrMarketNotPending() public {
        vm.expectRevert(PredictionMarket.PredictionMarket__LiquidityDeadlineIsNotOver.selector);
        market.cancelMarket();

        vm.startPrank(user);
        openMarketWithInitalSupply();
        vm.stopPrank();

        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotPending.selector);
        market.cancelMarket();
    }

    function testCancelMarket() public {
        vm.warp(marketConfig.liquidityDeadline);

        vm.expectEmit(true, true, true, true);
        emit MarketStateChanged(PredictionMarket.MarketState.CANCELLED);
        market.cancelMarket();

        assertEq(uint256(market.getMarketState()), uint256(PredictionMarket.MarketState.CANCELLED));
    }

    function testRefundLiquidityRevertsIfStateIsNotCancelledOrShareIsZero() public {
        vm.startPrank(user);
        mintAndApprove(user, 1e6);
        market.addInitialLiquidity(1e6);
        vm.stopPrank();

        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotCancelled.selector);
        market.refundLiquidity();

        vm.warp(marketConfig.liquidityDeadline);

        market.cancelMarket();

        vm.expectRevert(PredictionMarket.PredictionMarket__NeedMoreThanZero.selector);
        market.refundLiquidity();

        vm.startPrank(user);
        market.refundLiquidity();
        vm.stopPrank();

        vm.expectRevert(PredictionMarket.PredictionMarket__NoLiquidity.selector);
        market.refundLiquidity();
    }

    function testRefundLiquidity(uint256 amount) public {
        amount = bound(amount, 1e8, marketConfig.initialLiquidityTarget - 1);

        vm.startPrank(user);
        mintAndApprove(user, amount);
        market.addInitialLiquidity(amount);

        vm.warp(marketConfig.liquidityDeadline);
        market.cancelMarket();

        vm.expectEmit(true, true, true, true);
        emit LiquidityRefunded(user, amount, amount);
        market.refundLiquidity();
        vm.stopPrank();

        assertEq(ERC20DecimalsMock(networkConfig.asset).balanceOf(user), amount);
        assertEq(ERC20DecimalsMock(networkConfig.asset).balanceOf(address(market)), 0);
    }

    function testRemoveLiquidityRevertsIfZeroSharesOrMarketIsNotOpenOrResolved() public {
        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotOpenOrResolved.selector);
        market.removeLiquidity(1e6);

        vm.startPrank(user);
        openMarketWithInitalSupply();
        vm.stopPrank();

        vm.expectRevert(PredictionMarket.PredictionMarket__InsufficientLiquidity.selector);
        market.removeLiquidity(1e18);
    }

    function testRemoveLiquidity(uint256 amount) public {
        amount = bound(amount, marketConfig.initialLiquidityTarget, type(uint96).max);

        vm.startPrank(user);
        mintAndApprove(user, amount);
        market.addInitialLiquidity(amount);

        uint256 userIntialShares = LPToken(lpToken).balanceOf(user);

        vm.expectEmit(true, true, true, true);
        emit LiquidityRemoved(user, amount, amount, amount);
        market.removeLiquidity(amount);
        vm.stopPrank();

        (, uint256 yesId, uint256 noId) = market.getConditionAndTokenIds();

        uint256 yesBal = address(ct).balanceOf(user, yesId);
        uint256 noBal = address(ct).balanceOf(user, noId);

        assertEq(userIntialShares - amount, 0);
        assertEq(yesBal, amount);
        assertEq(noBal, amount);
    }
}
