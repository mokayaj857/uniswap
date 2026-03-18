# reToken Uniswap Hook

<img width="1804" height="1800" alt="558747898-e3dd9cc2-6a9c-4d10-ad9c-56fa5623ad5f" src="https://github.com/user-attachments/assets/9eb14931-dd19-4d69-924b-cfde9015c45f" />

## Overview

reToken is a synthetic token minted every time a user swaps on a specific pool.

For example, alice swaps 10 TKNA for 20 TKNB.
- Alice deposits 10 TKNA into the pool.
- Alice receives 20 TKNB.
- reToken mints 10 reTKNA.
- reToken mints 20 reTKNB.

## Setup

```bash
forge install
forge clear
forge build
forge test -vv
```

## Deploy

https://docs.uniswap.org/contracts/v4/deployments

```bash
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543

forge script script/ReHook.s.sol:Deploy \
    --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
    --private-key 0x7df59047b2... \
    $POSITION_MANAGER \
    --broadcast \
    --verify \
    --etherscan-api-key IV1187...
```

