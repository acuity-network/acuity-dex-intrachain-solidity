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
    error TokensNotDifferent(address sellToken, address buyToken);

    /**
     * @dev
     */
    error TokenTransferFailed(address token, address from, address to, uint value);

    /**
     * @dev
     */
    function safeTransfer(address token, address payable to, uint value) internal {
        if (token == address(0)) {
            payable(to).transfer(value);
        }
        else {
            (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transfer.selector, to, value));
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed(token, address(this), to, value);
        }
    }

    /**
     * @dev
     */
    function safeTransferFromSender(address token, address to, uint value) internal {
        if (token == address(0)) {
            payable(to).transfer(value);
        }
        else {
            (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transferFrom.selector, msg.sender, to, value));
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed(token, msg.sender, to, value);
        }
    }

    function encodeOrder(uint96 sellPrice) internal view returns (bytes32 order) {
        order = bytes32(bytes20(msg.sender)) | bytes32(bytes12(sellPrice));
    }

    function decodeOrder(bytes32 order) internal pure returns (address account, uint96 sellPrice) {

    }

    function _addSellOrder(address sellToken, address buyToken, uint96 sellPrice, uint value) internal {
        if (sellToken == buyToken) {
            revert TokensNotDifferent(sellToken, buyToken);
        }
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
        
        bytes32 order = encodeOrder(sellPrice);

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
        safeTransferFromSender(sellToken, address(this), value);

        _addSellOrder(sellToken, buyToken, sellPrice, value);
    }

    function removeSellOrder(address sellToken, address buyToken, uint96 sellPrice, uint value) external {
        bytes32 order = encodeOrder(sellPrice);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
    }

    function removeSellOrder(address sellToken, address buyToken, uint96 sellPrice) external {
        bytes32 order = encodeOrder(sellPrice);
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
        
        uint value = orderValue[order];
        
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
        
        safeTransfer(sellToken, payable(msg.sender), value);
    }
    
    function _buy(address sellToken, address buyToken, uint buyValue) internal {
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
                safeTransferFromSender(buyToken, sellAccount, buyValue);
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
                safeTransferFromSender(buyToken, sellAccount, matchedBuyValue);
            }
        }
        
        if (sellValue > 0) {
            safeTransfer(sellToken, payable(msg.sender), sellValue);
        }
    }

    function buy(address sellToken) external payable {
        _buy(sellToken, address(0), msg.value);
    }

    function buy(address sellToken, address buyToken, uint buyValue) external {
        _buy(sellToken, buyToken, buyValue);
    }

}
