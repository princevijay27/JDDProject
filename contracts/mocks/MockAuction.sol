// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockAuction {
    uint256 public nextAuctionId;
    mapping(uint256 => address) public auctionCollateralToken;
    mapping(uint256 => uint256) public auctionCollateralAmount;
    mapping(uint256 => uint256) public auctionDebtAmount;

    function createAuction(
        address _vaultOwner,
        uint256 _collateralAmount,
        uint256 _debtAmount,
        uint256 _startPrice,
        uint256 _endPrice,
        uint256 _duration
    ) external returns (uint256) {
        uint256 auctionId = nextAuctionId++;
        
        // Store auction details (we're only storing what we need for testing)
        auctionCollateralToken[auctionId] = msg.sender; // Using msg.sender as a proxy for collateral token
        auctionCollateralAmount[auctionId] = _collateralAmount;
        auctionDebtAmount[auctionId] = _debtAmount;

        return auctionId;
    }

    function getAuctionDetails(uint256 _auctionId) external view returns (address, uint256, uint256) {
        return (
            auctionCollateralToken[_auctionId],
            auctionCollateralAmount[_auctionId],
            auctionDebtAmount[_auctionId]
        );
    }

    // Function to simulate receiving collateral tokens
    function receiveCollateral(address _token, uint256 _amount) external {
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    }

    // Function to check the balance of collateral tokens held by this contract
    function getCollateralBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}