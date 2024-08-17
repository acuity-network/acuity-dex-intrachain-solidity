// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import "./ERC20.sol";

contract AcuityDexIntrachain {

    mapping (address => mapping (address => uint)) accountAssetBalance;

    /**
     * @dev Mapping of selling asset address to buying asset address to linked list of sell orders, starting with the lowest selling price.
     */
    mapping (address => mapping (address => mapping (bytes32 => bytes32))) sellBuyOrderLL;

    mapping (address => mapping (address => mapping (bytes32 => uint))) sellBuyOrderValue;

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
    event OrderValueAdded(address sellAsset, address buyAsset, address account, uint price, uint value);

    /**
     * @dev
     */
    event OrderValueRemoved(address sellAsset, address buyAsset, address account, uint price, uint value);

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
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellAsset][buyAsset];
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(price);
        // Log event.
        emit OrderValueAdded(sellAsset, buyAsset, msg.sender, price, value);
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
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellAsset][buyAsset];
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
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellAsset][buyAsset];
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
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellAsset][buyAsset];
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
        emit OrderValueRemoved(sellAsset, buyAsset, msg.sender, price, value);
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
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellAsset][buyAsset];
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
        emit OrderValueRemoved(sellAsset, buyAsset, msg.sender, price, valueRemoved);
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
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellAsset][buyAsset];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellAsset][buyAsset];

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

    function matchOrders(address sellAsset, address buyAsset, uint buyValueLimit, uint priceLimit) internal
        assetsDifferent(sellAsset, buyAsset)
        returns (uint sellValue, uint buyValue)
    {
        // A price limit of 0 is no limit.
        if (priceLimit == 0) priceLimit = type(uint).max;
        // Determine the value of 1 big unit of sell asset.
        uint sellAssetBigUnit = getAssetBigUnit(sellAsset);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellAsset][buyAsset];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellAsset][buyAsset];
        // Get the first sell order.
        bytes32 start = orderLL[0];
        bytes32 orderId = start;
        while (orderId != 0 && buyValueLimit != 0) {
            (address sellAccount, uint price) = decodeOrderId(orderId);
            // Check if we have hit the price limit.
            if (price > priceLimit) break;
            // Calculate how much buy asset it will take to buy this order.
            uint orderSellValue = orderValue[orderId];
            uint orderBuyValue = (orderSellValue * price) / sellAssetBigUnit;
            // Is there a full or partial match?
            if (buyValueLimit >= orderBuyValue) {
                // Full match. 8,700 - (1/5 refund) = 6,960 storage gas
                // Update buyer balances.
                sellValue += orderSellValue;
                buyValue += orderBuyValue;
                // Update remaining buy value.
                buyValueLimit -= orderBuyValue;
                // Pay seller.
                accountAssetBalance[sellAccount][buyAsset] += orderBuyValue;  // 2,900
                // Log the event.
                emit OrderFullMatch(sellAsset, buyAsset, orderId, orderSellValue);
                // Delete the order.
                bytes32 next = orderLL[orderId];
                delete orderLL[orderId];    // 2,900 and 4,800 refund
                delete orderValue[orderId]; // 2,900 and 4,800 refund
                orderId = next;
            }
            else {
                // Partial match.
                // Calculate how much of the sell asset can be bought at the current order's price.
                uint sellValueLimit = (buyValueLimit * sellAssetBigUnit) / price;
                // Update buyer balances.
                sellValue += sellValueLimit;
                buyValue += buyValueLimit;
                // Pay seller.
                accountAssetBalance[sellAccount][buyAsset] += buyValueLimit;
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
        // Log the event.
        emit MatchingCompleted(sellAsset, buyAsset, msg.sender, sellValue, buyValue);
    }

    /**
     * @dev Buy.
     */
    function buy(address sellAsset, address buyAsset, uint buyValueLimit, uint priceLimit) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchOrders(sellAsset, buyAsset, buyValueLimit, priceLimit);
        // Check there is sufficient balance.
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        if (assetBalance[buyAsset] < buyValue) revert InsufficientBalance();
        // Update buyer's balances.
        assetBalance[buyAsset] -= buyValue;
        assetBalance[sellAsset] += sellValue;
    }

    /**
     * @dev Buy with balance and withdraw.
     */
    function buyAndWithdraw(address sellAsset, address buyAsset, uint buyValueLimit, uint priceLimit, address to) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchOrders(sellAsset, buyAsset, buyValueLimit, priceLimit);
        // Check there is sufficient balance.
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        if (assetBalance[buyAsset] < buyValue) revert InsufficientBalance();
        // Update buyer's buy asset balance.
        assetBalance[buyAsset] -= buyValue;
        // Transfer the sell asset.
        _withdraw(sellAsset, to, sellValue);
    }
    
    /**
     * @dev Buy with base coin.
     */
    function buyWithDeposit(address sellAsset, uint priceLimit) external payable {
        // Log deposit.
        emit Deposit(address(0), msg.sender, msg.value);
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchOrders(sellAsset, address(0), msg.value, priceLimit);
        // Credit the buyer with their change.
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        if (buyValue < msg.value) {
            assetBalance[address(0)] += msg.value - buyValue;
        }
        // Update buyer's sell asset balance.
        assetBalance[sellAsset] += sellValue;
    }

    /**
     * @dev Buy with ERC20 asset.
     */
    function buyWithDepositERC20(address sellAsset, address buyAsset, uint buyValueLimit, uint priceLimit) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchOrders(sellAsset, buyAsset, buyValueLimit, priceLimit);
        // Update buyer's sell asset balance.
        accountAssetBalance[msg.sender][sellAsset] += sellValue;
        // Transfer the buy assets from the buyer to this contract.
        _depositERC20(buyAsset, buyValue);
    }

    /**
     * @dev Buy with base coin.
     */
    function buyWithDepositAndWithdraw(address sellAsset, uint priceLimit, address to) external payable {
        // Log deposit.
        emit Deposit(address(0), msg.sender, msg.value);
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchOrders(sellAsset, address(0), msg.value, priceLimit);
        // Send the buyer's change back.
        if (buyValue < msg.value) {
            _withdraw(address(0), msg.sender, msg.value - buyValue);
        }
        // Transfer the sell asset.
        _withdraw(sellAsset, to, sellValue);
    }

    /**
     * @dev Buy with ERC20 asset.
     */
    function buyWithDepositERC20AndWithdraw(address sellAsset, address buyAsset, uint buyValueLimit, uint priceLimit, address to) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchOrders(sellAsset, buyAsset, buyValueLimit, priceLimit);
        // Transfer the buy assets from the buyer to this contract.
        _depositERC20(buyAsset, buyValue);
        // Transfer the sell asset.
        _withdraw(sellAsset, to, sellValue);
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
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellAsset][buyAsset];
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellAsset][buyAsset];
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
        value = sellBuyOrderValue[sellAsset][buyAsset][orderId];
    }
}
