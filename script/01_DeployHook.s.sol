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
    // Override with `CREATE2_DEPLOYER` env var if your chain differs.
    address constant DEFAULT_CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() public {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address create2Deployer = vm.envOr("CREATE2_DEPLOYER", DEFAULT_CREATE2_DEPLOYER);

        // Our hook needs both BEFORE_SWAP_FLAG and AFTER_SWAP_FLAG
        // beforeSwap: for fee capture and volume tracking
        // afterSwap: for reToken minting
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        console.log("ChainId:", block.chainid);
        console.log("Mining for hook address with flags:", flags);
        console.log("BEFORE_SWAP_FLAG:", uint160(Hooks.BEFORE_SWAP_FLAG));
        console.log("AFTER_SWAP_FLAG:", uint160(Hooks.AFTER_SWAP_FLAG));
        console.log("POOL_MANAGER:", poolManager);
        console.log("CREATE2_DEPLOYER:", create2Deployer);

        // Constructor arguments for ReHook
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManager));

        // Mine for a salt that gives us the right address
        console.log("Starting address mining (this may take a minute)...");
        (address hookAddress, bytes32 salt) = HookMiner.find(
            create2Deployer,
            flags,
            type(ReHook).creationCode,
            constructorArgs
        );

        console.log("Found valid address!");
        console.log("Hook address:", hookAddress);
        console.log("Salt:", uint256(salt));

        // Deploy the hook using CREATE2 with the found salt
        vm.startBroadcast();
        
        ReHook hook = new ReHook{salt: salt}(IPoolManager(poolManager));
        
        console.log("");
        console.log("=== DEPLOYMENT SUCCESSFUL ===");
        console.log("PoolManager:", poolManager);
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
