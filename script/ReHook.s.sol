// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseScript} from "./base/BaseScript.sol";
import {console} from "forge-std/console.sol";
import {ReHook} from "../src/ReHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {ReHook} from "../src/ReHook.sol";

contract Deploy is BaseScript {
    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);

        bytes memory constructorArgs = abi.encode(poolManager);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY,
            flags,
            type(ReHook).creationCode,
            constructorArgs
        );

        vm.startBroadcast();
        address poolManager = vm.envAddress("POOL_MANAGER");
        ReHook rehook = new ReHook{salt: salt}(IPoolManager(poolManager));

        // log addresses
        console.log("POOL_MANAGER:", poolManager);
        console.log("ReHook address:", address(rehook));

        vm.stopBroadcast();

        require(
            address(rehook) == hookAddress,
            "DeployHookScript: Hook Address Mismatch"
        );
    }
}
