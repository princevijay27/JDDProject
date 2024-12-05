// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockOracle {
    mapping(address => uint256) private prices;
    
    // Event to log price updates
    event PriceUpdated(address indexed token, uint256 price);

    // Function to set the price for a token
    function setPrice(address token, uint256 price) external {
        prices[token] = price;
        emit PriceUpdated(token, price);
    }

    // Function to get the price of a token
    function getPrice(address token) external view returns (uint256) {
        require(prices[token] != 0, "Price not set for this token");
        return prices[token];
    }

    // Function to check if a price has been set for a token
    function hasPriceFor(address token) external view returns (bool) {
        return prices[token] != 0;
    }

    // Function to simulate price feed updates
    function updatePrice(address token, uint256 newPrice) external {
        require(prices[token] != 0, "Price not initialized for this token");
        prices[token] = newPrice;
        emit PriceUpdated(token, newPrice);
    }

    // Function to remove a price (simulate oracle failure)
    function removePrice(address token) external {
        delete prices[token];
    }
}