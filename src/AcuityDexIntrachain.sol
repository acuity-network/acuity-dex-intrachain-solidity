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
    error TokensNotDifferent(address sellToken, address buyToken);

    /**
     * @dev
     */
    error TokenTransferFailed(address token, address from, address to, uint value);

    /**
     * @dev
     */
    function safeTransferIn(address token, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transferFrom.selector, msg.sender, address(this), value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed(token, msg.sender, address(this), value);
    }

    /**
     * @dev
     */
    function safeTransferOut(address token, address to, uint value) internal {
        if (token == address(0)) {
            payable(to).transfer(value); // Fix this.
        }
        else {
            (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transfer.selector, to, value));
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed(token, address(this), to, value);
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

    /**
     * @dev Add sell order.
     */
    function addSellOrder(address sellToken, address buyToken, uint96 sellPrice, uint value) external {
        _addSellOrder(sellToken, buyToken, sellPrice, value);
        accountTokenBalance[msg.sender][sellToken] -= value;
    }

    /**
     * @dev Add sell order of base coin.
     */
    function addSellOrderFromDeposit(address buyToken, uint96 sellPrice) external payable {
        _addSellOrder(address(0), buyToken, sellPrice, msg.value);
    }

    /**
     * @dev Add sell order of ERC20 token.
     */
    function addSellOrderFromDepositERC20(address sellToken, address buyToken, uint96 sellPrice, uint value) external {
        // Add the sell order.
        _addSellOrder(sellToken, buyToken, sellPrice, value);
        // Transfer the tokens from the seller to this contract.
        safeTransferIn(sellToken, value);
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

        accountTokenBalance[msg.sender][sellToken] += value;
    }

    function _buy(address sellToken, address buyToken, uint buyValueMax) internal returns (uint buyValue, uint sellValue) {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyToken];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyToken];
        // Get the lowest sell order.
        bytes32 order = orderLL[0];
        while (order != 0) {
            (address sellAccount, uint96 sellPrice) = decodeOrder(order);
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

    function deposit() external payable {
        accountTokenBalance[msg.sender][address(0)] += msg.value;
    }

    function depositERC20(address token, uint value) external {
        accountTokenBalance[msg.sender][token] += value;
        safeTransferIn(token, value);
    }

    function withdraw(address token, uint value) external {
        accountTokenBalance[msg.sender][token] -= value;
        safeTransferOut(token, msg.sender, value);
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
    function buyWithDeposit(address sellToken) external payable {
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
        safeTransferIn(buyToken, buyValue);
        accountTokenBalance[msg.sender][sellToken] += sellValue;
    }

    /**
     * @dev Buy with base coin.
     */
    function buyWithDepositAndWithdraw(address sellToken) external payable {
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
}
