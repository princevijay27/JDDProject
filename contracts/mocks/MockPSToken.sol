// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

interface IExtendedERC20 is IERC20 {
    function decimals() external view returns (uint8);
}

contract MockPSToken is ERC20, ReentrancyGuard, Ownable {
    struct UserOrder {
        address user;
        uint256 orderAmount;
        uint256 orderAmountFilled;
        uint256 prepaidAmount;
        address prepaidCurrency;
    }

    struct PriceTier {
        uint256 price; // Price in cents
        uint256 totalAmountAllowedForPrice; // The amount of DD token that is reserved for this price above
    }

    PriceTier[9] public priceTiers;

    event SlotPositionLocked(address, uint256);
    event SlotPositionLockedWithoutDD(address);
    // variables
    IERC20 constant BTC = IERC20(0x0d787a4a1548f673ed375445535a6c7A1EE56180); // Mumbai testnet
    IERC20 constant WETH = IERC20(0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa); // Mumbai testnet
    IERC20 constant USDT = IERC20(0xA02f6adc7926efeBBd59Fd43A84f4E0c0c91e832); // Mumbai testnet

    // Mapping: Slot details; slots are numbers that starts from 1
    UserOrder[] public ddLockQueue;
    UserOrder[] public ddUnlockQueue;
    // Mapping: Allowed currency for PS token purchase
    mapping(address => AggregatorV3Interface) public tokenToPriceFeeder;
    // List of allowed currencies for PS Token purchase
    address[] public allowedCurrenciesForPurchase;
    // Total PS Bought
    uint256 totalPSBought;
    // Current locked user count
    uint88 public currentQueuePositionCounter;
    // Amount of P&S tokens reserved for DD lockers
    uint256 totalAmountForLockedDD; // 70%
    // Amount of P&S tokens reserved for non-DD lockers
    uint256 totalAmountForNonLockedDD; // 30%

    // Total DD locked
    uint256 private totalDDLocked;
    // PS Token supply for sale
    uint256 PSTokenSaleSupply;
    // DD Token address
    IERC20 public DDToken;

    // Need to make some queue implementation
    constructor(
        IERC20 _DDToken,
        string memory _tokenName,
        string memory _tokenSymbol
    ) ERC20(_tokenName, _tokenSymbol) Ownable(msg.sender) {
        DDToken = _DDToken;
    }

    modifier checkAllowedCurrency(address _currency) {
        require(
            address(tokenToPriceFeeder[_currency]) != address(0),
            "Currency not allowed"
        );
        _;
    }

    // Create orders by locking DD
    function lockSlotPositionWithDD(
        uint256 _psTokensToBuy, // Amount you want to purchase,
        uint256 _amountInCurrencyToSpend,
        IExtendedERC20 _paymentCurrency // Amount you're willing to spend
    ) public checkAllowedCurrency(address(_paymentCurrency)) {
        // --------------- Step 1: Checks
        // 1.1 Lock only if the supply is zero
        require(
            PSTokenSaleSupply == 0,
            "Not eligible for locking when supply available"
        );
        // 1.2 Order amount must be greater than 0
        require(_psTokensToBuy > 0, "Amount too low");

        // ----------- Step 2: Take payment: Transfer to contract
        _paymentCurrency.transferFrom(
            msg.sender,
            address(this),
            _amountInCurrencyToSpend
        );
        // Lock DD Token to this contract
        DDToken.transferFrom(msg.sender, address(this), _psTokensToBuy);

        // ------------- Step 3: State changes
        // transfer DD from user to this contract
        totalDDLocked += _psTokensToBuy;

        // Get the current queue position number where this user will stand
        // Save details in the mapping
        UserOrder memory userOrder = UserOrder({
            user: msg.sender,
            orderAmount: _psTokensToBuy,
            prepaidAmount: _amountInCurrencyToSpend,
            orderAmountFilled: 0,
            prepaidCurrency: address(_paymentCurrency)
        });
        ddLockQueue.push(userOrder);
        emit SlotPositionLocked(msg.sender, _psTokensToBuy);
    }

    // Create orders by not locking DD
    function lockSlotPositionWithoutDD(
        uint256 _amountInCurrencyToSpend,
        IExtendedERC20 _paymentCurrency // Amount you're willing to spend
    ) public checkAllowedCurrency(address(_paymentCurrency)) {
        // --------------- Step 1: Checks
        // 1.1 Lock only if the supply is zero
        require(
            PSTokenSaleSupply == 0,
            "Not eligible for locking when supply available"
        );
        // 1.2 Order amount must be greater than 0
        require(_amountInCurrencyToSpend > 0, "Amount too low");

        // ----------- Step 2: Take payment: Transfer to contract
        _paymentCurrency.transferFrom(
            msg.sender,
            address(this),
            _amountInCurrencyToSpend
        );

        // Get the current queue position number where this user will stand
        // Save details in the mapping
        UserOrder memory userOrder = UserOrder({
            user: msg.sender,
            orderAmount: 0,
            orderAmountFilled: 0,
            prepaidAmount: _amountInCurrencyToSpend,
            prepaidCurrency: address(_paymentCurrency)
        });
        ddUnlockQueue.push(userOrder);
        emit SlotPositionLockedWithoutDD(msg.sender);
    }

    function distributeTokens(uint256 _supplyToMint)
        public
        onlyOwner
        nonReentrant()
    {
        console.log("here0");
        console.logUint(_supplyToMint);
        setPSTokenSaleSupply(_supplyToMint);
        console.logUint(totalSupply());
        console.log("here1");

        uint256 i = 0;
        uint256 ddQueueLength = ddLockQueue.length;
        console.log("QueueLength");
        console.logUint(ddQueueLength);
        while (i < ddQueueLength) {
            console.log("here3");
            console.logUint(i);
            // Calculate how many PS tokens his money can buy
            UserOrder memory userOrder = ddLockQueue[i];
            (
                uint256 totalPSBoughtForUser,
                uint256 tokensToReturn
            ) = calculatePSTokenForLockedDD(userOrder);
            console.log("Here4");
            console.logUint(totalPSBoughtForUser);
            console.logUint(tokensToReturn);
            // IExtendedERC20(userOrder.prepaidCurrency).transferFrom(
            //     address(this),
            //     userOrder.user,
            //     tokensToReturn
            // );
            ddLockQueue[i].prepaidAmount = tokensToReturn;
            ddLockQueue[i].orderAmountFilled = totalPSBoughtForUser;
            totalPSBought += totalPSBoughtForUser;
            transferForOwner(userOrder.user, totalPSBoughtForUser);
            console.log("Here5");
            // Find how many PS tokens are left from the locked users allowance
            i++;
        }
        // Move the leftover PS tokens to the non-DD-locked PS token buyers
        totalAmountForNonLockedDD += (totalPSBought == totalAmountForLockedDD)
            ? 0
            : totalAmountForLockedDD - totalPSBought;
        i = 0;
        uint256 nonDDQueueLength = ddUnlockQueue.length;
        while (i < nonDDQueueLength) {
            UserOrder memory userOrder = ddUnlockQueue[i];
            (
                uint256 totalPSBoughtForUser,
                uint256 tokensToReturn
            ) = calculatePSTokenForUnlockedDD(userOrder);
            ddUnlockQueue[i].prepaidAmount = tokensToReturn;
            ddUnlockQueue[i].orderAmountFilled = totalPSBoughtForUser;
            totalPSBought += totalPSBoughtForUser;
            i++;
        }
    }

    // Withdraw DD Token and free up slot
    function withdrawDDAndFreeSlot() external nonReentrant {}

    function claimToken() external nonReentrant {}

    function calculatePSTokenForUnlockedDD(UserOrder memory _userOrder)
        public
        view
        returns (uint256, uint256)
    {
        uint256 totalPSBoughtSuccessfully;
        // convert the amount in USD
        uint256 priceOfToken = getPrice();

        uint256 tokensAvailableToPurchasePS = _userOrder.prepaidAmount; // Amount the user has paid to purchase PS Tokens
        uint256 totalPSBoughtTillNow = totalPSBought; // How many total PS tokens have been bought already
        uint8 i = 0;
        while (i < 9) {
            if (priceTiers[i].totalAmountAllowedForPrice < totalPSBoughtTillNow)
                continue;
            // How much money I have in USD (8 decimals)
            uint256 usdPriceFortoken = (tokensAvailableToPurchasePS *
                priceOfToken) /
                IExtendedERC20(_userOrder.prepaidCurrency).decimals();
            // How many PS tokens can I buy at current tier for all my money
            uint256 totalPSCanBuyAtCurrentTierPrice = (usdPriceFortoken *
                decimals()) / priceTiers[i].price;
            // How many PS tokens are available for purchase in current tier
            uint256 totalPSAvailableAtCurrentTier = priceTiers[i]
                .totalAmountAllowedForPrice - totalPSBoughtTillNow;
            uint256 totalPSToBuy = totalPSCanBuyAtCurrentTierPrice <
                totalAmountForNonLockedDD
                ? totalPSCanBuyAtCurrentTierPrice
                : (totalPSCanBuyAtCurrentTierPrice - totalAmountForNonLockedDD);
            if (uint256(totalPSAvailableAtCurrentTier) > totalPSToBuy) {
                // Give tokens less than or equal to the order amount and not what the money can buy
                totalPSBoughtSuccessfully += (totalPSAvailableAtCurrentTier -
                    totalPSToBuy);
                tokensAvailableToPurchasePS -=
                    (totalPSBoughtSuccessfully * priceTiers[i].price) /
                    (priceOfToken * decimals());
                break;
            } else {
                totalPSBoughtSuccessfully += (totalPSCanBuyAtCurrentTierPrice -
                    totalPSToBuy);
                tokensAvailableToPurchasePS -=
                    (totalPSBoughtSuccessfully * priceTiers[i].price) /
                    (priceOfToken * decimals());
            }
            i++;
        }
        totalPSBoughtTillNow += totalPSBoughtSuccessfully;
        return (totalPSBoughtSuccessfully, tokensAvailableToPurchasePS);
    }

    function calculatePSTokenForLockedDD(UserOrder memory _userOrder)
        public
        view
        returns (uint256, uint256)
    {
        uint256 totalPSBoughtSuccessfully;
        // convert the amount in USD

        uint256 priceOfToken = getPrice();
        console.log("here4.1");
        uint256 tokensAvailableToPurchasePS = _userOrder.prepaidAmount; // Amount the user has paid to purchase PS Tokens
        uint256 desiredAmountToBuy = _userOrder.orderAmount;
        uint256 totalPSBoughtTillNow = totalPSBought; // How many total PS tokens have been bought already
        uint256 i = 0;
        while (i < uint256(priceTiers.length)) {
            console.log("here4.2");
            console.logUint(i);

            if (priceTiers[i].totalAmountAllowedForPrice < totalPSBoughtTillNow)
                continue;
            // How much money I have in USD (8 decimals)
            uint256 usdPriceFortoken = (tokensAvailableToPurchasePS *
                priceOfToken) /
                (10 **
                IExtendedERC20(_userOrder.prepaidCurrency).decimals());
            // How many PS tokens can I buy at current tier for all my money
            uint256 totalPSCanBuyAtCurrentTierPrice = (usdPriceFortoken *
                decimals()) / priceTiers[i].price;
            // How many PS tokens are available for purchase in current tier
            uint256 totalPSAvailableAtCurrentTier = priceTiers[i]
                .totalAmountAllowedForPrice - totalPSBoughtTillNow;
            uint256 totalPSToBuy = desiredAmountToBuy >
                totalPSCanBuyAtCurrentTierPrice
                ? totalPSCanBuyAtCurrentTierPrice
                : desiredAmountToBuy;
            totalPSToBuy = totalPSToBuy > totalAmountForLockedDD
                ? totalPSToBuy - totalAmountForLockedDD
                : totalPSToBuy;
            if (uint256(totalPSAvailableAtCurrentTier) > totalPSToBuy) {
                // Give tokens less than or equal to the order amount and not what the money can buy
                totalPSBoughtSuccessfully += (totalPSAvailableAtCurrentTier -
                    totalPSToBuy);
                tokensAvailableToPurchasePS -=
                    (totalPSBoughtSuccessfully * priceTiers[i].price) /
                    (priceOfToken * decimals());
                console.log("Broken now");
                console.logUint(totalPSBoughtSuccessfully);
                console.logUint(tokensAvailableToPurchasePS);
                break;
            } else {
                totalPSBoughtSuccessfully += (totalPSCanBuyAtCurrentTierPrice -
                    totalPSToBuy);
                tokensAvailableToPurchasePS -=
                    (totalPSBoughtSuccessfully * priceTiers[i].price) /
                    (priceOfToken * decimals());
                desiredAmountToBuy -= totalPSBoughtSuccessfully;
                console.logUint(totalPSBoughtSuccessfully);
                console.logUint(tokensAvailableToPurchasePS);
            }
            i++;
        }
        totalPSBoughtTillNow += totalPSBoughtSuccessfully;
        return (totalPSBoughtSuccessfully, tokensAvailableToPurchasePS);
    }

    function resetQueuePositionCounter() external view returns (uint256) {}

    function addAllowedCurrencyForPurchase(
        address _token,
        AggregatorV3Interface _tokenFeederAddress
    ) external onlyOwner {
        tokenToPriceFeeder[_token] = _tokenFeederAddress;
    }

    // Set how many PS tokens to be minted on next sale and re-adjust the price-tiers accordingly
    function setPSTokenSaleSupply(uint256 _supplyAmount) internal onlyOwner {
      _mint(address(this), _supplyAmount);
      PSTokenSaleSupply = _supplyAmount;
      totalAmountForLockedDD = (_supplyAmount * 7) / 10; // 70% of PSTokenSaleSupply
      totalAmountForNonLockedDD = (_supplyAmount * 6) / 25; // 80% of (30% of PSTokenSaleSupply)

      // Dollar amounts are in cents, here 50 means $0.5
      priceTiers[0] = PriceTier(50 * 1e6, (PSTokenSaleSupply) / 10); // 10%
      priceTiers[1] = PriceTier(55 * 1e6, (PSTokenSaleSupply) / 30); // 3.33%
      priceTiers[2] = PriceTier(60 * 1e6, (PSTokenSaleSupply) / 10); // 10%
      priceTiers[3] = PriceTier(65 * 1e6, (PSTokenSaleSupply) / 30); // 3.33%
      priceTiers[4] = PriceTier(70 * 1e6, (PSTokenSaleSupply) / 5); // 20%
      priceTiers[5] = PriceTier(75 * 1e6, (PSTokenSaleSupply) / 15); // 6.67%
      priceTiers[6] = PriceTier(80 * 1e6, (PSTokenSaleSupply) / 5); // 20%
      priceTiers[7] = PriceTier(85 * 1e6, (PSTokenSaleSupply) / 15); // 6.67%
      priceTiers[8] = PriceTier(90 * 1e6, (PSTokenSaleSupply) / 5); // 20%
    }

    function getPrice() internal pure returns (uint256) {
        return 1240 * 1e8;
    }

    function mint(uint256 _amount) public onlyOwner {
        _mint(address(this), _amount);
    }

    function mintSaleSupply() public onlyOwner {
        require(PSTokenSaleSupply > 0, "Supply is not set");
        _mint(address(this), PSTokenSaleSupply);
    }

    function transferForOwner(address _to, uint256 _value) public onlyOwner returns (bool){
      _transfer(address(this), _to, _value);
      return true;
    }
}
