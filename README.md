# reToken Uniswap v4 Hook 🚀

<img width="1804" height="1800" alt="558747898-e3dd9cc2-6a9c-4d10-ad9c-56fa5623ad5f" src="https://github.com/user-attachments/assets/9eb14931-dd19-4d69-924b-cfde9015c45f" />

## Overview

**reToken** is an advanced Uniswap v4 hook that mints synthetic tokens for every swap, enables staking rewards, captures fees, and implements a gamified volume-based tier system to incentivize liquidity and trading activity.

### Core Concept

When Alice swaps 10 TKNA for 20 TKNB:
- Alice deposits 10 TKNA into the pool
- Alice receives 20 TKNB
- **reToken mints 10 reTKNA** (synthetic token)
- **reToken mints 20 reTKNB** (synthetic token)
- Alice's volume is tracked for tier progression
- Pool fees are captured and distributed to stakers

## ✨ Features

### 🎯 Core Features
- ✅ **Swap-based Token Minting** - Automatic synthetic token creation on every swap
- ✅ **Staking Rewards** - Time-weighted reward distribution for stakers
- ✅ **Partial Unstaking** - Flexible unstaking without losing all positions
- ✅ **Auto-Claim Rewards** - Automatic reward claims on unstake
- ✅ **Emergency Controls** - Pause/unpause and emergency withdraw functions

### 🔥 Advanced V4 Features
- ✅ **Fee Capture & Redistribution** - 0.1% swap fees (configurable, max 1%)
- ✅ **Volume-Based Multipliers** - Earn up to 2x rewards based on trading volume
- ✅ **4-Tier Progression System**:
  - 🥉 **Bronze** (0-100 ETH): 1.0x multiplier
  - 🥈 **Silver** (100-500 ETH): 1.25x multiplier
  - 🥇 **Gold** (500-2000 ETH): 1.5x multiplier
  - 💎 **Platinum** (2000+ ETH): 2.0x multiplier
- ✅ **Volume Decay Mechanism** - 10% decay per 30 days to encourage ongoing activity
- ✅ **Dynamic Fee Adjustment** - Owner-controlled fee percentages
- ✅ **Feature Toggles** - Enable/disable fees, volume tracking, and multipliers independently

### 🔒 Security Features
- ✅ ReentrancyGuard on all state-changing functions
- ✅ SafeERC20 for all token transfers
- ✅ Ownable access control
- ✅ Pausable emergency stops
- ✅ Zero-amount protection
- ✅ Over-withdrawal prevention
- ✅ Reward depletion handling
- ✅ Max fee cap (1%)

## 🏗️ Architecture

### Smart Contracts

```
src/
├── ReHook.sol          Main Uniswap v4 hook (beforeSwap + afterSwap)
├── ReToken.sol         Synthetic ERC20 token (Burnable, Pausable, Permit, FlashMint)
├── ReStaking.sol       Time-weighted staking with multiplier support
├── FeeCollector.sol    Dynamic fee capture and distribution
└── VolumeTracker.sol   Volume tracking with 4-tier system
```

### Hook Integration

**ReHook** implements both `beforeSwap` and `afterSwap` hooks:
- **beforeSwap**: Captures fees and tracks volume before swap execution
- **afterSwap**: Mints reTokens to the swapper after swap completion

## 📊 Test Results

**100% Test Coverage - 36/36 Tests Passing** ✅

```
ReStakingTest:        16/16 tests ✅
AdvancedFeaturesTest: 10/10 tests ✅
ReHookTest:            2/2 tests ✅
CounterTest:           2/2 tests ✅
EasyPosmTest:          6/6 tests ✅
```

## 🚀 Quick Start

### Setup

```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test -vv

# Run tests with gas report
forge test --gas-report
```

### Usage Flow

#### 1. For Traders
```solidity
// Swap on pool → Receive reTokens automatically
// Volume tracked → Tier upgrades (Bronze → Silver → Gold → Platinum)
// Higher tier = Higher staking rewards
```

#### 2. For Stakers
```solidity
// Approve reTokens
reToken.approve(stakingAddress, amount);

// Stake tokens
staking.stake(amount);

// Claim rewards (multiplied by volume tier)
staking.claimReward();

// Or unstake (auto-claims rewards)
staking.unstake(amount);
```

#### 3. For Hook Owner
```solidity
// Create staking pool
hook.createStakingPool(tokenAddress, rewardPerSecond);

// Fund reward pool
hook.fundRewardPool(tokenAddress, rewardAmount);

// Adjust fee percentage (0-1%)
hook.setFeePercentage(poolId, 10); // 0.1%

// Toggle features
hook.setFeeCollectionEnabled(poolId, true);
hook.setVolumeTrackingEnabled(poolId, true);
hook.setStakingMultiplierEnabled(tokenAddress, true);
```

## ⚡ Gas Optimization

Optimized gas costs:
- `beforeSwap`: ~30-50k gas
- `afterSwap`: ~45-60k gas
- `stake`: ~150k gas
- `unstake`: ~230k gas
- `claimReward`: ~250k gas (with multiplier)

## Deploy

Uniswap v4 deployments: https://docs.uniswap.org/contracts/v4/deployments

```bash
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543

forge script script/ReHook.s.sol:Deploy \
    --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

## 🎨 Creative V4 Innovations

This project showcases unique Uniswap v4 capabilities:

1. **Dual Hook Integration** - Uses both beforeSwap and afterSwap hooks
2. **Multi-layered Incentives** - Swap rewards + Staking + Volume tiers
3. **Dynamic Fee System** - Configurable per-pool fees
4. **Gamified Progression** - Tier-based multipliers encourage activity
5. **Time-decay Mechanics** - Volume decay maintains engagement
6. **Toggle Architecture** - Features can be enabled/disabled independently

## 📚 Documentation

All contracts include comprehensive NatSpec comments with:
- Function descriptions
- Parameter explanations
- Return value documentation
- Event descriptions
- Architecture notes

See `/test` directory for usage examples and edge case handling.

## 🔧 Development

- Solidity Version: ^0.8.26
- Framework: Foundry
- Dependencies: Uniswap v4, OpenZeppelin
- Test Framework: Forge
- Total Lines: ~1861 across all contracts and tests

## 📄 License

MIT

## 🤝 Contributing

Contributions welcome! Please ensure all tests pass before submitting PRs:

```bash
forge test
```

## ⚠️ Disclaimer

This code is provided as-is for educational and demonstration purposes. Conduct thorough audits before using in production.

