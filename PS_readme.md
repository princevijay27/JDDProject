Certainly! Here's the documentation rewritten in Markdown format suitable for a README.md file:

````markdown
# PSToken Contract

## Overview

The PSToken contract is an ERC20 token implementation with additional functionality for token distribution and sale. It allows users to lock positions with or without DD (another token) and purchase PS tokens through various mechanisms.

## External Functions

### For Users

#### Lock Position with DD

```solidity
function lockSlotPositionWithDD(uint256 _psTokensToBuy, uint256 _amountInCurrencyToSpend, IERC20Extended _paymentCurrency)
```
````

- Get in line to purchase PS tokens by locking DD tokens.
- Specify the amount of PS tokens to buy and the amount to spend in a specific currency.

#### Lock Position without DD

```solidity
function lockSlotPositionWithoutDD(uint256 _amountInCurrencyToSpend, IERC20Extended _paymentCurrency)
```

- Get in line to purchase PS tokens without locking DD tokens.
- Specify the amount to spend in a specific currency.

#### Direct Purchase

```solidity
function purchaseToken(uint256 _amount, IERC20Extended _currency)
```

- Directly purchase PS tokens using a specified amount and currency.
- Only works when there's available supply.

### For Owner

#### Distribute Tokens

```solidity
function distribute(uint256 _supplyToMint)
```

- Mint new PS tokens and distribute them to users who have locked positions.

#### Split Evenly After Distribution

```solidity
function splitEvenlyAfterDistribution()
```

- Distribute remaining PS tokens evenly among users whose orders weren't fully filled.

#### Fill Remaining Orders

```solidity
function fillRemainingOrders()
```

- Attempt to fill any remaining orders with available PS tokens.

#### Add Allowed Currency

```solidity
function addAllowedCurrencyForPurchase(address _token, IAggregatorV3Interface _tokenFeederAddress)
```

- Add a new currency that can be used to purchase PS tokens, along with its price feed.

#### Set Token Sale Supply

```solidity
function setPSTokenSaleSupply(uint256 _supplyAmount)
```

- Set the amount of PS tokens to be minted for the next sale and adjust price tiers accordingly.

## Usage Notes

1. Users: Use `lockSlotPositionWithDD`, `lockSlotPositionWithoutDD`, or `purchaseToken` to acquire PS tokens.
2. Owner: Use `distribute`, `splitEvenlyAfterDistribution`, `fillRemainingOrders`, `addAllowedCurrencyForPurchase`, and `setPSTokenSaleSupply` to manage the token distribution and sale process.

**Important:** Ensure you have the necessary permissions and meet the required conditions (e.g., having enough balance, using allowed currencies) when calling these functions.

```

This Markdown format is suitable for a README.md file on GitHub or similar platforms. It provides a clear structure with headers, code blocks for function signatures, and concise explanations of each function's purpose.
```
