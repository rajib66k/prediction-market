// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {Math} from "../../src/libraries/Math.sol";

/// forge-config: default.allow_internal_expect_revert = true
contract MathTest is Test {
    function testMulReturnsZero() public pure {
        assertEq(Math.mul(0, 1e18), 0);
        assertEq(Math.mul(1e18, 0), 0);
        assertEq(Math.mul(0, 0), 0);
    }

    function testMulRevertIfOverflow(uint256 a, uint256 b) public {
        b = bound(b, 1, type(uint96).max);
        a = bound(a, ((type(uint256).max - Math.HALF_PRECISION) / b) + 1, type(uint256).max);

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.mul(a, b);
    }

    function testMul(uint256 a, uint256 b) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, (type(uint256).max - Math.HALF_PRECISION) / b);

        assertEq(Math.mul(a, b), (a * b + Math.HALF_PRECISION) / Math.PRECISION);
    }

    function testDivRevertIfDenominatorIsZero() public {
        vm.expectRevert(Math.Math__DivisionByZero.selector);
        Math.div(1e18, 0);
    }

    function testDivRevertIfOverflow(uint256 b) public {
        b = bound(b, 1, type(uint96).max);
        uint256 a = (type(uint256).max - b / 2) / Math.PRECISION + 1;

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.div(a, b);
    }

    function testDiv(uint256 a, uint256 b) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, (type(uint256).max - b / 2) / Math.PRECISION);

        assertEq(Math.div(a, b), (a * Math.PRECISION + b / 2) / b);
    }

    function testMulFloorReturnsZero() public pure {
        assertEq(Math.mulFloor(0, 1e18), 0);
        assertEq(Math.mulFloor(1e18, 0), 0);
        assertEq(Math.mulFloor(0, 0), 0);
    }

    function testMulFloorIfOverflow(uint256 a, uint256 b) public {
        b = bound(b, 2, type(uint96).max);
        a = bound(a, (type(uint256).max / b) + 1, type(uint256).max);

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.mulFloor(a, b);
    }

    function testMulFloor(uint256 a, uint256 b) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, type(uint256).max / b);

        assertEq(Math.mulFloor(a, b), (a * b) / Math.PRECISION);
    }

    function testMulCeilReturnsZero() public pure {
        assertEq(Math.mulCeil(0, 1e18), 0);
        assertEq(Math.mulCeil(1e18, 0), 0);
        assertEq(Math.mulCeil(0, 0), 0);
    }

    function testMulCeilIfOverflow(uint256 a, uint256 b) public {
        b = bound(b, 2, type(uint96).max);
        a = bound(a, ((type(uint256).max - (Math.PRECISION - 1)) / b) + 1, type(uint256).max);

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.mulCeil(a, b);
    }

    function testMulCeil(uint256 a, uint256 b) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, (type(uint256).max - (Math.PRECISION - 1)) / b);

        assertEq(Math.mulCeil(a, b), (a * b + Math.PRECISION - 1) / Math.PRECISION);
    }

    function testDivFloorRevertIfDenominatorIsZero() public {
        vm.expectRevert(Math.Math__DivisionByZero.selector);
        Math.divFloor(1e18, 0);
    }

    function testDivFloorRevertIfOverflow(uint256 b) public {
        b = bound(b, 1, type(uint96).max);
        uint256 a = type(uint256).max / Math.PRECISION + 1;

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.divFloor(a, b);
    }

    function testDivFloor(uint256 a, uint256 b) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, type(uint256).max / Math.PRECISION);

        assertEq(Math.divFloor(a, b), (a * Math.PRECISION) / b);
    }

    function testDivCeilRevertIfDenominatorIsZero() public {
        vm.expectRevert(Math.Math__DivisionByZero.selector);
        Math.divCeil(1e18, 0);
    }

    function testDivCeilRevertIfOverflow(uint256 b) public {
        b = bound(b, 1, type(uint96).max);
        uint256 a = (type(uint256).max - (b - 1)) / Math.PRECISION + 1;

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.divCeil(a, b);
    }

    function testDivCeil(uint256 a, uint256 b) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, (type(uint256).max - (b - 1)) / Math.PRECISION);

        assertEq(Math.divCeil(a, b), (a * Math.PRECISION + b - 1) / b);
    }

    function testIntegerMulDivCeilRevertIfDenominatorIsZero() public {
        vm.expectRevert(Math.Math__DivisionByZero.selector);
        Math.integerMulDivCeil(1e18, 1e18, 0);
    }

    function testIntegerMulDivCeilReturnsZero() public pure {
        assertEq(Math.integerMulDivCeil(0, 1e18, 1e18), 0);
        assertEq(Math.integerMulDivCeil(1e18, 0, 1e18), 0);
        assertEq(Math.integerMulDivCeil(0, 0, 1e18), 0);
    }

    function testIntegerMulDivCeilRevertIfMultiplicationOverflows() public {
        uint256 a = type(uint256).max;
        uint256 b = 2;

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.integerMulDivCeil(a, b, 1e18);
    }

    function testIntegerMulDivCeilRevertIfRoundingOverflows() public {
        uint256 a = type(uint256).max;
        uint256 b = 1;
        uint256 c = 2;

        vm.expectRevert();
        Math.integerMulDivCeil(a, b, c);
    }

    function testIntegerMulDivCeil(uint256 a, uint256 b, uint256 c) public pure {
        b = bound(b, 1e8, type(uint96).max);
        c = bound(c, 1e8, type(uint96).max);
        a = bound(a, 1e8, (type(uint256).max - (c - 1)) / b);

        uint256 product = a * b;
        assertEq(Math.integerMulDivCeil(a, b, c), (product + c - 1) / c);
    }

    function testIntegerMulDivFloorRevertIfDenominatorIsZero() public {
        vm.expectRevert(Math.Math__DivisionByZero.selector);
        Math.integerMulDivFloor(1e18, 1e18, 0);
    }

    function testIntegerMulDivFloorReturnsZero() public pure {
        assertEq(Math.integerMulDivFloor(0, 1e18, 1e18), 0);
        assertEq(Math.integerMulDivFloor(1e18, 0, 1e18), 0);
        assertEq(Math.integerMulDivFloor(0, 0, 1e18), 0);
    }

    function testIntegerMulDivFloorRevertIfMultiplicationOverflows() public {
        uint256 a = type(uint256).max;
        uint256 b = 2;

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.integerMulDivFloor(a, b, 1e18);
    }

    function testIntegerMulDivFloor(uint256 a, uint256 b, uint256 c) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, type(uint256).max / b);
        c = bound(c, 1e8, type(uint96).max);

        uint256 product = a * b;
        assertEq(Math.integerMulDivFloor(a, b, c), product / c);
    }
}
