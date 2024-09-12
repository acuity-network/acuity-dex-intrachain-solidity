// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import "./ERC20.sol";

contract AcuityDexIntrachain {

    struct SellOrder {
        // --key----
        address sellAsset;
        address buyAsset;
        uint96 price;
        // --value--
        uint224 value;
        uint32 timeout;
        // ---------
        bytes32[] prevHint;
    }

    /**
     * @dev Mapping of asset to account to balance.
     */
    mapping (address => mapping (address => uint)) assetAccountBalance;

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
        assetAccountBalance[address(0)][msg.sender] += msg.value;
        // Log event.
        emit Deposit(address(0), msg.sender, msg.value);
    }

    // ERC1155?

    function depositERC20(address asset, uint value) external
        assetValid(asset)
        valueNonZero(value)
    {
        // Update balance.
        assetAccountBalance[asset][msg.sender] += value;
        // Transfer value.
        _depositERC20(asset, value);
    }

    function withdraw(address asset, address to, uint value) external
        assetValid(asset)
        addressValid(to)
        valueNonZero(value)
    {
        // Get asset balance.
        mapping(address => uint256) storage accountBalance = assetAccountBalance[asset];
        uint balance = accountBalance[msg.sender];
        // Check there is sufficient balance.
        if (balance < value) revert InsufficientBalance();
        // Update balance.
        accountBalance[msg.sender] = balance - value;
        // Transfer value.
        _withdraw(asset, to, value);
    }

    function withdrawAll(address asset, address to) external
        assetValid(asset)
        addressValid(to)
    {
        // Get asset balance.
        mapping(address => uint256) storage accountBalance = assetAccountBalance[asset];
        uint value = accountBalance[msg.sender];
        // Check there is a balance.
        if (value == 0) revert ValueZero();
        // Delete asset balance.
        delete accountBalance[msg.sender];
        // Transfer value.
        _withdraw(asset, to, value);
    }

    /**
     * @dev Add value to an order.
     */
    function _addOrderValue(SellOrder calldata sellOrder) internal {
        // Sell value of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellOrder.sellAsset][sellOrder.buyAsset];
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(sellOrder.price);
        // Get the old order value.
        (uint224 oldValue,) = decodeValueTimeout(orderValueTimeout[orderId]);
        // Does this order already exist?
        if (oldValue > 0) {
            // TODO: what if the existing order has timed out?
            orderValueTimeout[orderId] = encodeValueTimeout(oldValue + sellOrder.value, sellOrder.timeout);
            // Log event.
            emit OrderValueAdded(sellOrder.sellAsset, sellOrder.buyAsset, orderId, sellOrder.value, sellOrder.timeout);
            return;
        }
        // Set the order value.
        orderValueTimeout[orderId] = encodeValueTimeout(sellOrder.value, sellOrder.timeout);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellOrder.sellAsset][sellOrder.buyAsset];
        // Check the prev hints for a valid one.
        bytes32 prev = 0;
        uint i = 0;
        while (i < sellOrder.prevHint.length) {
            bytes32 prevHint = sellOrder.prevHint[i];
            (, uint96 prevPrice) = decodeOrderId(prevHint);
            // Ensure prev is in the linked list and less than or equal to new order.
            if (orderValueTimeout[prevHint] != 0 && prevPrice <= sellOrder.price) {
                prev = prevHint;
                break;
            }
            i++;
        }
        // Find correct place in linked list to insert order.
        bytes32 next = orderLL[prev];
        while (next != 0) {
            (, uint96 nextPrice) = decodeOrderId(next);
            // This ensures that new orders go after existing orders with the same price.
            if (nextPrice > sellOrder.price) {
                break;
            }
            prev = next;
            next = orderLL[prev];
        }
        // Insert into linked list.
        orderLL[prev] = orderId;
        orderLL[orderId] = next;
        // Log event.
        emit OrderAdded(sellOrder.sellAsset, sellOrder.buyAsset, orderId, sellOrder.value, sellOrder.timeout);
    }

    /**
     * @dev Add value to an order.
     */
    function addOrderValue(SellOrder calldata sellOrder) external
        assetPairValid(sellOrder.sellAsset, sellOrder.buyAsset)
        priceNonZero(sellOrder.price)
        valueNonZero(sellOrder.value)
        timeoutNotExpired(sellOrder.timeout)
    {
        // Get asset balance.
        mapping(address => uint256) storage accountBalance = assetAccountBalance[sellOrder.sellAsset];
        uint balance = accountBalance[msg.sender];
        // Check there is sufficient balance.
        if (balance < sellOrder.value) revert InsufficientBalance();
        // Add order.
        _addOrderValue(sellOrder);
        // Update Balance.
        accountBalance[msg.sender] = balance - sellOrder.value;
    }

    /**
     * @dev Add sell order of ERC20 asset.
     */
    function addOrderValueWithDeposit(SellOrder calldata sellOrder) external payable
        assetPairValid(sellOrder.sellAsset, sellOrder.buyAsset)
        priceNonZero(sellOrder.price)
        valueNonZero(sellOrder.value)
        timeoutNotExpired(sellOrder.timeout)
    {
        // Add the sell order.
        _addOrderValue(sellOrder);
        // Transfer the assets from the seller to this contract.
        _deposit(sellOrder.sellAsset, sellOrder.value);
    }

    function _removeOrder(SellOrder calldata sellOrder) internal
        returns (uint value)
    {
        // Sell value of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellOrder.sellAsset][sellOrder.buyAsset];
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(sellOrder.price);
        // Get the value of the order being removed.
        (value,) = decodeValueTimeout(orderValueTimeout[orderId]);
        // Check if the order exists.
        if (value == 0) {
            revert OrderNotFound();
        }
        // Delete the order value.
        delete orderValueTimeout[orderId];
        // Check the prev hints for a valid one.
        bytes32 prev = 0;
        uint i = 0;
        while (i < sellOrder.prevHint.length) {
            bytes32 prevHint = sellOrder.prevHint[i];
            // Check if prev is in the linked list.
            if (orderValueTimeout[prevHint] != 0) {
                prev = prevHint;
                break;
            }
            i++;
        }
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[sellOrder.sellAsset][sellOrder.buyAsset];
        // Find the previous sell order.
        // If the hint is after orderId, this will loop until gas runs out.
        while (orderLL[prev] != orderId) {
            prev = orderLL[prev];
        }
        // Remove from linked list.
        orderLL[prev] = orderLL[orderId];
        delete orderLL[orderId];
        // Log event.
        emit OrderRemoved(sellOrder.sellAsset, sellOrder.buyAsset, orderId, value);
    }

    function removeOrder(SellOrder calldata sellOrder) external
        assetPairValid(sellOrder.sellAsset, sellOrder.buyAsset)
        priceNonZero(sellOrder.price)
    {
        uint value = _removeOrder(sellOrder);
        assetAccountBalance[sellOrder.sellAsset][msg.sender] += value;
    }
    
    function removeOrderAndWithdraw(SellOrder calldata sellOrder, address to) external
        assetPairValid(sellOrder.sellAsset, sellOrder.buyAsset)
        priceNonZero(sellOrder.price)
        addressValid(to)
    {
        uint value = _removeOrder(sellOrder);
        _withdraw(sellOrder.sellAsset, to, value);
    }

    function _removeOrderValue(SellOrder calldata sellOrder) internal
        returns (uint valueRemoved)  // Is this neccessary?
    {
        // Determine the orderId.
        bytes32 orderId = encodeOrderId(sellOrder.price);
        // Sell value of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[sellOrder.sellAsset][sellOrder.buyAsset];
        // Get the value of the order being removed.
        (uint224 value,) = decodeValueTimeout(orderValueTimeout[orderId]);
        // Check if the order exists.
        if (value == 0) {
            revert OrderNotFound();
        }
        // Is the whole order being deleted?
        if (sellOrder.value >= value) {
            valueRemoved = _removeOrder(sellOrder);
        }
        else {
            orderValueTimeout[orderId] = encodeValueTimeout(value - sellOrder.value, sellOrder.timeout);
            valueRemoved = sellOrder.value;
            // Log event.
            emit OrderValueRemoved(sellOrder.sellAsset, sellOrder.buyAsset, orderId, valueRemoved, sellOrder.timeout);
        }
    }

    function removeOrderValue(SellOrder calldata sellOrder) external
        assetPairValid(sellOrder.sellAsset, sellOrder.buyAsset)
        priceNonZero(sellOrder.price)
        valueNonZero(sellOrder.value)
        timeoutNotExpired(sellOrder.timeout)
    {
        uint value = _removeOrderValue(sellOrder);
        assetAccountBalance[sellOrder.sellAsset][msg.sender] += value;
    }
    
    function removeOrderValueAndWithdraw(SellOrder calldata sellOrder, address to) external
        assetPairValid(sellOrder.sellAsset, sellOrder.buyAsset)
        priceNonZero(sellOrder.price)
        valueNonZero(sellOrder.value)
        timeoutNotExpired(sellOrder.timeout)
        addressValid(to)
    {
        uint value = _removeOrderValue(sellOrder);
        _withdraw(sellOrder.sellAsset, to, value);
    }

    function setOrderTimeout(address sellAsset, address buyAsset, uint96 price, uint32 newTimeout) external
        assetPairValid(sellAsset, buyAsset)
        priceNonZero(price)
    {
        // Sell value of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderIdValueTimeout = sellBuyOrderIdValueTimeout[sellAsset][buyAsset];

        bytes32 orderId = encodeOrderId(price);

        (uint224 value, ) = decodeValueTimeout(orderIdValueTimeout[orderId]);

        if (value == 0) {
            revert OrderNotFound();
        }

        orderIdValueTimeout[orderId] = encodeValueTimeout(value, newTimeout);
    }

    function setOrderPrice(address sellAsset, address buyAsset, uint96 oldPrice, uint96 newPrice) external
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

    struct MatchSellExactParams {
        address sellAsset;
        address buyAsset;
        uint224 sellValue;
    }

    /**
     * Purchase sellValue quanity of sellAsset. Quantity of buyAsset spent is returned as buyValue.
     */
    function matchSellExact(MatchSellExactParams memory params) internal
        returns (uint buyValue)
    {
        // Determine the value of 1 big unit of sell asset.
        uint sellAssetBigUnit = getAssetBigUnit(params.sellAsset);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[params.sellAsset][params.buyAsset];
        // Sell value and timeout of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[params.sellAsset][params.buyAsset];
        // Sell asset account balances.
        mapping (address => uint) storage sellAssetAccountBalance = assetAccountBalance[params.sellAsset];
        // Buy asset account balances.
        mapping (address => uint) storage buyAssetAccountBalance = assetAccountBalance[params.buyAsset];
        // Get the first sell order.
        bytes32 start = orderLL[0];
        bytes32 orderId = start;
        uint224 sellValue = params.sellValue;
        while (sellValue != 0) {
            // Check if we have run out of orders.
            if (orderId == 0) revert NoMatch();
            // Get order account, price, value and timeout.
            (address sellAccount, uint price) = decodeOrderId(orderId);
            (uint224 orderSellValue, uint32 timeout) = decodeValueTimeout(orderValueTimeout[orderId]);
            // Has the order timed out?
            if (timeout <= block.timestamp) {
                // Refund the seller.
                sellAssetAccountBalance[sellAccount] += orderSellValue;
                // Log event.
                emit OrderRemoved(params.sellAsset, params.buyAsset, orderId, orderSellValue);
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
                buyAssetAccountBalance[sellAccount] += orderBuyValue;
                // Log the event.
                emit OrderFullMatch(params.sellAsset, params.buyAsset, orderId, orderSellValue);
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
                buyAssetAccountBalance[sellAccount] += partialBuyValue;
                // Update order value. Will not be 0.
                orderValueTimeout[orderId] = encodeValueTimeout(orderSellValue - sellValue, timeout);
                // Log the event.
                emit OrderPartialMatch(params.sellAsset, params.buyAsset, orderId, params.sellValue);
                // Stop processing orders.
                break;
            }
        }
        // Update first order if neccessary.
        if (start != orderId) orderLL[0] = orderId;
    }

    struct MatchBuyExactParams {
        address sellAsset;
        address buyAsset;
        uint224 buyValue;
    }

    /**
     * Sell buyValue quanity of buyAsset. Quantity of sellAsset purchased is returned as sellValue.
     */
    function matchBuyExact(MatchBuyExactParams memory params) internal
        returns (uint sellValue)
    {
        // Determine the value of 1 big unit of sell asset.
        uint sellAssetBigUnit = getAssetBigUnit(params.sellAsset);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[params.sellAsset][params.buyAsset];
        // Sell value and timeout of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[params.sellAsset][params.buyAsset];
        // Sell asset account balances.
        mapping (address => uint) storage sellAssetAccountBalance = assetAccountBalance[params.sellAsset];
        // Buy asset account balances.
        mapping (address => uint) storage buyAssetAccountBalance = assetAccountBalance[params.buyAsset];
        // Get the first sell order.
        bytes32 start = orderLL[0];
        bytes32 orderId = start;
        uint buyValue = params.buyValue;
        while (buyValue != 0) {
            // Check if we have run out of orders.
            if (orderId == 0) revert NoMatch();
            // Get order account, price, value and timeout.
            (address sellAccount, uint price) = decodeOrderId(orderId);
            (uint224 orderSellValue, uint32 timeout) = decodeValueTimeout(orderValueTimeout[orderId]);
            // Has the order timed out?
            if (timeout <= block.timestamp) {
                // Refund the seller.
                sellAssetAccountBalance[sellAccount] += orderSellValue;
                // Log event.
                emit OrderRemoved(params.sellAsset, params.buyAsset, orderId, orderSellValue);
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
                buyAssetAccountBalance[sellAccount] += orderBuyValue;
                // Log the event.
                emit OrderFullMatch(params.sellAsset, params.buyAsset, orderId, orderSellValue);
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
                buyAssetAccountBalance[sellAccount] += buyValue;
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
                emit OrderPartialMatch(params.sellAsset, params.buyAsset, orderId, partialSellValue);
                // Exit.
                break;
            }
        }
        // Update first order if neccessary.
        if (start != orderId) orderLL[0] = orderId;
    }
/*
    function matchLimit(BuyOrder calldata buyOrder) internal
        returns (uint sellValue, uint buyValue)
    {
        // A limit of 0 is no limit.
        uint sellLimit = (buyOrder.sellValue == 0) ? type(uint).max : buyOrder.sellValue;
        uint buyLimit = (buyOrder.buyValue == 0) ? type(uint).max : buyOrder.buyValue;
        uint priceLimit = (buyOrder.priceLimit == 0) ? type(uint).max : buyOrder.priceLimit;
        // Determine the value of 1 big unit of sell asset.
        uint sellAssetBigUnit = getAssetBigUnit(buyOrder.sellAsset);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderIdLL[buyOrder.sellAsset][buyOrder.buyAsset];
        // Sell value and timeout of each sell order for this pair.
        mapping (bytes32 => bytes32) storage orderValueTimeout = sellBuyOrderIdValueTimeout[buyOrder.sellAsset][buyOrder.buyAsset];
        // Sell asset account balances.
        mapping (address => uint) storage sellAssetAccountBalance = assetAccountBalance[buyOrder.sellAsset];
        // Buy asset account balances.
        mapping (address => uint) storage buyAssetAccountBalance = assetAccountBalance[buyOrder.buyAsset];
        bytes32 start = orderLL[0];
        bytes32 orderId = start;
        while (orderId != 0 && buyLimit != 0 && sellLimit != 0) {
            // Get order account, price, value and timeout.
            (address sellAccount, uint price) = decodeOrderId(orderId);
            (uint224 orderSellValue, uint32 timeout) = decodeValueTimeout(orderValueTimeout[orderId]);
            // Has the order timed out?
            if (timeout <= block.timestamp) {
                // Refund the seller.
                sellAssetAccountBalance[sellAccount] += orderSellValue;
                // Log event.
                emit OrderRemoved(buyOrder.sellAsset, buyOrder.buyAsset, orderId, orderSellValue);
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
                buyAssetAccountBalance[sellAccount] += orderBuyValue;
                // Log the event.
                emit OrderFullMatch(buyOrder.sellAsset, buyOrder.buyAsset, orderId, orderSellValue);
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
                buyAssetAccountBalance[sellAccount] += buyLimit;
                // Update order value.
                orderValueTimeout[orderId] = encodeValueTimeout(orderSellValue - sellValueLimit, timeout); // TODO: ensure this isn't 0
                // Log the event.
                emit OrderPartialMatch(buyOrder.sellAsset, buyOrder.buyAsset, orderId, sellValueLimit);
                // Exit.
                break;
            }
        }
        // Was anything bought?
        if (sellValue == 0) revert NoMatch();
        // Update first order if neccessary.
        if (start != orderId) orderLL[0] = orderId;
    }
*/
    enum BuyOrderType { SellValueExact, BuyValueExact, Limit }

    struct BuyOrder {
        BuyOrderType orderType;
        address[] route;  // Route from buy asset to sell asset.
        uint224 sellValue;
        uint224 buyValue;
        // uint priceLimit;
    }

    function matchBuyOrder(BuyOrder calldata order) internal 
        // assetPairValid(order.sellAsset, order.buyAsset)
        returns (uint sellValue, uint buyValue)
    {
        if (order.orderType == BuyOrderType.SellValueExact) {
            sellValue = order.sellValue;
            for (uint i = order.route.length - 1; i > 0; i--) {
                MatchSellExactParams memory params = MatchSellExactParams({
                    sellAsset: order.route[i],
                    buyAsset: order.route[i - 1],
                    sellValue: uint224(sellValue)
                });
                // Is this the last hop?
                if (i == 1) {
                    buyValue = matchSellExact(params);
                }
                else {
                    sellValue = matchSellExact(params);
                }
            }
            // Ensure that the amount spent was not above the limit.
            if (buyValue > order.buyValue) revert NoMatch();
            sellValue = order.sellValue;
        }
        else if (order.orderType == BuyOrderType.BuyValueExact) {
            buyValue = order.buyValue;
            for (uint i = 0; i < order.route.length; i++) {
                MatchBuyExactParams memory params = MatchBuyExactParams({
                    sellAsset: order.route[i + 1],
                    buyAsset: order.route[i],
                    buyValue: uint224(buyValue)
                });
                // Is this the last hop?
                if (i == order.route.length - 2) {
                    sellValue = matchBuyExact(params);
                }
                else {
                    buyValue = matchBuyExact(params);
                }
            }
            // Ensure that the amount bought was not below the limit.
            if (sellValue < order.sellValue) revert NoMatch();
            buyValue = order.buyValue;
        }
        else {
            // (sellValue, buyValue) = matchLimit(order);
        }
        // Log the event.
        emit MatchingCompleted(order.route[order.route.length - 1], order.route[0], msg.sender, sellValue, buyValue);
    }

    /**
     * @dev Buy.
     */
    function buy(BuyOrder calldata order) external {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchBuyOrder(order);
        // Check there is sufficient balance.
        mapping(address => uint256) storage accountBalance = assetAccountBalance[order.route[0]];
        if (accountBalance[msg.sender] < buyValue) revert InsufficientBalance();
        // Update buyer's balances.
        accountBalance[msg.sender] -= buyValue;
        assetAccountBalance[order.route[order.route.length - 1]][msg.sender] += sellValue;
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
        mapping(address => uint256) storage accountBalance = assetAccountBalance[order.route[0]];
        if (accountBalance[msg.sender] < buyValue) revert InsufficientBalance();
        // Update buyer's buy asset balance.
        accountBalance[msg.sender] -= buyValue;
        // Transfer the sell asset.
        _withdraw(order.route[order.route.length - 1], to, sellValue);
    }

    /**
     * @dev Buy with base coin.
     */
    function buyWithDeposit(BuyOrder calldata order) external payable {
        // Execute the buy.
        (uint sellValue, uint buyValue) = matchBuyOrder(order);
        // Update buyer's sell asset balance.
        assetAccountBalance[order.route[order.route.length - 1]][msg.sender] += sellValue;
        // Transfer the buy assets from the buyer to this contract.
        _deposit(order.route[0], buyValue);
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
        _deposit(order.route[0], buyValue);
        // Transfer the sell asset.
        _withdraw(order.route[order.route.length - 1], to, sellValue);
    }

    /**
     * @dev Get balance of asset for account.
     */
    function getBalance(address asset, address account) external view returns (uint value) {
        value = assetAccountBalance[asset][account];
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
