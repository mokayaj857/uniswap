// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/console.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ReHook} from "../src/ReHook.sol";
import {ReStaking} from "../src/ReStaking.sol";
import {ReToken} from "../src/ReToken.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ReStakingTest is BaseTest {
    using EasyPosm for IPositionManager;

    Currency currency0;
    Currency currency1;
    ReHook hook;
    PoolKey poolKey;
    PoolId poolId;
    ReToken reToken0;
    ReToken reToken1;
    ReStaking staking0;
    ReStaking staking1;
    
    address alice = address(0x1);
    address bob = address(0x2);
    
    uint256 constant REWARD_PER_SECOND = 1e18;

    function setUp() public {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144)
        );
        bytes memory constructorArgs = abi.encode(poolManager);
        deployCodeTo("ReHook.sol:ReHook", constructorArgs, flags);
        hook = ReHook(flags);

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 10_000, 200, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide liquidity
        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);
        uint128 liquidityAmount = 100e18;

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

        // Perform a swap to create reTokens
        swapRouter.swapExactTokensForTokens({
            amountIn: 1000e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // Get reToken references
        reToken0 = hook.getReToken(Currency.unwrap(currency0));
        reToken1 = hook.getReToken(Currency.unwrap(currency1));

        // Create staking pools
        staking0 = hook.createStakingPool(Currency.unwrap(currency0), REWARD_PER_SECOND);
        staking1 = hook.createStakingPool(Currency.unwrap(currency1), REWARD_PER_SECOND);

        // Fund reward pools with enough for longer tests (10 hours worth)
        IERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);
        hook.fundRewardPool(Currency.unwrap(currency0), REWARD_PER_SECOND * 10 hours);
        hook.fundRewardPool(Currency.unwrap(currency1), REWARD_PER_SECOND * 10 hours);

        // Setup test users
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
    }

    function testStakingPoolCreation() public view {
        assertEq(address(hook.getReStaking(Currency.unwrap(currency0))), address(staking0));
        assertEq(address(hook.getReStaking(Currency.unwrap(currency1))), address(staking1));
        assertEq(address(staking0.stakingToken()), address(reToken0));
        assertEq(address(staking1.stakingToken()), address(reToken1));
    }

    function testCannotCreateDuplicateStakingPool() public {
        vm.expectRevert("Staking pool already exists");
        hook.createStakingPool(Currency.unwrap(currency0), REWARD_PER_SECOND);
    }

    function testStakeTokens() public {
        uint256 stakeAmount = 100e18;
        
        // Mint reTokens to alice (ReHook owns reToken so we transfer from origin)
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);
        
        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        vm.stopPrank();

        (uint256 amount, , uint256 stakedAt) = staking0.getStakeInfo(alice);
        assertEq(amount, stakeAmount);
        assertEq(stakedAt, block.timestamp);
        assertEq(reToken0.balanceOf(address(staking0)), stakeAmount);
    }

    function testCannotStakeZero() public {
        vm.startPrank(alice);
        vm.expectRevert("Cannot stake 0");
        staking0.stake(0);
        vm.stopPrank();
    }

    function testUnstakeTokens() public {
        uint256 stakeAmount = 100e18;
        
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);
        
        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        
        vm.warp(block.timestamp + 1 hours);
        
        staking0.unstake(stakeAmount);
        vm.stopPrank();

        (uint256 amount, , ) = staking0.getStakeInfo(alice);
        assertEq(amount, 0);
        assertEq(reToken0.balanceOf(alice), stakeAmount);
    }

    function testCannotUnstakeMoreThanStaked() public {
        uint256 stakeAmount = 100e18;
        
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);
        
        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        
        vm.expectRevert("Insufficient staked amount");
        staking0.unstake(stakeAmount + 1);
        vm.stopPrank();
    }

    function testRewardAccumulation() public {
        uint256 stakeAmount = 100e18;
        
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);
        
        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        vm.stopPrank();

        // Wait 1 hour
        vm.warp(block.timestamp + 1 hours);

        uint256 expectedReward = REWARD_PER_SECOND * 1 hours;
        uint256 pendingReward = staking0.pendingReward(alice);
        
        assertApproxEqAbs(pendingReward, expectedReward, 1e15);
    }

    function testClaimRewards() public {
        uint256 stakeAmount = 100e18;
        
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);
        
        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours);

        uint256 balanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 expectedReward = staking0.pendingReward(alice);

        vm.prank(alice);
        staking0.claimReward();

        uint256 balanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        assertApproxEqAbs(balanceAfter - balanceBefore, expectedReward, 1e15);
    }

    function testMultipleStakers() public {
        uint256 aliceStake = 100e18;
        uint256 bobStake = 200e18;
        
        vm.startPrank(tx.origin);
        reToken0.transfer(alice, aliceStake);
        reToken0.transfer(bob, bobStake);
        vm.stopPrank();

        // Alice stakes
        vm.startPrank(alice);
        reToken0.approve(address(staking0), aliceStake);
        staking0.stake(aliceStake);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours);

        // Bob stakes after 1 hour
        vm.startPrank(bob);
        reToken0.approve(address(staking0), bobStake);
        staking0.stake(bobStake);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours);

        // Alice should have more rewards (staked longer)
        uint256 aliceReward = staking0.pendingReward(alice);
        uint256 bobReward = staking0.pendingReward(bob);

        // Alice staked for 2 hours alone (1h) + shared (1h with 1/3 of rewards)
        // Bob staked for 1 hour with 2/3 of rewards
        assertGt(aliceReward, bobReward);
    }

    function testUnstakeWithRewards() public {
        uint256 stakeAmount = 100e18;
        
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);
        
        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours);

        uint256 rewardBalanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 expectedReward = staking0.pendingReward(alice);

        vm.prank(alice);
        staking0.unstake(stakeAmount);

        uint256 rewardBalanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        assertApproxEqAbs(rewardBalanceAfter - rewardBalanceBefore, expectedReward, 1e15);
        assertEq(reToken0.balanceOf(alice), stakeAmount);
    }

    function testEmergencyWithdraw() public {
        uint256 stakeAmount = 100e18;
        
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);
        
        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours);

        uint256 pendingBefore = staking0.pendingReward(alice);
        assertGt(pendingBefore, 0);

        vm.prank(alice);
        staking0.emergencyWithdraw();

        // Should get tokens back but lose rewards
        assertEq(reToken0.balanceOf(alice), stakeAmount);
        (uint256 amount, , ) = staking0.getStakeInfo(alice);
        assertEq(amount, 0);
    }

    function testPauseUnpause() public {
        uint256 stakeAmount = 100e18;
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);

        hook.pauseStaking(Currency.unwrap(currency0));

        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        vm.expectRevert();
        staking0.stake(stakeAmount);
        vm.stopPrank();

        hook.unpauseStaking(Currency.unwrap(currency0));

        vm.startPrank(alice);
        staking0.stake(stakeAmount);
        vm.stopPrank();

        (uint256 amount, , ) = staking0.getStakeInfo(alice);
        assertEq(amount, stakeAmount);
    }

    function testUpdateRewardRate() public {
        uint256 stakeAmount = 100e18;
        uint256 newRewardRate = 2e18;
        
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);
        
        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours);
        
        uint256 rewardBefore = staking0.pendingReward(alice);

        // Fund more rewards for the new rate
        IERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        hook.fundRewardPool(Currency.unwrap(currency0), newRewardRate * 10 hours);
        
        hook.setRewardRate(Currency.unwrap(currency0), newRewardRate);
        (, , , , uint256 lastMid, ) = staking0.poolInfo();

        // Warp using an absolute timestamp derived from staking state, to avoid relying on
        // the current test environment timestamp.
        vm.warp(lastMid + 1 hours);

        // Force a stateful pool update to avoid relying purely on view math.
        // This makes the test robust across compiler pipelines (via-ir/non-via-ir).
        staking0.updatePool();

        uint256 rewardAfter = staking0.pendingReward(alice);
        
        // Second hour should have approximately 2x the first hour's rate
        uint256 secondHourRewards = rewardAfter - rewardBefore;
        uint256 expectedSecondHour = newRewardRate * 1 hours;
        assertApproxEqAbs(secondHourRewards, expectedSecondHour, 1e16);
    }

    function testPartialUnstake() public {
        uint256 stakeAmount = 100e18;
        uint256 unstakeAmount = 30e18;
        
        vm.prank(tx.origin);
        reToken0.transfer(alice, stakeAmount);
        
        vm.startPrank(alice);
        reToken0.approve(address(staking0), stakeAmount);
        staking0.stake(stakeAmount);
        
        vm.warp(block.timestamp + 1 hours);
        
        staking0.unstake(unstakeAmount);
        vm.stopPrank();

        (uint256 amount, , ) = staking0.getStakeInfo(alice);
        assertEq(amount, stakeAmount - unstakeAmount);
        assertEq(reToken0.balanceOf(alice), unstakeAmount);
    }

    function testMultipleStakeIncreases() public {
        uint256 stake1 = 50e18;
        uint256 stake2 = 30e18;
        uint256 stake3 = 20e18;
        
        vm.prank(tx.origin);
        reToken0.transfer(alice, stake1 + stake2 + stake3);
        
        vm.startPrank(alice);
        reToken0.approve(address(staking0), stake1 + stake2 + stake3);
        
        staking0.stake(stake1);
        vm.warp(block.timestamp + 30 minutes);
        
        staking0.stake(stake2);
        vm.warp(block.timestamp + 30 minutes);
        
        staking0.stake(stake3);
        vm.stopPrank();

        (uint256 amount, , ) = staking0.getStakeInfo(alice);
        assertEq(amount, stake1 + stake2 + stake3);
    }

    function testRewardDepletionHandling() public {
        // Create a small reward pool
        address currency2 = address(deployToken());
        ReToken reToken2 = new ReToken("reToken2", "RT2", 18);
        ReStaking staking2 = new ReStaking(address(reToken2), currency2, REWARD_PER_SECOND);
        
        // Fund with limited rewards (1 hour worth)
        IERC20(currency2).approve(address(staking2), REWARD_PER_SECOND * 1 hours);
        staking2.depositReward(REWARD_PER_SECOND * 1 hours);

        uint256 stakeAmount = 100e18;
        reToken2.mint(alice, stakeAmount);
        
        vm.startPrank(alice);
        reToken2.approve(address(staking2), stakeAmount);
        staking2.stake(stakeAmount);
        vm.stopPrank();

        // Wait 2 hours (more than funded)
        vm.warp(block.timestamp + 2 hours);

        uint256 pending = staking2.pendingReward(alice);
        
        // Should only get 1 hour worth
        assertApproxEqAbs(pending, REWARD_PER_SECOND * 1 hours, 1e15);
    }
}
