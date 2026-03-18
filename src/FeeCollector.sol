// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FeeCollector is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct FeePool {
        uint256 accumulatedFees;
        uint256 distributedFees;
        uint256 lastDistributionTime;
        uint256 totalCollected;
    }

    mapping(address => FeePool) public feePools;
    
    uint256 public feePercentage = 10; // 0.1% of swap amount (10 basis points)
    uint256 public constant MAX_FEE_PERCENTAGE = 100; // 1% max
    uint256 public constant BASIS_POINTS = 10000;

    event FeeCollected(address indexed token, uint256 amount, address indexed from);
    event FeeDistributed(address indexed token, address indexed to, uint256 amount);
    event FeePercentageUpdated(uint256 oldPercentage, uint256 newPercentage);

    constructor() Ownable(msg.sender) {}

    function collectFee(address token, uint256 swapAmount, address from) external onlyOwner returns (uint256 feeAmount) {
        feeAmount = (swapAmount * feePercentage) / BASIS_POINTS;
        
        if (feeAmount == 0) {
            return 0;
        }

        FeePool storage pool = feePools[token];
        pool.accumulatedFees += feeAmount;
        pool.totalCollected += feeAmount;
        pool.lastDistributionTime = block.timestamp;

        emit FeeCollected(token, feeAmount, from);
        
        return feeAmount;
    }

    function recordFeeCollection(address token, uint256 feeAmount) external onlyOwner {
        if (feeAmount == 0) {
            return;
        }

        FeePool storage pool = feePools[token];
        pool.accumulatedFees += feeAmount;
        pool.totalCollected += feeAmount;
        
        emit FeeCollected(token, feeAmount, msg.sender);
    }

    function distributeFees(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        FeePool storage pool = feePools[token];
        require(pool.accumulatedFees >= amount, "Insufficient accumulated fees");
        
        pool.accumulatedFees -= amount;
        pool.distributedFees += amount;
        pool.lastDistributionTime = block.timestamp;

        IERC20(token).safeTransfer(to, amount);
        
        emit FeeDistributed(token, to, amount);
    }

    function getAccumulatedFees(address token) external view returns (uint256) {
        return feePools[token].accumulatedFees;
    }

    function getDistributedFees(address token) external view returns (uint256) {
        return feePools[token].distributedFees;
    }

    function getTotalCollected(address token) external view returns (uint256) {
        return feePools[token].totalCollected;
    }

    function getFeePoolInfo(address token) external view returns (
        uint256 accumulated,
        uint256 distributed,
        uint256 lastDistribution,
        uint256 totalCollected
    ) {
        FeePool memory pool = feePools[token];
        return (
            pool.accumulatedFees,
            pool.distributedFees,
            pool.lastDistributionTime,
            pool.totalCollected
        );
    }

    function setFeePercentage(uint256 newPercentage) external onlyOwner {
        require(newPercentage <= MAX_FEE_PERCENTAGE, "Fee percentage too high");
        
        uint256 oldPercentage = feePercentage;
        feePercentage = newPercentage;
        
        emit FeePercentageUpdated(oldPercentage, newPercentage);
    }

    function withdrawFees(address token, uint256 amount) external onlyOwner {
        FeePool storage pool = feePools[token];
        require(pool.accumulatedFees >= amount, "Insufficient fees");
        
        pool.accumulatedFees -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function estimateFee(uint256 swapAmount) external view returns (uint256) {
        return (swapAmount * feePercentage) / BASIS_POINTS;
    }
}
