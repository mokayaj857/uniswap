# 🚀 Testnet Deployment Guide

Complete guide for deploying reToken Uniswap v4 Hook to testnet networks.

## 📋 Prerequisites

1. **Foundry installed** - https://book.getfoundry.sh/getting-started/installation
2. **Testnet ETH** - Get from faucet for gas fees and rewards funding
3. **RPC endpoint** - For your target network (e.g., Unichain Sepolia, Base Sepolia, etc.)
4. **Block explorer API key** - For contract verification (optional but recommended)

## 🌐 Supported Networks

### Unichain Sepolia (Recommended for testing)
- **RPC**: https://sepolia.unichain.org
- **PoolManager**: `0x00B036B58a818B1BC34d502D3fE730Db729e62AC`
- **Faucet**: https://faucet.unichain.org
- **Explorer**: https://sepolia.uniscan.xyz

### Other Networks
Check [Uniswap v4 Deployments](https://docs.uniswap.org/contracts/v4/deployments) for PoolManager addresses on other networks.

## 🛠️ Setup

### 1. Clone and Build

```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run tests to verify everything works
forge test
```

### 2. Configure Environment

```bash
# Copy example env file
cp .env.example .env

# Edit .env with your settings
nano .env
```

Required variables in `.env`:
```bash
RPC_URL=https://sepolia.unichain.org
PRIVATE_KEY=your_private_key_here  # WITHOUT 0x prefix
ETHERSCAN_API_KEY=your_api_key_here
POOL_MANAGER=0x00B036B58a818B1BC34d502D3fE730Db729e62AC
TOKEN0=0x...  # Lower address
TOKEN1=0x...  # Higher address
```

**⚠️ SECURITY**: Never commit your `.env` file! It's already in `.gitignore`.

### 3. Get Test Tokens

You'll need two ERC20 tokens for your pool. Options:

**Option A: Deploy test tokens**
```bash
forge create src/MockERC20.sol:MockERC20 \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args "Test Token A" "TKNA" 18
```

**Option B: Use existing testnet tokens**
Find existing test tokens on the network's block explorer.

**Important**: Ensure `TOKEN0 < TOKEN1` (addresses sorted in ascending order).

## 🚀 Deployment Steps

### Step 1: Deploy the Hook

This script mines for a valid CREATE2 address and deploys the hook:

```bash
forge script script/01_DeployHook.s.sol:DeployReHook \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
```

**What happens:**
- ✅ Mines for address with `BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG`
- ✅ Deploys ReHook contract
- ✅ Deploys ReToken, ReStaking, FeeCollector, VolumeTracker
- ✅ Verifies all contracts on block explorer

**Output example:**
```
Hook deployed at: 0x1234...abcd
ReToken address: 0x5678...efgh
ReStaking address: 0x9abc...1234
FeeCollector address: 0xdef0...5678
VolumeTracker address: 0x1111...9999
```

**Save the hook address** - You'll need it for the next steps!

```bash
# Update .env with deployed hook address
HOOK_ADDRESS=0x1234...abcd  # From deployment output
```

### Step 2: Initialize the Pool

Create a new pool with your hook:

```bash
forge script script/02_InitializePool.s.sol:InitializePool \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv
```

**What happens:**
- ✅ Creates PoolKey with your tokens and hook
- ✅ Initializes pool at 1:1 price
- ✅ Returns Pool ID

**Output example:**
```
Pool ID: 0xabcd1234...
Pool initialized successfully
```

**Save the pool ID** for future operations!

### Step 3: Configure Hook Features

Setup staking pools and enable advanced features:

```bash
forge script script/03_ConfigureHook.s.sol:ConfigureHook \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv
```

**What happens:**
- ✅ Creates staking pools for both reTokens
- ✅ Funds reward pools with ETH (100 ETH each by default)
- ✅ Enables volume-based multipliers

**Configuration:**
Edit `script/03_ConfigureHook.s.sol` to adjust:
- `REWARD_PER_SECOND` - Reward rate (default: 0.01 ETH/sec)
- `INITIAL_REWARD_FUNDING` - Initial funding (default: 100 ETH)
- `FEE_PERCENTAGE` - Fee amount (default: 10 = 0.1%)

### Step 4: Enable Per-Pool Features (Optional)

Enable fee collection and volume tracking for your specific pool:

```bash
# Using cast (comes with Foundry)
cast send $HOOK_ADDRESS \
    "setFeeCollectionEnabled(bytes32,bool)" \
    $POOL_ID true \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY

cast send $HOOK_ADDRESS \
    "setVolumeTrackingEnabled(bytes32,bool)" \
    $POOL_ID true \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

## 🧪 Testing Your Deployment

### 1. Check Deployment Status

```bash
# View hook info
cast call $HOOK_ADDRESS "reToken()(address)" --rpc-url $RPC_URL
cast call $HOOK_ADDRESS "reStaking()(address)" --rpc-url $RPC_URL
cast call $HOOK_ADDRESS "feeCollector()(address)" --rpc-url $RPC_URL
cast call $HOOK_ADDRESS "volumeTracker()(address)" --rpc-url $RPC_URL
```

### 2. Test a Swap

Use the Uniswap interface or write a simple swap script to:
1. Swap TOKEN0 → TOKEN1
2. Check that reTokens were minted
3. Verify volume was tracked

### 3. Test Staking

```bash
# Get reToken address for TOKEN0
RETOKEN0=$(cast call $HOOK_ADDRESS "reTokenMap(address)(address)" $TOKEN0 --rpc-url $RPC_URL)

# Approve reToken for staking
cast send $RETOKEN0 \
    "approve(address,uint256)" \
    $(cast call $HOOK_ADDRESS "reStaking()(address)" --rpc-url $RPC_URL) \
    1000000000000000000 \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY

# Stake tokens
RESTAKING=$(cast call $HOOK_ADDRESS "reStaking()(address)" --rpc-url $RPC_URL)
cast send $RESTAKING \
    "stake(uint256)" \
    1000000000000000000 \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

## 📊 Monitoring & Management

### View Pool Stats

```bash
# Check fee collection status
cast call $HOOK_ADDRESS \
    "getFeeCollectionEnabled(bytes32)(bool)" \
    $POOL_ID \
    --rpc-url $RPC_URL

# Check volume tracking status
cast call $HOOK_ADDRESS \
    "getVolumeTrackingEnabled(bytes32)(bool)" \
    $POOL_ID \
    --rpc-url $RPC_URL

# Get user's volume and tier
cast call $HOOK_ADDRESS \
    "getUserVolume(address)(uint256,uint256,uint8)" \
    $YOUR_ADDRESS \
    --rpc-url $RPC_URL
```

### Manage Hook

```bash
# Update reward rate (only owner)
cast send $RESTAKING \
    "updateRewardRate(uint256)" \
    20000000000000000 \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY

# Adjust fee percentage (0-100, where 10 = 0.1%)
cast send $HOOK_ADDRESS \
    "setFeePercentage(bytes32,uint8)" \
    $POOL_ID 20 \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY

# Pause in emergency
cast send $RESTAKING \
    "pause()" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

## 🔍 Contract Verification

If automatic verification fails, verify manually:

```bash
forge verify-contract \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch \
    $HOOK_ADDRESS \
    src/ReHook.sol:ReHook \
    --constructor-args $(cast abi-encode "constructor(address)" $POOL_MANAGER)
```

## 🐛 Troubleshooting

### "HookMiner: Could not find salt"
- Mining takes time (up to 1-2 minutes)
- Try increasing `MAX_LOOP` in `HookMiner.sol` to 200_000
- Make sure your flags are correct

### "Hook address mismatch"
- Ensure PoolManager address is correct for your network
- Check that CREATE2_DEPLOYER exists on your network
- Verify you're using the same flags in deployment

### "Insufficient funds"
- Make sure you have enough testnet ETH for:
  - Contract deployment gas (~2-5M gas)
  - Pool initialization (~500k gas)
  - Reward pool funding (100+ ETH)

### "Invalid hook flags"
- Verify your hook implements the functions it claims
- Check that beforeSwap and afterSwap are properly implemented
- Ensure getHookPermissions() returns correct flags

## 📝 Network-Specific Notes

### Unichain Sepolia
- Very fast block times (~2 seconds)
- Generous faucet (1 ETH per request)
- Excellent for testing

### Base Sepolia
- PoolManager: Check Uniswap docs
- Faucet: https://faucet.quicknode.com/base/sepolia

### Arbitrum Sepolia
- PoolManager: Check Uniswap docs
- Faucet: https://faucet.quicknode.com/arbitrum/sepolia

## 🎯 Next Steps After Deployment

1. **Add Liquidity** - Use Uniswap interface or Position Manager
2. **Test Swaps** - Verify reTokens are minted correctly
3. **Test Staking** - Stake reTokens and check rewards
4. **Monitor Volume Tiers** - Make swaps to progress through tiers
5. **Test Emergency Functions** - Pause/unpause to verify safety
6. **Build Frontend** - Create UI for users to interact with your hook

## 📚 Additional Resources

- [Uniswap v4 Docs](https://docs.uniswap.org/contracts/v4/overview)
- [Uniswap v4 Deployments](https://docs.uniswap.org/contracts/v4/deployments)
- [Foundry Book](https://book.getfoundry.sh/)
- [Hook Development Guide](https://docs.uniswap.org/contracts/v4/guides/custom-accounting-hook)

## 💡 Tips

- **Use a burner wallet** for testnet deployments
- **Save all addresses** immediately after each deployment
- **Test thoroughly** before considering mainnet
- **Monitor gas costs** to optimize before mainnet
- **Document everything** for your team/users

## 🆘 Getting Help

If you run into issues:
1. Check the troubleshooting section above
2. Review Foundry logs with `-vvvv` flag
3. Verify addresses on block explorer
4. Test contracts individually with `cast call`
5. Check Uniswap v4 Discord for community help

---

**Good luck with your deployment! 🚀**
