// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/// @notice Helper library for mining hook addresses
/// @dev Uses CREATE2 to brute force addresses with specific hook flags
library HookMiner {
    uint256 internal constant MAX_LOOP = 100_000;

    /// @notice Find a salt that produces a hook address with desired `flags`
    /// @param deployer The address that will deploy the hook (CREATE2 factory)
    /// @param flags The desired flags for the hook address
    /// @param creationCode The creation bytecode of the hook contract
    /// @param constructorArgs The encoded constructor arguments
    /// @return hookAddress The computed hook address
    /// @return salt The salt value that produces the hook address
    function find(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal view returns (address, bytes32) {
        address hookAddress;
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        for (uint256 i = 0; i < MAX_LOOP; i++) {
            bytes32 salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, creationCodeWithArgs);
            
            if (uint160(hookAddress) & Hooks.ALL_HOOK_MASK == flags) {
                return (hookAddress, salt);
            }
        }
        
        revert("HookMiner: Could not find salt");
    }

    /// @notice Compute the CREATE2 address for a given salt
    function computeAddress(
        address deployer,
        bytes32 salt,
        bytes memory creationCode
    ) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            deployer,
                            salt,
                            keccak256(creationCode)
                        )
                    )
                )
            )
        );
    }
}
