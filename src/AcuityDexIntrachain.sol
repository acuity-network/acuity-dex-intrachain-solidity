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
    event Withdrawal(address asset, address account, uint value);
    
    /**
     * @dev
     */
    event OrderAdded(address sellAsset, address buyAsset, address account, uint price, uint value);

    /**
     * @dev
     */
    event OrderRemoved(address sellAsset, address buyAsset, address account, uint price, uint value);

    /**
     * @dev Sell orders have been purchased by a buyer.
     */
    event Matched(address sellAsset, address buyAsset, address buyer, uint buyValue, uint sellValue);
    
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
     * @dev Sell orders have been purchased by a buyer.
     */
    error NoMatch(address sellAsset, address buyAsset, address buyer, uint buyValueMax);

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

    function _withdrawBase(uint value) internal returns (bool success) {
        bytes memory data;
        (success, data) = msg.sender.call{value: value}(hex"");
        if (success && data.length != 0) success = abi.decode(data, (bool));
    }

    function _withdrawERC20(address asset, uint value) internal returns (bool success) {
        bytes memory data;
        (success, data) = asset.call(abi.encodeWithSelector(ERC20.transfer.selector, msg.sender, value));
        if (success && data.length != 0) success = abi.decode(data, (bool));
    }

    /**
     * @dev
     */
    function _withdraw(address asset, uint value) internal
        validAsset(asset)
    {
        // https://docs.openzeppelin.com/contracts/3.x/api/utils#Address-sendValue-address-payable-uint256-
        bool success;
        if (asset == address(0)) {
            success = _withdrawBase(value);
        }
        else {
            success = _withdrawERC20(asset, value);
        }
        if (!success) revert WithdrawalFailed(asset, msg.sender, value);
        // Log event.
        emit Withdrawal(asset, msg.sender, value);
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
        // Log event.
        emit Deposit(address(0), msg.sender, msg.value);
        // Update balance.
        accountAssetBalance[msg.sender][address(0)] += msg.value;
    }

    // ERC1155?

    function depositERC20(address asset, uint value) external hasValue(value) {
        // Update balance.
        accountAssetBalance[msg.sender][asset] += value;
        // Transfer value.
        _depositERC20(asset, value);
    }

    function withdraw(address asset, uint value) external hasValue(value) {
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        // Check there is sufficient balance.
        if (assetBalance[asset] < value) revert InsufficientBalance();
        // Update balance.
        accountAssetBalance[msg.sender][asset] -= value;
        // Transfer value.
        _withdraw(asset, value);
    }

    function withdrawAll(address asset) external {
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        // Get asset balance.
        uint value = assetBalance[asset];
        // Check there is a balance.
        if (value == 0) revert InsufficientBalance();
        // Delete asset balance.
        delete assetBalance[asset];
        // Transfer value.
        _withdraw(asset, value);
    }

    function _addOrder(address sellAsset, address buyAsset, uint96 price, uint value) internal
        assetsDifferent(sellAsset, buyAsset)
        hasValue(value)
    {
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellAsset][buyAsset];
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(price);
        // Log event.
        emit OrderAdded(sellAsset, buyAsset, msg.sender, price, value);
        // Get the old order value.
        uint oldValue = orderValue[orderId];
        // Does this order already exist?
        if (oldValue > 0) {
            orderValue[orderId] = oldValue + value;
            return;
        }
        // Set the order value.
        orderValue[orderId] = value;
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
        orderLL[prev] = orderId;
        orderLL[orderId] = next;
    }

    /**
     * @dev Add sell order.
     */
    function addOrder(address sellAsset, address buyAsset, uint96 sellPrice, uint sellValue) external {
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        // Check there is sufficient balance.
        if (assetBalance[sellAsset] < sellValue) revert InsufficientBalance();
        // Add order.
        _addOrder(sellAsset, buyAsset, sellPrice, sellValue);
        // Update Balance.
        assetBalance[sellAsset] -= sellValue;
    }

    /**
     * @dev Add sell order of base coin.
     */
    function addOrderWithDeposit(address buyAsset, uint96 sellPrice) external payable {
        _addOrder(address(0), buyAsset, sellPrice, msg.value);
    }

    /**
     * @dev Add sell order of ERC20 asset.
     */
    function addOrderWithDepositERC20(address sellAsset, address buyAsset, uint96 sellPrice, uint value) external {
        // Add the sell order.
        _addOrder(sellAsset, buyAsset, sellPrice, value);
        // Transfer the assets from the seller to this contract.
        _depositERC20(sellAsset, value);
    }

    function _removeOrder(address sellAsset, address buyAsset, uint96 sellPrice) internal
        assetsDifferent(sellAsset, buyAsset)
        returns (uint value)
    {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellAsset][buyAsset];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellAsset][buyAsset];
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(sellPrice);
        // Get the value of the order being removed.
        value = orderValue[orderId];
        // Check if the order exists.
        if (value == 0) {
            revert OrderNotFound();
        }
        // Delete the order value.
        delete orderValue[orderId];
        // Find the previous sell order.
        bytes32 prev = 0;
        while (orderLL[prev] != orderId) {
            prev = orderLL[prev];
        }
        // Remove from linked list.        
        orderLL[prev] = orderLL[orderId];
        delete orderLL[orderId];
        // Log event.
        emit OrderRemoved(sellAsset, buyAsset, msg.sender, sellPrice, value);
    }

    function removeOrder(address sellAsset, address buyAsset, uint96 sellPrice) external {
        uint value = _removeOrder(sellAsset, buyAsset, sellPrice);
        accountAssetBalance[msg.sender][sellAsset] += value;
    }
    
    function removeOrderAndWithdraw(address sellAsset, address buyAsset, uint96 sellPrice) external {
        uint value = _removeOrder(sellAsset, buyAsset, sellPrice);
        _withdraw(sellAsset, value);
    }

    function _removeOrderPartial(address sellAsset, address buyAsset, uint96 sellPrice, uint partialValue) internal
        assetsDifferent(sellAsset, buyAsset)
        hasValue(partialValue)
    {
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(sellPrice);
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellAsset][buyAsset];
        // Get the value of the order being removed.
        uint value = orderValue[orderId];
        // Check if the order exists.
        if (value == 0) {
            revert OrderNotFound();
        }
        // Is the whole order being deleted?
        if (partialValue >= value) {
            partialValue = value;
            // Delete the order value.
            delete orderValue[orderId];
            // _deleteOrderLL()
        }
        else {
            orderValue[orderId] = value - partialValue;
        }
        // Log event.
        emit OrderRemoved(sellAsset, buyAsset, msg.sender, sellPrice, partialValue);
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

    function _match(address sellAsset, address buyAsset, uint buyValueMax) internal
        assetsDifferent(sellAsset, buyAsset)
        returns (uint sellValue, uint buyValue)
    {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellAsset][buyAsset];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellAsset][buyAsset];
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
                accountAssetBalance[sellAccount][buyAsset] += buyValueMax;
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
                accountAssetBalance[sellAccount][buyAsset] += matchedBuyValue;
                sellValue += orderSellValue;
            }
        }
        if (sellValue == 0 || buyValue == 0) {
            revert NoMatch(sellAsset, buyAsset, msg.sender, buyValueMax);
        }
        // Log the event.
        emit Matched(sellAsset, buyAsset, msg.sender, sellValue, buyValue);
    }

    /**
     * @dev Buy.
     */
    function buy(address sellAsset, address buyAsset, uint buyValueMax) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = _match(sellAsset, buyAsset, buyValueMax);
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
    function buyAndWithdraw(address sellAsset, address buyAsset, uint buyValueMax) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = _match(sellAsset, buyAsset, buyValueMax);
        // Check there is sufficient balance.
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        if (assetBalance[buyAsset] < buyValue) revert InsufficientBalance();
        // Update buyer's buy asset balance.
        assetBalance[buyAsset] -= buyValue;
        // Transfer the sell assets to the buyer.
        _withdraw(sellAsset, sellValue);
    }
    
    /**
     * @dev Buy with base coin.
     */
    function buyWithDeposit(address sellAsset) external payable {
        // Log deposit.
        emit Deposit(address(0), msg.sender, msg.value);
        // Execute the buy.
        (uint sellValue, uint buyValue) = _match(sellAsset, address(0), msg.value);
        // Credit the buyer with their change.
        if (buyValue < msg.value) {
            accountAssetBalance[msg.sender][address(0)] += msg.value - buyValue;
        }
        // Update buyer's sell asset balance.
        accountAssetBalance[msg.sender][sellAsset] += sellValue;
    }

    /**
     * @dev Buy with ERC20 asset.
     */
    function buyWithDepositERC20(address sellAsset, address buyAsset, uint buyValueMax) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = _match(sellAsset, buyAsset, buyValueMax);
        // Transfer the buy assets from the buyer to this contract.
        _depositERC20(buyAsset, buyValue);
        // Update buyer's sell asset balance.
        accountAssetBalance[msg.sender][sellAsset] += sellValue;
    }

    /**
     * @dev Buy with base coin.
     */
    function buyWithDepositAndWithdraw(address sellAsset) external payable {
        // Log deposit.
        emit Deposit(address(0), msg.sender, msg.value);
        // Execute the buy.
        (uint sellValue, uint buyValue) = _match(sellAsset, address(0), msg.value);
        // Send the buyer's change back.
        if (buyValue < msg.value) {
            _withdraw(address(0), msg.value - buyValue);
        }
        // Transfer the sell assets to the buyer.
        _withdraw(sellAsset, sellValue);
    }

    /**
     * @dev Buy with ERC20 asset.
     */
    function buyWithDepositERC20AndWithdraw(address sellAsset, address buyAsset, uint buyValueMax) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = _match(sellAsset, buyAsset, buyValueMax);
        // Transfer the buy assets from the buyer to this contract.
        _depositERC20(buyAsset, buyValue);
        // Transfer the sell assets to the buyer.
        _withdraw(sellAsset, sellValue);
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
    function getOrderValue(address sellAsset, address buyAsset, address seller, uint96 price) external view
        assetsDifferent(sellAsset, buyAsset)
        returns (uint value)
    {
        bytes32 orderId = encodeOrderId(seller, price);
        value = sellBuyOrderValue[sellAsset][buyAsset][orderId];
    }
}
