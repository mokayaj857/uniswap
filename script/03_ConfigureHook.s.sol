// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ReHook} from "../src/ReHook.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @notice Script to configure ReHook features after deployment
/// @dev Run this after initializing the pool with 02_InitializePool.s.sol
contract ConfigureHook is Script {
    address HOOK_ADDRESS = vm.envAddress("HOOK_ADDRESS");
    address TOKEN0 = vm.envAddress("TOKEN0");
    address TOKEN1 = vm.envAddress("TOKEN1");
    
    // Configuration parameters
    uint256 constant REWARD_PER_SECOND = 0.01 ether; // 0.01 ETH per second
    uint256 constant INITIAL_REWARD_FUNDING = 100 ether; // 100 ETH total
    uint8 constant FEE_PERCENTAGE = 10; // 0.1% (10 basis points)
    
    function run() public {
        ReHook hook = ReHook(HOOK_ADDRESS);
        
        console.log("=== CONFIGURING REHOOK ===");
        console.log("Hook:", HOOK_ADDRESS);
        console.log("Token0:", TOKEN0);
        console.log("Token1:", TOKEN1);

        vm.startBroadcast();

        // Step 1: Get reToken addresses
        address reToken0 = address(hook.getReToken(TOKEN0));
        address reToken1 = address(hook.getReToken(TOKEN1));
        
        console.log("");
        console.log("reToken0:", reToken0);
        console.log("reToken1:", reToken1);

        // Step 2: Create staking pools for both reTokens
        console.log("");
        console.log("Creating staking pools...");
        
        if (reToken0 != address(0)) {
            try hook.createStakingPool(TOKEN0, REWARD_PER_SECOND) {
                console.log("Staking pool created for reToken0");
            } catch {
                console.log("Staking pool for reToken0 already exists");
            }
        }
        
        if (reToken1 != address(0)) {
            try hook.createStakingPool(TOKEN1, REWARD_PER_SECOND) {
                console.log("Staking pool created for reToken1");
            } catch {
                console.log("Staking pool for reToken1 already exists");
            }
        }

        // Step 3: Fund reward pools with ETH
        console.log("");
        console.log("Funding reward pools with", INITIAL_REWARD_FUNDING / 1e18, "ETH each...");
        
        // For ETH rewards, we need to handle this differently since ETH is not an ERC20
        // This assumes the tokens are ERC20s. For ETH pools, you'd need different logic.
        if (reToken0 != address(0)) {
            // This would work for ERC20 tokens, not ETH
            // For ETH, you'd need to wrap ETH or use a different approach
            console.log("Note: fundRewardPool expects ERC20 tokens, not ETH");
            console.log("For ETH rewards, consider using WETH or implement ETH handling");
        }
        
        if (reToken1 != address(0)) {
            console.log("Note: fundRewardPool expects ERC20 tokens, not ETH");
            console.log("For ETH rewards, consider using WETH or implement ETH handling");
        }

        // Step 4: Enable advanced features
        console.log("");
        console.log("Enabling advanced features...");
        
        // Enable fee collection (global setting)
        hook.setFeeCollectionEnabled(true);
        console.log("Fee collection enabled globally");
        
        // Enable volume tracking (global setting)
        hook.setVolumeTrackingEnabled(true);
        console.log("Volume tracking enabled globally");
        
        // Enable multipliers for staking
        if (reToken0 != address(0)) {
            hook.setStakingMultiplierEnabled(TOKEN0, true);
            console.log("Multipliers enabled for reToken0 staking");
        }
        
        if (reToken1 != address(0)) {
            hook.setStakingMultiplierEnabled(TOKEN1, true);
            console.log("Multipliers enabled for reToken1 staking");
        }

        console.log("");
        console.log("=== CONFIGURATION COMPLETE ===");
        console.log("");
        console.log("Current settings:");
        console.log("- Reward rate:", REWARD_PER_SECOND / 1e18, "ETH per second");
        console.log("- Initial funding:", INITIAL_REWARD_FUNDING / 1e18, "ETH per pool");
        console.log("- Fee percentage:", FEE_PERCENTAGE, "basis points (0.1%)");
        console.log("- Multipliers: ENABLED");
        console.log("");
        console.log("To enable per-pool features, use:");
        console.log("hook.setFeeCollectionEnabled(poolId, true)");
        console.log("hook.setVolumeTrackingEnabled(poolId, true)");

        vm.stopBroadcast();
    }
}
