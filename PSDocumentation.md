### **PSToken Contract Documentation**

**Overview:**

PSToken is an upgradeable ERC20 token that provides a sophisticated token sale mechanism. It supports two primary purchase options:
1. Purchase with DD token locking.
2. Purchase without DD token locking.

The contract incorporates a tiered pricing system that adjusts token prices based on the total supply sold.

**State Variables:**
- `totalAmountForLockedDD`: uint256 - Represents 70% of PS tokens, reserved exclusively for DD token lockers.
- `totalAmountForNonLockedDD`: uint256 - Represents 24% of PS tokens, allocated for purchasers without DD token locking.
- `lastFilledLockedOrderIndex`: uint256 - Index of the last filled order for locked DD token purchases.
- `lastFilledNonLockedOrderIndex`: uint256 - Index of the last filled order for non-locked DD token purchases.
- `DDToken`: address - Contract address of the DD token.
- `priceTiers`: (uint256, uint256)[] - An array of 9 price tiers, each defining a different token amount and corresponding price.

**Public Functions:**

**Token Purchase Functions:**

- `lockSlotPositionWithDD(uint256 _psTokensToBuy, uint256 _amountInCurrencyToSpend, IERC20Extended _paymentCurrency)`: Locks a slot for purchasing PS tokens while also locking DD tokens. Emits `SlotPositionLockedWithDD`.
  - `_psTokensToBuy`: Number of PS tokens to purchase.
  - `_amountInCurrencyToSpend`: Currency amount willing to be spent.
  - `_paymentCurrency`: Token address of the payment currency.

- `lockSlotPositionWithoutDD(uint256 _amountInCurrencyToSpend, IERC20Extended _paymentCurrency)`: Locks a slot for purchasing PS tokens without locking DD tokens. Emits `SlotPositionLockedWithoutDD`.
  - `_amountInCurrencyToSpend`: Currency amount willing to be spent.
  - `_paymentCurrency`: Token address of the payment currency.

- `purchaseToken(uint256 _amount, IERC20Extended _currency)`: Directly purchases PS tokens when supply is available.
  - `_amount`: Currency amount to spend.
  - `_currency`: Token address of the currency.

**Distribution Functions:**

- `distribute(uint256 _supplyToMint)`: Distributes PS tokens to users in the queue. Handles both locked and non-locked DD users.
  - `_supplyToMint`: Number of PS tokens to mint.

- `splitEvenlyAfterDistribution()`: Distributes the remaining 6% of the supply evenly among unfilled orders.

- `fillRemainingOrders()`: Processes the remaining unfilled orders in both queues, handling partial fills and refunds.

**Calculation Functions:**

- `calculatePSTokenForNonLockedDD(UserOrder _userOrder) returns (uint256, uint256)`: Calculates the number of PS tokens purchasable for non-DD locked orders.
  - Returns: Quantity of tokens purchasable and remaining money.

- `calculatePSTokenForLockedDD(UserOrder _userOrder) returns (uint256, uint256, uint256)`: Calculates the number of PS tokens purchasable for DD locked orders.
  - Returns: Tokens to buy, cost in currency, and remaining money.

- `getPSCost(uint256 psQuantity_) returns (uint256)`: Calculates the cost in USD for purchasing a specific quantity of PS tokens.
  - `psQuantity_`: Quantity of PS tokens to buy.

- `getCostFromMoney(uint256 _psAmount, uint256 _decimal) returns (uint256, uint256)`: Determines how many PS tokens can be purchased with a given amount of money.
  - `_psAmount`: Amount in USD.
  - `_decimal`: Currency decimals.

**Administrative Functions:**

- `setPSTokenSaleSupply(uint256 _supplyAmount)`: Sets the token supply and adjusts price tiers accordingly.
  - `_supplyAmount`: Total supply to mint.

- `addAllowedCurrencyForPurchase(address _token, IAggregatorV3Interface _tokenFeederAddress)`: Adds a new currency for purchasing tokens.
  - `_token`: Currency token address.
  - `_tokenFeederAddress`: Address of the Chainlink price feed.

**Events:**
- `SlotPositionLockedWithDD(address indexed user, uint256 amount)`: Triggered when a DD locked position is secured.
- `SlotPositionLockedWithoutDD(address indexed user)`: Triggered when a non-DD locked position is secured.

**Modifiers:**
- `checkAllowedCurrency(address _currency)`: Validates the payment currency.
- `whenNoSupply()`: Ensures that no token supply exists when called.
- `whenSupply()`: Ensures that a token supply exists when called.
- `nonReentrant`: Prevents reentrancy attacks.
- `onlyOwner`: Restricts function access to the contract owner.

This documentation is structured to help developers and integrators understand how to interact with the PSToken contract and its various functionalities.