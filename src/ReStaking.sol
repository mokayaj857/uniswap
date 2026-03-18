// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReToken} from "./ReToken.sol";
import {VolumeTracker} from "./VolumeTracker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract ReStaking is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 stakedAt;
    }

    struct PoolInfo {
        IERC20 rewardToken;
        uint256 rewardPerSecond;
        uint256 totalStaked;
        uint256 accRewardPerToken;
        uint256 lastRewardTime;
        uint256 rewardBalance;
    }

    ReToken public immutable stakingToken;
    PoolInfo public poolInfo;
    VolumeTracker public volumeTracker;
    
    mapping(address => StakeInfo) public stakes;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant BASIS_POINTS = 10000;
    
    bool public multiplierEnabled = false;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward, uint256 multiplier);
    event RewardDeposited(uint256 amount);
    event RewardRateUpdated(uint256 newRate);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event MultiplierEnabled(bool enabled);
    event VolumeTrackerUpdated(address indexed newTracker);

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardPerSecond
    ) Ownable(msg.sender) {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_rewardToken != address(0), "Invalid reward token");
        
        stakingToken = ReToken(_stakingToken);
        
        poolInfo = PoolInfo({
            rewardToken: IERC20(_rewardToken),
            rewardPerSecond: _rewardPerSecond,
            totalStaked: 0,
            accRewardPerToken: 0,
            lastRewardTime: block.timestamp,
            rewardBalance: 0
        });
    }

    function updatePool() public {
        if (block.timestamp <= poolInfo.lastRewardTime) {
            return;
        }

        if (poolInfo.totalStaked == 0) {
            poolInfo.lastRewardTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
        uint256 reward = timeElapsed * poolInfo.rewardPerSecond;

        if (reward > poolInfo.rewardBalance) {
            reward = poolInfo.rewardBalance;
        }

        if (reward > 0) {
            poolInfo.accRewardPerToken += (reward * PRECISION) / poolInfo.totalStaked;
            poolInfo.rewardBalance -= reward;
        }

        poolInfo.lastRewardTime = block.timestamp;
    }

    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot stake 0");
        
        updatePool();

        StakeInfo storage userStake = stakes[msg.sender];

        if (userStake.amount > 0) {
            uint256 pending = _pendingReward(msg.sender);
            if (pending > 0) {
                // Apply multiplier if enabled
                uint256 finalReward = pending;
                uint256 multiplier = BASIS_POINTS;
                
                if (multiplierEnabled && address(volumeTracker) != address(0)) {
                    multiplier = volumeTracker.getMultiplier(msg.sender);
                    finalReward = (pending * multiplier) / BASIS_POINTS;
                }
                
                _safeRewardTransfer(msg.sender, finalReward);
                emit RewardClaimed(msg.sender, finalReward, multiplier);
            }
        }

        stakingToken.transferFrom(msg.sender, address(this), amount);
        
        userStake.amount += amount;
        userStake.rewardDebt = (userStake.amount * poolInfo.accRewardPerToken) / PRECISION;
        
        if (userStake.stakedAt == 0) {
            userStake.stakedAt = block.timestamp;
        }

        poolInfo.totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.amount >= amount, "Insufficient staked amount");
        require(amount > 0, "Cannot unstake 0");

        updatePool();

        uint256 pending = _pendingReward(msg.sender);
        if (pending > 0) {
            // Apply multiplier if enabled
            uint256 finalReward = pending;
            uint256 multiplier = BASIS_POINTS;
            
            if (multiplierEnabled && address(volumeTracker) != address(0)) {
                multiplier = volumeTracker.getMultiplier(msg.sender);
                finalReward = (pending * multiplier) / BASIS_POINTS;
            }
            
            _safeRewardTransfer(msg.sender, finalReward);
            emit RewardClaimed(msg.sender, finalReward, multiplier);
        }

        userStake.amount -= amount;
        userStake.rewardDebt = (userStake.amount * poolInfo.accRewardPerToken) / PRECISION;

        if (userStake.amount == 0) {
            userStake.stakedAt = 0;
        }

        poolInfo.totalStaked -= amount;
        stakingToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function claimReward() external nonReentrant {
        updatePool();

        uint256 pending = _pendingReward(msg.sender);
        require(pending > 0, "No rewards to claim");

        StakeInfo storage userStake = stakes[msg.sender];
        
        // Apply multiplier if enabled
        uint256 finalReward = pending;
        uint256 multiplier = BASIS_POINTS; // Default 1.0x
        
        if (multiplierEnabled && address(volumeTracker) != address(0)) {
            multiplier = volumeTracker.getMultiplier(msg.sender);
            finalReward = (pending * multiplier) / BASIS_POINTS;
        }
        
        userStake.rewardDebt = (userStake.amount * poolInfo.accRewardPerToken) / PRECISION;

        _safeRewardTransfer(msg.sender, finalReward);
        emit RewardClaimed(msg.sender, finalReward, multiplier);
    }

    function pendingReward(address user) external view returns (uint256) {
        StakeInfo memory userStake = stakes[user];
        
        if (userStake.amount == 0) {
            return 0;
        }

        uint256 accRewardPerToken = poolInfo.accRewardPerToken;
        
        if (block.timestamp > poolInfo.lastRewardTime && poolInfo.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
            uint256 reward = timeElapsed * poolInfo.rewardPerSecond;
            
            if (reward > poolInfo.rewardBalance) {
                reward = poolInfo.rewardBalance;
            }
            
            accRewardPerToken += (reward * PRECISION) / poolInfo.totalStaked;
        }

        uint256 baseReward = (userStake.amount * accRewardPerToken) / PRECISION - userStake.rewardDebt;
        
        // Apply multiplier if enabled
        if (multiplierEnabled && address(volumeTracker) != address(0)) {
            uint256 multiplier = volumeTracker.getMultiplier(user);
            return (baseReward * multiplier) / BASIS_POINTS;
        }
        
        return baseReward;
    }

    function depositReward(uint256 amount) external onlyOwner {
        require(amount > 0, "Cannot deposit 0");
        
        poolInfo.rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        poolInfo.rewardBalance += amount;
        
        emit RewardDeposited(amount);
    }

    function setRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        updatePool();
        poolInfo.rewardPerSecond = _rewardPerSecond;
        emit RewardRateUpdated(_rewardPerSecond);
    }

    function emergencyWithdraw() external nonReentrant {
        StakeInfo storage userStake = stakes[msg.sender];
        uint256 amount = userStake.amount;
        
        require(amount > 0, "No staked amount");

        poolInfo.totalStaked -= amount;
        
        userStake.amount = 0;
        userStake.rewardDebt = 0;
        userStake.stakedAt = 0;

        stakingToken.transfer(msg.sender, amount);
        
        emit EmergencyWithdraw(msg.sender, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawExcessRewards(uint256 amount) external onlyOwner {
        require(amount <= poolInfo.rewardBalance, "Insufficient reward balance");
        
        poolInfo.rewardBalance -= amount;
        poolInfo.rewardToken.safeTransfer(msg.sender, amount);
    }

    function _pendingReward(address user) internal view returns (uint256) {
        StakeInfo memory userStake = stakes[user];
        
        if (userStake.amount == 0) {
            return 0;
        }

        return (userStake.amount * poolInfo.accRewardPerToken) / PRECISION - userStake.rewardDebt;
    }

    function _safeRewardTransfer(address to, uint256 amount) internal {
        uint256 balance = poolInfo.rewardToken.balanceOf(address(this));
        
        if (amount > balance) {
            poolInfo.rewardToken.safeTransfer(to, balance);
        } else {
            poolInfo.rewardToken.safeTransfer(to, amount);
        }
    }

    function getStakeInfo(address user) external view returns (
        uint256 amount,
        uint256 pending,
        uint256 stakedAt
    ) {
        StakeInfo memory userStake = stakes[user];
        amount = userStake.amount;
        stakedAt = userStake.stakedAt;
        
        if (userStake.amount == 0) {
            pending = 0;
        } else {
            uint256 accRewardPerToken = poolInfo.accRewardPerToken;
            
            if (block.timestamp > poolInfo.lastRewardTime && poolInfo.totalStaked > 0) {
                uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
                uint256 reward = timeElapsed * poolInfo.rewardPerSecond;
                
                if (reward > poolInfo.rewardBalance) {
                    reward = poolInfo.rewardBalance;
                }
                
                accRewardPerToken += (reward * PRECISION) / poolInfo.totalStaked;
            }

            uint256 baseReward = (userStake.amount * accRewardPerToken) / PRECISION - userStake.rewardDebt;
            
            // Apply multiplier if enabled
            if (multiplierEnabled && address(volumeTracker) != address(0)) {
                uint256 multiplier = volumeTracker.getMultiplier(user);
                pending = (baseReward * multiplier) / BASIS_POINTS;
            } else {
                pending = baseReward;
            }
        }
    }
    
    function setVolumeTracker(address _volumeTracker) external onlyOwner {
        require(_volumeTracker != address(0), "Invalid volume tracker");
        volumeTracker = VolumeTracker(_volumeTracker);
        emit VolumeTrackerUpdated(_volumeTracker);
    }
    
    function setMultiplierEnabled(bool _enabled) external onlyOwner {
        multiplierEnabled = _enabled;
        emit MultiplierEnabled(_enabled);
    }
    
    function getMultiplier(address user) external view returns (uint256) {
        if (!multiplierEnabled || address(volumeTracker) == address(0)) {
            return BASIS_POINTS; // 1.0x
        }
        return volumeTracker.getMultiplier(user);
    }
}
