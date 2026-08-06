// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {FeeLogic} from "./../base/FeeLogic.sol";
import {ERC1155TokenReceiver} from "./../base/ERC1155Receiver.sol";
import {Pricing} from "./../libraries/Pricing.sol";
import {ConditionalTokensOperator} from "./../libraries/ConditionalTokensOperator.sol";
import {Math} from "./../libraries/Math.sol";
import {ILPToken} from "./../interfaces/ILPToken.sol";
import {DataTypes} from "./../types/DataTypes.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PredictionMarket
 * @author Rajib Kumar Pradhan
 *
 * Binary prediction market using Gnosis Conditional Tokens and LP shares. Liquidity providers can add/remove
 * liquidity and users trade YES/NO positions. The market is resolved by an oracle after a specified time.
 *
 * @notice Initial liquidity providers deposit collateral which is split equally into YES/NO positions. If the market
 *         is failed to reach the minimum liquidity target, it can be cancelled and lp can claim their funds.
 * @notice Markets open only after reaching a minimum liquidity target before deadline.
 * @notice Liquidity providers can add/remove liquidity while the market is open. Liquidity added to market
 *         is split into YES/NO positions based on current pool proportions if the market is already open.
 * @dev Liquidity providers receive LP shares representing their share of the pool.
 */
contract PredictionMarket is FeeLogic, ERC1155TokenReceiver, Ownable, AccessControl {
    error PredictionMarket__NeedMoreThanZero();
    error PredictionMarket__InsufficientLiquidity();
    error PredictionMarket__IsNotPending();
    error PredictionMarket__IsNotOpen();
    error PredictionMarket__LiquidityPeriodEnded();
    error PredictionMarket__LiquidityDeadlineIsNotOver();
    error PredictionMarket__IsNotCancelled();
    error PredictionMarket__NoLiquidity();
    error PredictionMarket__LiquidityTargetReached();
    error PredictionMarket__MinimumOutputNotMet();
    error PredictionMarket__MaximumInputExceeded();
    error PredictionMarket__TradingWindowIsOver();
    error PredictionMarket__MarketCanNotResolve();
    error PredictionMarket__IsNotResolved();
    error PredictionMarket__NothingToRedeem();
    error PredictionMarket__IsOpenOrResolvingOrResolved();

    using ConditionalTokensOperator for address;
    using Pricing for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Current lifecycle state of the market.
    enum MarketState {
        PENDING,
        OPEN,
        RESOLVING,
        RESOLVED,
        CANCELLED
    }

    /// @dev Current market state.
    MarketState state = MarketState.PENDING;

    /// @dev Position ID of the winning outcome after market resolution.
    uint256 winningTokenId;

    /// @dev Oracle responsible for resolving the market.
    address internal immutable oracle;

    /// @dev ERC20 token used as collateral.
    address internal immutable collateral;

    /// @dev Gnosis Conditional Tokens contract.
    address internal immutable conditionalToken;

    /// @dev ERC20 LP token contract.
    address internal immutable lpToken;

    /// @dev Condition identifier in Conditional Tokens.
    bytes32 internal immutable conditionId;

    /// @dev Question identifier associated with the condition.
    bytes32 internal immutable questionId;

    /// @dev Position ID for the YES outcome.
    uint256 internal immutable yesTokenId;

    /// @dev Position ID for the NO outcome.
    uint256 internal immutable noTokenId;

    /// @dev Timestamp after which the market can be resolved.
    uint256 internal immutable resolveTime;

    /// @dev Deadline for reaching the initial liquidity target.
    uint256 internal immutable liquidityDeadline;

    /// @dev Minimum liquidity required to open the market.
    uint256 internal immutable initialLiquidityTarget;

    /// @dev Role identifier to resolve the market.
    bytes32 internal constant RESOLUTION_ROLE = keccak256("MINT_AND_BURN_ROLE");

    /// @notice Emitted when a user buys outcome tokens.
    event Bought(
        address indexed buyer, uint256 indexed tokenId, uint256 collateralAmount, uint256 fee, uint256 amountBrought
    );

    /// @notice Emitted when a user sells outcome tokens.
    event Sold(
        address indexed buyer, uint256 indexed tokenId, uint256 collateralAmount, uint256 fee, uint256 amountSold
    );

    /// @notice Emitted when liquidity is added.
    event LiquidityAdded(address indexed provider, uint256 collateralAmount, uint256 lpTokensMinted);

    /// @notice Emitted when liquidity is removed.
    event LiquidityRemoved(address indexed provider, uint256 lpTokensBurned, uint256 yesAmount, uint256 noAmount);

    /// @notice Emitted when cancelled market liquidity is refunded.
    event LiquidityRefunded(address indexed provider, uint256 lpTokensBurned, uint256 collateralAmount);

    /// @notice Emitted whenever the market state changes.
    event MarketStateChanged(MarketState marketState);

    /// @notice Emitted when user redeem position after resolution.
    event PositionRedeemed(address winner, uint256 winningAmount);

    /**
     * @notice Creates a new prediction market.
     * @param params Market initialization parameters.
     */
    constructor(DataTypes.MarketInitParams memory params) Ownable(msg.sender) {
        conditionalToken = params.conditionalToken;
        collateral = params.collateral;
        lpToken = params.lpToken;
        oracle = params.oracle;

        conditionId = params.conditionId;
        questionId = params.questionId;

        yesTokenId = params.yesTokenId;
        noTokenId = params.noTokenId;

        resolveTime = params.resolveTime;
        liquidityDeadline = params.liquidityDeadline;
        initialLiquidityTarget = params.initialLiquidityTarget;

        _grantRole(RESOLUTION_ROLE, params.oracle);
    }

    /// @dev Restricts execution to amounts greater than zero.
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) revert PredictionMarket__NeedMoreThanZero();
        _;
    }

    /// @dev Restricts execution to the pending state.
    modifier onlyPending() {
        if (state != MarketState.PENDING) revert PredictionMarket__IsNotPending();
        _;
    }

    /// @dev Restricts execution to the open state.
    modifier onlyOpen() {
        if (state != MarketState.OPEN) revert PredictionMarket__IsNotOpen();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= resolveTime) revert PredictionMarket__TradingWindowIsOver();
        _;
    }

    /// @dev Restricts execution to cancelled markets.
    modifier onlyCancelled() {
        if (state != MarketState.CANCELLED) revert PredictionMarket__IsNotCancelled();
        _;
    }

    /// @dev Restricts execution to resolved markets.
    modifier onlyResolved() {
        if (state != MarketState.RESOLVED) revert PredictionMarket__IsNotResolved();
        _;
    }

    /// @dev Restricts execution to the open or resolving or resolved state.
    modifier onlyOpenOrResolvingOrResolved() {
        if (state == MarketState.PENDING || state == MarketState.CANCELLED) {
            revert PredictionMarket__IsOpenOrResolvingOrResolved();
        }
        _;
    }

    /**
     * @notice Updates the protocol fee rate.
     * @param newRate The new fee rate.
     * @dev Only callable by the contract owner.
     * @dev The fee rate is expressed in 18-decimal precision.
     */
    function updateFeeRate(uint256 newRate) external onlyOwner {
        updateFee(newRate);
    }

    /**
     * @notice Buys YES outcome tokens.
     * @param collateralAmount Amount of collateral to spend.
     * @param minOutcomeTokens Minimum number of outcome tokens to receive.
     */
    function buyYes(uint256 collateralAmount, uint256 minOutcomeTokens) external onlyOpen {
        _buy(collateralAmount, minOutcomeTokens, true);
    }

    /**
     * @notice Buys NO outcome tokens.
     * @param collateralAmount Amount of collateral to spend.
     * @param minOutcomeTokens Minimum number of outcome tokens to receive.
     */
    function buyNo(uint256 collateralAmount, uint256 minOutcomeTokens) external onlyOpen {
        _buy(collateralAmount, minOutcomeTokens, false);
    }

    /**
     * @notice Sells YES outcome tokens.
     * @param collateralAmount Amount of collateral to receive.
     * @param maxOutcomeTokens Maximum number of outcome tokens to sell.
     */
    function sellYes(uint256 collateralAmount, uint256 maxOutcomeTokens) external onlyOpen {
        _sell(collateralAmount, maxOutcomeTokens, true);
    }

    /**
     * @notice Sells NO outcome tokens.
     * @param collateralAmount Amount of collateral to receive.
     * @param maxOutcomeTokens Maximum number of outcome tokens to sell.
     */
    function sellNo(uint256 collateralAmount, uint256 maxOutcomeTokens) external onlyOpen {
        _sell(collateralAmount, maxOutcomeTokens, false);
    }

    /**
     * @notice Redeems winning outcome tokens for collateral after market resolution.
     * @dev Redeems any winning YES or NO positions held by the caller. The Conditional
     *      Tokens contract burns the redeemed positions and transfers the corresponding
     *      collateral to this contract, which then forwards it to the caller.
     */
    function redeem() external onlyResolved {
        uint256 amount = conditionalToken.balanceOf(msg.sender, winningTokenId);
        if (amount == 0) revert PredictionMarket__NothingToRedeem();

        conditionalToken.transferPositionFrom(msg.sender, address(this), winningTokenId, amount);

        uint256 balanceBefore = IERC20(collateral).balanceOf(address(this));
        conditionalToken.redeemPositions(collateral, conditionId);
        uint256 winningAmount = IERC20(collateral).balanceOf(address(this)) - balanceBefore;

        IERC20(collateral).safeTransfer(msg.sender, winningAmount);
        emit PositionRedeemed(msg.sender, winningAmount);
    }

    /**
     * @notice Adds initial liquidity during market creation. Opens the market once the liquidity target is
     * reached before deadline. If the target is not reached, the market can be cancelled and liquidity refunded.
     * @param collateralAmount Amount of collateral to deposit.
     */
    function addInitialLiquidity(uint256 collateralAmount) external onlyPending {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= liquidityDeadline) revert PredictionMarket__LiquidityPeriodEnded();

        _addLiquidity(collateralAmount);

        (uint256 yesReserve, uint256 noReserve) = conditionalToken.getPoolBalances(yesTokenId, noTokenId);
        uint256 initialLiquidity = yesReserve > noReserve ? yesReserve : noReserve;

        // forge-lint: disable-next-line(block-timestamp)
        if (initialLiquidity >= initialLiquidityTarget) {
            state = MarketState.OPEN;
            emit MarketStateChanged(MarketState.OPEN);
        }
    }

    /**
     * @notice Adds liquidity to an open market.
     * @param collateralAmount Amount of collateral to deposit.
     */
    function addLiquidity(uint256 collateralAmount) external onlyOpen {
        _addLiquidity(collateralAmount);
    }

    /**
     * @notice Removes liquidity by burning LP shares.
     * @param sharesToBurn Amount of LP tokens to burn.
     */
    function removeLiquidity(uint256 sharesToBurn) external moreThanZero(sharesToBurn) onlyOpenOrResolvingOrResolved {
        uint256 supply = IERC20(lpToken).totalSupply();
        if (sharesToBurn > supply) revert PredictionMarket__InsufficientLiquidity();

        (uint256 yesReserve, uint256 noReserve) = conditionalToken.getPoolBalances(yesTokenId, noTokenId);
        uint256 yesAmount = sharesToBurn.integerMulDivFloor(yesReserve, supply);
        uint256 noAmount = sharesToBurn.integerMulDivFloor(noReserve, supply);

        ILPToken(lpToken).burn(msg.sender, sharesToBurn);
        conditionalToken.transferPositions(msg.sender, yesTokenId, noTokenId, yesAmount, noAmount);
        emit LiquidityRemoved(msg.sender, sharesToBurn, yesAmount, noAmount);
    }

    /**
     * @notice Refunds liquidity after market cancellation.
     */
    function refundLiquidity() external onlyCancelled {
        uint256 sharesToBurn = IERC20(lpToken).balanceOf(msg.sender);
        if (sharesToBurn == 0) revert PredictionMarket__NeedMoreThanZero();

        uint256 supply = IERC20(lpToken).totalSupply();
        if (supply == 0) revert PredictionMarket__NoLiquidity();

        (uint256 yesReserve, uint256 noReserve) = conditionalToken.getPoolBalances(yesTokenId, noTokenId);
        uint256 yesAmount = sharesToBurn.integerMulDivFloor(yesReserve, supply);
        uint256 noAmount = sharesToBurn.integerMulDivFloor(noReserve, supply);

        ILPToken(lpToken).burn(msg.sender, sharesToBurn);

        uint256 mergeAmount = yesAmount < noAmount ? yesAmount : noAmount;

        if (mergeAmount > 0) {
            conditionalToken.mergePosition(collateral, conditionId, mergeAmount);
        }
        IERC20(collateral).safeTransfer(msg.sender, mergeAmount);
        emit LiquidityRefunded(msg.sender, sharesToBurn, mergeAmount);
    }

    /**
     * @notice Cancels the market if the liquidity target was not reached before deadline.
     */
    function cancelMarket() external onlyPending {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < liquidityDeadline) revert PredictionMarket__LiquidityDeadlineIsNotOver();

        (uint256 yesReserve, uint256 noReserve) = conditionalToken.getPoolBalances(yesTokenId, noTokenId);
        uint256 liquidity = yesReserve > noReserve ? yesReserve : noReserve;

        if (liquidity >= initialLiquidityTarget) revert PredictionMarket__LiquidityTargetReached();

        state = MarketState.CANCELLED;
        emit MarketStateChanged(MarketState.CANCELLED);
    }

    /**
     * @notice Sets the market state to resolving if the market is open
     * and the resolution time has passed.
     */
    function setMarketResolving() external {
        _canMarketResolve();

        state = MarketState.RESOLVING;
        emit MarketStateChanged(MarketState.RESOLVING);
    }

    /**
     * @notice Resolves the market by reporting payouts to the Conditional Tokens contract.
     * @param yesWins True if the YES outcome wins, false if NO wins.
     * @dev Only callable by the oracle with the RESOLUTION_ROLE.
     */
    function resolveMarket(bool yesWins) external onlyRole(RESOLUTION_ROLE) {
        _canMarketResolve();

        conditionalToken.reportPayouts(conditionId, yesWins);
        winningTokenId = yesWins ? yesTokenId : noTokenId;
        state = MarketState.RESOLVED;
        emit MarketStateChanged(MarketState.RESOLVED);
    }

    /**
     * @notice Internal helper to buy YES or NO outcome tokens.
     * @param collateralAmount Amount of collateral to spend.
     * @param minOutcomeTokens Minimum acceptable outcome tokens.
     * @param isYes True to buy YES, false to buy NO.
     */
    function _buy(uint256 collateralAmount, uint256 minOutcomeTokens, bool isYes)
        internal
        moreThanZero(collateralAmount)
    {
        (uint256 yesReserve, uint256 noReserve) = conditionalToken.getPoolBalances(yesTokenId, noTokenId);
        uint256 fee = calculateFee(collateralAmount);
        uint256 collateralIn = collateralAmount - fee;

        uint256 amountOut;
        if (isYes) {
            amountOut = yesReserve.buyAmount(noReserve, collateralIn);
        } else {
            amountOut = noReserve.buyAmount(yesReserve, collateralIn);
        }

        if (amountOut < minOutcomeTokens) revert PredictionMarket__MinimumOutputNotMet();

        IERC20(collateral).safeTransferFrom(msg.sender, address(this), collateralAmount);
        IERC20(collateral).forceApprove(conditionalToken, collateralIn);
        conditionalToken.splitPosition(collateral, conditionId, collateralIn);
        conditionalToken.transferPositionFrom(address(this), msg.sender, isYes ? yesTokenId : noTokenId, amountOut);
        emit Bought(msg.sender, isYes ? yesTokenId : noTokenId, collateralAmount, fee, amountOut);
    }

    /**
     * @notice Internal helper to sells YES or NO outcome tokens.
     * @param collateralAmount Desired collateral to receive.
     * @param maxOutcomeTokens Maximum outcome tokens willing to spend.
     * @param isYes True to sell YES, false to sell NO.
     */
    function _sell(uint256 collateralAmount, uint256 maxOutcomeTokens, bool isYes)
        internal
        moreThanZero(collateralAmount)
    {
        (uint256 yesReserve, uint256 noReserve) = conditionalToken.getPoolBalances(yesTokenId, noTokenId);
        uint256 fee = calculateFeeFromNet(collateralAmount);
        uint256 collateralOutPlusFee = collateralAmount + fee;

        uint256 amountIn;
        if (isYes) {
            amountIn = yesReserve.sellAmount(noReserve, collateralOutPlusFee);
        } else {
            amountIn = noReserve.sellAmount(yesReserve, collateralOutPlusFee);
        }

        if (amountIn > maxOutcomeTokens) revert PredictionMarket__MaximumInputExceeded();

        conditionalToken.transferPositionFrom(msg.sender, address(this), isYes ? yesTokenId : noTokenId, amountIn);
        conditionalToken.mergePosition(collateral, conditionId, collateralOutPlusFee);
        IERC20(collateral).safeTransfer(msg.sender, collateralAmount);
        emit Sold(msg.sender, isYes ? yesTokenId : noTokenId, collateralAmount, fee, amountIn);
    }

    /**
     * @dev Adds liquidity and mints LP shares based on current reserve ratio.
     *      Excess conditional tokens are returned to maintain pool proportions.
     * @param collateralAmount Amount of collateral deposited.
     */
    function _addLiquidity(uint256 collateralAmount) internal moreThanZero(collateralAmount) {
        uint256 supply = IERC20(lpToken).totalSupply();

        uint256 shares;
        uint256 yesReserve;
        uint256 noReserve;

        if (supply == 0) {
            shares = collateralAmount;
        } else {
            (yesReserve, noReserve) = conditionalToken.getPoolBalances(yesTokenId, noTokenId);
            uint256 poolWeight = yesReserve > noReserve ? yesReserve : noReserve;
            shares = collateralAmount.integerMulDivFloor(supply, poolWeight);
        }

        if (shares == 0) revert PredictionMarket__InsufficientLiquidity();

        IERC20(collateral).safeTransferFrom(msg.sender, address(this), collateralAmount);
        IERC20(collateral).forceApprove(conditionalToken, collateralAmount);
        conditionalToken.splitPosition(collateral, conditionId, collateralAmount);
        ILPToken(lpToken).mint(msg.sender, shares);

        if (supply > 0) {
            uint256 poolWeight = yesReserve > noReserve ? yesReserve : noReserve;
            uint256 yesKeep = collateralAmount.integerMulDivFloor(yesReserve, poolWeight);
            uint256 noKeep = collateralAmount.integerMulDivFloor(noReserve, poolWeight);

            uint256 yesReturn = collateralAmount - yesKeep;
            uint256 noReturn = collateralAmount - noKeep;

            conditionalToken.transferPositions(msg.sender, yesTokenId, noTokenId, yesReturn, noReturn);
        }
        emit LiquidityAdded(msg.sender, collateralAmount, shares);
    }

    /**
     * @dev Internal helper to check if the market can be resolved if the
     * market is open and the resolution time has passed.
     */
    function _canMarketResolve() internal view {
        // forge-lint: disable-next-line(block-timestamp)
        if (state != MarketState.OPEN || block.timestamp < resolveTime) {
            revert PredictionMarket__MarketCanNotResolve();
        }
    }
}
