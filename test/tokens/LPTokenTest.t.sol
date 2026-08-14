// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test, console} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {LPToken} from "../../src/tokens/LPToken.sol";

contract LPTokenTest is Test {
    LPToken lpToken;

    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    address market = makeAddr("market");

    function setUp() public {
        LPToken implementation = new LPToken();

        address clone = Clones.clone(address(implementation));
        lpToken = LPToken(clone);

        lpToken.initialize(market, "Prediction Market LP", "PMLP");
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    function testConstructor() public view {
        console.log(lpToken.name());
        assertEq(lpToken.name(), "Prediction Market LP");
        assertEq(lpToken.symbol(), "PMLP");
        assertEq(lpToken.owner(), market);
        assertEq(lpToken.decimals(), 18);
    }

    ///////////////////////////
    // Initialize Tests //
    ///////////////////////////
    function testInitializeRevertIfZeroAddress() public {
        LPToken implementation = new LPToken();

        address clone = Clones.clone(address(implementation));
        LPToken token = LPToken(clone);

        vm.expectRevert(LPToken.LPToken__NotZeroAddress.selector);
        token.initialize(address(0), "", "");
    }

    function testInitializeRevertIfAlreadyInitialized() public {
        vm.expectRevert();
        lpToken.initialize(user, "", "");
    }

    ///////////////////////////
    // Mint and Burn Tests //
    ///////////////////////////
    function testMint() public {
        uint256 amount = 100 ether;

        vm.prank(market);
        lpToken.mint(user, amount);

        assertEq(lpToken.balanceOf(user), amount);
        assertEq(lpToken.totalSupply(), amount);
    }

    function testMintRevertIfZeroAddress() public {
        vm.prank(market);
        vm.expectRevert(LPToken.LPToken__NotZeroAddress.selector);
        lpToken.mint(address(0), 100 ether);
    }

    function testMintRevertIfZero() public {
        vm.prank(market);
        vm.expectRevert(LPToken.LPToken__MustBeMoreThanZero.selector);
        lpToken.mint(user, 0);
    }

    function testMintRevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        lpToken.mint(user, 100 ether);
    }

    function testBurn() public {
        uint256 amount = 100 ether;

        vm.startPrank(market);
        lpToken.mint(user, amount);
        lpToken.burn(user, amount);
        vm.stopPrank();

        assertEq(lpToken.balanceOf(user), 0);
        assertEq(lpToken.totalSupply(), 0);
    }

    function testBurnRevertIfZeroAddress() public {
        vm.prank(market);
        vm.expectRevert(LPToken.LPToken__NotZeroAddress.selector);
        lpToken.burn(address(0), 100 ether);
    }

    function testBurnRevertIfZero() public {
        vm.prank(market);
        vm.expectRevert(LPToken.LPToken__MustBeMoreThanZero.selector);
        lpToken.burn(user, 0);
    }

    function testBurnRevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        lpToken.burn(user, 100 ether);
    }

    function testBurnRevertIfInsufficientBalance() public {
        vm.startPrank(market);
        lpToken.mint(user, 100 ether);

        vm.expectRevert();
        lpToken.burn(user, 200 ether);
        vm.stopPrank();
    }

    ///////////////////////////////
    // Transfer On Behalf Tests //
    ///////////////////////////////
    function testTransferOnBehalf() public {
        uint256 amount = 100 ether;

        vm.startPrank(market);
        lpToken.mint(user, amount);
        bool result = lpToken.transferOnBehalf(user, user2, 40 ether);
        vm.stopPrank();

        assertTrue(result);
        assertEq(lpToken.balanceOf(user), 60 ether);
        assertEq(lpToken.balanceOf(user2), 40 ether);
        assertEq(lpToken.totalSupply(), amount);
    }

    function testTransferOnBehalfRevertIfZero() public {
        vm.startPrank(market);
        lpToken.mint(user, 100 ether);

        vm.expectRevert(LPToken.LPToken__MustBeMoreThanZero.selector);
        lpToken.transferOnBehalf(user, user2, 0);
        vm.stopPrank();
    }

    function testTransferOnBehalfRevertIfNotOwner() public {
        vm.prank(market);
        lpToken.mint(user, 100 ether);

        vm.prank(user);
        vm.expectRevert();
        lpToken.transferOnBehalf(user, user2, 40 ether);
    }

    function testTransferOnBehalfRevertIfInsufficientBalance() public {
        vm.startPrank(market);
        lpToken.mint(user, 100 ether);

        vm.expectRevert();
        lpToken.transferOnBehalf(user, user2, 200 ether);
        vm.stopPrank();
    }

    function testTransferOnBehalfToZeroAddressRevert() public {
        vm.startPrank(market);
        lpToken.mint(user, 100 ether);

        vm.expectRevert();
        lpToken.transferOnBehalf(user, address(0), 100 ether);
        vm.stopPrank();
    }

    function testTransferOnBehalfFromZeroAddressRevert() public {
        vm.prank(market);
        vm.expectRevert();
        lpToken.transferOnBehalf(address(0), user, 100 ether);
    }

    /////////////////////////////
    // Decimals and BalanceOf //
    /////////////////////////////
    function testDecimals() public view {
        assertEq(lpToken.decimals(), 18);
    }

    function testBalanceOf() public {
        vm.prank(market);
        lpToken.mint(user, 100 ether);

        assertEq(lpToken.balanceOf(user), 100 ether);
    }

    function testTotalSupply() public {
        vm.startPrank(market);
        lpToken.mint(user, 100 ether);
        lpToken.mint(user2, 200 ether);
        vm.stopPrank();

        assertEq(lpToken.totalSupply(), 300 ether);
    }

    function testBalanceOfZeroBalance() public view {
        assertEq(lpToken.balanceOf(user), 0);
    }

    function testTotalSupplyZero() public view {
        assertEq(lpToken.totalSupply(), 0);
    }

    /////////////////////////////////
    // Unsupported Functions Tests //
    /////////////////////////////////
    function testTransferRevert() public {
        vm.expectRevert(LPToken.LPToken__OperationNotSupported.selector);
        bool success = lpToken.transfer(user, 100 ether);
        assertFalse(success);
    }

    function testTransferFromRevert() public {
        vm.expectRevert(LPToken.LPToken__OperationNotSupported.selector);
        bool success = lpToken.transferFrom(user, user2, 100 ether);
        assertFalse(success);
    }

    function testApproveRevert() public {
        vm.expectRevert(LPToken.LPToken__OperationNotSupported.selector);
        lpToken.approve(user, 100 ether);
    }

    function testAllowance() public view {
        assertEq(lpToken.allowance(user, user2), 0);
    }

    ////////////////////
    // Full Flow Test //
    ////////////////////
    function testFullFlow() public {
        vm.startPrank(market);
        lpToken.mint(user, 1_000 ether);

        bool result = lpToken.transferOnBehalf(user, user2, 300 ether);

        assertTrue(result);
        assertEq(lpToken.balanceOf(user), 700 ether);
        assertEq(lpToken.balanceOf(user2), 300 ether);
        assertEq(lpToken.totalSupply(), 1_000 ether);

        lpToken.burn(user2, 100 ether);
        vm.stopPrank();

        assertEq(lpToken.balanceOf(user), 700 ether);
        assertEq(lpToken.balanceOf(user2), 200 ether);
        assertEq(lpToken.totalSupply(), 900 ether);
    }
}
