// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AcuityDexIntrachain} from "../src/AcuityDexIntrachain.sol";

contract AcuityDexIntrachainHarness is AcuityDexIntrachain {
    function encodeOrderIdHarness(uint96 sellPrice) external view returns (bytes32 order) {
        order = super.encodeOrderId(sellPrice);
    }

    function decodeOrderIdHarness(bytes32 order) external pure returns (address account, uint96 sellPrice) {
        (account, sellPrice) = super.decodeOrderId(order);
    }
    
}

contract AcuityDexIntrachainTest is AcuityDexIntrachain, Test {

    AcuityDexIntrachain public dex;
    AcuityDexIntrachainHarness public dexHarness;

    function setUp() public {
        dex = new AcuityDexIntrachain();
        dexHarness = new AcuityDexIntrachainHarness();
    }

    function testEncodeDecodeOrderId() public view {
        bytes32 orderId = dexHarness.encodeOrderIdHarness(5678);
        console.logBytes32(orderId);
        (address account, uint96 price) = dexHarness.decodeOrderIdHarness(orderId);
        assertEq(account, address(this));
        assertEq(price, 5678);
    }

    function testAdjustOrderPrice() public {
        
    }

    function testDeposit() public {
        vm.expectRevert(NoValue.selector);
        dex.deposit();

        vm.expectEmit(false, false, false, true);
        emit Deposit(address(0), address(this), 1);
        dex.deposit{value: 1}();
        assertEq(dex.getBalance(address(0), address(this)), 1);

        vm.expectEmit(false, false, false, true);
        emit Deposit(address(0), address(this), 12345);
        dex.deposit{value: 12345}();
        assertEq(dex.getBalance(address(0), address(this)), 12346);
    }
}
