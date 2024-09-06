// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {AcuityDexIntrachain} from "../src/AcuityDexIntrachain.sol";
import {ERC20} from "../src/AcuityDexIntrachain.sol";

contract AccountProxy {

    AcuityDexIntrachainHarness harness;

    constructor (AcuityDexIntrachainHarness _harness) {
        harness = _harness;
    }

    receive() payable external {}

    function _addOrderValueHarness(AcuityDexIntrachain.SellOrder calldata sellOrder) external {
        harness._addOrderValueHarness(sellOrder);
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
    
    function encodeValueTimeoutHarness(uint224 value, uint32 timeout) external pure returns (bytes32 valueTimeout) {
        valueTimeout = super.encodeValueTimeout(value, timeout);
    }

    function decodeValueTimeoutHarness(bytes32 valueTimeout) external pure returns (uint224 value, uint32 timeout) {
        (value, timeout) = super.decodeValueTimeout(valueTimeout);
    }

    function _addOrderValueHarness(SellOrder calldata sellOrder) external {
        super._addOrderValue(sellOrder);
    }
    
    function _removeOrderHarness(SellOrder calldata sellOrder) external {
        super._removeOrder(sellOrder);
    }
    
    function _removeOrderValueHarness(SellOrder calldata sellOrder) external
        returns (uint valueRemoved)
    {
        valueRemoved = super._removeOrderValue(sellOrder);
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

    function so(address sellAsset, address buyAsset, uint96 price) pure internal
        returns (SellOrder memory sellOrder)
    {
        sellOrder = SellOrder({
            sellAsset: sellAsset,
            buyAsset: buyAsset,
            price: price,
            value: 0,
            timeout: 0,
            prevHint: new bytes32[](0)
        });
    }

    function so(address sellAsset, address buyAsset, uint96 price, uint224 value, uint32 timeout) pure internal
        returns (SellOrder memory sellOrder)
    {
        sellOrder = SellOrder({
            sellAsset: sellAsset,
            buyAsset: buyAsset,
            price: price,
            value: value,
            timeout: timeout,
            prevHint: new bytes32[](0)
        });
    }

    function so(address sellAsset, address buyAsset, uint96 price, uint224 value, uint32 timeout, bytes32[] memory prevHint) pure internal
        returns (SellOrder memory sellOrder)
    {
        sellOrder = SellOrder({
            sellAsset: sellAsset,
            buyAsset: buyAsset,
            price: price,
            value: value,
            timeout: timeout,
            prevHint: prevHint
        });
    }

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

    function testEncodeDecodeValueTimeout() public view {
        bytes32 valueTimeout = harness.encodeValueTimeoutHarness(1234, 5678);
        console.logBytes32(valueTimeout);
        (uint224 value, uint32 timeout) = harness.decodeValueTimeoutHarness(valueTimeout);
        assertEq(value, 1234);
        assertEq(timeout, 5678);

        valueTimeout = harness.encodeValueTimeoutHarness(1234, 0);
        console.logBytes32(valueTimeout);
        (value, timeout) = harness.decodeValueTimeoutHarness(valueTimeout);
        assertEq(value, 1234);
        assertEq(timeout, type(uint32).max);
    }

    function testDeposit() public {
        vm.expectRevert(ValueZero.selector);
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
        vm.expectRevert(InvalidAsset.selector);
        harness.depositERC20(address(this), 1001);

        vm.expectRevert(InvalidAsset.selector);
        harness.depositERC20(address(harness), 1001);

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
        vm.expectRevert(InvalidAsset.selector);
        harness.withdraw(address(this), address(0), 2);

        vm.expectRevert(InvalidAsset.selector);
        harness.withdraw(address(harness), address(0), 2);

        vm.expectRevert(InvalidAddress.selector);
        harness.withdraw(address(0), address(harness), 2);

        vm.expectRevert(ValueZero.selector);
        harness.withdraw(address(0), address(0), 0);

        harness.deposit{value: 1}();
        vm.expectRevert(InsufficientBalance.selector);
        harness.withdraw(address(0), address(0), 2);

        uint oldBalance = address(this).balance;
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(0), address(this), address(this), 1);
        harness.withdraw(address(0), address(0), 1);
        assertEq(harness.getBalance(address(0), address(this)), 0);
        uint newBalance = address(this).balance;
        assertEq(newBalance - oldBalance, 1);

        harness.depositERC20(address(dummyToken), 10);
        vm.expectRevert(InsufficientBalance.selector);
        harness.withdraw(address(dummyToken), address(0), 11);

        oldBalance = dummyToken.balanceOf(address(this));
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(dummyToken), address(this), address(this), 1);
        harness.withdraw(address(dummyToken), address(0), 1);
        assertEq(harness.getBalance(address(dummyToken), address(this)), 9);
        newBalance = dummyToken.balanceOf(address(this));
        assertEq(newBalance - oldBalance, 1);

        oldBalance = dummyToken.balanceOf(address(this));
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(dummyToken), address(this), address(this), 9);
        harness.withdraw(address(dummyToken), address(0), 9);
        assertEq(harness.getBalance(address(dummyToken), address(this)), 0);
        newBalance = dummyToken.balanceOf(address(this));
        assertEq(newBalance - oldBalance, 9);

        harness.deposit{value: 1}();
        vm.expectRevert(InsufficientBalance.selector);
        harness.withdraw(address(0), address(account0), 2);
        
        oldBalance = address(account0).balance;
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(0), address(this), address(account0), 1);
        harness.withdraw(address(0), address(account0), 1);
        assertEq(harness.getBalance(address(0), address(this)), 0);
        newBalance = address(account0).balance;
        assertEq(newBalance - oldBalance, 1);

        harness.depositERC20(address(dummyToken), 10);
        vm.expectRevert(InsufficientBalance.selector);
        harness.withdraw(address(dummyToken), address(account0), 11);

        oldBalance = dummyToken.balanceOf(address(account0));
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(dummyToken), address(this), address(account0), 1);
        harness.withdraw(address(dummyToken), address(account0), 1);
        assertEq(harness.getBalance(address(dummyToken), address(this)), 9);
        newBalance = dummyToken.balanceOf(address(account0));
        assertEq(newBalance - oldBalance, 1);

        oldBalance = dummyToken.balanceOf(address(account0));
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(dummyToken), address(this), address(account0), 9);
        harness.withdraw(address(dummyToken), address(account0), 9);
        assertEq(harness.getBalance(address(dummyToken), address(this)), 0);
        newBalance = dummyToken.balanceOf(address(account0));
        assertEq(newBalance - oldBalance, 9);
    }

    function testWithdrawAll() public {
        vm.expectRevert(InvalidAsset.selector);
        harness.withdrawAll(address(this), address(0));

        vm.expectRevert(InvalidAsset.selector);
        harness.withdrawAll(address(harness), address(0));

        vm.expectRevert(InvalidAddress.selector);
        harness.withdrawAll(address(0), address(harness));

        vm.expectRevert(ValueZero.selector);
        harness.withdrawAll(address(0), address(0));
        
        harness.deposit{value: 80}();
        uint oldBalance = address(this).balance;
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(0), address(this), address(this), 80);
        harness.withdrawAll(address(0), address(0));
        assertEq(harness.getBalance(address(0), address(this)), 0);
        uint newBalance = address(this).balance;
        assertEq(newBalance - oldBalance, 80);
        
        harness.depositERC20(address(dummyToken), 10);
        oldBalance = dummyToken.balanceOf(address(this));
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(dummyToken), address(this), address(this), 10);
        harness.withdrawAll(address(dummyToken), address(0));
        assertEq(harness.getBalance(address(dummyToken), address(this)), 0);
        newBalance = dummyToken.balanceOf(address(this));
        assertEq(newBalance - oldBalance, 10);

        vm.expectRevert(ValueZero.selector);
        harness.withdrawAll(address(0), address(account0));
        
        harness.deposit{value: 80}();
        oldBalance = address(account0).balance;
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(0), address(this), address(account0), 80);
        harness.withdrawAll(address(0), address(account0));
        assertEq(harness.getBalance(address(0), address(this)), 0);
        newBalance = address(account0).balance;
        assertEq(newBalance - oldBalance, 80);
        
        harness.depositERC20(address(dummyToken), 10);
        oldBalance = dummyToken.balanceOf(address(account0));
        vm.expectEmit(false, false, false, true);
        emit Withdrawal(address(dummyToken), address(this), address(account0), 10);
        harness.withdrawAll(address(dummyToken), address(account0));
        assertEq(harness.getBalance(address(dummyToken), address(this)), 0);
        newBalance = dummyToken.balanceOf(address(account0));
        assertEq(newBalance - oldBalance, 10);
    }

    function test_AddOrderValue() public {
        SellOrder memory sellOrder = so(address(7), address(8), 82, 90, 1);
        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(7), address(8), harness.encodeOrderIdHarness(address(this), 82), 90, 1);
        harness._addOrderValueHarness(sellOrder);
        Order[] memory orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 82);
        assertEq(orderBook[0].value, 90);
        assertEq(orderBook[0].timeout, 1);

        sellOrder = so(address(7), address(8), 18, 90, 2);
        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(7), address(8), harness.encodeOrderIdHarness(address(this), 18), 90, 2);
        harness._addOrderValueHarness(sellOrder);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 2);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 90);
        assertEq(orderBook[0].timeout, 2);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 82);
        assertEq(orderBook[1].value, 90);
        assertEq(orderBook[1].timeout, 1);

        sellOrder = so(address(7), address(8), 18, 90, 3);
        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(7), address(8), harness.encodeOrderIdHarness(address(this), 18), 90, 3);
        harness._addOrderValueHarness(sellOrder);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 2);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 180);
        assertEq(orderBook[0].timeout, 3);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 82);
        assertEq(orderBook[1].value, 90);
        assertEq(orderBook[1].timeout, 1);

        sellOrder = so(address(7), address(8), 17, 60, 4);
        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(7), address(8), harness.encodeOrderIdHarness(address(this), 17), 60, 4);
        harness._addOrderValueHarness(sellOrder);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 3);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[0].timeout, 4);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[1].timeout, 3);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 82);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[2].timeout, 1);

        bytes32[] memory prevHint = new bytes32[](1);
        prevHint[0] = harness.encodeOrderIdHarness(address(this), 18);
        sellOrder = so(address(7), address(8), 19, 61, 5, prevHint);
        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(7), address(8), harness.encodeOrderIdHarness(address(this), 19), 61, 5);
        harness._addOrderValueHarness(sellOrder);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 4);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[0].timeout, 4);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[1].timeout, 3);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 19);
        assertEq(orderBook[2].value, 61);
        assertEq(orderBook[2].timeout, 5);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 82);
        assertEq(orderBook[3].value, 90);
        assertEq(orderBook[3].timeout, 1);

        prevHint = new bytes32[](1);
        prevHint[0] = harness.encodeOrderIdHarness(address(this), 18);
        sellOrder = so(address(7), address(8), 1000, 1, 6, prevHint);
        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(7), address(8), harness.encodeOrderIdHarness(address(this), 1000), 1, 6);
        harness._addOrderValueHarness(sellOrder);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 5);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[0].timeout, 4);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[1].timeout, 3);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 19);
        assertEq(orderBook[2].value, 61);
        assertEq(orderBook[2].timeout, 5);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 82);
        assertEq(orderBook[3].value, 90);
        assertEq(orderBook[3].timeout, 1);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 1000);
        assertEq(orderBook[4].value, 1);
        assertEq(orderBook[4].timeout, 6);

        prevHint = new bytes32[](1);
        prevHint[0] = harness.encodeOrderIdHarness(address(this), 82);
        sellOrder = so(address(7), address(8), 999, 1, 7, prevHint);
        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(7), address(8), harness.encodeOrderIdHarness(address(this), 999), 1, 7);
        harness._addOrderValueHarness(sellOrder);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 6);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[0].timeout, 4);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[1].timeout, 3);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 19);
        assertEq(orderBook[2].value, 61);
        assertEq(orderBook[2].timeout, 5);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 82);
        assertEq(orderBook[3].value, 90);
        assertEq(orderBook[3].timeout, 1);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 999);
        assertEq(orderBook[4].value, 1);
        assertEq(orderBook[4].timeout, 7);
        assertEq(orderBook[5].account, address(this));
        assertEq(orderBook[5].price, 1000);
        assertEq(orderBook[5].value, 1);
        assertEq(orderBook[5].timeout, 6);

        prevHint = new bytes32[](2);
        prevHint[0] = harness.encodeOrderIdHarness(address(this), 998);
        prevHint[1] = harness.encodeOrderIdHarness(address(this), 1000);
        sellOrder = so(address(7), address(8), 1001, 1, 8, prevHint);
        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(7), address(8), harness.encodeOrderIdHarness(address(this), 1001), 1, 8);
        harness._addOrderValueHarness(sellOrder);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 7);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[0].timeout, 4);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[1].timeout, 3);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 19);
        assertEq(orderBook[2].value, 61);
        assertEq(orderBook[2].timeout, 5);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 82);
        assertEq(orderBook[3].value, 90);
        assertEq(orderBook[3].timeout, 1);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 999);
        assertEq(orderBook[4].value, 1);
        assertEq(orderBook[4].timeout, 7);
        assertEq(orderBook[5].account, address(this));
        assertEq(orderBook[5].price, 1000);
        assertEq(orderBook[5].value, 1);
        assertEq(orderBook[5].timeout, 6);
        assertEq(orderBook[6].account, address(this));
        assertEq(orderBook[6].price, 1001);
        assertEq(orderBook[6].value, 1);
        assertEq(orderBook[6].timeout, 8);

        prevHint = new bytes32[](2);
        prevHint[0] = harness.encodeOrderIdHarness(address(this), 16);
        prevHint[1] = harness.encodeOrderIdHarness(address(this), 20);
        sellOrder = so(address(7), address(8), 18, 90, 9, prevHint);
        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(7), address(8), harness.encodeOrderIdHarness(address(account0), 18), 90, 9);
        account0._addOrderValueHarness(sellOrder);
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 8);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 60);
        assertEq(orderBook[0].timeout, 4);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 180);
        assertEq(orderBook[1].timeout, 3);
        assertEq(orderBook[2].account, address(account0));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[2].timeout, 9);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 19);
        assertEq(orderBook[3].value, 61);
        assertEq(orderBook[3].timeout, 5);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 82);
        assertEq(orderBook[4].value, 90);
        assertEq(orderBook[4].timeout, 1);
        assertEq(orderBook[5].account, address(this));
        assertEq(orderBook[5].price, 999);
        assertEq(orderBook[5].value, 1);
        assertEq(orderBook[5].timeout, 7);
        assertEq(orderBook[6].account, address(this));
        assertEq(orderBook[6].price, 1000);
        assertEq(orderBook[6].value, 1);
        assertEq(orderBook[6].timeout, 6);
        assertEq(orderBook[7].account, address(this));
        assertEq(orderBook[7].price, 1001);
        assertEq(orderBook[7].value, 1);
        assertEq(orderBook[7].timeout, 8);
    }

    function testAddOrderValue() public {
        uint32 t = uint32(block.timestamp) + 1;
        vm.expectRevert(InvalidAsset.selector);
        harness.addOrderValue(so(address(this), address(7), 82, 90, t));
        vm.expectRevert(InvalidAsset.selector);
        harness.addOrderValue(so(address(harness), address(7), 82, 90, t));
        vm.expectRevert(InvalidAsset.selector);
        harness.addOrderValue(so(address(7), address(this), 82, 90, t));
        vm.expectRevert(InvalidAsset.selector);
        harness.addOrderValue(so(address(7), address(harness), 82, 90, t));
        vm.expectRevert(AssetsNotDifferent.selector);
        harness.addOrderValue(so(address(7), address(7), 82, 90, t));
        vm.expectRevert(PriceZero.selector);
        harness.addOrderValue(so(address(7), address(8), 0, 90, t));
        vm.expectRevert(ValueZero.selector);
        harness.addOrderValue(so(address(7), address(8), 82, 0, t));
        vm.expectRevert(TimeoutExpired.selector);
        harness.addOrderValue(so(address(0), address(8), 18, 90, t - 1));
        vm.expectRevert(InsufficientBalance.selector);
        harness.addOrderValue(so(address(0), address(8), 18, 90, t));

        harness.deposit{value: 100}();
        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 90, t);
        harness.addOrderValue(so(address(0), address(8), 18, 90, t));
        assertEq(harness.getBalance(address(0), address(this)), 10);
/*
        vm.expectEmit(false, false, false, true);
        emit OrderValueAdded(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 10, t);
        harness.addOrderValue(so(address(0), address(8), 18, 10, t));
        assertEq(harness.getBalance(address(0), address(this)), 0);
        */
    }

    function testAddOrderWithDeposit() public {
        uint32 t = uint32(block.timestamp) + 1;
        vm.expectRevert(InvalidAsset.selector);
        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(this), 82, 90, t));
        vm.expectRevert(InvalidAsset.selector);
        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(harness), 82, 90, t));
        vm.expectRevert(PriceZero.selector);
        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 0, 90, t));
        vm.expectRevert(ValueZero.selector);
        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 82, 0, t));
        vm.expectRevert(TimeoutExpired.selector);
        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 82, 90, t - 1));

        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 90, t);
        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 18, 90, t));

        vm.expectRevert(InvalidAsset.selector);
        harness.addOrderValueWithDeposit(so(address(this), address(dummyToken), 82, 90, t));
        vm.expectRevert(InvalidAsset.selector);
        harness.addOrderValueWithDeposit(so(address(harness), address(dummyToken), 82, 90, t));
        vm.expectRevert(InvalidAsset.selector);
        harness.addOrderValueWithDeposit(so(address(dummyToken), address(this), 82, 90, t));
        vm.expectRevert(InvalidAsset.selector);
        harness.addOrderValueWithDeposit(so(address(dummyToken), address(harness), 82, 90, t));
        vm.expectRevert(AssetsNotDifferent.selector);
        harness.addOrderValueWithDeposit(so(address(dummyToken), address(dummyToken), 82, 90, t));
        vm.expectRevert(PriceZero.selector);
        harness.addOrderValueWithDeposit(so(address(dummyToken), address(8), 0, 90, t));
        vm.expectRevert(ValueZero.selector);
        harness.addOrderValueWithDeposit(so(address(dummyToken), address(8), 82, 0, t));
        vm.expectRevert(TimeoutExpired.selector);
        harness.addOrderValueWithDeposit(so(address(dummyToken), address(8), 82, 90, t - 1));

        uint oldBalance = dummyToken.balanceOf(address(this));
        bytes memory error = abi.encodeWithSelector(DepositFailed.selector, address(dummyToken), address(this), oldBalance + 1);
        vm.expectRevert(error);
        harness.addOrderValueWithDeposit(so(address(dummyToken), address(8), 18, uint224(oldBalance + 1), t));

        vm.expectEmit(false, false, false, true);
        emit OrderAdded(address(dummyToken), address(8), harness.encodeOrderIdHarness(address(this), 18), 90, t);
        harness.addOrderValueWithDeposit(so(address(dummyToken), address(8), 18, 90, t));
        uint newBalance = dummyToken.balanceOf(address(this));
        assertEq(oldBalance - newBalance, 90);
    }

    function test_RemoveOrder() public {
        uint32 t = uint32(block.timestamp) + 1;

        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 18, 90, t));
        Order[] memory orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 90);
        assertEq(orderBook[0].timeout, t);
        
        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 90);
        harness._removeOrderHarness(so(address(0), address(8), 18));
        orderBook = harness.getOrderBook(address(7), address(8), 0);
        assertEq(orderBook.length, 0);

        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 18, 90, t));
        harness.addOrderValueWithDeposit{value: 91}(so(address(0), address(8), 17, 91, t + 1));
        harness.addOrderValueWithDeposit{value: 94}(so(address(0), address(8), 16, 94, t + 2));
        harness.addOrderValueWithDeposit{value: 93}(so(address(0), address(8), 180972, 93, t + 3));
        harness.addOrderValueWithDeposit{value: 946}(so(address(0), address(8), 180973, 946, t + 4));
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 5);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 94);
        assertEq(orderBook[0].timeout, t + 2);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 17);
        assertEq(orderBook[1].value, 91);
        assertEq(orderBook[1].timeout, t + 1);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[2].timeout, t);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 180972);
        assertEq(orderBook[3].value, 93);
        assertEq(orderBook[3].timeout, t + 3);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 180973);
        assertEq(orderBook[4].value, 946);
        assertEq(orderBook[4].timeout, t + 4);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 16), 94);
        harness._removeOrderHarness(so(address(0), address(8), 16));
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 4);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 91);
        assertEq(orderBook[0].timeout, t + 1);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 90);
        assertEq(orderBook[1].timeout, t);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 180972);
        assertEq(orderBook[2].value, 93);
        assertEq(orderBook[2].timeout, t + 3);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 180973);
        assertEq(orderBook[3].value, 946);
        assertEq(orderBook[3].timeout, t + 4);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 90);
        harness._removeOrderHarness(so(address(0), address(8), 18));
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 3);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 91);
        assertEq(orderBook[0].timeout, t + 1);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 180972);
        assertEq(orderBook[1].value, 93);
        assertEq(orderBook[1].timeout, t + 3);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 180973);
        assertEq(orderBook[2].value, 946);
        assertEq(orderBook[2].timeout, t + 4);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 180973), 946);
        harness._removeOrderHarness(so(address(0), address(8), 180973));
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 2);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 91);
        assertEq(orderBook[0].timeout, t + 1);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 180972);
        assertEq(orderBook[1].value, 93);
        assertEq(orderBook[1].timeout, t + 3);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 180972), 93);
        harness._removeOrderHarness(so(address(0), address(8), 180972));
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 17);
        assertEq(orderBook[0].value, 91);
        assertEq(orderBook[0].timeout, t + 1);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 17), 91);
        harness._removeOrderHarness(so(address(0), address(8), 17));
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 0);
    }

    function testRemoveOrder() public {
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrder(so(address(this), address(7), 82));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrder(so(address(harness), address(7), 82));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrder(so(address(7), address(this), 82));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrder(so(address(7), address(harness), 82));
        vm.expectRevert(AssetsNotDifferent.selector);
        harness.removeOrder(so(address(7), address(7), 82));
        vm.expectRevert(PriceZero.selector);
        harness.removeOrder(so(address(7), address(8), 0));

        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 18, 90, uint32(block.timestamp) + 1));
        uint oldBalance = harness.getBalance(address(0), address(this));
        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 90);
        harness.removeOrder(so(address(0), address(8), 18));
        uint newBalance = harness.getBalance(address(0), address(this));
        assertEq(newBalance - oldBalance, 90);
    }

    function testRemoveOrderAndWithdraw() public {
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderAndWithdraw(so(address(this), address(7), 82), address(this));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderAndWithdraw(so(address(harness), address(7), 82), address(this));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderAndWithdraw(so(address(7), address(this), 82), address(this));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderAndWithdraw(so(address(7), address(harness), 82), address(this));
        vm.expectRevert(AssetsNotDifferent.selector);
        harness.removeOrderAndWithdraw(so(address(7), address(7), 82), address(this));
        vm.expectRevert(PriceZero.selector);
        harness.removeOrderAndWithdraw(so(address(7), address(8), 0), address(this));
        vm.expectRevert(InvalidAddress.selector);
        harness.removeOrderAndWithdraw(so(address(7), address(8), 82), address(harness));

        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 18, 90, uint32(block.timestamp) + 1));
        uint oldBalance = address(this).balance;
        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 90);
        harness.removeOrderAndWithdraw(so(address(0), address(8), 18), address(this));
        uint newBalance = address(this).balance;
        assertEq(newBalance - oldBalance, 90);
    }

    function test_RemoveOrderValue() public {
        uint32 t = uint32(block.timestamp) + 1;

        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 18, 90, t));
        Order[] memory orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 90);
        assertEq(orderBook[0].timeout, t);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 1, t + 1);
        uint valueRemoved = harness._removeOrderValueHarness(so(address(0), address(8), 18, 1, t + 1));
        assertEq(valueRemoved, 1);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 89);
        assertEq(orderBook[0].timeout, t + 1);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 88, t + 2);
        valueRemoved = harness._removeOrderValueHarness(so(address(0), address(8), 18, 88, t + 2));
        assertEq(valueRemoved, 88);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 1);
        assertEq(orderBook[0].timeout, t + 2);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 1);
        valueRemoved = harness._removeOrderValueHarness(so(address(0), address(8), 18, 1, t + 3));
        assertEq(valueRemoved, 1);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 0);

        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 18, 90, t + 4));
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 18);
        assertEq(orderBook[0].value, 90);
        assertEq(orderBook[0].timeout, t + 4);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 90);
        valueRemoved = harness._removeOrderValueHarness(so(address(0), address(8), 18, 100, t + 5));
        assertEq(valueRemoved, 90);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 0);

        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 18, 90, t + 5));
        harness.addOrderValueWithDeposit{value: 91}(so(address(0), address(8), 17, 91, t + 6));
        harness.addOrderValueWithDeposit{value: 94}(so(address(0), address(8), 16, 94, t + 7));
        harness.addOrderValueWithDeposit{value: 93}(so(address(0), address(8), 180972, 93, t + 8));
        harness.addOrderValueWithDeposit{value: 946}(so(address(0), address(8), 180973, 946, t + 9));
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 5);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 94);
        assertEq(orderBook[0].timeout, t + 7);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 17);
        assertEq(orderBook[1].value, 91);
        assertEq(orderBook[1].timeout, t + 6);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[2].timeout, t + 5);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 180972);
        assertEq(orderBook[3].value, 93);
        assertEq(orderBook[3].timeout, t + 8);
        assertEq(orderBook[4].account, address(this));
        assertEq(orderBook[4].price, 180973);
        assertEq(orderBook[4].value, 946);
        assertEq(orderBook[4].timeout, t + 9);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 180973), 946);
        valueRemoved = harness._removeOrderValueHarness(so(address(0), address(8), 180973, 946, t + 10));
        assertEq(valueRemoved, 946);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 4);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 94);
        assertEq(orderBook[0].timeout, t + 7);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 17);
        assertEq(orderBook[1].value, 91);
        assertEq(orderBook[1].timeout, t + 6);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[2].timeout, t + 5);
        assertEq(orderBook[3].account, address(this));
        assertEq(orderBook[3].price, 180972);
        assertEq(orderBook[3].value, 93);
        assertEq(orderBook[3].timeout, t + 8);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 180972), 93);
        valueRemoved = harness._removeOrderValueHarness(so(address(0), address(8), 180972, 946, t + 11));
        assertEq(valueRemoved, 93);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 3);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 94);
        assertEq(orderBook[0].timeout, t + 7);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 17);
        assertEq(orderBook[1].value, 91);
        assertEq(orderBook[1].timeout, t + 6);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[2].timeout, t + 5);

        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 16), 93, t + 12);
        valueRemoved = harness._removeOrderValueHarness(so(address(0), address(8), 16, 93, t + 12));
        assertEq(valueRemoved, 93);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 3);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 1);
        assertEq(orderBook[0].timeout, t + 12);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 17);
        assertEq(orderBook[1].value, 91);
        assertEq(orderBook[1].timeout, t + 6);
        assertEq(orderBook[2].account, address(this));
        assertEq(orderBook[2].price, 18);
        assertEq(orderBook[2].value, 90);
        assertEq(orderBook[2].timeout, t + 5);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 17), 91);
        valueRemoved = harness._removeOrderValueHarness(so(address(0), address(8), 17, 91, t + 13));
        assertEq(valueRemoved, 91);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 2);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 1);
        assertEq(orderBook[0].timeout, t + 12);
        assertEq(orderBook[1].account, address(this));
        assertEq(orderBook[1].price, 18);
        assertEq(orderBook[1].value, 90);
        assertEq(orderBook[1].timeout, t + 5);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 90);
        valueRemoved = harness._removeOrderValueHarness(so(address(0), address(8), 18, 91, t + 14));
        assertEq(valueRemoved, 90);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 1);
        assertEq(orderBook[0].account, address(this));
        assertEq(orderBook[0].price, 16);
        assertEq(orderBook[0].value, 1);
        assertEq(orderBook[0].timeout, t + 12);

        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 16), 1);
        valueRemoved = harness._removeOrderValueHarness(so(address(0), address(8), 16, 1, t + 15));
        assertEq(valueRemoved, 1);
        orderBook = harness.getOrderBook(address(0), address(8), 0);
        assertEq(orderBook.length, 0);
    }

    function testRemoveOrderValue() public {
        uint32 t = uint32(block.timestamp) + 1;

        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderValue(so(address(this), address(7), 82, 90, t));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderValue(so(address(harness), address(7), 82, 90, t));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderValue(so(address(7), address(this), 82, 90, t));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderValue(so(address(7), address(harness), 82, 90, t));
        vm.expectRevert(AssetsNotDifferent.selector);
        harness.removeOrderValue(so(address(7), address(7), 82, 90, t));
        vm.expectRevert(PriceZero.selector);
        harness.removeOrderValue(so(address(7), address(8), 0, 90, t));
        vm.expectRevert(ValueZero.selector);
        harness.removeOrderValue(so(address(7), address(8), 82, 0, t));
        vm.expectRevert(TimeoutExpired.selector);
        harness.removeOrderValue(so(address(7), address(8), 82, 90, t - 1));

        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 18, 90, t + 1));
        uint oldBalance = harness.getBalance(address(0), address(this));
        vm.expectEmit(false, false, false, true);
        emit OrderRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 90);
        harness.removeOrderValue(so(address(0), address(8), 18, 91, t + 2));
        uint newBalance = harness.getBalance(address(0), address(this));
        assertEq(newBalance - oldBalance, 90);
    }

    function testRemoveOrderValueAndWithdraw() public {
        uint32 t = uint32(block.timestamp) + 1;

        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderValueAndWithdraw(so(address(this), address(7), 82, 90, t), address(this));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderValueAndWithdraw(so(address(harness), address(7), 82, 90, t), address(this));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderValueAndWithdraw(so(address(7), address(this), 82, 90, t), address(this));
        vm.expectRevert(InvalidAsset.selector);
        harness.removeOrderValueAndWithdraw(so(address(7), address(harness), 82, 90, t), address(this));
        vm.expectRevert(AssetsNotDifferent.selector);
        harness.removeOrderValueAndWithdraw(so(address(7), address(7), 82, 90, t), address(this));
        vm.expectRevert(PriceZero.selector);
        harness.removeOrderValueAndWithdraw(so(address(7), address(8), 0, 90, t), address(this));
        vm.expectRevert(ValueZero.selector);
        harness.removeOrderValueAndWithdraw(so(address(7), address(8), 82, 0, t), address(this));
        vm.expectRevert(TimeoutExpired.selector);
        harness.removeOrderValueAndWithdraw(so(address(7), address(8), 82, 90, t - 1), address(this));
        vm.expectRevert(InvalidAddress.selector);
        harness.removeOrderValueAndWithdraw(so(address(7), address(8), 82, 90, t), address(harness));

        harness.addOrderValueWithDeposit{value: 90}(so(address(0), address(8), 18, 90, t + 1));
        uint oldBalance = address(this).balance;
        vm.expectEmit(false, false, false, true);
        emit OrderValueRemoved(address(0), address(8), harness.encodeOrderIdHarness(address(this), 18), 80, t + 2);
        harness.removeOrderValueAndWithdraw(so(address(0), address(8), 18, 80, t + 2), address(this));
        uint newBalance = address(this).balance;
        assertEq(newBalance - oldBalance, 80);
    }
}
