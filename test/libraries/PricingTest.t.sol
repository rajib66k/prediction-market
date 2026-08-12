// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {Pricing} from "../../src/libraries/Pricing.sol";

/// forge-config: default.allow_internal_expect_revert = true
contract PricingTest is Test {
    function testBuyAmountRevertIfBuyReserveIsZero() public {
        vm.expectRevert(Pricing.Pricing__InsufficientLiquidity.selector);
        Pricing.buyAmount(0, 1e18, 1e18);
    }

    function testBuyAmountRevertIfOtherReserveIsZero() public {
        vm.expectRevert(Pricing.Pricing__InsufficientLiquidity.selector);
        Pricing.buyAmount(1e18, 0, 1e18);
    }

    function testBuyAmountReturnsCollateralIfCollateralIsZero() public pure {
        assertEq(Pricing.buyAmount(1e18, 1e18, 0), 0);
        assertEq(Pricing.buyAmount(1e18, 2e18, 0), 0);
        assertEq(Pricing.buyAmount(2e18, 1e18, 0), 0);
    }

    function testBuyAmount(uint256 buyReserve, uint256 otherReserve, uint256 collateralInMinusFee) public pure {
        buyReserve = bound(buyReserve, 1e8, type(uint96).max);
        otherReserve = bound(otherReserve, 1e8, type(uint96).max);
        collateralInMinusFee = bound(collateralInMinusFee, 1e8, type(uint96).max);

        uint256 product = buyReserve * otherReserve;
        uint256 denominator = otherReserve + collateralInMinusFee;
        uint256 endingReserve = (product + denominator - 1) / denominator;

        assertEq(
            Pricing.buyAmount(buyReserve, otherReserve, collateralInMinusFee),
            buyReserve + collateralInMinusFee - endingReserve
        );
    }

    function testSellAmountRevertIfSellReserveIsZero() public {
        vm.expectRevert(Pricing.Pricing__InsufficientLiquidity.selector);
        Pricing.sellAmount(0, 1e18, 1e18);
    }

    function testSellAmountRevertIfOtherReserveIsZero() public {
        vm.expectRevert(Pricing.Pricing__InsufficientLiquidity.selector);
        Pricing.sellAmount(1e18, 0, 1e18);
    }

    function testSellAmountRevertIfCollateralOutPlusFeeEqualsOtherReserve() public {
        vm.expectRevert(Pricing.Pricing__InsufficientLiquidity.selector);
        Pricing.sellAmount(1e18, 1e18, 1e18);
    }

    function testSellAmountRevertIfCollateralOutPlusFeeExceedsOtherReserve() public {
        vm.expectRevert(Pricing.Pricing__InsufficientLiquidity.selector);
        Pricing.sellAmount(1e18, 1e18, 1e18 + 1);
    }

    function testSellAmountReturnsZeroIfCollateralIsZero() public pure {
        assertEq(Pricing.sellAmount(1e18, 1e18, 0), 0);
        assertEq(Pricing.sellAmount(1e18, 2e18, 0), 0);
        assertEq(Pricing.sellAmount(2e18, 1e18, 0), 0);
    }

    function testSellAmount(uint256 sellReserve, uint256 otherReserve, uint256 collateralOutPlusFee) public pure {
        sellReserve = bound(sellReserve, 1e8, type(uint96).max);
        otherReserve = bound(otherReserve, 1e8, type(uint96).max);
        collateralOutPlusFee = bound(collateralOutPlusFee, 1e8 - 1, otherReserve - 1);

        uint256 product = sellReserve * otherReserve;
        uint256 denominator = otherReserve - collateralOutPlusFee;
        uint256 endingReserve = (product + denominator - 1) / denominator;

        assertEq(
            Pricing.sellAmount(sellReserve, otherReserve, collateralOutPlusFee),
            collateralOutPlusFee + endingReserve - sellReserve
        );
    }
}
