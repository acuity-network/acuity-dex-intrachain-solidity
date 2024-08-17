// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AcuityDexIntrachain} from "../src/AcuityDexIntrachain.sol";
import {ERC20} from "../src/AcuityDexIntrachain.sol";

contract AccountProxy {

    AcuityDexIntrachainHarness harness;

    constructor (AcuityDexIntrachainHarness _harness) {
        harness = _harness;
    }

    function _addOrderValueHarness(address sellAsset, address buyAsset, uint96 price, uint value) external {
        harness._addOrderValueHarness(sellAsset, buyAsset, price, value);
    }
    
}

contract AcuityDexIntrachainHarness is AcuityDexIntrachain {
    function encodeOrderIdHarness(uint96 price) external view returns (bytes32 order) {
        order = super.encodeOrderId(price);
    }

    function encodeOrderIdHarness(address account, uint96 price) external pure returns (bytes32 order) {
        order = super.encodeOrderId(account, price);
    }

    function decodeOrderIdHarness(bytes32 order) external pure
        returns (address account, uint96 price)
    {
        (account, price) = super.decodeOrderId(order);
    }
    
    function _addOrderValueHarness(address sellAsset, address buyAsset, uint96 price, uint value) external {
        super._addOrderValue(sellAsset, buyAsset, price, value);
    }
    
    function _removeOrderHarness(address sellAsset, address buyAsset, uint96 price) external {
        super._removeOrder(sellAsset, buyAsset, price);
    }
    
    function _removeOrderValueHarness(address sellAsset, address buyAsset, uint96 price, uint value) external
        returns (uint valueRemoved)
    {
        valueRemoved = super._removeOrderValue(sellAsset, buyAsset, price, value);
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
    AcuityDexIntrachainHarness public harness;
    DummyToken dummyToken;
    AccountProxy account0;
    AccountProxy account1;
    AccountProxy account2;
    AccountProxy account3;

    receive() external payable {}

    function setUp() public {
        harness = new AcuityDexIntrachainHarness();
        account0 = new AccountProxy(harness);
        account1 = new AccountProxy(harness);
        account2 = new AccountProxy(harness);
        account3 = new AccountProxy(harness);

        address[] memory accounts = new address[](5);
        accounts[0] = address(this);
        accounts[1] = address(account0);
        accounts[2] = address(account1);
        accounts[3] = address(account2);
        accounts[4] = address(account3);
        dummyToken = new DummyToken(accounts);
    }

    function testEncodeDecodeOrderId() public view {
        bytes32 orderId = harness.encodeOrderIdHarness(1234);
        console.logBytes32(orderId);
        (address account, uint96 price) = harness.decodeOrderIdHarness(orderId);
        assertEq(account, address(this));
        assertEq(price, 1234);

        orderId = harness.encodeOrderIdHarness(address(7), 5678);
        console.logBytes32(orderId);
        (account, price) = harness.decodeOrderIdHarness(orderId);
        assertEq(account, address(7));
        assertEq(price, 5678);
    }

    function testDeposit() public {
        vm.expectRevert(NoValue.selector);
        harness.deposit();

        vm.expectEmit(false, false, false, true);
        emit Deposit(address(0), address(this), 1);
        harness.deposit{value: 1}();
        assertEq(harness.getBalance(address(0), address(this)), 1);

        vm.expectEmit(false, false, false, true);
        emit Deposit(address(0), address(this), 12345);
        harness.deposit{value: 12345}();
        assertEq(harness.getBalance(address(0), address(this)), 12346);
    }

    function testDepositERC20() public {
        bytes memory error = abi.encodeWithSelector(DepositFailed.selector, address(dummyToken), address(this), 1001);
        vm.expectRevert(error);
        harness.depositERC20(address(dummyToken), 1001);

        uint oldBalance = dummyToken.balanceOf(address(this));
        vm.expectEmit(false, false, false, true);
        emit Deposit(address(dummyToken), address(this), 10);
        harness.depositERC20(address(dummyToken), 10);
        assertEq(harness.getBalance(address(dummyToken), address(this)), 10);
        uint newBalance = dummyToken.balanceOf(address(this));
        assertEq(oldBalance - newBalance, 10);

        oldBalance = dummyToken.balanceOf(address(this));
        vm.expectEmit(false, false, false, true);
        emit Deposit(address(dummyToken), address(this), 20);
        harness.depositERC20(address(dummyToken), 20);
        assertEq(harness.getBalance(address(dummyToken), address(this)), 30);
        newBalance = dummyToken.balanceOf(address(this));
        assertEq(oldBalance - newBalance, 20);
    }

    function testWithdraw() public {
        harness.deposit{value: 1}();
        vm.expectRevert(InsufficientBalance.selector);
        harness.withdraw(address(0), 2);
        
        uint oldBalance = address(this).balance;
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(0), address(this), 1);
        harness.withdraw(address(0), 1);
        assertEq(harness.getBalance(address(0), address(this)), 0);
        uint newBalance = address(this).balance;
        assertEq(newBalance - oldBalance, 1);

        harness.depositERC20(address(dummyToken), 10);
        vm.expectRevert(InsufficientBalance.selector);
        harness.withdraw(address(dummyToken), 11);

        oldBalance = dummyToken.balanceOf(address(this));
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(dummyToken), address(this), 1);
        harness.withdraw(address(dummyToken), 1);
        assertEq(harness.getBalance(address(dummyToken), address(this)), 9);
        newBalance = dummyToken.balanceOf(address(this));
        assertEq(newBalance - oldBalance, 1);

        oldBalance = dummyToken.balanceOf(address(this));
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(dummyToken), address(this), 9);
        harness.withdraw(address(dummyToken), 9);
        assertEq(harness.getBalance(address(dummyToken), address(this)), 0);
        newBalance = dummyToken.balanceOf(address(this));
        assertEq(newBalance - oldBalance, 9);
    }

    function testWithdrawAll() public {
        vm.expectRevert(InsufficientBalance.selector);
        harness.withdrawAll(address(0));
        
        harness.deposit{value: 80}();
        uint oldBalance = address(this).balance;
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(0), address(this), 80);
        harness.withdrawAll(address(0));
        assertEq(harness.getBalance(address(0), address(this)), 0);
        uint newBalance = address(this).balance;
        assertEq(newBalance - oldBalance, 80);
        
        harness.depositERC20(address(dummyToken), 10);
        oldBalance = dummyToken.balanceOf(address(this));
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(dummyToken), address(this), 10);
        harness.withdrawAll(address(dummyToken));
        assertEq(harness.getBalance(address(dummyToken), address(this)), 0);
        newBalance = dummyToken.balanceOf(address(this));
        assertEq(newBalance - oldBalance, 10);
    }

    function test_AddOrderValue() public {
        vm.expectRevert(AssetsNotDifferent.selector);
        harness._addOrderValueHarness(address(7), address(7), 82, 90);
        vm.expectRevert(NoValue.selector);
        harness._addOrderValueHarness(address(7), address(8), 82, 0);

        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(7), address(8), address(this), 82, 90);
        harness._addOrderValueHarness(address(7), address(8), 82, 90);
        Order[] memory orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 82);
        assertEq(orderBook[0].value, 90);

        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(7), address(8), address(this), 18, 90);
        harness._addOrderValueHarness(address(7), address(8), 18, 90);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 2);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 90);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 82);
        assertEq(orderBook[1].value, 90);

        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(7), address(8), address(this), 18, 90);
        harness._addOrderValueHarness(address(7), address(8), 18, 90);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 2);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 180);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 82);
        assertEq(orderBook[1].value, 90);

        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(7), address(8), address(this), 17, 60);
        harness._addOrderValueHarness(address(7), address(8), 17, 60);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 3);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 82);
        assertEq(orderBook[2].value, 90);

        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(7), address(8), address(this), 19, 61);
        harness._addOrderValueHarness(address(7), address(8), 19, 61);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 4);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 19);
        assertEq(orderBook[2].value, 61);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 82);
        assertEq(orderBook[3].value, 90);

        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(7), address(8), address(this), 1000, 1);
        harness._addOrderValueHarness(address(7), address(8), 1000, 1);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 5);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 19);
        assertEq(orderBook[2].value, 61);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 82);
        assertEq(orderBook[3].value, 90);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 1000);
        assertEq(orderBook[4].value, 1);

        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(7), address(8), address(this), 999, 1);
        harness._addOrderValueHarness(address(7), address(8), 999, 1);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 6);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 19);
        assertEq(orderBook[2].value, 61);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 82);
        assertEq(orderBook[3].value, 90);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 999);
        assertEq(orderBook[4].value, 1);
        assertEq(orderBook[5].account, address(this));
        assertEq(orderBook[5].price, 1000);
        assertEq(orderBook[5].value, 1);

        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(7), address(8), address(this), 1001, 1);
        harness._addOrderValueHarness(address(7), address(8), 1001, 1);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 7);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 19);
        assertEq(orderBook[2].value, 61);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 82);
        assertEq(orderBook[3].value, 90);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 999);
        assertEq(orderBook[4].value, 1);
        assertEq(orderBook[5].account, address(this));
        assertEq(orderBook[5].price, 1000);
        assertEq(orderBook[5].value, 1);
        assertEq(orderBook[6].account, address(this));
        assertEq(orderBook[6].price, 1001);
        assertEq(orderBook[6].value, 1);

        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(7), address(8), address(account0), 18, 90);
        account0._addOrderValueHarness(address(7), address(8), 18, 90);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 8);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[2].account, address(account0));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 19);
        assertEq(orderBook[3].value, 61);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 82);
        assertEq(orderBook[4].value, 90);
        assertEq(orderBook[5].account, address(this));
        assertEq(orderBook[5].price, 999);
        assertEq(orderBook[5].value, 1);
        assertEq(orderBook[6].account, address(this));
        assertEq(orderBook[6].price, 1000);
        assertEq(orderBook[6].value, 1);
        assertEq(orderBook[7].account, address(this));
        assertEq(orderBook[7].price, 1001);
        assertEq(orderBook[7].value, 1);
    }

    function testAddOrderValue() public {
        vm.expectRevert(InsufficientBalance.selector);
        harness.addOrderValue(address(0), address(8), 18, 90);

        harness.deposit{value: 100}();
        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(0), address(8), address(this), 18, 90);
        harness.addOrderValue(address(0), address(8), 18, 90);
        assertEq(harness.getBalance(address(0), address(this)), 10);

        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(0), address(8), address(this), 18, 10);
        harness.addOrderValue(address(0), address(8), 18, 10);
        assertEq(harness.getBalance(address(0), address(this)), 0);
    }

    function testAddOrderWithDeposit() public {
        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(0), address(8), address(this), 18, 90);
        harness.addOrderValueWithDeposit{value: 90}(address(8), 18);
    }

    function testAddOrderWithDepositERC20() public {
        uint oldBalance = dummyToken.balanceOf(address(this));
        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(dummyToken), address(8), address(this), 18, 90);
        harness.addOrderValueWithDepositERC20(address(dummyToken), address(8), 18, 90);
        uint newBalance = dummyToken.balanceOf(address(this));
        assertEq(oldBalance - newBalance, 90);
    }
    
    function test_RemoveOrder() public {
        vm.expectRevert(AssetsNotDifferent.selector);
        harness._removeOrderHarness(address(7), address(7), 82);
        vm.expectRevert(OrderNotFound.selector);
        harness._removeOrderHarness(address(7), address(8), 82);

        harness.addOrderValueWithDeposit{value: 90}(address(8), 18);
        Order[] memory orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 90);
        
        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 90);
        harness._removeOrderHarness(address(0), address(8), 18);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 0);

        harness.addOrderValueWithDeposit{value: 90}(address(8), 18);
        harness.addOrderValueWithDeposit{value: 91}(address(8), 17);
        harness.addOrderValueWithDeposit{value: 94}(address(8), 16);
        harness.addOrderValueWithDeposit{value: 93}(address(8), 180972);
        harness.addOrderValueWithDeposit{value: 946}(address(8), 180973);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 5);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 94);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 17);
        assertEq(orderBook[1].value, 91);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 180972);
        assertEq(orderBook[3].value, 93);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 180973);
        assertEq(orderBook[4].value, 946);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 16, 94);
        harness._removeOrderHarness(address(0), address(8), 16);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 4);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 91);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 90);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 180972);
        assertEq(orderBook[2].value, 93);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 180973);
        assertEq(orderBook[3].value, 946);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 90);
        harness._removeOrderHarness(address(0), address(8), 18);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 3);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 91);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 180972);
        assertEq(orderBook[1].value, 93);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 180973);
        assertEq(orderBook[2].value, 946);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 180973, 946);
        harness._removeOrderHarness(address(0), address(8), 180973);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 2);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 91);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 180972);
        assertEq(orderBook[1].value, 93);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 180972, 93);
        harness._removeOrderHarness(address(0), address(8), 180972);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 91);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 17, 91);
        harness._removeOrderHarness(address(0), address(8), 17);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 0);
    }

    function testRemoveOrder() public {
        harness.addOrderValueWithDeposit{value: 90}(address(8), 18);

        uint oldBalance = harness.getBalance(address(0), address(this));
        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 90);
        harness.removeOrder(address(0), address(8), 18);
        uint newBalance = harness.getBalance(address(0), address(this));
        assertEq(newBalance - oldBalance, 90);
    }

    function testRemoveOrderAndWithdraw() public {
        harness.addOrderValueWithDeposit{value: 90}(address(8), 18);

        uint oldBalance = address(this).balance;
        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 90);
        harness.removeOrderAndWithdraw(address(0), address(8), 18);
        uint newBalance = address(this).balance;
        assertEq(newBalance - oldBalance, 90);
    }

    function test_RemoveOrderValue() public {
        vm.expectRevert(AssetsNotDifferent.selector);
        harness._removeOrderValueHarness(address(7), address(7), 82, 8);
        vm.expectRevert(NoValue.selector);
        harness._removeOrderValueHarness(address(7), address(8), 82, 0);
        vm.expectRevert(OrderNotFound.selector);
        harness._removeOrderValueHarness(address(7), address(8), 82, 9);

        harness.addOrderValueWithDeposit{value: 90}(address(8), 18);
        Order[] memory orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 90);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 1);
        uint valueRemoved = harness._removeOrderValueHarness(address(0), address(8), 18, 1);
        assertEq(valueRemoved, 1);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 89);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 88);
        valueRemoved = harness._removeOrderValueHarness(address(0), address(8), 18, 88);
        assertEq(valueRemoved, 88);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 1);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 1);
        valueRemoved = harness._removeOrderValueHarness(address(0), address(8), 18, 1);
        assertEq(valueRemoved, 1);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 0);

        harness.addOrderValueWithDeposit{value: 90}(address(8), 18);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 90);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 90);
        valueRemoved = harness._removeOrderValueHarness(address(0), address(8), 18, 100);
        assertEq(valueRemoved, 90);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 0);

        harness.addOrderValueWithDeposit{value: 90}(address(8), 18);
        harness.addOrderValueWithDeposit{value: 91}(address(8), 17);
        harness.addOrderValueWithDeposit{value: 94}(address(8), 16);
        harness.addOrderValueWithDeposit{value: 93}(address(8), 180972);
        harness.addOrderValueWithDeposit{value: 946}(address(8), 180973);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 5);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 94);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 17);
        assertEq(orderBook[1].value, 91);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 180972);
        assertEq(orderBook[3].value, 93);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 180973);
        assertEq(orderBook[4].value, 946);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 180973, 946);
        valueRemoved = harness._removeOrderValueHarness(address(0), address(8), 180973, 946);
        assertEq(valueRemoved, 946);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 4);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 94);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 17);
        assertEq(orderBook[1].value, 91);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 180972);
        assertEq(orderBook[3].value, 93);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 180972, 93);
        valueRemoved = harness._removeOrderValueHarness(address(0), address(8), 180972, 946);
        assertEq(valueRemoved, 93);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 3);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 94);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 17);
        assertEq(orderBook[1].value, 91);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 16, 93);
        valueRemoved = harness._removeOrderValueHarness(address(0), address(8), 16, 93);
        assertEq(valueRemoved, 93);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 3);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 1);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 17);
        assertEq(orderBook[1].value, 91);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 17, 91);
        valueRemoved = harness._removeOrderValueHarness(address(0), address(8), 17, 91);
        assertEq(valueRemoved, 91);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 2);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 1);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 90);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 90);
        valueRemoved = harness._removeOrderValueHarness(address(0), address(8), 18, 91);
        assertEq(valueRemoved, 90);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 1);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 16, 1);
        valueRemoved = harness._removeOrderValueHarness(address(0), address(8), 16, 1);
        assertEq(valueRemoved, 1);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 0);
    }
    
    function testRemoveOrderValue() public {
        harness.addOrderValueWithDeposit{value: 90}(address(8), 18);

        uint oldBalance = harness.getBalance(address(0), address(this));
        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 90);
        harness.removeOrderValue(address(0), address(8), 18, 91);
        uint newBalance = harness.getBalance(address(0), address(this));
        assertEq(newBalance - oldBalance, 90);
    }

    function testRemoveOrderValueAndWithdraw() public {
        harness.addOrderValueWithDeposit{value: 90}(address(8), 18);

        uint oldBalance = address(this).balance;
        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), address(this), 18, 80);
        harness.removeOrderValueAndWithdraw(address(0), address(8), 18, 80);
        uint newBalance = address(this).balance;
        assertEq(newBalance - oldBalance, 80);
    }

    function testMatchOrders() public {
        
    }
}
