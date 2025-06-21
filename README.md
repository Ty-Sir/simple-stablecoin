## Simple Stable Coin

**NOT PRODUCTION READY**

Demonstrates a simple-version of an overcollateralized stablecoin. This stablecoin has the following features:

1. ETH Collateralization

- Accepts ETH as collateral with Chainlink price feeds
- 150% minimum collateralization ratio
- 130% liquidation threshold

2. Core Functionality

- Mint stablecoins by depositing ETH
- Repay debt to retrieve collateral
- Liquidation system for undercollateralized positions

3. Simple Vault System

- One vault per user
- Tracks collateral and debt amounts
- Standard ERC20 implementation ("Simple USD" - sUSD)

Deploy:

```
forge script script/DeployStablecoin.s.sol:DeployStablecoin --rpc-url your_rpc_url --private-key your_private_key_here --broadcast -vvvv
```

Mint Tokens:

```
forge script script/VaultOperations.s.sol:VaultOperations --sig "createAndMint()" \
    --rpc-url https://your_rpc_url \
    --private-key your_private_key_here \
    --broadcast \
    -vvvv
```

Repay and Get Eth Back:

```
forge script script/VaultOperations.s.sol:VaultOperations --sig "repayAndWithdraw(uint256)" AMOUNT_IN_WEI \
    --rpc-url https://your_rpc_url \
    --private-key your_private_key_here \
    --broadcast \
    -vvvv
```

Check Vault Status:

```
forge script script/VaultOperations.s.sol:VaultOperations --sig "checkLiquidation(address)" "TARGET_ADDRESS" \
    --rpc-url https://your_rpc_url \
    -vvvv
```

Liquidate Unsafe Positions

```
forge script script/VaultOperations.s.sol:VaultOperations --sig "liquidatePosition(address)" "TARGET_ADDRESS" \
    --rpc-url https://your_rpc_url \
    --private-key your_private_key_here \
    --broadcast \
    -vvvv
```
