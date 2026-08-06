// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {FeeLogic} from "./../base/FeeLogic.sol";
import {ERC1155TokenReceiver} from "./../base/ERC1155Receiver.sol";
import {ConditionalTokensOperator} from "./../libraries/ConditionalTokensOperator.sol";
import {Math} from "./../libraries/Math.sol";
import {ILPToken} from "./../interfaces/ILPToken.sol";
import {DataTypes} from "./../types/DataTypes.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
contract PredictionMarket is FeeLogic, ERC1155TokenReceiver {
    error PredictionMarket__NeedMoreThanZero();
    error PredictionMarket__InsufficientLiquidity();
    error PredictionMarket__IsNotPending();
    error PredictionMarket__IsNotOpen();
    error PredictionMarket__LiquidityPeriodEnded();
    error PredictionMarket__LiquidityDeadlineIsNotOver();
    error PredictionMarket__IsNotCancelled();
    error PredictionMarket__NoLiquidity();
    error PredictionMarket__LiquidityTargetReached();

    using ConditionalTokensOperator for address;
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

    /// @notice Emitted when liquidity is added.
    event LiquidityAdded(address indexed provider, uint256 collateralAmount, uint256 lpTokensMinted);

    /// @notice Emitted when liquidity is removed.
    event LiquidityRemoved(address indexed provider, uint256 lpTokensBurned, uint256 yesAmount, uint256 noAmount);

    /// @notice Emitted when cancelled market liquidity is refunded.
    event LiquidityRefunded(address indexed provider, uint256 lpTokensBurned, uint256 collateralAmount);

    /// @notice Emitted whenever the market state changes.
    event MarketStateChanged(MarketState marketState);

    /**
     * @notice Creates a new prediction market.
     * @param params Market initialization parameters.
     */
    constructor(DataTypes.MarketInitParams memory params) {
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
    }

    /// @dev Restricts execution to the pending state.
    modifier onlyPending() {
        if (state != MarketState.PENDING) revert PredictionMarket__IsNotPending();
        _;
    }

    /// @dev Restricts execution to the open state.
    modifier onlyOpen() {
        if (state != MarketState.OPEN) revert PredictionMarket__IsNotOpen();
        _;
    }

    /// @dev Restricts execution to cancelled markets.
    modifier onlyCancelled() {
        if (state != MarketState.CANCELLED) revert PredictionMarket__IsNotCancelled();
        _;
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
    function removeLiquidity(uint256 sharesToBurn) external onlyOpen {
        if (sharesToBurn == 0) revert PredictionMarket__NeedMoreThanZero();

        uint256 supply = IERC20(lpToken).totalSupply();
        if (sharesToBurn > supply) revert PredictionMarket__InsufficientLiquidity();

        (uint256 yesReserve, uint256 noReserve) = conditionalToken.getPoolBalances(yesTokenId, noTokenId);
        uint256 yesAmount = sharesToBurn.integerMulDivFloor(yesReserve, supply);
        uint256 noAmount = sharesToBurn.integerMulDivFloor(noReserve, supply);

        ILPToken(lpToken).burn(msg.sender, sharesToBurn);
        ConditionalTokensOperator.transferPositions(
            conditionalToken, msg.sender, yesTokenId, noTokenId, yesAmount, noAmount
        );
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
            ConditionalTokensOperator.mergePosition(conditionalToken, collateral, conditionId, mergeAmount);
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
     * @dev Adds liquidity and mints LP shares based on current reserve ratio.
     *      Excess conditional tokens are returned to maintain pool proportions.
     * @param collateralAmount Amount of collateral deposited.
     */
    function _addLiquidity(uint256 collateralAmount) internal {
        if (collateralAmount == 0) revert PredictionMarket__NeedMoreThanZero();

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

            ConditionalTokensOperator.transferPositions(
                conditionalToken, msg.sender, yesTokenId, noTokenId, yesReturn, noReturn
            );
        }
        emit LiquidityAdded(msg.sender, collateralAmount, shares);
    }
}
