# Prediction Market

A binary prediction market built with Solidity and Foundry.

Users can trade YES/NO positions, add liquidity, earn trading fees, and redeem winning positions after a market is resolved. Market resolution is handled through Chainlink price feeds.

![Solidity](https://img.shields.io/badge/Solidity-0.8.35-363636?style=for-the-badge\&logo=solidity\&logoColor=white)
![Foundry](https://img.shields.io/badge/Foundry-000000?style=for-the-badge\&logo=ethereum\&logoColor=white)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-Contracts-4E5EE4?style=for-the-badge\&logo=openzeppelin\&logoColor=white)
![Chainlink](https://img.shields.io/badge/Chainlink-Oracle-375BD2?style=for-the-badge\&logo=chainlink\&logoColor=white)

## What it does

The market has two possible outcomes: **YES** and **NO**.

Users can:

* Buy and sell YES/NO positions
* Add and remove liquidity
* Receive LP tokens for providing liquidity
* Earn a share of trading fees
* Redeem winning positions after resolution
* Trade against an AMM instead of relying on an order book

The market uses Gnosis Conditional Tokens for the YES/NO positions, while Chainlink is used to determine the final outcome.

## How pricing works

The market uses a constant-product AMM for pricing.

At a high level, the pool maintains:

```text
YES reserve × NO reserve = K
```

When someone buys or sells an outcome, the reserves change and the price moves accordingly.
The actual calculations are kept in the `Pricing` library.

## Liquidity

Liquidity providers deposit the market's collateral and receive LP tokens in return. LP tokens represent the provider's share of the pool. Liquidity can be added while the market is active and removed by burning the corresponding LP shares.

Trading fees are tracked separately so that liquidity providers can claim the fees they have accumulated.

## Market resolution

Markets are resolved through `BinaryOracle`.

The oracle uses a Chainlink price feed together with:

* Strike price
* Resolution time
* Settlement round
* Settlement delay
* Price-feed timestamps

The basic outcome is:

If the settlement price is at or above the strike price, YES wins.

If it's below the strike price, NO wins.

There is also a timeout path for cases where a market cannot be settled within the configured settlement window.

## Market lifecycle

A market starts in `PENDING`.

Once the required initial liquidity has been provided:

```text
PENDING -> OPEN -> RESOLVED
```

If the liquidity target is not reached before the deadline:

```text
PENDING -> CANCELLED
```

The state transitions and related checks are handled by `PredictionMarket`.

## Contracts

### `PredictionMarket.sol`

This is the main market contract.

It handles:

* Market initialization
* Initial liquidity
* Adding/removing liquidity
* YES/NO trading
* Fee accounting
* Cancellation
* Resolution
* Position redemption
* LP token management

### `MarketManager.sol`

`MarketManager` is used to create and keep track of markets.

Instead of deploying a new full contract every time, it uses OpenZeppelin Clones to create minimal proxy instances of the market and LP token implementations. Markets are also indexed by their question ID.

### `BinaryOracle.sol`

Handles market resolution using Chainlink price-feed data.

Before reporting an outcome, it checks things such as the settlement round, timestamps, price validity, and the allowed settlement window.

### `LPToken.sol`

An ERC-20 based token representing a user's share of a market's liquidity. Normal ERC-20 transfers and approvals are disabled. LP share movements are controlled by the market contract instead.

### `Pricing.sol`

Contains the AMM calculations used when buying and selling outcome positions.

The main calculations are exposed through functions such as:

```solidity
buyAmount(...)
sellAmount(...)
```

### `FeeLogic.sol`

Contains the fee accounting used by the market. It keeps track of the fee rate, fee index, user fee debt, and claimable fees.

## Tech stack

* Solidity `0.8.35`
* Foundry
* OpenZeppelin Contracts
* Gnosis Conditional Tokens
* Chainlink Price Feeds

## Getting started

### Requirements

Install Foundry if you don't already have it:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Check the installation:

```bash
forge --version
```

### Clone the repo

```bash
git clone https://github.com/rajib66k/prediction-market.git
cd prediction-market
```

## Build

```bash
forge build
```

## Tests

Run the test suite with:

```bash
forge test
```

## Formatting

```bash
forge fmt
```

## Local development

Start a local Anvil node:

```bash
anvil
```

Deployment scripts can then be run against the local network.

## Notes

This is primarily a development/experimental project. It has not been presented as production-ready software.

If you plan to use it with real funds, the contracts should go through a proper security review first. In particular, the AMM math, oracle assumptions, fee accounting, access control, and market-resolution edge cases deserve careful testing.
