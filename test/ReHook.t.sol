// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/console.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ReHook} from "../src/ReHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ReToken} from "../src/ReToken.sol";

contract ReHookTest is BaseTest {
    using EasyPosm for IPositionManager;

    Currency currency0;
    Currency currency1;
    ReHook hook;
    PoolKey poolKey;
    PoolId poolId;
    int24 tickLower;
    int24 tickUpper;
    uint256 tokenId;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(poolManager); // Add all the necessary constructor arguments from the hook
        deployCodeTo("ReHook.sol:ReHook", constructorArgs, flags);
        hook = ReHook(flags);

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 10_000, 200, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts
            .getAmountsForLiquidity(
                Constants.SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                liquidityAmount
            );

        (tokenId, ) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    function testOrigin() public view {
        console.log("msg.sender ", msg.sender);
        console.log("tx.origin  ", tx.origin);
        console.log("EOA address", vm.addr(1));
        assertEq(msg.sender, tx.origin);
    }

    function testCounterHook() public {
        // Perform a test swap
        swapRouter.swapExactTokensForTokens({
            amountIn: 100,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        // get reToken
        ReToken reToken0 = hook.getReToken(Currency.unwrap(poolKey.currency0));
        ReToken reToken1 = hook.getReToken(Currency.unwrap(poolKey.currency1));
        // check token name and symbol
        assertEq(reToken0.name(), "reTest Token");
        assertEq(reToken0.symbol(), "reTEST");
        // check EOA balance
        assertEq(reToken0.balanceOf(tx.origin), 100);
        assertEq(reToken1.balanceOf(tx.origin), 98); // from slippage + fee
    }
}
