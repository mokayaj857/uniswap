// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VolumeTracker is Ownable {
    struct UserVolume {
        uint256 totalVolume;
        uint256 lastUpdateTime;
        uint8 tier;
    }

    mapping(address => UserVolume) public userVolumes;
    
    uint256 public constant DECAY_PERIOD = 30 days;
    uint256 public constant DECAY_RATE = 10; // 10% decay per period
    
    // Tier thresholds in wei
    uint256 public constant BRONZE_THRESHOLD = 0;
    uint256 public constant SILVER_THRESHOLD = 100 ether;
    uint256 public constant GOLD_THRESHOLD = 500 ether;
    uint256 public constant PLATINUM_THRESHOLD = 2000 ether;
    
    // Multipliers (in basis points, 10000 = 1.0x)
    uint256 public constant BRONZE_MULTIPLIER = 10000;   // 1.0x
    uint256 public constant SILVER_MULTIPLIER = 12500;   // 1.25x
    uint256 public constant GOLD_MULTIPLIER = 15000;     // 1.5x
    uint256 public constant PLATINUM_MULTIPLIER = 20000; // 2.0x

    event VolumeUpdated(address indexed user, uint256 newVolume, uint8 tier);
    event TierUpgraded(address indexed user, uint8 oldTier, uint8 newTier);
    event VolumeDecayed(address indexed user, uint256 oldVolume, uint256 newVolume);

    constructor() Ownable(msg.sender) {}

    function updateVolume(address user, uint256 amount) external onlyOwner {
        UserVolume storage userVol = userVolumes[user];
        
        // Apply decay if needed
        if (userVol.lastUpdateTime > 0) {
            uint256 timeSinceLastUpdate = block.timestamp - userVol.lastUpdateTime;
            if (timeSinceLastUpdate >= DECAY_PERIOD) {
                uint256 decayPeriods = timeSinceLastUpdate / DECAY_PERIOD;
                uint256 decayAmount = (userVol.totalVolume * DECAY_RATE * decayPeriods) / 100;
                
                if (decayAmount >= userVol.totalVolume) {
                    userVol.totalVolume = 0;
                } else {
                    uint256 oldVolume = userVol.totalVolume;
                    userVol.totalVolume -= decayAmount;
                    emit VolumeDecayed(user, oldVolume, userVol.totalVolume);
                }
            }
        }
        
        uint8 oldTier = userVol.tier;
        userVol.totalVolume += amount;
        userVol.lastUpdateTime = block.timestamp;
        
        // Calculate new tier
        uint8 newTier = _calculateTier(userVol.totalVolume);
        
        if (newTier != oldTier) {
            userVol.tier = newTier;
            emit TierUpgraded(user, oldTier, newTier);
        }
        
        emit VolumeUpdated(user, userVol.totalVolume, userVol.tier);
    }

    function getUserVolume(address user) external view returns (uint256 volume, uint8 tier, uint256 lastUpdate) {
        UserVolume memory userVol = userVolumes[user];
        
        // Calculate decayed volume for view function
        uint256 currentVolume = userVol.totalVolume;
        if (userVol.lastUpdateTime > 0) {
            uint256 timeSinceLastUpdate = block.timestamp - userVol.lastUpdateTime;
            if (timeSinceLastUpdate >= DECAY_PERIOD) {
                uint256 decayPeriods = timeSinceLastUpdate / DECAY_PERIOD;
                uint256 decayAmount = (currentVolume * DECAY_RATE * decayPeriods) / 100;
                
                if (decayAmount >= currentVolume) {
                    currentVolume = 0;
                } else {
                    currentVolume -= decayAmount;
                }
            }
        }
        
        return (currentVolume, _calculateTier(currentVolume), userVol.lastUpdateTime);
    }

    function getMultiplier(address user) external view returns (uint256) {
        (uint256 volume, , ) = this.getUserVolume(user);
        uint8 tier = _calculateTier(volume);
        return _getTierMultiplier(tier);
    }

    function _calculateTier(uint256 volume) internal pure returns (uint8) {
        if (volume >= PLATINUM_THRESHOLD) {
            return 3; // Platinum
        } else if (volume >= GOLD_THRESHOLD) {
            return 2; // Gold
        } else if (volume >= SILVER_THRESHOLD) {
            return 1; // Silver
        } else {
            return 0; // Bronze
        }
    }

    function _getTierMultiplier(uint8 tier) internal pure returns (uint256) {
        if (tier == 3) {
            return PLATINUM_MULTIPLIER;
        } else if (tier == 2) {
            return GOLD_MULTIPLIER;
        } else if (tier == 1) {
            return SILVER_MULTIPLIER;
        } else {
            return BRONZE_MULTIPLIER;
        }
    }

    function getTierName(uint8 tier) public pure returns (string memory) {
        if (tier == 3) return "Platinum";
        if (tier == 2) return "Gold";
        if (tier == 1) return "Silver";
        return "Bronze";
    }

    function getTierThresholds() external pure returns (uint256, uint256, uint256, uint256) {
        return (BRONZE_THRESHOLD, SILVER_THRESHOLD, GOLD_THRESHOLD, PLATINUM_THRESHOLD);
    }

    function getTierMultipliers() external pure returns (uint256, uint256, uint256, uint256) {
        return (BRONZE_MULTIPLIER, SILVER_MULTIPLIER, GOLD_MULTIPLIER, PLATINUM_MULTIPLIER);
    }
}
