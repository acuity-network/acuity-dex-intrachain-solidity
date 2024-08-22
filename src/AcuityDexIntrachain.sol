// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import "./ERC20.sol";

contract AcuityDexIntrachain {

    mapping (address => mapping (address => uint)) accountAssetBalance;

    /**
     * @dev Mapping of selling asset address to buying asset address to linked list of sell orders, starting with the lowest selling price.
     */
    mapping (address => mapping (address => mapping (bytes32 => bytes32))) sellBuyOrderIdLL;

    mapping (address => mapping (address => mapping (bytes32 => uint))) sellBuyOrderIdValue;

    /**
     * @dev
     */
    event Deposit(address asset, address account, uint value);

    /**
     * @dev
     */
    event Withdrawal(address asset, address account, address to, uint value);
    
    /**
     * @dev
     */
    event OrderValueAdded(address sellAsset, address buyAsset, bytes32 orderId, uint value);

    /**
     * @dev
     */
    event OrderValueRemoved(address sellAsset, address buyAsset, bytes32 orderId, uint value);

    /**
     * @dev
     */
    event OrderPartialMatch(address sellAsset, address buyAsset, bytes32 orderId, uint value);

    /**
     * @dev
     */
    event OrderFullMatch(address sellAsset, address buyAsset, bytes32 orderId, uint value);

    /**
     * @dev Sell orders have been purchased by a buyer.
     */
    event MatchingCompleted(address sellAsset, address buyAsset, address buyer, uint sellValue, uint buyValue);
    /**
     * @dev
     */
    error InvalidAsset();

    /**
     * @dev
     */
    error NoValue();

    /**
     * @dev
     */
    error HasValue();

    /**
     * @dev
     */
    error InsufficientBalance();

    /**
     * @dev
     */
    error AssetsNotDifferent();

    /**
     * @dev
     */
    error OrderNotFound();

    /**
     * @dev
     */
    error NoMatch();

    /**
     * @dev
     */
    error DepositFailed(address asset, address from, uint value);

    /**
     * @dev
     */
    error WithdrawalFailed(address asset, address to, uint value);

    /**
     * @dev
     */
    modifier validAsset(address asset) {
        if (asset == msg.sender || asset == address(this)) revert InvalidAsset();
        _;
    }

    /**
     * @dev
     */
    modifier notBaseAsset(address asset) {
        if (asset == address(0)) revert InvalidAsset();
        _;
    }

    /**
     * @dev Revert if no value is sent.
     */
    modifier hasMsgValue() {
        if (msg.value == 0) revert NoValue();
        _;
    }

    /**
     * @dev Revert if no value is sent.
     */
    modifier hasValue(uint value) {
        if (value == 0) revert NoValue();
        _;
    }

    /**
     * @dev Check sell and buy assets are not the same.
     */
    modifier assetsDifferent(address sellAsset, address buyAsset) {
        if (sellAsset == buyAsset) {
            revert AssetsNotDifferent();
        }
        _;
    }

    /**
     * @dev
     */
    function _depositERC20(address asset, uint value) internal
        validAsset(asset)
        notBaseAsset(asset)
    {
        (bool success, bytes memory data) = asset.call(abi.encodeWithSelector(ERC20.transferFrom.selector, msg.sender, address(this), value));
        if (success && data.length != 0) success = abi.decode(data, (bool));
        if (!success) revert DepositFailed(asset, msg.sender, value);
        // Log event.
        emit Deposit(asset, msg.sender, value);
    }

    /**
     * @dev
     */
    function _withdraw(address asset, address to, uint value) internal
        validAsset(asset)
    {
        // Default to withdrawing to sender.
        if (to == address(0)) to = msg.sender;
        bool success;
        bytes memory data;
        if (asset == address(0)) {
            (success, data) = to.call{value: value}(hex"");
        }
        else {
            (success, data) = asset.call(abi.encodeWithSelector(ERC20.transfer.selector, to, value));
        }
        // TODO: Check this
        if (success && data.length != 0) success = abi.decode(data, (bool));
        if (!success) revert WithdrawalFailed(asset, to, value);
        // Log event.
        emit Withdrawal(asset, msg.sender, to, value);
    }

    function encodeOrderId(uint96 price) internal view returns (bytes32 orderId) {
        orderId = bytes32(bytes20(msg.sender)) | bytes32(uint(price));
    }

    function encodeOrderId(address seller, uint96 price) internal pure returns (bytes32 orderId) {
        orderId = bytes32(bytes20(seller)) | bytes32(uint(price));
    }

    function decodeOrderId(bytes32 orderId) internal pure returns (address account, uint96 price) {
        account = address(bytes20(orderId));
        price = uint96(uint(orderId));
    }

    /**
     * @dev Deposit base coin.
     */
    function deposit() external payable hasMsgValue {
        // Update balance.
        accountAssetBalance[msg.sender][address(0)] += msg.value;
        // Log event.
        emit Deposit(address(0), msg.sender, msg.value);
    }

    // ERC1155?

    function depositERC20(address asset, uint value) external hasValue(value) {
        // Update balance.
        accountAssetBalance[msg.sender][asset] += value;
        // Transfer value.
        _depositERC20(asset, value);
    }

    function withdraw(address asset, address to, uint value) external hasValue(value) {
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        // Check there is sufficient balance.
        if (assetBalance[asset] < value) revert InsufficientBalance();
        // Update balance.
        assetBalance[asset] -= value;
        // Transfer value.
        _withdraw(asset, to, value);
    }

    function withdrawAll(address asset, address to) external {
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        // Get asset balance.
        uint value = assetBalance[asset];
        // Check there is a balance.
        if (value == 0) revert NoValue();
        // Delete asset balance.
        delete assetBalance[asset];
        // Transfer value.
        _withdraw(asset, to, value);
    }

    /**
     * @dev Add value to an order.
     */
    function _addOrderValue(address sellAsset, address buyAsset, uint96 price, uint value) internal
        assetsDifferent(sellAsset, buyAsset)
        hasValue(value)
    {
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderIdValue[sellAsset][buyAsset];
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(price);
        // Log event.
        emit OrderValueAdded(sellAsset, buyAsset, orderId, value);
        // Get the old order value.
        uint oldValue = orderValue[orderId];
        // Does this order already exist?
        if (oldValue > 0) {
            orderValue[orderId] = oldValue + value;
            return;
        }
        // Set the order value.
        orderValue[orderId] = value;  // 20,000
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellAsset][buyAsset];
        // Find correct place in linked list to insert order.
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
        orderLL[prev] = orderId;  // 2,900
        orderLL[orderId] = next;  // 20,000
    }

    /**
     * @dev Add value to an order.
     *
     * Typical storage gas for new order: 45,800
     */
    function addOrderValue(address sellAsset, address buyAsset, uint96 price, uint value) external {
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        // Check there is sufficient balance.
        if (assetBalance[sellAsset] < value) revert InsufficientBalance();
        // Add order.
        _addOrderValue(sellAsset, buyAsset, price, value);
        // Update Balance.
        assetBalance[sellAsset] -= value;  // 2,900
    }

    /**
     * @dev Add sell order of base coin.
     */
    function addOrderValueWithDeposit(address buyAsset, uint96 price) external payable {
        _addOrderValue(address(0), buyAsset, price, msg.value);
    }

    /**
     * @dev Add sell order of ERC20 asset.
     */
    function addOrderValueWithDepositERC20(address sellAsset, address buyAsset, uint96 price, uint value) external {
        // Add the sell order.
        _addOrderValue(sellAsset, buyAsset, price, value);
        // Transfer the assets from the seller to this contract.
        _depositERC20(sellAsset, value);
    }

    function deleteOrderLL(address sellAsset, address buyAsset, bytes32 orderId) internal {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellAsset][buyAsset];
        // Find the previous sell order.
        bytes32 prev = 0;
        while (orderLL[prev] != orderId) {
            prev = orderLL[prev];
        }
        // Remove from linked list.        
        orderLL[prev] = orderLL[orderId];
        delete orderLL[orderId];
    }

    function _removeOrder(address sellAsset, address buyAsset, uint96 price) internal
        assetsDifferent(sellAsset, buyAsset)
        returns (uint value)
    {
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderIdValue[sellAsset][buyAsset];
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(price);
        // Get the value of the order being removed.
        value = orderValue[orderId];
        // Check if the order exists.
        if (value == 0) {
            revert OrderNotFound();
        }
        // Delete the order value.
        delete orderValue[orderId];
        // Delete the order from the linked list.
        deleteOrderLL(sellAsset, buyAsset, orderId);
        // Log event.
        emit OrderValueRemoved(sellAsset, buyAsset, orderId, value);
    }

    function removeOrder(address sellAsset, address buyAsset, uint96 price) external {
        uint value = _removeOrder(sellAsset, buyAsset, price);
        accountAssetBalance[msg.sender][sellAsset] += value;
    }
    
    function removeOrderAndWithdraw(address sellAsset, address buyAsset, uint96 price, address to) external {
        uint value = _removeOrder(sellAsset, buyAsset, price);
        _withdraw(sellAsset, to, value);
    }

    function _removeOrderValue(address sellAsset, address buyAsset, uint96 price, uint valueLimit) internal
        assetsDifferent(sellAsset, buyAsset)
        hasValue(valueLimit)
        returns (uint valueRemoved)  // Is this neccessary?
    {
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(price);
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderIdValue[sellAsset][buyAsset];
        // Get the value of the order being removed.
        uint value = orderValue[orderId];
        // Check if the order exists.
        if (value == 0) {
            revert OrderNotFound();
        }
        // Is the whole order being deleted?
        if (valueLimit >= value) {
            valueRemoved = value;
            // Delete the order value.
            delete orderValue[orderId];
            // Delete the order from the linked list.
            deleteOrderLL(sellAsset, buyAsset, orderId);
        }
        else {
            orderValue[orderId] = value - valueLimit;
            valueRemoved = valueLimit;
        }
        // Log event.
        emit OrderValueRemoved(sellAsset, buyAsset, orderId, valueRemoved);
    }

    function removeOrderValue(address sellAsset, address buyAsset, uint96 price, uint valueLimit) external {
        uint value = _removeOrderValue(sellAsset, buyAsset, price, valueLimit);
        accountAssetBalance[msg.sender][sellAsset] += value;
    }
    
    function removeOrderValueAndWithdraw(address sellAsset, address buyAsset, uint96 price, uint valueLimit, address to) external {
        uint value = _removeOrderValue(sellAsset, buyAsset, price, valueLimit);
        _withdraw(sellAsset, to, value);
    }

    function adjustOrderPrice(address sellAsset, address buyAsset, uint96 oldPrice, uint96 newPrice) external
        assetsDifferent(sellAsset, buyAsset)
     {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellAsset][buyAsset];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderIdValue[sellAsset][buyAsset];

        bytes32 oldOrder = encodeOrderId(oldPrice);
        bytes32 newOrder = encodeOrderId(newPrice);

        if (orderValue[oldOrder] == 0) {
            revert OrderNotFound();
        }

        // What if newOrder already exists?

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

    function getAssetBigUnit(address asset) internal view
        returns (uint bigUnit)
    {
        if (asset == address(0)) {
            bigUnit = 1 ether;
        }
        else {
            bigUnit = 10 ** ERC20(asset).decimals();
        }
    }

    function matchSellExact(address sellAsset, address buyAsset, uint sellValue, uint buyLimit) internal
        returns (uint buyValue)
    {
        // Determine the value of 1 big unit of sell asset.
        uint sellAssetBigUnit = getAssetBigUnit(sellAsset);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellAsset][buyAsset];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderIdValue[sellAsset][buyAsset];
        // Get the first sell order.
        bytes32 start = orderLL[0];
        bytes32 orderId = start;
        while (sellValue != 0) {
            // Check if we have run out of orders.
            if (orderId == 0) revert NoMatch();
            // Get order account, price and value.
            (address sellAccount, uint price) = decodeOrderId(orderId);
            uint orderSellValue = orderValue[orderId];
            // Is there a full or partial match?
            if (sellValue >= orderSellValue) {
                // Full match.
                // Calculate how much buy asset it will take to buy this order.
                uint orderBuyValue = (orderSellValue * price) / sellAssetBigUnit;
                // Update buyer balances.
                buyValue += orderBuyValue;
                sellValue -= orderSellValue;
                // Pay seller.
                accountAssetBalance[sellAccount][buyAsset] += orderBuyValue;
                // Log the event.
                emit OrderFullMatch(sellAsset, buyAsset, orderId, orderSellValue);
                // Delete the order.
                bytes32 next = orderLL[orderId];
                delete orderLL[orderId];
                delete orderValue[orderId];
                orderId = next;
            }
            else {
                // Partial match.
                // Calculate how much of the sell asset can be bought at the current order's price.
                uint partialBuyValue = (sellValue * price) / sellAssetBigUnit;
                // Update buy balance.
                buyValue += partialBuyValue;
                // Pay seller.
                accountAssetBalance[sellAccount][buyAsset] += partialBuyValue;
                // Update order value. Will not be 0.
                orderValue[orderId] = orderSellValue - sellValue;
                // Update remaining sell value.
                sellValue = 0;
                // Log the event.
                emit OrderPartialMatch(sellAsset, buyAsset, orderId, sellValue);
            }
            // Ensure that the amount spent was not above the limit.
            if (buyValue > buyLimit) revert NoMatch();
        }
        // Update first order if neccessary.
        if (start != orderId) orderLL[0] = orderId;
    }

    function matchBuyExact(address sellAsset, address buyAsset, uint buyValue, uint sellLimit) internal
        returns (uint sellValue)
    {
        // Determine the value of 1 big unit of sell asset.
        uint sellAssetBigUnit = getAssetBigUnit(sellAsset);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellAsset][buyAsset];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderIdValue[sellAsset][buyAsset];
        // Get the first sell order.
        bytes32 start = orderLL[0];
        bytes32 orderId = start;
        while (buyValue != 0) {
            // Check if we have run out of orders.
            if (orderId == 0) revert NoMatch();
            // Get order account, price and value.
            (address sellAccount, uint price) = decodeOrderId(orderId);
            uint orderSellValue = orderValue[orderId];
            // Calculate how much buy asset it will take to buy this order.
            uint orderBuyValue = (orderSellValue * price) / sellAssetBigUnit;
            // Is there a full or partial match?
            if (buyValue >= orderBuyValue) {
                // Full match. Update sell balance.
                sellValue += orderSellValue;
                // Update remaining buy limit.
                buyValue -= orderBuyValue;
                // Pay seller.
                accountAssetBalance[sellAccount][buyAsset] += orderBuyValue;
                // Log the event.
                emit OrderFullMatch(sellAsset, buyAsset, orderId, orderSellValue);
                // Delete the order.
                bytes32 next = orderLL[orderId];
                delete orderLL[orderId];
                delete orderValue[orderId];
                orderId = next;
            }
            else {
                // Partial match.
                // Calculate how much of the sell asset can be bought at the current order's price.
                uint partialSellValue = (buyValue * sellAssetBigUnit) / price;
                // Update sell balance.
                sellValue += partialSellValue;
                // Pay seller.
                accountAssetBalance[sellAccount][buyAsset] += buyValue;
                // Update order value.
                orderSellValue -= partialSellValue;
                // It may be possible for the order to be consumed entirely due to rounding error.
                if (orderSellValue == 0) {
                    // Delete the order.
                    bytes32 next = orderLL[orderId];
                    delete orderLL[orderId];
                    delete orderValue[orderId];
                    orderId = next;
                }
                else {
                    orderValue[orderId] = orderSellValue;
                }
                // Log the event.
                emit OrderPartialMatch(sellAsset, buyAsset, orderId, partialSellValue);
                // Exit.
                break;
            }
        }
        if (sellValue < sellLimit) revert NoMatch();
        // Update first order if neccessary.
        if (start != orderId) orderLL[0] = orderId;
    }

    function matchLimit(address sellAsset, address buyAsset, uint sellLimit, uint buyLimit, uint priceLimit) internal
        returns (uint sellValue, uint buyValue)
    {
        // A limit of 0 is no limit.
        if (sellLimit == 0) sellLimit = type(uint).max;
        if (buyLimit == 0) buyLimit = type(uint).max;
        if (priceLimit == 0) priceLimit = type(uint).max;
        // Determine the value of 1 big unit of sell asset.
        uint sellAssetBigUnit = getAssetBigUnit(sellAsset);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellAsset][buyAsset];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderIdValue[sellAsset][buyAsset];
        // Get the first sell order.
        bytes32 start = orderLL[0];
        bytes32 orderId = start;
        while (orderId != 0 && buyLimit != 0 && sellLimit != 0) {
            // Get order account, price.
            (address sellAccount, uint price) = decodeOrderId(orderId);
            // Check if we have hit the price limit.
            if (price > priceLimit) break;
            // Calculate how much buy asset it will take to buy this order.
            uint orderSellValue = orderValue[orderId];
            uint orderBuyValue = (orderSellValue * price) / sellAssetBigUnit;
            // Is there a full or partial match?
            if (sellLimit >= orderSellValue && buyLimit >= orderBuyValue) {
                // Full match.
                // Update buyer balances.
                sellValue += orderSellValue;
                buyValue += orderBuyValue;
                // Update remaining buy limit.
                sellLimit -= orderSellValue;
                buyLimit -= orderBuyValue;
                // Pay seller.
                accountAssetBalance[sellAccount][buyAsset] += orderBuyValue;
                // Log the event.
                emit OrderFullMatch(sellAsset, buyAsset, orderId, orderSellValue);
                // Delete the order.
                bytes32 next = orderLL[orderId];
                delete orderLL[orderId];
                delete orderValue[orderId];
                orderId = next;
            }
            else {
                // Partial match.
                // Calculate how much of the sell asset can be bought at the current order's price.
                uint sellValueLimit = (buyLimit * sellAssetBigUnit) / price;
                // Update buyer balances.
                sellValue += sellValueLimit;
                buyValue += buyLimit;
                // Buy limit has now been spent.
                buyLimit = 0;
                // Pay seller.
                accountAssetBalance[sellAccount][buyAsset] += buyLimit;
                // Update order value.
                orderValue[orderId] = orderSellValue - sellValueLimit; // TODO: ensure this isn't 0
                // Log the event.
                emit OrderPartialMatch(sellAsset, buyAsset, orderId, sellValueLimit);
                // Exit.
                break;
            }
        }
        // Was anything bought?
        if (sellValue == 0) revert NoMatch();
        // Update first order if neccessary.
        if (start != orderId) orderLL[0] = orderId;
    }

    enum BuyOrderType { SellValueExact, BuyValueExact, Limit }

    struct BuyOrder {
        BuyOrderType orderType;
        address sellAsset;
        address buyAsset;
        uint sellValue;
        uint buyValue;
        uint priceLimit;
    }

    function matchBuyOrder(BuyOrder calldata order) internal 
        assetsDifferent(order.sellAsset, order.buyAsset)
        returns (uint sellValue, uint buyValue)
    {
        if (order.orderType == BuyOrderType.SellValueExact) {
            buyValue = matchSellExact(order.sellAsset, order.buyAsset, order.sellValue, order.buyValue);
            sellValue = order.sellValue;
        }
        else if (order.orderType == BuyOrderType.BuyValueExact) {
            sellValue = matchBuyExact(order.sellAsset, order.buyAsset, order.buyValue, order.sellValue);
            buyValue = order.buyValue;
        }
        else {
            (sellValue, buyValue) = matchLimit(order.sellAsset, order.buyAsset, order.sellValue, order.buyValue, order.priceLimit);
        }
        // Log the event.
        emit MatchingCompleted(order.sellAsset, order.buyAsset, msg.sender, sellValue, buyValue);
    }

    /**
     * @dev Buy.
     */
    function buy(BuyOrder calldata order) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchBuyOrder(order);
        // Check there is sufficient balance.
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        if (assetBalance[order.buyAsset] < buyValue) revert InsufficientBalance();
        // Update buyer's balances.
        assetBalance[order.buyAsset] -= buyValue;
        assetBalance[order.sellAsset] += sellValue;
    }

    /**
     * @dev Buy with balance and withdraw.
     */
    function buyAndWithdraw(BuyOrder calldata order, address to) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchBuyOrder(order);
        // Check there is sufficient balance.
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        if (assetBalance[order.buyAsset] < buyValue) revert InsufficientBalance();
        // Update buyer's buy asset balance.
        assetBalance[order.buyAsset] -= buyValue;
        // Transfer the sell asset.
        _withdraw(order.sellAsset, to, sellValue);
    }

    function depositAsset(address asset, uint value) internal {
        if (asset == address(0)) {
            // Did the buyer pay enough?
            if (value > msg.value) {
                revert();
            }
            // Log deposit.
            emit Deposit(address(0), msg.sender, msg.value);
            // Send the buyer's change back.
            if (value < msg.value) {
                _withdraw(address(0), msg.sender, msg.value - value);
            }
        }
        else {
            if (msg.value != 0) revert HasValue();
            // Transfer the buy assets from the buyer to this contract.
            _depositERC20(asset, value);
        }
    }

    /**
     * @dev Buy with base coin.
     */
    function buyWithDeposit(BuyOrder calldata order) external payable {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchBuyOrder(order);
        // Update buyer's sell asset balance.
        accountAssetBalance[msg.sender][order.sellAsset] += sellValue;
        // Transfer the buy assets from the buyer to this contract.
        depositAsset(order.buyAsset, buyValue);
    }

    /**
     * @dev Buy with base coin.
     */
    function buyWithDepositAndWithdraw(BuyOrder calldata order, address to) external payable {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchBuyOrder(order);
        // Transfer the buy assets from the buyer to this contract.
        depositAsset(order.buyAsset, buyValue);
        // Transfer the sell asset.
        _withdraw(order.sellAsset, to, sellValue);
    }

    /**
     * @dev Get balance of asset for account.
     */
    function getBalance(address asset, address account) external view returns (uint value) {
        value = accountAssetBalance[account][asset];
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
    function getOrderBook(address sellAsset, address buyAsset, uint maxOrders) external view
        assetsDifferent(sellAsset, buyAsset)
        returns (Order[] memory orderBook)
    {
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellAsset][buyAsset];
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderIdValue[sellAsset][buyAsset];
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
            (address sellAccount, uint96 price) = decodeOrderId(orderId);
            
            orderBook[i] = Order({
                account: sellAccount,
                price: price,
                value: orderValue[orderId] 
            });

            orderId = orderLL[orderId];
        }
    }

    /**
     * @dev
     */
    function getOrderValue(address sellAsset, address buyAsset, address seller, uint96 price) external view
        assetsDifferent(sellAsset, buyAsset)
        returns (uint value)
    {
        bytes32 orderId = encodeOrderId(seller, price);
        value = sellBuyOrderIdValue[sellAsset][buyAsset][orderId];
    }
}
