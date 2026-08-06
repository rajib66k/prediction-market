// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/**
 * @title Math
 * @author Rajib Kumar Pradhan
 * @notice Collection of mathematical utilities used throughout the prediction market.
 */
library Math {
    error Math__DivisionByZero();
    error Math__MathOverflow();

    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant HALF_PRECISION = 5e17;

    /**
     * @notice Multiplies two values, rounding half up.
     * @return (a * b) / PRECISION
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        if (a > (type(uint256).max - HALF_PRECISION) / b) revert Math__MathOverflow();

        return (a * b + HALF_PRECISION) / PRECISION;
    }

    /**
     * @notice Divides to values, rounding half up.
     * @return (a * PRECISION) / b
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert Math__DivisionByZero();
        if (a > (type(uint256).max - b / 2) / PRECISION) revert Math__MathOverflow();

        return (a * PRECISION + b / 2) / b;
    }

    /**
     * @notice Multiplies two values, rounding down.
     * @return (a * b) / PRECISION
     */
    function mulFloor(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        if (a > type(uint256).max / b) revert Math__MathOverflow();

        return (a * b) / PRECISION;
    }

    /**
     * @notice Multiplies two values, rounding up.
     * @return ceil((a * b) / PRECISION)
     */
    function mulCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        if (a > (type(uint256).max - (PRECISION - 1)) / b) revert Math__MathOverflow();

        return (a * b + PRECISION - 1) / PRECISION;
    }

    /**
     * @notice Divides two values, rounding down.
     * @return (a * PRECISION) / b
     */
    function divFloor(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert Math__DivisionByZero();
        if (a > type(uint256).max / PRECISION) revert Math__MathOverflow();

        return (a * PRECISION) / b;
    }

    /**
     * @notice Divides two values, rounding up.
     * @return ceil((a * PRECISION) / b)
     */
    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert Math__DivisionByZero();
        if (a > (type(uint256).max - (b - 1)) / PRECISION) revert Math__MathOverflow();

        return (a * PRECISION + b - 1) / b;
    }

    /**
     * @notice Calculates ceil((a * b) / c) safely.
     * @dev Prevents overflow from intermediate multiplication.
     */
    function integerMulDivCeil(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if (c == 0) revert Math__DivisionByZero();
        if (a == 0 || b == 0) return 0;

        if (a > type(uint256).max / b) revert Math__MathOverflow();

        uint256 product = a * b;

        return divCeil(product, c);
    }

    /**
     * @notice Calculates floor((a * b) / c) safely.
     * @dev Prevents overflow from intermediate multiplication.
     */
    function integerMulDivFloor(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if (c == 0) revert Math__DivisionByZero();
        if (a == 0 || b == 0) return 0;

        if (a > type(uint256).max / b) revert Math__MathOverflow();

        uint256 product = a * b;

        return product / c;
    }
}
