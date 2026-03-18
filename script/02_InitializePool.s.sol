// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {ReHook} from "../src/ReHook.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Script to initialize a pool with the ReHook
/// @dev Run this after deploying the hook with 01_DeployHook.s.sol
contract InitializePool is Script {
    using PoolIdLibrary for PoolKey;

    // Update these addresses based on your deployment
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    
    // Configure your pool parameters here
    // Update these with your token addresses
    address TOKEN0 = vm.envAddress("TOKEN0"); // Lower address
    address TOKEN1 = vm.envAddress("TOKEN1"); // Higher address
    address HOOK_ADDRESS = vm.envAddress("HOOK_ADDRESS"); // From 01_DeployHook output
    
    // Pool parameters
    uint24 constant POOL_FEE = 3000; // 0.3% fee
    int24 constant TICK_SPACING = 60; // Standard tick spacing for 0.3% fee
    
    function run() public {
        require(TOKEN0 < TOKEN1, "TOKEN0 must be < TOKEN1");
        
        console.log("=== POOL INITIALIZATION ===");
        console.log("Token0:", TOKEN0);
        console.log("Token1:", TOKEN1);
        console.log("Hook:", HOOK_ADDRESS);
        console.log("Fee:", POOL_FEE);
        console.log("Tick Spacing:", uint256(uint24(TICK_SPACING)));

        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(TOKEN0),
            currency1: Currency.wrap(TOKEN1),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK_ADDRESS)
        });

        // Calculate pool ID
        PoolId poolId = poolKey.toId();
        console.log("Pool ID:", PoolId.unwrap(poolId));

        // Initialize at 1:1 price (sqrtPriceX96 = sqrt(1) * 2^96)
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);
        console.log("Initial sqrtPriceX96:", sqrtPriceX96);

        vm.startBroadcast();

        // Initialize the pool
        IPoolManager(POOL_MANAGER).initialize(poolKey, sqrtPriceX96);

        console.log("");
        console.log("=== POOL INITIALIZED SUCCESSFULLY ===");
        console.log("Pool ID:", PoolId.unwrap(poolId));
        console.log("");
        console.log("Next steps:");
        console.log("1. Create staking pool: hook.createStakingPool(token0)");
        console.log("2. Create staking pool: hook.createStakingPool(token1)");
        console.log("3. Fund reward pools with ETH");
        console.log("4. Add liquidity to the pool");
        console.log("5. Test swaps to mint reTokens");

        vm.stopBroadcast();
    }
}
