// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AcuityDexIntrachain} from "../src/AcuityDexIntrachain.sol";
import {ERC20} from "../src/AcuityDexIntrachain.sol";

contract AcuityDexIntrachainHarness is AcuityDexIntrachain {
    function encodeOrderIdHarness(uint96 sellPrice) external view returns (bytes32 order) {
        order = super.encodeOrderId(sellPrice);
    }

    function encodeOrderIdHarness(address account, uint96 sellPrice) external view returns (bytes32 order) {
        order = super.encodeOrderId(account, sellPrice);
    }

    function decodeOrderIdHarness(bytes32 order) external pure returns (address account, uint96 sellPrice) {
        (account, sellPrice) = super.decodeOrderId(order);
    }
    
}

contract DummyToken is ERC20 {

    mapping (address => uint) balances;

    constructor(address[] memory accounts) {
        for (uint i = 0; i < accounts.length; i++) {
            balances[accounts[i]] = 1000;
        }
    }

    function name() external view returns (string memory) {}
    function symbol() external view returns (string memory) {}
    function decimals() external view returns (uint8) {}
    function totalSupply() external view returns (uint) {}
    function balanceOf(address owner) external view returns (uint) {
        return balances[owner];
    }
    function transfer(address to, uint value) external returns (bool success) {
        balances[msg.sender] -= value;
        balances[to] += value;
        return true;
    }
    function transferFrom(address from, address to, uint value) external returns (bool success) {
        balances[from] -= value;
        balances[to] += value;
        return true;
    }
    function approve(address spender, uint value) external returns (bool) {}
    function allowance(address owner, address spender) external view returns (uint remaining) {}
}

contract AcuityDexIntrachainTest is AcuityDexIntrachain, Test {
    AcuityDexIntrachain public dex;
    AcuityDexIntrachainHarness public dexHarness;
    DummyToken dummyToken;

    function setUp() public {
        dex = new AcuityDexIntrachain();
        dexHarness = new AcuityDexIntrachainHarness();
        address[] memory accounts = new address[](1);
        accounts[0] = address(this);
        dummyToken = new DummyToken(accounts);
    }

    function testEncodeDecodeOrderId() public view {
        bytes32 orderId = dexHarness.encodeOrderIdHarness(1234);
        console.logBytes32(orderId);
        (address account, uint96 price) = dexHarness.decodeOrderIdHarness(orderId);
        assertEq(account, address(this));
        assertEq(price, 1234);

        orderId = dexHarness.encodeOrderIdHarness(address(7), 5678);
        console.logBytes32(orderId);
        (account, price) = dexHarness.decodeOrderIdHarness(orderId);
        assertEq(account, address(7));
        assertEq(price, 5678);
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

    function testDepositERC20() public {
        bytes memory error = abi.encodeWithSelector(TokenTransferInFailed.selector, address(dummyToken), address(this), 1001);
        vm.expectRevert(error);
        dex.depositERC20(address(dummyToken), 1001);

        vm.expectEmit(false, false, false, true);
        emit Deposit(address(dummyToken), address(this), 10);
        dex.depositERC20(address(dummyToken), 10);
        assertEq(dex.getBalance(address(dummyToken), address(this)), 10);

        vm.expectEmit(false, false, false, true);
        emit Deposit(address(dummyToken), address(this), 20);
        dex.depositERC20(address(dummyToken), 20);
        assertEq(dex.getBalance(address(dummyToken), address(this)), 30);
    }
}
