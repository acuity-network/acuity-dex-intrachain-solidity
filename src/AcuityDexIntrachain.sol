// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import "./ERC20.sol";

contract AcuityDexIntrachain {

    /**
     * @dev Mapping of selling ERC20 contract address to buying ERC20 contract address to linked list of sell orders, starting with the lowest selling price.
     */
    mapping (address => mapping (address => mapping (bytes32 => bytes32))) sellBuyOrderLL;

    mapping (address => mapping (address => mapping (bytes32 => uint))) sellBuyOrderValue;

    /**
     * @dev
     */
    error TokenTransferFailed(address token, address from, address to, uint value);

    /**
     * @dev
     */
    function safeTransfer(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transfer.selector, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed(token, address(this), to, value);
    }

    /**
     * @dev
     */
    function safeTransferFrom(address token, address from, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transferFrom.selector, from, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed(token, from, to, value);
    }

    function encodeOrder(address account, uint96 sellPrice) internal pure returns (bytes32 order) {
        order = bytes32(bytes20(account)) | bytes32(bytes12(sellPrice));
    }

    function decodeOrder(bytes32 order) internal pure returns (address account, uint96 sellPrice) {

    }

    function _addSellOrder(address sellToken, address buyToken, uint96 sellPrice, uint value) internal {
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
        
        bytes32 order = encodeOrder(msg.sender, sellPrice);

        // Does this order already exist?
        if (orderValue[order] > 0) {
            orderValue[order] += value;
            return;
        }

        bytes32 prev = 0;
        bytes32 next = orderLL[prev];
        while (next != 0) {
            (, uint96 nextSellPrice) = decodeOrder(next);

            if (nextSellPrice > sellPrice) {
                break;
            }

            prev = next;
            next = orderLL[prev];
        }

        // Insert into linked list.
        orderLL[prev] = order;
        orderLL[order] = next;
        orderValue[order] = value;
    }

    function addSellOrder(address buyToken, uint96 sellPrice) external payable {
        _addSellOrder(address(0), buyToken, sellPrice, msg.value);
    }

    function addSellOrder(address sellToken, address buyToken, uint96 sellPrice, uint value) external {
        safeTransferFrom(sellToken, msg.sender, address(this), value);

        _addSellOrder(sellToken, buyToken, sellPrice, value);
    }

    function removeSellOrder(address sellToken, address buyToken, uint96 sellPrice, uint value) external {
        bytes32 order = encodeOrder(msg.sender, sellPrice);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
    }

    function removeSellOrder(address sellToken, address buyToken, uint96 sellPrice) external {
        bytes32 order = encodeOrder(msg.sender, sellPrice);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
        
        uint value = sellBuyOrderValue[sellToken][buyToken][order];
        
        if (value == 0) {
            return;
        }

        delete orderValue[order];

        // Find the previous sell order.

        bytes32 previousOrder = 0;

        while (orderLL[previousOrder] != order) {
            previousOrder = orderLL[previousOrder];
        }
        
        orderLL[previousOrder] = orderLL[order];
        delete orderLL[order];
        
        safeTransfer(sellToken, msg.sender, value);
    }

    function buy(address sellToken, address buyToken, uint buyValue) external {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
        // Accumulator of how much of the sell token the buyer will receive.
        uint sellValue = 0;
        // Get the lowest sell order.
        bytes32 order = orderLL[0];
        while (order != 0) {
            (address sellAccount, uint96 sellPrice) = decodeOrder(order);
            uint orderSellValue = orderValue[order];
            uint matchedSellValue = (buyValue * 1 ether) / sellPrice;

            if (orderSellValue > matchedSellValue) {
                // Partial buy.
                orderValue[order] -= matchedSellValue;
                // Transfer value.
                sellValue += matchedSellValue;
                safeTransferFrom(buyToken, msg.sender, sellAccount, buyValue);
                break;
            }
            else {
                // Full buy.
                uint matchedBuyValue = (orderSellValue * sellPrice) / 1 ether;
                buyValue -= matchedBuyValue;
                bytes32 next = orderLL[order];
                // Delete the sell order.
                orderLL[0] = next;
                delete orderLL[order];
                delete orderValue[order];
                order = next;
                // Transfer value.
                sellValue += orderSellValue;
                safeTransferFrom(buyToken, msg.sender, sellAccount, matchedBuyValue);
            }
        }

        if (sellValue > 0) {
            safeTransfer(sellToken, msg.sender, sellValue);
        }
    }

}
