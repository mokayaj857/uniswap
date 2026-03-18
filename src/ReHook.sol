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
import {ReStaking} from "./ReStaking.sol";
import {FeeCollector} from "./FeeCollector.sol";
import {VolumeTracker} from "./VolumeTracker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ReHook is BaseHook, Ownable {
    using StateLibrary for IPoolManager;
    mapping(address => ReToken) public reToken;
    mapping(address => ReStaking) public reStaking;
    
    FeeCollector public feeCollector;
    VolumeTracker public volumeTracker;
    
    bool public feeCollectionEnabled = true;
    bool public volumeTrackingEnabled = true;

    event FeeCollected(address indexed token, uint256 amount, address indexed user);
    event VolumeTracked(address indexed user, uint256 amount);

    constructor(
        IPoolManager _poolManager
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        feeCollector = new FeeCollector();
        volumeTracker = new VolumeTracker();
    }

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
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        address user = sender; // Use sender for tracking instead of tx.origin
        
        // Calculate swap amount for volume tracking and fee collection
        uint256 swapAmount = params.amountSpecified < 0 
            ? uint256(-params.amountSpecified) 
            : uint256(params.amountSpecified);
        
        // Track volume if enabled
        if (volumeTrackingEnabled && swapAmount > 0) {
            volumeTracker.updateVolume(user, swapAmount);
            emit VolumeTracked(user, swapAmount);
        }
        
        // Collect fees if enabled
        if (feeCollectionEnabled && swapAmount > 0) {
            address swapToken = params.zeroForOne 
                ? Currency.unwrap(key.currency0) 
                : Currency.unwrap(key.currency1);
            
            uint256 feeAmount = feeCollector.collectFee(swapToken, swapAmount, user);
            
            if (feeAmount > 0) {
                emit FeeCollected(swapToken, feeAmount, user);
            }
        }
        
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
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

    function getReStaking(address currency) public view returns (ReStaking) {
        return reStaking[currency];
    }

    function createStakingPool(
        address currency,
        uint256 rewardPerSecond
    ) external onlyOwner returns (ReStaking) {
        require(address(reToken[currency]) != address(0), "ReToken does not exist");
        require(address(reStaking[currency]) == address(0), "Staking pool already exists");
        
        ReStaking stakingPool = new ReStaking(
            address(reToken[currency]),
            currency,
            rewardPerSecond
        );
        
        reStaking[currency] = stakingPool;
        
        return stakingPool;
    }

    function fundRewardPool(address currency, uint256 amount) external onlyOwner {
        require(address(reStaking[currency]) != address(0), "Staking pool does not exist");
        require(amount > 0, "Amount must be greater than 0");
        
        ERC20(currency).transferFrom(msg.sender, address(this), amount);
        ERC20(currency).approve(address(reStaking[currency]), amount);
        reStaking[currency].depositReward(amount);
    }

    function setRewardRate(address currency, uint256 rewardPerSecond) external onlyOwner {
        require(address(reStaking[currency]) != address(0), "Staking pool does not exist");
        reStaking[currency].setRewardPerSecond(rewardPerSecond);
    }

    function pauseStaking(address currency) external onlyOwner {
        require(address(reStaking[currency]) != address(0), "Staking pool does not exist");
        reStaking[currency].pause();
    }

    function unpauseStaking(address currency) external onlyOwner {
        require(address(reStaking[currency]) != address(0), "Staking pool does not exist");
        reStaking[currency].unpause();
    }

    // Fee collection functions
    function setFeeCollectionEnabled(bool enabled) external onlyOwner {
        feeCollectionEnabled = enabled;
    }

    function setFeePercentage(uint256 percentage) external onlyOwner {
        feeCollector.setFeePercentage(percentage);
    }

    function distributeFees(address token, address to, uint256 amount) external onlyOwner {
        feeCollector.distributeFees(token, to, amount);
    }

    function getAccumulatedFees(address token) external view returns (uint256) {
        return feeCollector.getAccumulatedFees(token);
    }

    // Volume tracking functions
    function setVolumeTrackingEnabled(bool enabled) external onlyOwner {
        volumeTrackingEnabled = enabled;
    }

    function getUserVolume(address user) external view returns (uint256 volume, uint8 tier, uint256 lastUpdate) {
        return volumeTracker.getUserVolume(user);
    }

    function getUserMultiplier(address user) external view returns (uint256) {
        return volumeTracker.getMultiplier(user);
    }

    function getFeeCollector() external view returns (address) {
        return address(feeCollector);
    }

    function getVolumeTracker() external view returns (address) {
        return address(volumeTracker);
    }

    function setStakingVolumeTracker(address currency) external onlyOwner {
        require(address(reStaking[currency]) != address(0), "Staking pool does not exist");
        reStaking[currency].setVolumeTracker(address(volumeTracker));
    }

    function setStakingMultiplierEnabled(address currency, bool enabled) external onlyOwner {
        require(address(reStaking[currency]) != address(0), "Staking pool does not exist");
        reStaking[currency].setMultiplierEnabled(enabled);
    }
}
