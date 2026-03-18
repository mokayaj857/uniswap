// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ReToken} from "./ReToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ReHook is BaseHook, Ownable {
    using StateLibrary for IPoolManager;
    mapping(address => ReToken) public reToken;

    constructor(
        IPoolManager _poolManager
    ) BaseHook(_poolManager) Ownable(msg.sender) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta balanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // get token0 and token1 address
        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);
        // if reToken0 isn't created, create it
        if (address(reToken[currency0]) == address(0)) {
            ERC20 erc20 = ERC20(Currency.unwrap(key.currency0));
            reToken[currency0] = new ReToken(
                string(abi.encodePacked("re", erc20.name())),
                string(abi.encodePacked("re", erc20.symbol())),
                erc20.decimals()
            );
        }
        // if reToken1 isn't created, create it
        if (address(reToken[currency1]) == address(0)) {
            ERC20 erc20 = ERC20(Currency.unwrap(key.currency1));
            reToken[currency1] = new ReToken(
                string(abi.encodePacked("re", erc20.name())),
                string(abi.encodePacked("re", erc20.symbol())),
                erc20.decimals()
            );
        }
        // get amount0 and amount1
        int256 delta0 = balanceDelta.amount0();
        int256 delta1 = balanceDelta.amount1();
        uint256 amount0 = delta0 < 0 ? uint256(-delta0) : uint256(delta0);
        uint256 amount1 = delta1 < 0 ? uint256(-delta1) : uint256(delta1);
        // mint token amount to sender
        reToken[currency0].mint(tx.origin, amount0);
        reToken[currency1].mint(tx.origin, amount1);

        return (BaseHook.afterSwap.selector, 0);
    }

    function getReToken(address currency) public view returns (ReToken) {
        return reToken[currency];
    }
}
