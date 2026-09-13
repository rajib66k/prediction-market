// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test, console} from "forge-std/Test.sol";
import {PredictionMarket} from "../../src/market/PredictionMarket.sol";
import {MarketManager} from "../../src/market/MarketManager.sol";
import {LPToken} from "../../src/tokens/LPToken.sol";
import {IConditionalTokens} from "../../src/interfaces/IConditionalTokens.sol";
import {BinaryOracle} from "../../src/oracle/BinaryOracle.sol";
import {DataTypes} from "../../src/types/DataTypes.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployCore} from "../../script/DeployCore.s.sol";
import {DeployMarket} from "../../script/DeployMarket.s.sol";
import {Math} from "../../src/libraries/Math.sol";
import {ERC20DecimalsMock} from "./../mocks/ERC20DecimalsMock.sol";
import {ConditionalTokensOperator} from "../../src/libraries/ConditionalTokensOperator.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract PredictionMarketTest is Test {
    using ConditionalTokensOperator for address;
    using Math for uint256;

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
    address public user2 = makeAddr("user2");
    address public constant ANVIL_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    event LiquidityAdded(address indexed provider, uint256 collateralAmount, uint256 lpTokensMinted);

    event LiquidityRefunded(address indexed provider, uint256 lpTokensBurned, uint256 collateralAmount);

    event MarketStateChanged(PredictionMarket.MarketState marketState);

    event LiquidityRemoved(address indexed provider, uint256 lpTokensBurned, uint256 yesAmount, uint256 noAmount);

    event Bought(
        address indexed buyer, uint256 indexed tokenId, uint256 collateralAmount, uint256 fee, uint256 amountBrought
    );

    event PositionRedeemed(address user, uint256 amount);

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
            question: marketConfig.question,
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
            question: marketConfig.question,
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
            question: marketConfig.question,
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
            question: marketConfig.question,
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
        amount = bound(amount, 1e3, type(uint64).max);

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
        amount = bound(amount, 1e3, type(uint64).max);

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
        amount = bound(amount, 1e3, type(uint64).max);

        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotOpen.selector);
        market.addLiquidity(amount);

        vm.startPrank(user);
        openMarketWithInitalSupply();
        vm.stopPrank();

        vm.expectRevert(PredictionMarket.PredictionMarket__NeedMoreThanZero.selector);
        market.addLiquidity(0);
    }

    function testAddLiquidity(uint256 amount) public {
        amount = bound(amount, 1e3, type(uint64).max);

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
        amount = bound(amount, 1e3, marketConfig.initialLiquidityTarget - 1);

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

    ////////////////////////
    // Buy Yes & No Tests //
    ////////////////////////
    function testBuyRevertsIfNotOpenOrZeroAmntOrNoSupplyOrSlippageIsMore() external {
        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotOpen.selector);
        market.buyYes(1e6, 1e6);
        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotOpen.selector);
        market.buyNo(1e6, 1e6);

        vm.startPrank(user);
        openMarketWithInitalSupply();

        vm.expectRevert(PredictionMarket.PredictionMarket__NeedMoreThanZero.selector);
        market.buyYes(0, 1e6);

        vm.expectRevert(PredictionMarket.PredictionMarket__MinimumOutputNotMet.selector);
        market.buyYes(1e6, 1e7);
        vm.stopPrank();
    }

    function testBuyYes(uint256 amount) external {
        amount = bound(amount, 1e3, type(uint64).max);

        vm.startPrank(user);
        openMarketWithInitalSupply();
        mintAndApprove(user, amount);
        market.addLiquidity(amount);
        vm.stopPrank();

        (, uint256 yesId, uint256 noId) = market.getConditionAndTokenIds();
        uint256 quotedAmount = market.getBuyYesQuote(amount);
        uint256 feeDeducted = amount.mul(1e16);

        vm.startPrank(user2);
        mintAndApprove(user2, amount);
        vm.expectEmit(true, true, true, true);
        emit Bought(user2, yesId, amount, feeDeducted, quotedAmount);
        market.buyYes(amount, quotedAmount);
        vm.stopPrank();

        uint256 yesUserBal = address(ct).balanceOf(user2, yesId);
        uint256 noUserBal = address(ct).balanceOf(user2, noId);

        assertEq(
            IERC20(networkConfig.asset).balanceOf(address(ct)),
            (amount * 2) + marketConfig.initialLiquidityTarget - feeDeducted
        );
        assertEq(yesUserBal, quotedAmount);
        assertEq(noUserBal, 0);
        assertEq(IERC20(networkConfig.asset).balanceOf(address(market)), feeDeducted);
        assertEq(market.getFeeIndex(), feeDeducted.divFloor(lpToken.totalSupply()));
    }

    function testBuyNo(uint256 amount) external {
        amount = bound(amount, 1e3, type(uint64).max);

        vm.startPrank(user);
        openMarketWithInitalSupply();
        mintAndApprove(user, amount);
        market.addLiquidity(amount);
        vm.stopPrank();

        (, uint256 yesId, uint256 noId) = market.getConditionAndTokenIds();
        uint256 quotedAmount = market.getBuyNoQuote(amount);
        uint256 feeDeducted = amount.mul(1e16);

        vm.startPrank(user2);
        mintAndApprove(user2, amount);
        vm.expectEmit(true, true, true, true);
        emit Bought(user2, noId, amount, feeDeducted, quotedAmount);
        market.buyNo(amount, quotedAmount);
        vm.stopPrank();

        uint256 yesUserBal = address(ct).balanceOf(user2, yesId);
        uint256 noUserBal = address(ct).balanceOf(user2, noId);

        assertEq(
            IERC20(networkConfig.asset).balanceOf(address(ct)),
            (amount * 2) + marketConfig.initialLiquidityTarget - feeDeducted
        );
        assertEq(yesUserBal, 0);
        assertEq(noUserBal, quotedAmount);
        assertEq(IERC20(networkConfig.asset).balanceOf(address(market)), feeDeducted);
        assertEq(market.getFeeIndex(), feeDeducted.divFloor(lpToken.totalSupply()));
    }

    /////////////////////////
    // Sell Yes & No Tests //
    /////////////////////////
    function testSellRevertsIfNotOpenOrZeroAmntOrNoSupplyOrSlippageIsMore() public {
        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotOpen.selector);
        market.sellYes(1e6, 1e6);
        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotOpen.selector);
        market.sellNo(1e6, 1e6);

        vm.startPrank(user);
        openMarketWithInitalSupply();

        vm.expectRevert(PredictionMarket.PredictionMarket__NeedMoreThanZero.selector);
        market.sellYes(0, 1e6);

        vm.expectRevert(PredictionMarket.PredictionMarket__MaximumInputExceeded.selector);
        market.sellYes(1e6, 1e6);
        vm.stopPrank();
    }

    function testSellYes(uint256 amount, uint256 sellAmount) public {
        amount = bound(amount, 1e3, type(uint64).max);

        vm.startPrank(user);
        openMarketWithInitalSupply();
        mintAndApprove(user, amount);
        market.addLiquidity(amount);
        vm.stopPrank();

        (, uint256 yesId,) = market.getConditionAndTokenIds();
        uint256 buyQuote = market.getBuyYesQuote(amount);

        vm.startPrank(user2);
        mintAndApprove(user2, amount);
        market.buyYes(amount, buyQuote);

        uint256 yesBalance = IERC1155(address(ct)).balanceOf(user2, yesId);
        sellAmount = bound(sellAmount, 1, yesBalance);
        uint256 yesTokensRequired = market.getSellYesQuote(sellAmount);
        vm.assume(yesTokensRequired <= yesBalance);

        uint256 collateralBefore = IERC20(networkConfig.asset).balanceOf(user2);
        uint256 yesBalanceBefore = IERC1155(address(ct)).balanceOf(user2, yesId);

        IERC1155(address(ct)).setApprovalForAll(address(market), true);
        market.sellYes(sellAmount, yesTokensRequired);
        vm.stopPrank();

        uint256 collateralAfter = IERC20(networkConfig.asset).balanceOf(user2);
        uint256 yesBalanceAfter = IERC1155(address(ct)).balanceOf(user2, yesId);

        assertEq(collateralAfter - collateralBefore, sellAmount);
        assertEq(yesBalanceBefore - yesBalanceAfter, yesTokensRequired);
        assertEq(yesBalance, buyQuote);
    }

    function testSellNo(uint256 amount, uint256 sellAmount) public {
        amount = bound(amount, 1e3, type(uint64).max);

        vm.startPrank(user);
        openMarketWithInitalSupply();
        mintAndApprove(user, amount);
        market.addLiquidity(amount);
        vm.stopPrank();

        (,, uint256 noId) = market.getConditionAndTokenIds();
        uint256 buyQuote = market.getBuyNoQuote(amount);

        vm.startPrank(user2);
        mintAndApprove(user2, amount);
        market.buyNo(amount, buyQuote);

        uint256 noBalance = IERC1155(address(ct)).balanceOf(user2, noId);
        sellAmount = bound(sellAmount, 1, noBalance);
        uint256 noTokensRequired = market.getSellNoQuote(sellAmount);
        vm.assume(noTokensRequired <= noBalance);

        uint256 collateralBefore = IERC20(networkConfig.asset).balanceOf(user2);
        uint256 noBalanceBefore = IERC1155(address(ct)).balanceOf(user2, noId);

        IERC1155(address(ct)).setApprovalForAll(address(market), true);
        market.sellNo(sellAmount, noTokensRequired);
        vm.stopPrank();

        uint256 collateralAfter = IERC20(networkConfig.asset).balanceOf(user2);
        uint256 noBalanceAfter = IERC1155(address(ct)).balanceOf(user2, noId);

        assertEq(collateralAfter - collateralBefore, sellAmount);
        assertEq(noBalanceBefore - noBalanceAfter, noTokensRequired);
        assertEq(noBalance, buyQuote);
    }

    //////////////////////////////////////
    // Resolve, Transfer & Redeem Tests //
    //////////////////////////////////////
    function testResolveRevertsIfNotByResolutionRoleOrWrongQuestionIdOrNotOpenOrResolutionTimeNotReached() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), keccak256("RESOLUTION_ROLE")
            )
        );
        market.resolveMarket(marketConfig.questionId, DataTypes.YesWins.TRUE);

        vm.prank(address(oracle));
        vm.expectRevert(PredictionMarket.PredictionMarket__WrongQuestionId.selector);
        market.resolveMarket(bytes32(0), DataTypes.YesWins.TRUE);

        vm.prank(address(oracle));
        vm.expectRevert(PredictionMarket.PredictionMarket__MarketCanNotResolve.selector);
        market.resolveMarket(marketConfig.questionId, DataTypes.YesWins.TRUE);

        vm.startPrank(user);
        openMarketWithInitalSupply();
        vm.stopPrank();

        vm.prank(address(oracle));
        vm.expectRevert(PredictionMarket.PredictionMarket__MarketCanNotResolve.selector);
        market.resolveMarket(marketConfig.questionId, DataTypes.YesWins.TRUE);
    }

    function testResolveMarket() public {
        vm.startPrank(user);
        openMarketWithInitalSupply();
        vm.stopPrank();

        vm.warp(marketConfig.resolveTime);

        vm.prank(address(oracle));
        vm.expectEmit(true, true, true, true);
        emit MarketStateChanged(PredictionMarket.MarketState.RESOLVED);
        market.resolveMarket(marketConfig.questionId, DataTypes.YesWins.FALSE);

        assertEq(uint256(market.getMarketState()), uint256(PredictionMarket.MarketState.RESOLVED));
    }

    function testTransferRevertsIfAmountIsZero() public {
        vm.expectRevert(PredictionMarket.PredictionMarket__NeedMoreThanZero.selector);
        market.transferLiquidityToken(address(0), 0);
    }

    function testTransferLiquidityToken() public {
        vm.startPrank(user);
        openMarketWithInitalSupply();

        market.transferLiquidityToken(user2, marketConfig.initialLiquidityTarget);
        vm.stopPrank();

        assertEq(lpToken.balanceOf(user), 0);
        assertEq(lpToken.balanceOf(user2), marketConfig.initialLiquidityTarget);
    }

    function testRedeemRevertsIfMarketNotResolvedOrNothingToRedeem() public {
        vm.expectRevert(PredictionMarket.PredictionMarket__IsNotResolved.selector);
        market.redeem();

        vm.startPrank(user);
        openMarketWithInitalSupply();
        vm.stopPrank();

        vm.warp(marketConfig.resolveTime);

        vm.prank(address(oracle));
        market.resolveMarket(marketConfig.questionId, DataTypes.YesWins.FALSE);

        vm.expectRevert(PredictionMarket.PredictionMarket__NothingToRedeem.selector);
        market.redeem();
    }

    function testRedeem() public {
        vm.startPrank(user);
        openMarketWithInitalSupply();
        vm.stopPrank();

        vm.warp(marketConfig.resolveTime);

        vm.prank(address(oracle));
        market.resolveMarket(marketConfig.questionId, DataTypes.YesWins.UNRESOLVED);

        vm.startPrank(user);
        market.removeLiquidity(marketConfig.initialLiquidityTarget);

        IERC1155(address(ct)).setApprovalForAll(address(market), true);
        vm.expectEmit(true, true, true, true);
        emit PositionRedeemed(user, marketConfig.initialLiquidityTarget);
        market.redeem();
        vm.stopPrank();

        assertEq(IERC20(networkConfig.asset).balanceOf(address(market)), 0);
        assertEq(IERC20(networkConfig.asset).balanceOf(user), marketConfig.initialLiquidityTarget);
    }
}
