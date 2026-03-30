import { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  Zap, 
  TrendingUp, 
  Coins, 
  Award, 
  ArrowRight, 
  Sparkles,
  Wallet,
  RefreshCw
} from 'lucide-react';
import { BrowserProvider, Contract, formatUnits, MaxUint256, parseUnits } from 'ethers';
import './App.css';
// Eslint's `no-unused-vars` sometimes doesn't understand `motion.*` usage in JSX tag names.
// This ensures the import is treated as used.
void motion;

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

// Must match `VolumeTracker` (Bronze/Silver/Gold/Platinum) thresholds in "token units".
const TIER_THRESHOLDS = [0, 100, 500, 2000];
const TIER_NAMES = ['Bronze', 'Silver', 'Gold', 'Platinum'];
const TIER_COLORS = [
  'from-orange-500 to-orange-700',
  'from-gray-400 to-gray-600',
  'from-yellow-400 to-yellow-600',
  'from-cyan-400 to-cyan-600'
];

const CONFIG = {
  chainId: Number(import.meta.env.VITE_CHAIN_ID ?? 0),
  hookAddress: import.meta.env.VITE_HOOK_ADDRESS ?? '',
  swapRouterAddress: import.meta.env.VITE_SWAP_ROUTER_ADDRESS ?? '',
  token0Address: import.meta.env.VITE_TOKEN0_ADDRESS ?? '',
  token1Address: import.meta.env.VITE_TOKEN1_ADDRESS ?? '',
  poolFee: Number(import.meta.env.VITE_POOL_FEE ?? 10000),
  tickSpacing: Number(import.meta.env.VITE_TICK_SPACING ?? 60),
  hookData: import.meta.env.VITE_HOOK_DATA ?? '0x'
};

const HAS_CONFIG = Boolean(
  CONFIG.hookAddress &&
  CONFIG.swapRouterAddress &&
  CONFIG.token0Address &&
  CONFIG.token1Address &&
  Number.isFinite(CONFIG.poolFee) &&
  Number.isFinite(CONFIG.tickSpacing)
);

// Minimal ABI surface for the frontend.
const ERC20_ABI = [
  'function name() view returns (string)',
  'function symbol() view returns (string)',
  'function decimals() view returns (uint8)',
  'function balanceOf(address owner) view returns (uint256)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function approve(address spender, uint256 value) returns (bool)'
];

const REHOOK_ABI = [
  'function getReToken(address currency) view returns (address)',
  'function getReStaking(address currency) view returns (address)',
  'function getUserVolume(address user) view returns (uint256 volume, uint8 tier, uint256 lastUpdate)',
  'function getUserMultiplier(address user) view returns (uint256)',
  'function getAccumulatedFees(address token) view returns (uint256)',
  'function getVolumeTracker() view returns (address)',
  'function getFeeCollector() view returns (address)'
];

const RESTAKING_ABI = [
  'function stakingToken() view returns (address)',
  'function getStakeInfo(address user) view returns (uint256 amount, uint256 pending, uint256 stakedAt)',
  'function stake(uint256 amount) external',
  'function unstake(uint256 amount) external',
  'function claimReward() external',
  'function pendingReward(address user) view returns (uint256)'
];

// Uniswap v4 `SwapRouter` ABI for the single-pool exact input swap call.
const SWAP_ROUTER_ABI = [
  {
    type: 'function',
    name: 'swapExactTokensForTokens',
    stateMutability: 'payable',
    inputs: [
      { name: 'amountIn', type: 'uint256' },
      { name: 'amountOutMin', type: 'uint256' },
      { name: 'zeroForOne', type: 'bool' },
      {
        name: 'poolKey',
        type: 'tuple',
        components: [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' }
        ]
      },
      { name: 'hookData', type: 'bytes' },
      { name: 'receiver', type: 'address' },
      { name: 'deadline', type: 'uint256' }
    ],
    outputs: [{ name: '', type: 'int256' }]
  }
];

function App() {
  const [activeTab, setActiveTab] = useState('swap');
  const [swapAmount, setSwapAmount] = useState('');
  const [stakeAmount, setStakeAmount] = useState('');
  const [isConnected, setIsConnected] = useState(false);
  const [address, setAddress] = useState('');

  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [txLoading, setTxLoading] = useState(false);
  const [error, setError] = useState('');

  const [token0Decimals, setToken0Decimals] = useState(18);

  const [reToken0Address, setReToken0Address] = useState(ZERO_ADDRESS);
  const [staking0Address, setStaking0Address] = useState(ZERO_ADDRESS);

  const [token0BalanceRaw, setToken0BalanceRaw] = useState(0n);
  const [reToken0BalanceRaw, setReToken0BalanceRaw] = useState(0n);
  const [stakedAmountRaw, setStakedAmountRaw] = useState(0n);
  const [pendingRewardsRaw, setPendingRewardsRaw] = useState(0n);
  
  const [userData, setUserData] = useState({
    token0Balance: 0,
    token1Balance: 0,
    reToken0Balance: 0,
    reToken1Balance: 0,
    volume: 0,
    tier: 0,
    stakedAmount: 0,
    pendingRewards: 0,
    feesCollected: 0,
    multiplier: 1
  });

  const hasReToken0 = reToken0Address !== ZERO_ADDRESS;
  const hasStaking0 = staking0Address !== ZERO_ADDRESS;

  const getCurrentTier = (volume) => {
    for (let i = TIER_THRESHOLDS.length - 1; i >= 0; i--) {
      if (volume >= TIER_THRESHOLDS[i]) return i;
    }
    return 0;
  };

  const getProgressToNextTier = (volume) => {
    const currentTier = getCurrentTier(volume);
    if (currentTier >= TIER_THRESHOLDS.length - 1) return 100;
    const current = TIER_THRESHOLDS[currentTier];
    const next = TIER_THRESHOLDS[currentTier + 1];
    return ((volume - current) / (next - current)) * 100;
  };

  const loadUserData = useCallback(async () => {
    if (!provider || !address) return;
    // If config is missing, treat it as a setup state (not an error).
    if (!HAS_CONFIG) return;

    setError('');
    try {
      if (CONFIG.token0Address.toLowerCase() >= CONFIG.token1Address.toLowerCase()) {
        setError('Invalid token order: set `VITE_TOKEN0_ADDRESS` to be numerically smaller than `VITE_TOKEN1_ADDRESS` (Uniswap V4 pool sorting).');
        return;
      }

      const hook = new Contract(CONFIG.hookAddress, REHOOK_ABI, provider);
      const token0 = new Contract(CONFIG.token0Address, ERC20_ABI, provider);
      const token1 = new Contract(CONFIG.token1Address, ERC20_ABI, provider);

      const [dec0, dec1] = await Promise.all([token0.decimals(), token1.decimals()]);
      setToken0Decimals(Number(dec0));

      const [token0Bal, token1Bal] = await Promise.all([
        token0.balanceOf(address),
        token1.balanceOf(address)
      ]);

      const [fee0, reToken0, reToken1, staking0, _staking1] = await Promise.all([
        hook.getAccumulatedFees(CONFIG.token0Address),
        hook.getReToken(CONFIG.token0Address),
        hook.getReToken(CONFIG.token1Address),
        hook.getReStaking(CONFIG.token0Address),
        hook.getReStaking(CONFIG.token1Address)
      ]);

      setReToken0Address(reToken0);
      setStaking0Address(staking0);

      let reToken0Bal = 0n;
      let reToken1Bal = 0n;
      if (reToken0 !== ZERO_ADDRESS) {
        const re0 = new Contract(reToken0, ERC20_ABI, provider);
        reToken0Bal = await re0.balanceOf(address);
      }
      if (reToken1 !== ZERO_ADDRESS) {
        const re1 = new Contract(reToken1, ERC20_ABI, provider);
        reToken1Bal = await re1.balanceOf(address);
      }

      let stakedAmount = 0n;
      let pendingRewards = 0n;
      if (staking0 !== ZERO_ADDRESS) {
        const staking0Contract = new Contract(staking0, RESTAKING_ABI, provider);
        const info = await staking0Contract.getStakeInfo(address);
        // Tuple return values can come back as array-like or named fields.
        stakedAmount = info.amount ?? info[0];
        pendingRewards = info.pending ?? info[1];
      }

      // Volume tracking key depends on how the swap router calls into the hook.
      // We display whichever key currently has larger volume.
      const volUser = await hook.getUserVolume(address);
      const userVolumeRaw = volUser.volume ?? volUser[0];
      const userTier = volUser.tier ?? volUser[1];

      const selectedVolumeRaw = userVolumeRaw;
      const selectedTier = Number(userTier);

      // `ReStaking` applies multipliers using the staker address (`msg.sender`).
      const multiplierBp = await hook.getUserMultiplier(address);

      setToken0BalanceRaw(token0Bal);
      setReToken0BalanceRaw(reToken0Bal);
      setStakedAmountRaw(stakedAmount);
      setPendingRewardsRaw(pendingRewards);

      setUserData({
        token0Balance: Number(formatUnits(token0Bal, dec0)),
        token1Balance: Number(formatUnits(token1Bal, dec1)),
        reToken0Balance: Number(formatUnits(reToken0Bal, dec0)),
        reToken1Balance: Number(formatUnits(reToken1Bal, dec1)),
        volume: Number(formatUnits(selectedVolumeRaw, dec0)),
        tier: selectedTier,
        stakedAmount: Number(formatUnits(stakedAmount, dec0)),
        pendingRewards: Number(formatUnits(pendingRewards, dec0)),
        feesCollected: Number(formatUnits(fee0, dec0)),
        multiplier: Number(multiplierBp) / 10000
      });
    } catch (e) {
      console.error(e);
      setError(e?.shortMessage || e?.message || 'Failed to read on-chain state.');
    }
  }, [provider, address]);

  const connectWallet = async () => {
    setError('');
    setTxLoading(false);
    try {
      if (!window.ethereum) {
        setError('No wallet detected. Install MetaMask or another EIP-1193 compatible wallet.');
        return;
      }
      // Allow wallet connection even if config is missing, so the UI doesn't look broken.

      const web3Provider = new BrowserProvider(window.ethereum);
      await web3Provider.send('eth_requestAccounts', []);
      const _signer = await web3Provider.getSigner();
      const _address = await _signer.getAddress();

      if (CONFIG.chainId && CONFIG.chainId !== 0) {
        const net = await web3Provider.getNetwork();
        if (Number(net.chainId) !== CONFIG.chainId) {
          setError(`Wrong network. Please switch to chainId=${CONFIG.chainId}. Current chainId=${Number(net.chainId)}.`);
          return;
        }
      }

      setProvider(web3Provider);
      setSigner(_signer);
      setAddress(_address);
      setIsConnected(true);
    } catch (e) {
      console.error(e);
      setError(e?.shortMessage || e?.message || 'Failed to connect wallet.');
    }
  };

  useEffect(() => {
    if (!provider || !address) return;
    loadUserData();
  }, [provider, address, loadUserData]);

  useEffect(() => {
    if (HAS_CONFIG) return;
    // Intentionally silent in UI; dev-only hint.
    console.warn(
      '[reToken frontend] Missing VITE_* config. Create `frontend/.env` from `.env.example` to enable on-chain reads/writes.'
    );
  }, []);

  const handleSwap = async () => {
    setError('');
    if (!signer || !provider || !isConnected) return;
    if (!swapAmount || Number(swapAmount) <= 0) return;
    if (!HAS_CONFIG) return;

    const amountIn = parseUnits(swapAmount, token0Decimals);
    if (amountIn <= 0n) return;
    if (amountIn > token0BalanceRaw) {
      setError('Insufficient TKNA balance for this swap.');
      return;
    }

    if (CONFIG.token0Address.toLowerCase() >= CONFIG.token1Address.toLowerCase()) {
      setError('Invalid token order in config. Ensure TOKEN0_ADDRESS < TOKEN1_ADDRESS.');
      return;
    }

    setTxLoading(true);
    try {
      const token0WithSigner = new Contract(CONFIG.token0Address, ERC20_ABI, signer);
      const swapRouter = new Contract(CONFIG.swapRouterAddress, SWAP_ROUTER_ABI, signer);

      const allowance = await token0WithSigner.allowance(address, CONFIG.swapRouterAddress);
      if (allowance < amountIn) {
        const approveTx = await token0WithSigner.approve(CONFIG.swapRouterAddress, MaxUint256);
        await approveTx.wait();
      }

      const poolKey = [CONFIG.token0Address, CONFIG.token1Address, CONFIG.poolFee, CONFIG.tickSpacing, CONFIG.hookAddress];
      const deadline = Math.floor(Date.now() / 1000) + 60 * 10;

      const tx = await swapRouter.swapExactTokensForTokens(
        amountIn,
        0,
        true,
        poolKey,
        CONFIG.hookData,
        address,
        deadline
      );
      await tx.wait();

      setSwapAmount('');
      await loadUserData();
    } catch (e) {
      console.error(e);
      setError(e?.shortMessage || e?.message || 'Swap failed.');
    } finally {
      setTxLoading(false);
    }
  };

  const handleStake = async () => {
    setError('');
    if (!signer || !provider || !isConnected) return;
    if (!stakeAmount || Number(stakeAmount) <= 0) return;
    if (!hasReToken0 || !hasStaking0) {
      setError('Staking pool is not available yet. The hook owner must create staking pools for your token.');
      return;
    }

    const amount = parseUnits(stakeAmount, token0Decimals);
    if (amount <= 0n) return;
    if (amount > reToken0BalanceRaw) {
      setError('Insufficient reTKNA balance for staking.');
      return;
    }

    setTxLoading(true);
    try {
      const reToken0WithSigner = new Contract(reToken0Address, ERC20_ABI, signer);
      const staking0 = new Contract(staking0Address, RESTAKING_ABI, signer);

      const allowance = await reToken0WithSigner.allowance(address, staking0Address);
      if (allowance < amount) {
        const approveTx = await reToken0WithSigner.approve(staking0Address, MaxUint256);
        await approveTx.wait();
      }

      const tx = await staking0.stake(amount);
      await tx.wait();

      setStakeAmount('');
      await loadUserData();
    } catch (e) {
      console.error(e);
      setError(e?.shortMessage || e?.message || 'Stake failed.');
    } finally {
      setTxLoading(false);
    }
  };

  const handleUnstake = async () => {
    setError('');
    if (!signer || !provider || !isConnected) return;
    if (!hasStaking0) return;
    if (stakedAmountRaw <= 0n) return;

    setTxLoading(true);
    try {
      const staking0 = new Contract(staking0Address, RESTAKING_ABI, signer);
      const tx = await staking0.unstake(stakedAmountRaw);
      await tx.wait();
      await loadUserData();
    } catch (e) {
      console.error(e);
      setError(e?.shortMessage || e?.message || 'Unstake failed.');
    } finally {
      setTxLoading(false);
    }
  };

  const handleClaimRewards = async () => {
    setError('');
    if (!signer || !provider || !isConnected) return;
    if (!hasStaking0) return;
    if (pendingRewardsRaw <= 0n) return;

    setTxLoading(true);
    try {
      const staking0 = new Contract(staking0Address, RESTAKING_ABI, signer);
      const tx = await staking0.claimReward();
      await tx.wait();
      await loadUserData();
    } catch (e) {
      console.error(e);
      setError(e?.shortMessage || e?.message || 'Claim failed.');
    } finally {
      setTxLoading(false);
    }
  };

  return (
    <div className="app">
      <div className="animated-bg">
        <div className="gradient-orb orb-1"></div>
        <div className="gradient-orb orb-2"></div>
        <div className="gradient-orb orb-3"></div>
      </div>

      <header className="header">
        <motion.div 
          className="logo"
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
        >
          <Sparkles className="logo-icon" />
          <h1>reToken Protocol</h1>
        </motion.div>
        
        <motion.button
          className={`connect-btn ${isConnected ? 'connected' : ''}`}
          onClick={connectWallet}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
        >
          <Wallet size={20} />
          {isConnected ? address : 'Connect Wallet'}
        </motion.button>
      </header>

      {error && (
        <div className="main-content">
          <div className="info-box" style={{ borderColor: 'rgba(239, 68, 68, 0.6)' }}>
            <p style={{ color: '#ef4444', fontWeight: 700 }}>Error</p>
            <p style={{ color: 'rgba(255,255,255,0.9)' }}>{error}</p>
          </div>
        </div>
      )}

      <main className="main-content">
        <motion.div 
          className="tier-card"
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
        >
          <div className="tier-header">
            <Award className="tier-icon" />
            <div>
              <h3>Your Tier</h3>
              <div className={`tier-badge bg-gradient-to-r ${TIER_COLORS[userData.tier]}`}>
                {TIER_NAMES[userData.tier]}
              </div>
            </div>
          </div>
          
          <div className="tier-progress">
            <div className="progress-info">
              <span>Volume: {userData.volume.toFixed(2)} TKNA</span>
              {userData.tier < TIER_THRESHOLDS.length - 1 && (
                <span>Next: {TIER_THRESHOLDS[userData.tier + 1]} TKNA</span>
              )}
            </div>
            <div className="progress-bar">
              <motion.div 
                className="progress-fill"
                initial={{ width: 0 }}
                animate={{ width: `${getProgressToNextTier(userData.volume)}%` }}
                transition={{ duration: 1, ease: "easeOut" }}
              />
            </div>
          </div>
        </motion.div>

        <div className="stats-grid">
          <motion.div 
            className="stat-card"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
          >
            <Coins className="stat-icon" />
            <div className="stat-content">
              <p className="stat-label">reToken Balance</p>
              <p className="stat-value">{userData.reToken0Balance.toFixed(2)} reTKNA</p>
            </div>
          </motion.div>

          <motion.div 
            className="stat-card"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3 }}
          >
            <TrendingUp className="stat-icon" />
            <div className="stat-content">
              <p className="stat-label">Staked Amount</p>
              <p className="stat-value">{userData.stakedAmount.toFixed(2)} reTKNA</p>
            </div>
          </motion.div>

          <motion.div 
            className="stat-card highlight"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4 }}
          >
            <Zap className="stat-icon" />
            <div className="stat-content">
              <p className="stat-label">Pending Rewards</p>
              <p className="stat-value">{userData.pendingRewards.toFixed(4)} TKNA</p>
            </div>
          </motion.div>
        </div>

        <div className="tabs">
          <button
            className={`tab ${activeTab === 'swap' ? 'active' : ''}`}
            onClick={() => setActiveTab('swap')}
          >
            <RefreshCw size={20} />
            Swap
          </button>
          <button
            className={`tab ${activeTab === 'stake' ? 'active' : ''}`}
            onClick={() => setActiveTab('stake')}
          >
            <TrendingUp size={20} />
            Stake
          </button>
        </div>

        <AnimatePresence mode="wait">
          {activeTab === 'swap' && (
            <motion.div
              key="swap"
              className="tab-content"
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: 20 }}
            >
              <div className="swap-card glass-card">
                <h2>Swap Tokens</h2>
                <p className="subtitle">Swap TKNA for TKNB and earn reTokens</p>

                <div className="input-group">
                  <label>From</label>
                  <div className="token-input">
                    <input
                      type="number"
                      value={swapAmount}
                      onChange={(e) => setSwapAmount(e.target.value)}
                      placeholder="0.0"
                    />
                    <div className="token-badge">
                      <span>TKNA</span>
                    </div>
                  </div>
                  <div className="balance">Balance: {userData.token0Balance.toFixed(2)} TKNA</div>
                </div>

                <div className="swap-arrow">
                  <ArrowRight />
                </div>

                <div className="input-group">
                  <label>To (estimated)</label>
                  <div className="token-input">
                    <input
                      type="number"
                      value={swapAmount ? (parseFloat(swapAmount) * 0.99).toFixed(4) : ''}
                      disabled
                      placeholder="0.0"
                    />
                    <div className="token-badge">
                      <span>TKNB</span>
                    </div>
                  </div>
                </div>

                {swapAmount && (
                  <motion.div 
                    className="rewards-preview"
                    initial={{ opacity: 0, height: 0 }}
                    animate={{ opacity: 1, height: 'auto' }}
                  >
                    <Sparkles size={16} />
                    <span>You will receive {swapAmount} reTKNA + {(parseFloat(swapAmount) * 0.99).toFixed(4)} reTKNB</span>
                  </motion.div>
                )}

                <motion.button
                  className="primary-btn"
                  onClick={handleSwap}
                  disabled={
                    !swapAmount ||
                    Number(swapAmount) <= 0 ||
                    !isConnected ||
                    !HAS_CONFIG ||
                    txLoading
                  }
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                >
                  {txLoading ? 'Submitting...' : 'Swap Now'}
                </motion.button>

                <div className="info-box">
                  <p><strong>Fee:</strong> 1% ({(parseFloat(swapAmount || 0) * 0.01).toFixed(2)} TKNA)</p>
                  <p><strong>Volume Added:</strong> {swapAmount || '0'} TKNA</p>
                </div>
              </div>
            </motion.div>
          )}

          {activeTab === 'stake' && (
            <motion.div
              key="stake"
              className="tab-content"
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -20 }}
            >
              <div className="stake-card glass-card">
                <h2>Stake reTokens</h2>
                <p className="subtitle">Stake your reTokens to earn rewards</p>

                <div className="input-group">
                  <label>Amount to Stake</label>
                  <div className="token-input">
                    <input
                      type="number"
                      value={stakeAmount}
                      onChange={(e) => setStakeAmount(e.target.value)}
                      placeholder="0.0"
                    />
                    <div className="token-badge">
                      <span>reTKNA</span>
                    </div>
                  </div>
                  <div className="balance">Available: {userData.reToken0Balance.toFixed(2)} reTKNA</div>
                </div>

                <motion.button
                  className="primary-btn"
                  onClick={handleStake}
                  disabled={
                    !stakeAmount ||
                    Number(stakeAmount) <= 0 ||
                    !isConnected ||
                    !HAS_CONFIG ||
                    txLoading ||
                    !hasReToken0 ||
                    !hasStaking0
                  }
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                >
                  {txLoading ? 'Submitting...' : 'Stake Tokens'}
                </motion.button>

                {userData.stakedAmount > 0 && (
                  <motion.div
                    className="staking-info"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                  >
                    <div className="info-row">
                      <span>Currently Staked:</span>
                      <strong>{userData.stakedAmount.toFixed(2)} reTKNA</strong>
                    </div>
                    <div className="info-row highlight">
                      <span>Pending Rewards:</span>
                      <strong>{userData.pendingRewards.toFixed(4)} TKNA</strong>
                    </div>
                    
                    <div className="action-buttons">
                      <motion.button
                        className="secondary-btn"
                        onClick={handleUnstake}
                        whileHover={{ scale: 1.02 }}
                        whileTap={{ scale: 0.98 }}
                      >
                        Unstake All
                      </motion.button>
                      <motion.button
                        className="primary-btn"
                        onClick={handleClaimRewards}
                        disabled={userData.pendingRewards <= 0}
                        whileHover={{ scale: 1.02 }}
                        whileTap={{ scale: 0.98 }}
                      >
                        Claim Rewards
                      </motion.button>
                    </div>
                  </motion.div>
                )}

                <div className="info-box">
                  <p><strong>APY:</strong> ~45% (variable)</p>
                  <p><strong>Multiplier:</strong> {userData.multiplier.toFixed(2)}x ({TIER_NAMES[userData.tier]})</p>
                  <p><strong>Total Fees Collected:</strong> {userData.feesCollected.toFixed(4)} TKNA</p>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        <motion.div 
          className="footer-stats"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.5 }}
        >
          <div className="footer-stat">
            <span className="label">Total Volume</span>
            <span className="value">{userData.volume.toFixed(2)} TKNA</span>
          </div>
          <div className="footer-stat">
            <span className="label">Your Tier</span>
            <span className="value">{TIER_NAMES[userData.tier]}</span>
          </div>
          <div className="footer-stat">
            <span className="label">Fees Collected</span>
            <span className="value">{userData.feesCollected.toFixed(4)} TKNA</span>
          </div>
        </motion.div>
      </main>
    </div>
  );
}

export default App;
