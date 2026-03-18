// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {ReHook} from "../src/ReHook.sol";

/// @notice Script to deploy ReHook to testnet using CREATE2 address mining
/// @dev Mines for an address with BEFORE_SWAP_FLAG and AFTER_SWAP_FLAG enabled
contract DeployReHook is Script {
    // CREATE2 Deployer address (same across most EVM chains)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Unichain Sepolia PoolManager
    // For other networks, update this address from: https://docs.uniswap.org/contracts/v4/deployments
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;

    function run() public {
        // Our hook needs both BEFORE_SWAP_FLAG and AFTER_SWAP_FLAG
        // beforeSwap: for fee capture and volume tracking
        // afterSwap: for reToken minting
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        console.log("Mining for hook address with flags:", flags);
        console.log("BEFORE_SWAP_FLAG:", uint160(Hooks.BEFORE_SWAP_FLAG));
        console.log("AFTER_SWAP_FLAG:", uint160(Hooks.AFTER_SWAP_FLAG));

        // Constructor arguments for ReHook
        bytes memory constructorArgs = abi.encode(IPoolManager(POOL_MANAGER));

        // Mine for a salt that gives us the right address
        console.log("Starting address mining (this may take a minute)...");
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(ReHook).creationCode,
            constructorArgs
        );

        console.log("Found valid address!");
        console.log("Hook address:", hookAddress);
        console.log("Salt:", uint256(salt));

        // Deploy the hook using CREATE2 with the found salt
        vm.startBroadcast();
        
        ReHook hook = new ReHook{salt: salt}(IPoolManager(POOL_MANAGER));
        
        console.log("");
        console.log("=== DEPLOYMENT SUCCESSFUL ===");
        console.log("PoolManager:", POOL_MANAGER);
        console.log("ReHook deployed at:", address(hook));
        console.log("FeeCollector address:", address(hook.feeCollector()));
        console.log("VolumeTracker address:", address(hook.volumeTracker()));
        console.log("");
        
        vm.stopBroadcast();

        // Verify the address matches what we mined
        require(
            address(hook) == hookAddress,
            "DeployReHook: Hook address mismatch"
        );

        console.log("Address verification passed!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Create a pool using this hook");
        console.log("3. Initialize the pool and add liquidity");
    }
}
