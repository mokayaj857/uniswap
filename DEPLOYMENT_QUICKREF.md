# 🚀 Quick Deployment Reference

## One-Command Deployment Sequence

```bash
# 1. Deploy Hook (mines address, deploys all contracts)
forge script script/01_DeployHook.s.sol:DeployReHook \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify -vvvv

# 2. Initialize Pool (creates pool with hook)
forge script script/02_InitializePool.s.sol:InitializePool \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv

# 3. Configure Features (setup staking + rewards)
forge script script/03_ConfigureHook.s.sol:ConfigureHook \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv

# 4. Enable Per-Pool Features
cast send $HOOK_ADDRESS "setFeeCollectionEnabled(bytes32,bool)" $POOL_ID true \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $HOOK_ADDRESS "setVolumeTrackingEnabled(bytes32,bool)" $POOL_ID true \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## Required Environment Variables

```bash
# Network
RPC_URL=https://sepolia.unichain.org
PRIVATE_KEY=your_key_here

# Addresses (Unichain Sepolia)
POOL_MANAGER=0x00B036B58a818B1BC34d502D3fE730Db729e62AC
TOKEN0=0x...  # Lower address
TOKEN1=0x...  # Higher address

# Deployment outputs (fill after each step)
HOOK_ADDRESS=    # From step 1
POOL_ID=         # From step 2
```

## Quick Status Check

```bash
# View deployed contracts
cast call $HOOK_ADDRESS "reToken()(address)" --rpc-url $RPC_URL
cast call $HOOK_ADDRESS "reStaking()(address)" --rpc-url $RPC_URL
cast call $HOOK_ADDRESS "feeCollector()(address)" --rpc-url $RPC_URL
cast call $HOOK_ADDRESS "volumeTracker()(address)" --rpc-url $RPC_URL

# Check feature status
cast call $HOOK_ADDRESS "getFeeCollectionEnabled(bytes32)(bool)" $POOL_ID --rpc-url $RPC_URL
cast call $HOOK_ADDRESS "getVolumeTrackingEnabled(bytes32)(bool)" $POOL_ID --rpc-url $RPC_URL
```

## Common Operations

```bash
# Fund reward pool
cast send $HOOK_ADDRESS "fundRewardPool(address)" $TOKEN0 \
    --value 100ether --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Update reward rate
RESTAKING=$(cast call $HOOK_ADDRESS "reStaking()(address)" --rpc-url $RPC_URL)
cast send $RESTAKING "updateRewardRate(uint256)" 10000000000000000 \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Emergency pause
cast send $RESTAKING "pause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Unpause
cast send $RESTAKING "unpause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## Network Quick Reference

| Network          | PoolManager                                | RPC                           |
|------------------|-------------------------------------------|-------------------------------|
| Unichain Sepolia | 0x00B036B58a818B1BC34d502D3fE730Db729e62AC | https://sepolia.unichain.org |
| Base Sepolia     | Check Uniswap docs                        | https://sepolia.base.org     |
| Arbitrum Sepolia | Check Uniswap docs                        | https://sepolia.arbitrum.io  |

## Verification

```bash
forge verify-contract \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $HOOK_ADDRESS \
    src/ReHook.sol:ReHook \
    --constructor-args $(cast abi-encode "constructor(address)" $POOL_MANAGER)
```
