// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import { IAggregatorV3Interface } from "./interfaces/ChainlinkAggregator.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { IERC20Extended } from "./interfaces/PSToken.sol";
import { UserOrder, PriceTier } from "./Misc/Types.sol";

contract PSToken is ERC20Upgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    /// @notice Amount of P&S tokens reserved for DD lockers
    uint256 public totalAmountForLockedDD; // 70%
    /// @notice Amount of P&S tokens reserved for non-DD lockers
    uint256 public totalAmountForNonLockedDD; // 24%
    /// @notice Stores the index of last person whose order was filled from locked DD queue
    uint256 public lastFilledLockedOrderIndex;
    /// @notice Stores the index of last person whose order was filled from non-locked DD queue
    uint256 public lastFilledNonLockedOrderIndex;
    /// @notice DD Token address
    IERC20 public DDToken;
    PriceTier[9] public priceTiers;
    // constant variables
    IERC20 constant BTC = IERC20(0x0d787a4a1548f673ed375445535a6c7A1EE56180); // Mumbai testnet
    IERC20 constant WETH = IERC20(0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa); // Mumbai testnet
    IERC20 constant USDT = IERC20(0xA02f6adc7926efeBBd59Fd43A84f4E0c0c91e832); // Mumbai testnet

    // Mapping: Slot details; slots are numbers that starts from 1
    UserOrder[] public ddLockQueue;
    UserOrder[] public ddUnlockQueue;
    // Mapping: Allowed currency for PS token purchase
    mapping(address => IAggregatorV3Interface) public tokenToPriceFeeder;

    uint256[50] private __gap;

    /// @notice Event emitted when a user locks his position
    event SlotPositionLockedWithDD(address, uint256);
    /// @notice Event emitted when a user locks his position without DD
    event SlotPositionLockedWithoutDD(address);

    function initialize(IERC20 _DDToken, string memory _tokenName, string memory _tokenSymbol) public initializer {
        __ERC20_init(_tokenName, _tokenSymbol);
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        DDToken = _DDToken;
    }

    modifier checkAllowedCurrency(address _currency) {
        require(address(tokenToPriceFeeder[_currency]) != address(0), "Currency not allowed");
        _;
    }

    modifier whenNoSupply() {
        require(totalSupply() == 0, "Supply available");
        _;
    }

    modifier whenSupply() {
        require(totalSupply() != 0, "Supply not available");
        _;
    }

    /////////////////////////////////////////////////////////////////////
    ///////////////////////// PUBLIC FUNCTIONS //////////////////////////
    /////////////////////////////////////////////////////////////////////

    /// @notice Get in line to purchase PS tokens with DD locking
    function lockSlotPositionWithDD(
        uint256 _psTokensToBuy, // Amount you want to purchase,
        uint256 _amountInCurrencyToSpend,
        IERC20Extended _paymentCurrency // Amount you're willing to spend
    )
        public
        whenNoSupply
        checkAllowedCurrency(address(_paymentCurrency))
    {
        require(_psTokensToBuy > 0 && _amountInCurrencyToSpend > 0, "Amount too low");
        _paymentCurrency.transferFrom(msg.sender, address(this), _amountInCurrencyToSpend);
        // Lock DD Token to this contract
        DDToken.transferFrom(msg.sender, address(this), _psTokensToBuy);
        // Save details in the mapping
        ddLockQueue.push(
            UserOrder({
                user: msg.sender,
                orderAmount: _psTokensToBuy,
                prepaidAmount: _amountInCurrencyToSpend,
                orderAmountFilled: 0,
                prepaidCurrency: address(_paymentCurrency)
            })
        );
        emit SlotPositionLockedWithDD(msg.sender, _psTokensToBuy);
    }

    /// @notice Get in line to purchase PS tokens without locking DD
    function lockSlotPositionWithoutDD(
        uint256 _amountInCurrencyToSpend,
        IERC20Extended _paymentCurrency // Amount you're willing to spend
    )
        public
        whenNoSupply
        checkAllowedCurrency(address(_paymentCurrency))
    {
        // --------------- Step 1: Checks
        require(_amountInCurrencyToSpend > 0, "Amount too low");

        // ----------- Step 2: Take payment: Transfer to contract
        _paymentCurrency.transferFrom(msg.sender, address(this), _amountInCurrencyToSpend);

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

    /**
     * @notice Distribute the PS tokens to the users whose orders aren't filled
     * @dev Function only works when supply is available
     * @param _supplyToMint: Amount of PS tokens to mint
     */
    function distribute(uint256 _supplyToMint) public onlyOwner nonReentrant {
        // Step 1: Set the total supply of PS tokens and mint them
        setPSTokenSaleSupply(_supplyToMint);

        // Step 2: Distribute the PS tokens to users who locked DD/xDD tokens
        uint256 psDistributed = handleLockedUserDistribution();

        // Step 3 (Conditional): Move the leftover PS tokens to the non-DD-locked PS token buyers' allocation
        /// @notice state change here
        totalAmountForNonLockedDD +=
            (psDistributed == totalAmountForLockedDD) ? 0 : totalAmountForLockedDD - psDistributed;

        // Step 4: Distribute the PS tokens to users who didn't lock DD/xDD tokens
        handleNonLockedUserDistribution();
    }

    /**
     * @notice Directly buy PS tokens with money
     * @dev Function only works when supply is available
     * @param _amount: Amount of money to spend
     * @param _currency: Currency to spend
     */
    function purchaseToken(uint256 _amount, IERC20Extended _currency) external whenSupply nonReentrant {
        require(_amount > 0, "Amount too low");
        require(address(tokenToPriceFeeder[address(_currency)]) != address(0), "Currency not allowed");

        // Step 1: Convert this currency into USD
        uint256 currencyTokenToUSD = getPrice(tokenToPriceFeeder[address(_currency)]);
        uint256 totalUSDAvailable = _convertCurrencyToUSD(_amount, currencyTokenToUSD, _currency.decimals());
        uint256 totalPSBought = totalSupply() - balanceOf(address(this));
        // Calculate how many PS tokens his money can buy
        uint256 decimals = _currency.decimals();
        (uint256 totalPurchaseable,) = getCostFromMoney(totalUSDAvailable, decimals);
        // Check if this amount is even available
        if (totalPurchaseable + totalPSBought > totalAmountForLockedDD + totalAmountForNonLockedDD) {
            uint256 totalCanBuy = totalSupply() - totalPSBought;
            _amount = _convertUSDToCurrency(getPSCost(totalCanBuy), currencyTokenToUSD, decimals);
        }
        // Take payment
        _currency.transferFrom(msg.sender, address(this), _amount);
        // Transfer PS tokens to user
        _transfer(address(this), msg.sender, totalPurchaseable);
    }

    /**
     * @notice Calculate the amount of PS tokens that can be bought by the user
     * @param _userOrder: User order details
     * @return Quantity: Quantity of PS token purchased
     * @return Remaining: Remaining money after purchasing PS tokens
     */
    function calculatePSTokenForNonLockedDD(UserOrder memory _userOrder) public view returns (uint256, uint256) {
        // Maximum amount purchaseable = Max(total available to purchase from the allocation of Non-locked buyers, total
        // can buy from the money)
        uint256 maxQuantityCanBuy = _maxQuantityCanBuyByNonLockedBuyers();
        if (maxQuantityCanBuy == 0) {
            return (0, _userOrder.prepaidAmount);
        }

        address purchaseTokenCurrency = _userOrder.prepaidCurrency;
        IAggregatorV3Interface priceFeeder = tokenToPriceFeeder[purchaseTokenCurrency];
        // convert the amount in USD
        uint256 prepaidCurrencyDecimals = IERC20Extended(_userOrder.prepaidCurrency).decimals();
        uint256 priceOfToken = getPrice(priceFeeder);
        uint256 tokensAvailableToPurchasePS = _userOrder.prepaidAmount; // Amount the user has paid to purchase PS
            // Tokens
        tokensAvailableToPurchasePS =
            _convertCurrencyToUSD(tokensAvailableToPurchasePS, priceOfToken, prepaidCurrencyDecimals);

        // Get the amount of PS tokens that can be bought with available USD
        (uint256 quantity, uint256 remainingMoney) =
            getCostFromMoney(tokensAvailableToPurchasePS, prepaidCurrencyDecimals);
        remainingMoney = _convertUSDToCurrency(remainingMoney, priceOfToken, prepaidCurrencyDecimals);
        if (quantity > maxQuantityCanBuy) {
            uint256 totalPrice = getPSCost(maxQuantityCanBuy);
            totalPrice = _convertUSDToCurrency(totalPrice, priceOfToken, prepaidCurrencyDecimals);
            return (maxQuantityCanBuy, _userOrder.prepaidAmount - totalPrice);
        }

        return (quantity, remainingMoney);
    }

    function calculatePSTokenForLockedDD(UserOrder memory _userOrder) public view returns (uint256, uint256, uint256) {
        // Step 0: Get the total PS tokens bought till now
        uint256 totalPSBought = totalSupply() - balanceOf(address(this));
        // Step 1: Get the desired amount of PS tokens to buy
        uint256 desiredAmountToBuy = _userOrder.orderAmount;
        // Step 2: Check if desired amount is available or not
        uint256 tokensToBuy = Math.min(
            desiredAmountToBuy, totalAmountForLockedDD < totalPSBought ? 0 : totalAmountForLockedDD - totalPSBought
        );
        if (tokensToBuy == 0) {
            return (0, 0, _userOrder.prepaidAmount);
        }

        // convert the amount in USD (18 decimals)
        uint256 prepaidCurrencyDecimal = IERC20Extended(_userOrder.prepaidCurrency).decimals();
        // Price of 1 currency token in USD
        uint256 priceOfToken = getPrice(tokenToPriceFeeder[_userOrder.prepaidCurrency]);
        uint256 tokensAvailableToPurchasePS = _userOrder.prepaidAmount; // Amount the user has paid to purchase PS
            // Tokens
        // Price of total currency tokens in USD
        tokensAvailableToPurchasePS =
            _convertCurrencyToUSD(tokensAvailableToPurchasePS, priceOfToken, prepaidCurrencyDecimal);

        // Step 3: Get the total cost of the desired PS tokens
        uint256 totalCost = getPSCost(tokensToBuy); // USDC 1e18
        // Step 4: Check if you have that much money
        if (totalCost > tokensAvailableToPurchasePS) {
            (uint256 quantity, uint256 remaining) =
                getCostFromMoney(tokensAvailableToPurchasePS, prepaidCurrencyDecimal);
            // Convert the total cost in the prepaid currency
            remaining = _userOrder.prepaidCurrency != address(USDT)
                ? _convertUSDToCurrency(remaining, priceOfToken, prepaidCurrencyDecimal)
                : remaining;
            return (quantity, _userOrder.prepaidAmount - remaining, remaining);
        }
        // Convert the total cost in the prepaid currency
        totalCost = _userOrder.prepaidCurrency != address(USDT)
            ? _convertUSDToCurrency(totalCost, priceOfToken, prepaidCurrencyDecimal)
            : totalCost;
        return (tokensToBuy, totalCost, _userOrder.prepaidAmount - totalCost);
    }

    /**
     * @notice Get the cost of purchasing PS tokens from the quantity
     * @param psQuantity_: Quantity of USD to be used for purchasing PS tokens
     * return Remaining money after purchasing PS tokens
     */
    function getPSCost(uint256 psQuantity_) public view returns (uint256) {
        uint256 totalSupply = totalSupply();
        uint256 totalPSBoughtTillNow = totalSupply - balanceOf(address(this));

        uint256 remainingQuantity = psQuantity_;
        uint256 totalPrice = 0;
        for (uint256 i = 0; i < 9 && totalPSBoughtTillNow < totalSupply; i++) {
            PriceTier memory tier = priceTiers[i];
            uint256 tierSupply = tier.totalAmountAllowedForPrice;
            if (i > 0) {
                tierSupply -= priceTiers[i - 1].totalAmountAllowedForPrice;
            }

            if (totalPSBoughtTillNow >= tier.totalAmountAllowedForPrice) {
                continue;
            }

            uint256 tokensInTier = tier.totalAmountAllowedForPrice - totalPSBoughtTillNow;
            uint256 quantityInTier = Math.min(tokensInTier, remainingQuantity);
            totalPrice += (quantityInTier * tier.price) / 1e18;
            remainingQuantity -= quantityInTier;
            totalPSBoughtTillNow += quantityInTier;
            if (remainingQuantity == 0) {
                break;
            }
        }

        require(remainingQuantity == 0, "Insufficient token supply");

        return totalPrice;
    }

    /**
     * @notice Get the quantity of PS tokens that can be bought from the money
     * @param _psAmount: Amount of money to spend
     * @param _decimal: Decimal of the currency
     * @return Quantity of PS tokens that can be bought
     * @return Remaining money after purchasing PS tokens
     */
    function getCostFromMoney(uint256 _psAmount, uint256 _decimal) public view returns (uint256, uint256) {
        uint256 totalMoneyLeft = _psAmount;
        uint256 totalPSBoughtTillNow = totalSupply() - balanceOf(address(this));
        uint256 totalQuantityPurchased = 0;
        uint256 moneySpentInCurrentTier = 0;
        for (uint256 i = 0; i < 9; i++) {
            if (totalPSBoughtTillNow >= priceTiers[i].totalAmountAllowedForPrice) {
                continue;
            }
            PriceTier memory tier = priceTiers[i];
            uint256 tierPrice = tier.price;
            // Step 1: Check how many allowed in the current tier
            uint256 tokensInTier = tier.totalAmountAllowedForPrice - totalPSBoughtTillNow;
            // Step 2: Can buy from current tier with the money
            uint256 canBuyFromCurrentTier = (totalMoneyLeft * (10 ** _decimal)) / tierPrice;
            // Step 3: How much to finally buy from current tier
            uint256 quantityInTier = Math.min(tokensInTier, canBuyFromCurrentTier);
            moneySpentInCurrentTier = (quantityInTier * tierPrice) / 1e18;
            totalMoneyLeft -= moneySpentInCurrentTier;
            totalPSBoughtTillNow += quantityInTier;
            totalQuantityPurchased += quantityInTier;
            if (totalMoneyLeft <= 10) {
                // Ignore the dust amount
                totalMoneyLeft = 0;
                break;
            }
        }

        return (totalQuantityPurchased, totalMoneyLeft);
    }

    /**
     * @notice Distribute the PS tokens to the users whose orders aren't filled
     */
    function splitEvenlyAfterDistribution() external onlyOwner nonReentrant {
        // From the last 6% supply, distribute it evenly to the users who didn't lock DD
        uint256 totalPSLeft = balanceOf(address(this));
        // Step 1: Distribute the PS tokens starting with DD locked users whose orders didn't fill entirely
        uint256 totalUnfilledOrders = (ddLockQueue.length - lastFilledLockedOrderIndex)
            + (ddUnlockQueue.length - lastFilledNonLockedOrderIndex) - 2;
        uint256 totalPerUserDistribution = totalPSLeft / totalUnfilledOrders;

        for (uint256 i = lastFilledNonLockedOrderIndex + 1; i < ddUnlockQueue.length; i++) {
            UserOrder memory userOrder = ddUnlockQueue[i];
            uint256 USDAmt = _convertCurrencyToUSD(
                userOrder.prepaidAmount,
                getPrice(tokenToPriceFeeder[userOrder.prepaidCurrency]),
                IERC20Extended(userOrder.prepaidCurrency).decimals()
            );
            uint256 cost = getPSCost(totalPerUserDistribution);
            if (cost < USDAmt) {
                // update state
                ddUnlockQueue[i].prepaidAmount -= cost;

                // Transfer the PS tokens
                _transfer(address(this), userOrder.user, totalPerUserDistribution);
            } else {
                (uint256 quantity, uint256 remaining) =
                    getCostFromMoney(USDAmt, IERC20Extended(userOrder.prepaidCurrency).decimals());
                // Return the money
                IERC20Extended(userOrder.prepaidCurrency).transfer(userOrder.user, remaining);
                // Transfer the PS tokens
                _transfer(address(this), userOrder.user, quantity);
            }
        }

        for (uint256 i = lastFilledLockedOrderIndex + 1; i < ddLockQueue.length; i++) {
            UserOrder memory userOrder = ddLockQueue[i];
            uint256 USDAmt = _convertCurrencyToUSD(
                userOrder.prepaidAmount,
                getPrice(tokenToPriceFeeder[userOrder.prepaidCurrency]),
                IERC20Extended(userOrder.prepaidCurrency).decimals()
            );
            uint256 cost = getPSCost(totalPerUserDistribution);
            if (cost < USDAmt) {
                // update state
                ddLockQueue[i].prepaidAmount -= cost;

                // Transfer the PS tokens
                _transfer(address(this), userOrder.user, totalPerUserDistribution);
            } else {
                (uint256 quantity, uint256 remaining) =
                    getCostFromMoney(USDAmt, IERC20Extended(userOrder.prepaidCurrency).decimals());
                // Return the money
                IERC20Extended(userOrder.prepaidCurrency).transfer(userOrder.user, remaining);
                // Transfer the PS tokens
                _transfer(address(this), userOrder.user, quantity);
            }
        }
    }

    /**
     * @notice Get the total amount of PS tokens bought by the users
     * @dev Function only works when supply is available
     */
    function fillRemainingOrders() external onlyOwner {
        // From the last 6% supply, distribute it evenly to the users who didn't lock DD
        uint256 totalPSLeft = balanceOf(address(this));

        for (uint256 i = lastFilledNonLockedOrderIndex + 1; i < ddUnlockQueue.length; i++) {
            UserOrder memory userOrder = ddUnlockQueue[i];
            uint256 orderQuantity = userOrder.orderAmount - userOrder.orderAmountFilled;
            uint256 USDAmt = _convertCurrencyToUSD(
                userOrder.prepaidAmount,
                getPrice(tokenToPriceFeeder[userOrder.prepaidCurrency]),
                IERC20Extended(userOrder.prepaidCurrency).decimals()
            );

            if (orderQuantity > totalPSLeft) {
                uint256 cost = getPSCost(totalPSLeft);
                if (cost > USDAmt) {
                    (uint256 quantity, uint256 remaining) =
                        getCostFromMoney(USDAmt, IERC20Extended(userOrder.prepaidCurrency).decimals());
                    IERC20Extended(userOrder.prepaidCurrency).transfer(userOrder.user, remaining);
                    _transfer(address(this), userOrder.user, quantity);
                } else {
                    ddUnlockQueue[i].prepaidAmount -= cost;
                    _transfer(address(this), userOrder.user, totalPSLeft);
                }
            } else {
                uint256 cost = getPSCost(orderQuantity);
                if (cost > USDAmt) {
                    (uint256 quantity, uint256 remaining) =
                        getCostFromMoney(USDAmt, IERC20Extended(userOrder.prepaidCurrency).decimals());
                    IERC20Extended(userOrder.prepaidCurrency).transfer(userOrder.user, remaining);
                    _transfer(address(this), userOrder.user, quantity);
                } else {
                    ddUnlockQueue[i].prepaidAmount -= cost;
                    _transfer(address(this), userOrder.user, orderQuantity);
                }
            }
        }

        for (uint256 i = lastFilledLockedOrderIndex + 1; i < ddLockQueue.length; i++) {
            UserOrder memory userOrder = ddLockQueue[i];
            uint256 orderQuantity = userOrder.orderAmount - userOrder.orderAmountFilled;
            uint256 USDAmt = _convertCurrencyToUSD(
                userOrder.prepaidAmount,
                getPrice(tokenToPriceFeeder[userOrder.prepaidCurrency]),
                IERC20Extended(userOrder.prepaidCurrency).decimals()
            );

            if (orderQuantity > totalPSLeft) {
                uint256 cost = getPSCost(totalPSLeft);
                if (cost > USDAmt) {
                    (uint256 quantity, uint256 remaining) =
                        getCostFromMoney(USDAmt, IERC20Extended(userOrder.prepaidCurrency).decimals());
                    IERC20Extended(userOrder.prepaidCurrency).transfer(userOrder.user, remaining);
                    _transfer(address(this), userOrder.user, quantity);
                } else {
                    ddLockQueue[i].prepaidAmount -= cost;
                    _transfer(address(this), userOrder.user, totalPSLeft);
                }
            } else {
                uint256 cost = getPSCost(orderQuantity);
                if (cost > USDAmt) {
                    (uint256 quantity, uint256 remaining) =
                        getCostFromMoney(USDAmt, IERC20Extended(userOrder.prepaidCurrency).decimals());
                    IERC20Extended(userOrder.prepaidCurrency).transfer(userOrder.user, remaining);
                    _transfer(address(this), userOrder.user, quantity);
                } else {
                    ddLockQueue[i].prepaidAmount -= cost;
                    _transfer(address(this), userOrder.user, orderQuantity);
                }
            }
        }
    }

    /// @notice Get the total amount of PS tokens bought by the users
    function addAllowedCurrencyForPurchase(
        address _token,
        IAggregatorV3Interface _tokenFeederAddress
    )
        external
        onlyOwner
    {
        tokenToPriceFeeder[_token] = _tokenFeederAddress;
    }

    /// @notice Set how many PS tokens to be minted on next sale and re-adjust the price-tiers accordingly
    /// @param _supplyAmount: Amount of PS tokens to mint
    function setPSTokenSaleSupply(uint256 _supplyAmount) public onlyOwner {
        totalAmountForLockedDD = (_supplyAmount * 7) / 10; // 70% of _supplyAmount
        // 24% of _supplyAmount
        totalAmountForNonLockedDD = (_supplyAmount * 24) / 100;
        // Dollar amounts are in cents, here 50 means $0.5
        uint256 totalTokens = 0;
        priceTiers[0] = PriceTier(50 * 1e4, (_supplyAmount) / 10); // 10%
        totalTokens += (_supplyAmount) / 10;

        priceTiers[1] = PriceTier(55 * 1e4, totalTokens + (_supplyAmount) / 30); // 3.33%
        totalTokens += (_supplyAmount) / 30;

        priceTiers[2] = PriceTier(60 * 1e4, totalTokens + (_supplyAmount) / 10); // 10%
        totalTokens += (_supplyAmount) / 10;

        priceTiers[3] = PriceTier(65 * 1e4, totalTokens + (_supplyAmount) / 30); // 3.33%
        totalTokens += (_supplyAmount) / 30;

        priceTiers[4] = PriceTier(70 * 1e4, totalTokens + (_supplyAmount) / 5); // 20%
        totalTokens += (_supplyAmount) / 5;

        priceTiers[5] = PriceTier(75 * 1e4, totalTokens + (_supplyAmount) / 15); // 6.67%
        totalTokens += (_supplyAmount) / 15;

        priceTiers[6] = PriceTier(80 * 1e4, totalTokens + (_supplyAmount) / 5); // 20%
        totalTokens += (_supplyAmount) / 5;

        priceTiers[7] = PriceTier(85 * 1e4, totalTokens + (_supplyAmount) / 15); // 6.67%
        totalTokens += (_supplyAmount) / 15;

        priceTiers[8] = PriceTier(90 * 1e4, totalTokens + (_supplyAmount) / 5); // 20%

        _mint(address(this), _supplyAmount);
    }

    ///////////////////////////////////////////////////////////////////
    ///////////////////////// INTERNAL FUNCTIONS /////////////////////
    /////////////////////////////////////////////////////////////////

    /**
     * @notice Get the maximum quantity of PS tokens that can be bought by non-locked buyers
     * @return Quantity of PS tokens that can be bought
     */
    function _maxQuantityCanBuyByNonLockedBuyers() internal view virtual returns (uint256) {
        uint256 totalPSBought = totalSupply() - balanceOf(address(this));
        if (totalPSBought < totalAmountForLockedDD) {
            return totalAmountForNonLockedDD;
        } else if (
            totalPSBought > totalAmountForLockedDD && totalPSBought < totalAmountForLockedDD + totalAmountForNonLockedDD
        ) {
            return totalAmountForLockedDD + totalAmountForNonLockedDD - totalPSBought;
        } else {
            return 0;
        }
    }

    function maxPurchaseableByAmount() internal view returns (uint256) { }

    function getPrice(IAggregatorV3Interface _feederAddress) internal view virtual returns (uint256) {
        (
            ,
            /* uint80 roundID */
            int256 answer, /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/
            ,
            ,
        ) = _feederAddress.latestRoundData();

        return uint256(answer / 100); // Make the price 6 decimals
    }

    function _convertUSDToCurrency(
        uint256 _usdCost,
        uint256 _tokenPrice,
        uint256 _decimal
    )
        internal
        pure
        returns (uint256)
    {
        return Math.mulDiv(_usdCost, 10 ** _decimal, _tokenPrice);
    }

    function _convertCurrencyToUSD(
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _decimal
    )
        internal
        pure
        returns (uint256)
    {
        return Math.mulDiv(_amount, _tokenPrice, 10 ** _decimal);
    }

    function handleLockedUserDistribution() internal returns (uint256) {
        uint256 psDistributed = 0;
        uint256 i = 0;
        uint256 ddQueueLength = ddLockQueue.length;
        while (i < ddQueueLength || psDistributed <= totalAmountForLockedDD) {
            // Get the user data
            UserOrder memory userOrder = ddLockQueue[i];
            /// @notice Calculate the amount of PS tokens that can be bought by the user
            (uint256 totalPSBoughtForUser,, uint256 tokensToReturn) = calculatePSTokenForLockedDD(userOrder);
            /// @dev If the user was able to purchase any PS tokens then perform actions
            if (totalPSBoughtForUser != 0) {
                // State changes
                ddLockQueue[i].prepaidAmount = tokensToReturn;
                ddLockQueue[i].orderAmountFilled = totalPSBoughtForUser;
                psDistributed += totalPSBoughtForUser;
                // Transfer the PS tokens to the user
                _transfer(address(this), userOrder.user, totalPSBoughtForUser);
            }

            // Find how many PS tokens are left from the locked users allowance
            i++;
        }

        lastFilledLockedOrderIndex = i;
        return psDistributed;
    }

    function handleNonLockedUserDistribution() internal {
        uint256 nonDDQueueLength = ddUnlockQueue.length;
        uint256 i = 0;
        uint256 psDistributed = 0;
        while (i < nonDDQueueLength || (psDistributed <= totalAmountForNonLockedDD)) {
            UserOrder memory userOrder = ddUnlockQueue[i];
            (uint256 totalPSBoughtForUser, uint256 tokensToReturn) = calculatePSTokenForNonLockedDD(userOrder);
            if (totalPSBoughtForUser != 0) {
                // State changes
                ddUnlockQueue[i].prepaidAmount = tokensToReturn;
                ddUnlockQueue[i].orderAmountFilled = totalPSBoughtForUser;
                // Transfer the PS tokens to the user
                psDistributed += totalPSBoughtForUser;
                _transfer(address(this), userOrder.user, totalPSBoughtForUser);
            }
            i++;
        }
        lastFilledNonLockedOrderIndex = i;
    }
}

