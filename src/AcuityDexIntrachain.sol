// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import "./ERC20.sol";

contract AcuityDexIntrachain {

    mapping (address => mapping (address => uint)) accountAssetBalance;

    /**
     * @dev Mapping of selling asset address to buying asset address to linked list of sell orders, starting with the lowest selling price.
     */
    mapping (address => mapping (address => mapping (bytes32 => bytes32))) sellBuyOrderIdLL;

    mapping (address => mapping (address => mapping (bytes32 => bytes32))) sellBuyOrderIdValueTimeout;

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
    event OrderAdded(address sellAsset, address buyAsset, bytes32 orderId, uint value, uint timeout);

    /**
     * @dev
     */
    event OrderRemoved(address sellAsset, address buyAsset, bytes32 orderId, uint value);

    /**
     * @dev
     */
    event OrderValueAdded(address sellAsset, address buyAsset, bytes32 orderId, uint value, uint timeout);

    /**
     * @dev
     */
    event OrderValueRemoved(address sellAsset, address buyAsset, bytes32 orderId, uint value, uint timeout);

    /**
     * @dev
     */
    event OrderFullMatch(address sellAsset, address buyAsset, bytes32 orderId, uint value);

    /**
     * @dev
     */
    event OrderPartialMatch(address sellAsset, address buyAsset, bytes32 orderId, uint value);

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
    error InvalidAddress();

    /**
     * @dev
     */
    error ValueZero();

    /**
     * @dev
     */
    error ValueNonZero();

    /**
     * @dev
     */
    error TimeoutExpired();

    /**
     * @dev
     */
    error PriceZero();

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
     * @dev Ensure the asset is valid.
     */
    modifier assetValid(address asset) {
        if (asset == msg.sender || asset == address(this)) revert InvalidAsset();
        _;
    }

    /**
     * @dev
     */
    modifier addressValid(address _address) {
        if (_address == address(this)) revert InvalidAddress();
        _;
    }

    /**
     * @dev Ensure the call has value.
     */
    modifier msgValueNonZero() {
        if (msg.value == 0) revert ValueZero();
        _;
    }

    /**
     * @dev Ensure value is non-zero.
     */
    modifier valueNonZero(uint value) {
        if (value == 0) revert ValueZero();
        _;
    }

    /**
     * @dev Ensure timeout has not expired.
     */
    modifier timeoutNotExpired(uint32 timeout) {
        if (timeout <= block.timestamp) revert TimeoutExpired();
        _;
    }

    /**
     * @dev Ensure price is non-zero.
     */
    modifier priceNonZero(uint price) {
        if (price == 0) revert PriceZero();
        _;
    }

    /**
     * @dev Check sell and buy assets are not the same.
     */
    modifier assetPairValid(address sellAsset, address buyAsset) {
        if (sellAsset == msg.sender || sellAsset == address(this)) revert InvalidAsset();
        if (buyAsset == msg.sender || buyAsset == address(this)) revert InvalidAsset();
        if (sellAsset == buyAsset) revert AssetsNotDifferent();
        _;
    }

    /**
     * @dev
     */
    function _depositERC20(address asset, uint value) internal {
        (bool success, bytes memory data) = asset.call(abi.encodeWithSelector(ERC20.transferFrom.selector, msg.sender, address(this), value));
        if (success && data.length != 0) success = abi.decode(data, (bool));
        if (!success) revert DepositFailed(asset, msg.sender, value);
        // Log event.
        emit Deposit(asset, msg.sender, value);
    }

    /**
     * @dev
     */
    function _deposit(address asset, uint value) internal {
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
            if (msg.value != 0) revert ValueNonZero();
            // Transfer the buy assets from the buyer to this contract.
            _depositERC20(asset, value);
        }
    }

    /**
     * @dev
     */
    function _withdraw(address asset, address to, uint value) internal {
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

    function encodeValueTimeout(uint224 value, uint32 timeout) internal pure returns (bytes32 valueTimeout) {
        if (timeout == 0) timeout = type(uint32).max;
        valueTimeout = bytes32((uint(value) << 32) | uint(timeout));
    }

    function decodeValueTimeout(bytes32 valueTimeout) internal pure returns (uint224 value, uint32 timeout) {
        value = uint224(uint(valueTimeout) >> 32);
        timeout = uint32(uint(valueTimeout));
    }

    /**
     * @dev Deposit base coin.
     */
    function deposit() external payable msgValueNonZero {
        // Update balance.
        accountAssetBalance[msg.sender][address(0)] += msg.value;
        // Log event.
        emit Deposit(address(0), msg.sender, msg.value);
    }

    // ERC1155?

    function depositERC20(address asset, uint value) external
        assetValid(asset)
        valueNonZero(value)
    {
        // Update balance.
        accountAssetBalance[msg.sender][asset] += value;
        // Transfer value.
        _depositERC20(asset, value);
    }

    function withdraw(address asset, address to, uint value) external
        assetValid(asset)
        addressValid(to)
        valueNonZero(value)
    {
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        // Check there is sufficient balance.
        if (assetBalance[asset] < value) revert InsufficientBalance();
        // Update balance.
        assetBalance[asset] -= value;
        // Transfer value.
        _withdraw(asset, to, value);
    }

    function withdrawAll(address asset, address to) external
        assetValid(asset)
        addressValid(to)
    {
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        // Get asset balance.
        uint value = assetBalance[asset];
        // Check there is a balance.
        if (value == 0) revert ValueZero();
        // Delete asset balance.
        delete assetBalance[asset];
        // Transfer value.
        _withdraw(asset, to, value);
    }

    /**
     * @dev Add value to an order.
     */
    function _addOrderValue(address sellAsset, address buyAsset, uint96 price, uint224 value, uint32 timeout) internal {
        // Sell value of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellAsset][buyAsset];
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(price);
        // Get the old order value.
        (uint224 oldValue,) = decodeValueTimeout(orderValueTimeout[orderId]);
        // Does this order already exist?
        if (oldValue > 0) {
            orderValueTimeout[orderId] = encodeValueTimeout(oldValue + value, timeout);
            // Log event.
            emit OrderValueAdded(sellAsset, buyAsset, orderId, value, timeout);
            return;
        }
        // Set the order value.
        orderValueTimeout[orderId] = encodeValueTimeout(value, timeout);
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
        orderLL[prev] = orderId;
        orderLL[orderId] = next;
        // Log event.
        emit OrderAdded(sellAsset, buyAsset, orderId, value, timeout);
    }

    /**
     * @dev Add value to an order.
     */
    function addOrderValue(address sellAsset, address buyAsset, uint96 price, uint224 value, uint32 timeout) external
        assetPairValid(sellAsset, buyAsset)
        priceNonZero(price)
        valueNonZero(value)
        timeoutNotExpired(timeout)
    {
        mapping(address => uint256) storage assetBalance = accountAssetBalance[msg.sender];
        // Check there is sufficient balance.
        if (assetBalance[sellAsset] < value) revert InsufficientBalance();
        // Add order.
        _addOrderValue(sellAsset, buyAsset, price, value, timeout);
        // Update Balance.
        assetBalance[sellAsset] -= value;
    }

    /**
     * @dev Add sell order of base coin.
     */
    function addOrderValueWithDeposit(address buyAsset, uint96 price, uint32 timeout) external payable
        assetValid(buyAsset)
        priceNonZero(price)
        msgValueNonZero
        timeoutNotExpired(timeout)
    {
        _addOrderValue(address(0), buyAsset, price, uint224(msg.value), timeout);
    }

    /**
     * @dev Add sell order of ERC20 asset.
     */
    function addOrderValueWithDepositERC20(address sellAsset, address buyAsset, uint96 price, uint224 value, uint32 timeout) external
        assetPairValid(sellAsset, buyAsset)
        priceNonZero(price)
        valueNonZero(value)
        timeoutNotExpired(timeout)
    {
        // Add the sell order.
        _addOrderValue(sellAsset, buyAsset, price, value, timeout);
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
        returns (uint value)
    {
        // Sell value of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellAsset][buyAsset];
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(price);
        // Get the value of the order being removed.
        (value,) = decodeValueTimeout(orderValueTimeout[orderId]);
        // Check if the order exists.
        if (value == 0) {
            revert OrderNotFound();
        }
        // Delete the order value.
        delete orderValueTimeout[orderId];
        // Delete the order from the linked list.
        deleteOrderLL(sellAsset, buyAsset, orderId);
        // Log event.
        emit OrderRemoved(sellAsset, buyAsset, orderId, value);
    }

    function removeOrder(address sellAsset, address buyAsset, uint96 price) external
        assetPairValid(sellAsset, buyAsset)
        priceNonZero(price)
    {
        uint value = _removeOrder(sellAsset, buyAsset, price);
        accountAssetBalance[msg.sender][sellAsset] += value;
    }
    
    function removeOrderAndWithdraw(address sellAsset, address buyAsset, uint96 price, address to) external
        assetPairValid(sellAsset, buyAsset)
        priceNonZero(price)
        addressValid(to)
    {
        uint value = _removeOrder(sellAsset, buyAsset, price);
        _withdraw(sellAsset, to, value);
    }

    function _removeOrderValue(address sellAsset, address buyAsset, uint96 price, uint224 valueLimit, uint32 timeout) internal
        returns (uint valueRemoved)  // Is this neccessary?
    {
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(price);
        // Sell value of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellAsset][buyAsset];
        // Get the value of the order being removed.
        (uint224 value,) = decodeValueTimeout(orderValueTimeout[orderId]);
        // Check if the order exists.
        if (value == 0) {
            revert OrderNotFound();
        }
        // Is the whole order being deleted?
        if (valueLimit >= value) {
            valueRemoved = value;
            // Delete the order value.
            delete orderValueTimeout[orderId];
            // Delete the order from the linked list.
            deleteOrderLL(sellAsset, buyAsset, orderId);
            // Log event.
            emit OrderRemoved(sellAsset, buyAsset, orderId, valueRemoved);
        }
        else {
            orderValueTimeout[orderId] = encodeValueTimeout(value - valueLimit, timeout);
            valueRemoved = valueLimit;
            // Log event.
            emit OrderValueRemoved(sellAsset, buyAsset, orderId, valueRemoved, timeout);
        }
    }

    function removeOrderValue(address sellAsset, address buyAsset, uint96 price, uint224 valueLimit, uint32 timeout) external
        assetPairValid(sellAsset, buyAsset)
        priceNonZero(price)
        valueNonZero(valueLimit)
        timeoutNotExpired(timeout)
    {
        uint value = _removeOrderValue(sellAsset, buyAsset, price, valueLimit, timeout);
        accountAssetBalance[msg.sender][sellAsset] += value;
    }
    
    function removeOrderValueAndWithdraw(address sellAsset, address buyAsset, uint96 price, uint224 valueLimit, uint32 timeout, address to) external
        assetPairValid(sellAsset, buyAsset)
        priceNonZero(price)
        valueNonZero(valueLimit)
        timeoutNotExpired(timeout)
        addressValid(to)
    {
        uint value = _removeOrderValue(sellAsset, buyAsset, price, valueLimit, timeout);
        _withdraw(sellAsset, to, value);
    }

    function adjustOrderPrice(address sellAsset, address buyAsset, uint96 oldPrice, uint96 newPrice) external
        assetPairValid(sellAsset, buyAsset)
        priceNonZero(oldPrice)
        priceNonZero(newPrice)
     {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellAsset][buyAsset];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellAsset][buyAsset];

        bytes32 oldOrder = encodeOrderId(oldPrice);
        bytes32 newOrder = encodeOrderId(newPrice);

        if (orderValueTimeout[oldOrder] == 0) {
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
        orderValueTimeout[newOrder] = orderValueTimeout[oldOrder];
        delete orderValueTimeout[oldOrder];
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

    function matchSellExact(address sellAsset, address buyAsset, uint224 sellValue, uint buyLimit) internal
        returns (uint buyValue)
    {
        // Determine the value of 1 big unit of sell asset.
        uint sellAssetBigUnit = getAssetBigUnit(sellAsset);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellAsset][buyAsset];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellAsset][buyAsset];
        // Get the first sell order.
        bytes32 start = orderLL[0];
        bytes32 orderId = start;
        while (sellValue != 0) {
            // Check if we have run out of orders.
            if (orderId == 0) revert NoMatch();
            // Get order account, price, value and timeout.
            (address sellAccount, uint price) = decodeOrderId(orderId);
            (uint224 orderSellValue, uint32 timeout) = decodeValueTimeout(orderValueTimeout[orderId]);
            // Has the order timed out?
            if (timeout <= block.timestamp) {
                // Refund the seller.
                accountAssetBalance[sellAccount][sellAsset] += orderSellValue;
                // Log event.
                emit OrderRemoved(sellAsset, buyAsset, orderId, orderSellValue);
                // Delete the order.
                bytes32 next = orderLL[orderId];
                delete orderLL[orderId];
                delete orderValueTimeout[orderId];
                orderId = next;
                // Goto next order.
                continue;
            }
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
                delete orderValueTimeout[orderId];
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
                orderValueTimeout[orderId] = encodeValueTimeout(orderSellValue - sellValue, timeout);
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
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellAsset][buyAsset];
        // Get the first sell order.
        bytes32 start = orderLL[0];
        bytes32 orderId = start;
        while (buyValue != 0) {
            // Check if we have run out of orders.
            if (orderId == 0) revert NoMatch();
            // Get order account, price, value and timeout.
            (address sellAccount, uint price) = decodeOrderId(orderId);
            (uint224 orderSellValue, uint32 timeout) = decodeValueTimeout(orderValueTimeout[orderId]);
            // Has the order timed out?
            if (timeout <= block.timestamp) {
                // Refund the seller.
                accountAssetBalance[sellAccount][sellAsset] += orderSellValue;
                // Log event.
                emit OrderRemoved(sellAsset, buyAsset, orderId, orderSellValue);
                // Delete the order.
                bytes32 next = orderLL[orderId];
                delete orderLL[orderId];
                delete orderValueTimeout[orderId];
                orderId = next;
                // Goto next order.
                continue;
            }
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
                delete orderValueTimeout[orderId];
                orderId = next;
            }
            else {
                // Partial match.
                // Calculate how much of the sell asset can be bought at the current order's price.
                uint224 partialSellValue = uint224((buyValue * sellAssetBigUnit) / price);
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
                    delete orderValueTimeout[orderId];
                    orderId = next;
                }
                else {
                    orderValueTimeout[orderId] = encodeValueTimeout(orderSellValue, timeout);
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
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellAsset][buyAsset];
        // Get the first sell order.
        bytes32 start = orderLL[0];
        bytes32 orderId = start;
        while (orderId != 0 && buyLimit != 0 && sellLimit != 0) {
            // Get order account, price, value and timeout.
            (address sellAccount, uint price) = decodeOrderId(orderId);
            (uint224 orderSellValue, uint32 timeout) = decodeValueTimeout(orderValueTimeout[orderId]);
            // Has the order timed out?
            if (timeout <= block.timestamp) {
                // Refund the seller.
                accountAssetBalance[sellAccount][sellAsset] += orderSellValue;
                // Log event.
                emit OrderRemoved(sellAsset, buyAsset, orderId, orderSellValue);
                // Delete the order.
                bytes32 next = orderLL[orderId];
                delete orderLL[orderId];
                delete orderValueTimeout[orderId];
                orderId = next;
                // Goto next order.
                continue;
            }
            // Check if we have hit the price limit.
            if (price > priceLimit) break;
            // Calculate how much buy asset it will take to buy this order.
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
                delete orderValueTimeout[orderId];
                orderId = next;
            }
            else {
                // Partial match.
                // Calculate how much of the sell asset can be bought at the current order's price.
                uint224 sellValueLimit = uint224((buyLimit * sellAssetBigUnit) / price);
                // Update buyer balances.
                sellValue += sellValueLimit;
                buyValue += buyLimit;
                // Buy limit has now been spent.
                buyLimit = 0;
                // Pay seller.
                accountAssetBalance[sellAccount][buyAsset] += buyLimit;
                // Update order value.
                orderValueTimeout[orderId] = encodeValueTimeout(orderSellValue - sellValueLimit, timeout); // TODO: ensure this isn't 0
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
        uint224 sellValue;
        uint buyValue;
        uint priceLimit;
    }

    function matchBuyOrder(BuyOrder calldata order) internal 
        assetPairValid(order.sellAsset, order.buyAsset)
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
    function buyAndWithdraw(BuyOrder calldata order, address to) external
        addressValid(to)
    {
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

    /**
     * @dev Buy with base coin.
     */
    function buyWithDeposit(BuyOrder calldata order) external payable {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchBuyOrder(order);
        // Update buyer's sell asset balance.
        accountAssetBalance[msg.sender][order.sellAsset] += sellValue;
        // Transfer the buy assets from the buyer to this contract.
        _deposit(order.buyAsset, buyValue);
    }

    /**
     * @dev Buy with base coin.
     */
    function buyWithDepositAndWithdraw(BuyOrder calldata order, address to) external payable
        addressValid(to)
    {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchBuyOrder(order);
        // Transfer the buy assets from the buyer to this contract.
        _deposit(order.buyAsset, buyValue);
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
        uint32 timeout;
    }

    // paging?
    /**
     * @dev
     */
    function getOrderBook(address sellAsset, address buyAsset, uint maxOrders) external view
        assetPairValid(sellAsset, buyAsset)
        returns (Order[] memory orderBook)
    {
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellAsset][buyAsset];
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellAsset][buyAsset];
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
            // Get order account, price, value and timeout.
            (address account, uint price) = decodeOrderId(orderId);
            (uint value, uint32 timeout) = decodeValueTimeout(orderValueTimeout[orderId]);
            
            orderBook[i] = Order({
                account: account,
                price: price,
                value: value, 
                timeout: timeout
            });

            orderId = orderLL[orderId];
        }
    }

    /**
     * @dev
     */
    function getOrderValueTimeout(address sellAsset, address buyAsset, address seller, uint96 price) external view
        assetPairValid(sellAsset, buyAsset)
        returns (uint value, uint32 timeout)
    {
        bytes32 orderId = encodeOrderId(seller, price);
        (value, timeout) = decodeValueTimeout(sellBuyOrderIdValueTimeout[sellAsset][buyAsset][orderId]);
    }
}
