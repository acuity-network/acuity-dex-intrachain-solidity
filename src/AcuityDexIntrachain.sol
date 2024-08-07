// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import "./ERC20.sol";

contract AcuityDexIntrachain {

    mapping (address => mapping (address => uint)) accountTokenBalance;
    
    /**
     * @dev Mapping of selling ERC20 contract address to buying ERC20 contract address to linked list of sell orders, starting with the lowest selling price.
     */
    mapping (address => mapping (address => mapping (bytes32 => bytes32))) sellBuyOrderLL;

    mapping (address => mapping (address => mapping (bytes32 => uint))) sellBuyOrderValue;

    /**
     * @dev
     */
    event Deposit(address token, address account, uint value);

    /**
     * @dev
     */
    event Withdrawal(address token, address account, uint value);
    
    /**
     * @dev
     */
    error NoValue();

    /**
     * @dev
     */
    error InsufficientBalance();

    /**
     * @dev
     */
    error TokensNotDifferent(address sellToken, address buyToken);

    /**
     * @dev
     */
    error OrderNotFound(address sellToken, address buyToken, address account, uint value);

    /**
     * @dev
     */
    error TokenTransferInFailed(address token, address from, uint value);

    /**
     * @dev
     */
    error TokenTransferOutFailed(address token, address to, uint value);

    /**
     * @dev Revert if no value is sent.
     */
    modifier hasValue() {
        if (msg.value == 0) revert NoValue();
        _;
    }

    /**
     * @dev
     */
    function safeTransferIn(address token, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transferFrom.selector, msg.sender, address(this), value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferInFailed(token, msg.sender, value);
    }

    /**
     * @dev
     */
    function safeTransferOut(address token, address to, uint value) internal {
        // https://docs.openzeppelin.com/contracts/3.x/api/utils#Address-sendValue-address-payable-uint256-
        if (token == address(0)) {
            payable(to).transfer(value); // Fix this.
        }
        else {
            (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transfer.selector, to, value));
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferOutFailed(token, to, value);
        }
    }

    function encodeOrderId(uint96 price) internal view returns (bytes32 orderId) {
        orderId = bytes32(bytes20(msg.sender)) | bytes32(uint(price));
    }

    function encodeOrderId(address seller, uint96 price) internal view returns (bytes32 orderId) {
        orderId = bytes32(bytes20(seller)) | bytes32(uint(price));
    }

    function decodeOrderId(bytes32 orderId) internal pure returns (address account, uint96 price) {
        account = address(bytes20(orderId));
        price = uint96(uint(orderId));
    }

    /**
     * @dev Fallback function.
     */
    function deposit() external payable hasValue {
        // Update balance.
        accountTokenBalance[msg.sender][address(0)] += msg.value;
        // Log event.
        emit Deposit(address(0), msg.sender, msg.value);
    }

    // ERC1155?

    function depositERC20(address token, uint value) external {
        // Update balance.
        accountTokenBalance[msg.sender][token] += value;
        // Transfer value.
        safeTransferIn(token, value);
        // Log event.
        emit Deposit(token, msg.sender, value);
    }

    function withdraw(address token, uint value) external {
        mapping(address => uint256) storage tokenBalance = accountTokenBalance[msg.sender];
        // Check there is sufficient balance.
        if (tokenBalance[token] < value) revert InsufficientBalance();
        // Update balance.
        accountTokenBalance[msg.sender][token] -= value;
        // Transfer value.
        safeTransferOut(token, msg.sender, value);
        // Log event.
        emit Withdrawal(token, msg.sender, value);
    }

    function withdrawAll(address token) external {
        mapping(address => uint256) storage tokenBalance = accountTokenBalance[msg.sender];
        // Get token balance.
        uint value = tokenBalance[token];
        // Check there is a balance.
        if (value == 0) revert InsufficientBalance();
        // Delete token balance.
        delete tokenBalance[token];
        // Transfer value.
        safeTransferOut(token, msg.sender, value);
        // Log event.
        emit Withdrawal(token, msg.sender, value);
    }

    function _addOrder(address sellToken, address buyToken, uint96 price, uint value) internal {
        if (sellToken == buyToken) {
            revert TokensNotDifferent(sellToken, buyToken);
        }
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
        
        bytes32 orderId = encodeOrderId(price);

        // Does this order already exist?
        if (orderValue[orderId] > 0) {
            orderValue[orderId] += value;
            return;
        }

        // Find correct place in linked list to insert order.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        bytes32 prev = 0;
        bytes32 next = orderLL[0];
        while (next != 0) {
            (, uint96 nextPrice) = decodeOrderId(next);
            // This ensures that new orders go after existing orders with the same price.
            if (nextPrice > price) {
                break;
            }

            prev = next;
            next = orderLL[prev];
        }

        // Insert into linked list.
        orderLL[prev] = orderId;
        orderLL[orderId] = next;
        orderValue[orderId] = value;
    }

    /**
     * @dev Add sell order.
     */
    function addOrder(address sellToken, address buyToken, uint96 sellPrice, uint value) external {
        _addOrder(sellToken, buyToken, sellPrice, value);
        accountTokenBalance[msg.sender][sellToken] -= value;
    }

    /**
     * @dev Add sell order of base coin.
     */
    function addOrderWithDeposit(address buyToken, uint96 sellPrice) external payable hasValue {
        _addOrder(address(0), buyToken, sellPrice, msg.value);
    }

    /**
     * @dev Add sell order of ERC20 token.
     */
    function addOrderWithDepositERC20(address sellToken, address buyToken, uint96 sellPrice, uint value) external {
        // Add the sell order.
        _addOrder(sellToken, buyToken, sellPrice, value);
        // Transfer the tokens from the seller to this contract.
        safeTransferIn(sellToken, value);
    }

    function removeOrder(address sellToken, address buyToken, uint96 sellPrice, uint value) external {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];

        bytes32 orderId = encodeOrderId(sellPrice);
        if (orderValue[orderId] == 0) {
            revert OrderNotFound(sellToken, buyToken, msg.sender, sellPrice);
        }
    }

    function _removeOrder(address sellToken, address buyToken, uint96 sellPrice) internal returns (uint value) {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];

        bytes32 orderId = encodeOrderId(sellPrice);
        
        value = orderValue[orderId];
        
        if (value == 0) {
            revert OrderNotFound(sellToken, buyToken, msg.sender, sellPrice);
        }

        delete orderValue[orderId];

        // Find the previous sell order.
        bytes32 prev = 0;
        while (orderLL[prev] != orderId) {
            prev = orderLL[prev];
        }
        // Remove from linked list.        
        orderLL[prev] = orderLL[orderId];
        delete orderLL[orderId];
    }

    function removeOrder(address sellToken, address buyToken, uint96 sellPrice) external {
        uint value = _removeOrder(sellToken, buyToken, sellPrice);
        accountTokenBalance[msg.sender][sellToken] += value;
    }
    
    function removeOrderAndWithdraw(address sellToken, address buyToken, uint96 sellPrice) external {
        uint value = _removeOrder(sellToken, buyToken, sellPrice);
        safeTransferOut(sellToken, msg.sender, value);
    }

    function adjustOrderPrice(address sellToken, address buyToken, uint96 oldPrice, uint96 newPrice) external {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];

        bytes32 oldOrder = encodeOrderId(oldPrice);
        bytes32 newOrder = encodeOrderId(newPrice);

        if (orderValue[oldOrder] == 0) {
            revert OrderNotFound(sellToken, buyToken, msg.sender, oldPrice);
        }

        // Find oldPrev
        bytes32 oldPrev = 0;
        bytes32 next = orderLL[0];
        while (next != oldOrder) {
            oldPrev = next;
            next = orderLL[oldPrev];
        }

        // Find newPrev
        bytes32 newPrev = 0;
        next = orderLL[0];
        while (next != 0) {
            (, uint96 nextSellPrice) = decodeOrderId(next);

            if (nextSellPrice > newPrice) {
                break;
            }

            newPrev = next;
            next = orderLL[newPrev];
        }

        // Are we replacing the existing order?
        if (newPrev == oldPrev || newPrev == oldOrder) {
            orderLL[oldPrev] = newOrder;
            orderLL[newOrder] = orderLL[oldOrder];
        }
        else {
            // Remove old order from linked list.
            orderLL[oldPrev] = orderLL[oldOrder];
            // Insert into linked list.
            orderLL[newPrev] = newOrder;
            orderLL[newOrder] = next;
        }

        delete orderLL[oldOrder];
        orderValue[newOrder] = orderValue[oldOrder];
        delete orderValue[oldOrder];
    }

    function _buy(address sellToken, address buyToken, uint buyValueMax) internal returns (uint buyValue, uint sellValue) {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
        // Get the lowest sell order.
        bytes32 order = orderLL[0];
        while (order != 0) {
            (address sellAccount, uint96 sellPrice) = decodeOrderId(order);
            uint orderSellValue = orderValue[order];
            uint matchedSellValue = (buyValueMax * 1 ether) / sellPrice;

            if (orderSellValue > matchedSellValue) {
                // Partial buy.
                orderValue[order] -= matchedSellValue;
                // Transfer value.
                buyValue += buyValueMax;
                accountTokenBalance[sellAccount][buyToken] += buyValueMax;
                sellValue += matchedSellValue;
                break;
            }
            else {
                // Full buy.
                uint matchedBuyValue = (orderSellValue * sellPrice) / 1 ether;
                buyValueMax -= matchedBuyValue;
                bytes32 next = orderLL[order];
                // Delete the sell order.
                orderLL[0] = next;
                delete orderLL[order];
                delete orderValue[order];
                order = next;
                // Transfer value.
                buyValue += matchedBuyValue;
                accountTokenBalance[sellAccount][buyToken] += matchedBuyValue;
                sellValue += orderSellValue;
            }
        }
    }

    /**
     * @dev Buy.
     */
    function buy(address sellToken, address buyToken, uint buyValueMax) external {
        // Execute the buy.
        (uint buyValue, uint sellValue) = _buy(sellToken, buyToken, buyValueMax);
        accountTokenBalance[msg.sender][buyToken] -= buyValue;
        accountTokenBalance[msg.sender][sellToken] += sellValue;
    }

    /**
     * @dev Buy with balance and withdraw.
     */
    function buyAndWithdraw(address sellToken, address buyToken, uint buyValueMax) external {
        // Execute the buy.
        (uint buyValue, uint sellValue) = _buy(sellToken, buyToken, buyValueMax);
        accountTokenBalance[msg.sender][buyToken] -= buyValue;
        safeTransferOut(sellToken, msg.sender, sellValue);
    }
    
    /**
     * @dev Buy with base coin.
     */
    function buyWithDeposit(address sellToken) external payable hasValue {
        (uint buyValue, uint sellValue) = _buy(sellToken, address(0), msg.value);
        accountTokenBalance[msg.sender][sellToken] += sellValue;
        // Send the change back.
        if (buyValue < msg.value) {
            safeTransferOut(address(0), msg.sender, msg.value - buyValue);
        }
    }

    /**
     * @dev Buy with ERC20 token.
     */
    function buyWithDepositERC20(address sellToken, address buyToken, uint buyValueMax) external {
        // Execute the buy.
        (uint buyValue, uint sellValue) = _buy(sellToken, buyToken, buyValueMax);
        // Transfer the buy tokens from the buyer to this contract.
        accountTokenBalance[msg.sender][sellToken] += sellValue;
        safeTransferIn(buyToken, buyValue);
    }

    /**
     * @dev Buy with base coin.
     */
    function buyWithDepositAndWithdraw(address sellToken) external payable hasValue {
        (uint buyValue, uint sellValue) = _buy(sellToken, address(0), msg.value);
        // Transfer the sell tokens to the buyer.
        if (sellValue > 0) {
            safeTransferOut(sellToken, msg.sender, sellValue);
        }
        // Send the change back.
        if (buyValue < msg.value) {
            safeTransferOut(address(0), msg.sender, msg.value - buyValue);
        }
    }

    /**
     * @dev Buy with ERC20 token.
     */
    function buyWithDepositAndWithdrawERC20(address sellToken, address buyToken, uint buyValueMax) external {
        // Execute the buy.
        (uint buyValue, uint sellValue) = _buy(sellToken, buyToken, buyValueMax);
        // Transfer the buy tokens from the buyer to this contract.
        safeTransferIn(buyToken, buyValue);
        // Transfer the sell tokens to the buyer.
        if (sellValue > 0) {
            safeTransferOut(sellToken, msg.sender, sellValue);
        }
    }

    /**
     * @dev Get balance of token for account.
     */
    function getBalance(address token, address account) external view returns (uint value) {
        value = accountTokenBalance[account][token];
    }

    /**
     * @dev
     */
    struct Order {
        address account;
        uint price;
        uint value;
    }

    // paging?
    /**
     * @dev
     */
    function getOrderBook(address sellToken, address buyToken, uint maxOrders) external view returns (Order[] memory orderBook) {
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
        uint orderCount = 0;
        
        bytes32 orderId = orderLL[0];

        if (maxOrders == 0) {
            while (orderId != 0) {
                orderCount++;
                orderId = orderLL[orderId];
            }
        }
        else {
            while (orderId != 0 && orderCount < maxOrders) {
                orderCount++;
                orderId = orderLL[orderId];
            }
        }
        orderBook = new Order[](orderCount);

        orderId = orderLL[0];
        for (uint i = 0; i < orderCount; i++) {
            (address sellAccount, uint96 sellPrice) = decodeOrderId(orderId);
            
            orderBook[i] = Order({
                account: sellAccount,
                price: sellPrice,
                value: orderValue[orderId] 
            });

            orderId = orderLL[orderId];
        }
    }

    /**
     * @dev
     */
    function getOrderValue(address sellToken, address buyToken, address seller, uint96 price) external view returns (uint value) {
        bytes32 orderId = encodeOrderId(seller, price);
        value = sellBuyOrderValue[sellToken][buyToken][orderId];
    }
}
