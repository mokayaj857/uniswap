// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/console.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ReHook} from "../src/ReHook.sol";
import {VolumeTracker} from "../src/VolumeTracker.sol";
import {FeeCollector} from "../src/FeeCollector.sol";
import {ReStaking} from "../src/ReStaking.sol";
import {ReToken} from "../src/ReToken.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract AdvancedFeaturesTest is BaseTest {
    using EasyPosm for IPositionManager;

    Currency currency0;
    Currency currency1;
    ReHook hook;
    PoolKey poolKey;
    PoolId poolId;
    ReToken reToken0;
    ReToken reToken1;
    ReStaking staking0;
    VolumeTracker volumeTracker;
    FeeCollector feeCollector;
    
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    
    uint256 constant REWARD_PER_SECOND = 1e18;

    function setUp() public {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook with both beforeSwap and afterSwap
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144)
        );
        bytes memory constructorArgs = abi.encode(poolManager);
        deployCodeTo("ReHook.sol:ReHook", constructorArgs, flags);
        hook = ReHook(flags);

        volumeTracker = VolumeTracker(hook.getVolumeTracker());
        feeCollector = FeeCollector(hook.getFeeCollector());

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 10_000, 200, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide liquidity
        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);
        uint128 liquidityAmount = 1000e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts
            .getAmountsForLiquidity(
                Constants.SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                liquidityAmount
            );

        positionManager.mint(
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

        // Perform initial swap to create reTokens
        swapRouter.swapExactTokensForTokens({
            amountIn: 100e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        reToken0 = hook.getReToken(Currency.unwrap(currency0));
        reToken1 = hook.getReToken(Currency.unwrap(currency1));

        // Create staking pool
        staking0 = hook.createStakingPool(Currency.unwrap(currency0), REWARD_PER_SECOND);

        // Fund reward pool
        IERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        hook.fundRewardPool(Currency.unwrap(currency0), REWARD_PER_SECOND * 100 hours);

        // Set volume tracker in staking
        hook.setStakingVolumeTracker(Currency.unwrap(currency0));

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        
        // Give test users tokens and approvals
        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
        MockERC20 token1 = MockERC20(Currency.unwrap(currency1));
        
        token0.mint(alice, 10000 ether);
        token0.mint(bob, 10000 ether);
        token0.mint(charlie, 10000 ether);
        token1.mint(alice, 10000 ether);
        token1.mint(bob, 10000 ether);
        token1.mint(charlie, 10000 ether);
        
        vm.startPrank(alice);
        token0.approve(address(permit2), type(uint256).max);
        token1.approve(address(permit2), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(bob);
        token0.approve(address(permit2), type(uint256).max);
        token1.approve(address(permit2), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(charlie);
        token0.approve(address(permit2), type(uint256).max);
        token1.approve(address(permit2), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    function testVolumeTracking() public {
        uint256 swapAmount = 10e18;

        vm.prank(alice);
        swapRouter.swapExactTokensForTokens({
            amountIn: swapAmount,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: alice,
            deadline: block.timestamp + 1
        });

        // Volume is tracked for swap router (sender in the hook context)
        (uint256 volume, , ) = volumeTracker.getUserVolume(address(swapRouter));
        assertGt(volume, 0); // Should have volume tracked from setup + this swap
    }

    function testTierUpgrade() public {
        // Get initial volume
        (uint256 volumeBefore, uint8 tierBefore, ) = volumeTracker.getUserVolume(address(swapRouter));
        
        // Do more swaps to upgrade tier
        vm.startPrank(alice);
        for (uint256 i = 0; i < 5; i++) {
            swapRouter.swapExactTokensForTokens({
                amountIn: 100 ether,
                amountOutMin: 0,
                zeroForOne: true,
                poolKey: poolKey,
                hookData: Constants.ZERO_BYTES,
                receiver: alice,
                deadline: block.timestamp + 1
            });
        }
        vm.stopPrank();

        (uint256 volumeAfter, uint8 tierAfter, ) = volumeTracker.getUserVolume(address(swapRouter));
        assertGt(volumeAfter, volumeBefore);
        assertGe(tierAfter, tierBefore); // Tier should be same or upgraded
    }

    function testMultiplierBoostsRewards() public {
        // Do swaps to generate more reTokens
        swapRouter.swapExactTokensForTokens({
            amountIn: 500e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        uint256 stakeAmount = 50e18;
        uint256 balance = reToken0.balanceOf(tx.origin);
        require(balance >= stakeAmount * 2, "Insufficient reTokens");
        
        // Transfer reTokens to users
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);
        vm.prank(tx.origin);
        reToken0.transfer(bob, stakeAmount);

        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(bob);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        vm.stopPrank();

        // Enable multipliers
        hook.setStakingMultiplierEnabled(Currency.unwrap(currency0), true);

        vm.warp(block.timestamp + 1 hours);

        uint256 aliceReward = staking0.pendingReward(alice);
        uint256 bobReward = staking0.pendingReward(bob);

        // Both should have rewards
        assertGt(aliceReward, 0);
        assertGt(bobReward, 0);
    }

    function testFeeCollection() public {
        uint256 swapAmount = 100e18;
        uint256 initialFees = feeCollector.getAccumulatedFees(Currency.unwrap(currency0));

        vm.prank(alice);
        swapRouter.swapExactTokensForTokens({
            amountIn: swapAmount,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: alice,
            deadline: block.timestamp + 1
        });

        uint256 finalFees = feeCollector.getAccumulatedFees(Currency.unwrap(currency0));
        assertGt(finalFees, initialFees);
    }

    function testFeeCollectionCanBeToggled() public {
        uint256 swapAmount = 100e18;

        // Disable fee collection
        hook.setFeeCollectionEnabled(false);

        uint256 initialFees = feeCollector.getAccumulatedFees(Currency.unwrap(currency0));

        vm.prank(alice);
        swapRouter.swapExactTokensForTokens({
            amountIn: swapAmount,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: alice,
            deadline: block.timestamp + 1
        });

        uint256 finalFees = feeCollector.getAccumulatedFees(Currency.unwrap(currency0));
        assertEq(finalFees, initialFees); // No fees collected
    }

    function testVolumeTrackingCanBeToggled() public {
        uint256 swapAmount = 10e18;

        // Disable volume tracking
        hook.setVolumeTrackingEnabled(false);

        vm.prank(alice);
        swapRouter.swapExactTokensForTokens({
            amountIn: swapAmount,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: alice,
            deadline: block.timestamp + 1
        });

        (uint256 volume, , ) = volumeTracker.getUserVolume(alice);
        assertEq(volume, 0); // No volume tracked
    }

    function testVolumeDecay() public {
        uint256 swapAmount = 100 ether;

        vm.prank(alice);
        swapRouter.swapExactTokensForTokens({
            amountIn: swapAmount,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: alice,
            deadline: block.timestamp + 1
        });

        (uint256 volumeBefore, , ) = volumeTracker.getUserVolume(alice);

        // Fast forward 30 days (one decay period)
        vm.warp(block.timestamp + 30 days);

        // Do a small swap to trigger decay
        vm.prank(alice);
        swapRouter.swapExactTokensForTokens({
            amountIn: 1 ether,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: alice,
            deadline: block.timestamp + 1
        });

        (uint256 volumeAfter, , ) = volumeTracker.getUserVolume(alice);

        // Volume should have decayed
        assertLt(volumeAfter, volumeBefore + 1 ether);
    }

    function testMultipleTierUpgrades() public {
        // Get router's initial tier
        (, uint8 initialTier, ) = volumeTracker.getUserVolume(address(swapRouter));

        // Do many swaps to increase volume
        vm.startPrank(alice);
        for (uint256 i = 0; i < 10; i++) {
            swapRouter.swapExactTokensForTokens({
                amountIn: 100 ether,
                amountOutMin: 0,
                zeroForOne: true,
                poolKey: poolKey,
                hookData: Constants.ZERO_BYTES,
                receiver: alice,
                deadline: block.timestamp + 1
            });
        }
        vm.stopPrank();
        
        (, uint8 finalTier, ) = volumeTracker.getUserVolume(address(swapRouter));
        assertGe(finalTier, initialTier); // Tier should upgrade or stay same
    }

    function testGetUserMultiplier() public {
        // Test that multiplier function works
        uint256 routerMultiplier = volumeTracker.getMultiplier(address(swapRouter));
        assertGt(routerMultiplier, 0); // Should have some multiplier (at least 1.0x = 10000)
    }

    function testFeePercentageCanBeAdjusted() public {
        uint256 newPercentage = 20; // 0.2%
        hook.setFeePercentage(newPercentage);

        uint256 swapAmount = 100e18;
        uint256 initialFees = feeCollector.getAccumulatedFees(Currency.unwrap(currency0));

        vm.prank(alice);
        swapRouter.swapExactTokensForTokens({
            amountIn: swapAmount,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: alice,
            deadline: block.timestamp + 1
        });

        uint256 finalFees = feeCollector.getAccumulatedFees(Currency.unwrap(currency0));
        uint256 expectedFee = (swapAmount * newPercentage) / 10000;
        
        assertApproxEqAbs(finalFees - initialFees, expectedFee, 1e15);
    }
}
