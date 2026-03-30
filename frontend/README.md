# 🚀 reToken Protocol - Frontend

A stunning, modern React frontend for the reToken Protocol with glassmorphism design, smooth animations, and exceptional UX.

## ✨ Features

- **Glassmorphism UI** with beautiful frosted glass effects
- **Animated Background** with dynamic gradient orbs
- **Smooth Animations** powered by Framer Motion
- **Token Swapping** with automatic reToken minting
- **6-Tier System** with volume-based progression
- **Staking & Rewards** with live accumulation
- **Real-time Stats** and balance tracking

## 🚀 Getting Started

```bash
npm install
npm run dev
```

Visit `http://localhost:5173` to see the magic! ✨

## Configuration
Create a `frontend/.env` file (use `frontend/.env.example` as a template) and set the deployed contract + pool parameters:
- `VITE_HOOK_ADDRESS`: your deployed `ReHook` address (with BEFORE_SWAP|AFTER_SWAP flags)
- `VITE_SWAP_ROUTER_ADDRESS`: Uniswap v4 `SwapRouter` address for your chain
- `VITE_TOKEN0_ADDRESS`, `VITE_TOKEN1_ADDRESS`: pool currencies (IMPORTANT: `TOKEN0_ADDRESS` must be numerically smaller than `TOKEN1_ADDRESS`)
- `VITE_POOL_FEE`, `VITE_TICK_SPACING`: your pool parameters

## 🎨 What Makes It Special

- Instant visual feedback on every action
- Real-time rewards counter
- Smooth tier progression animations
- Sparkles and glow effects everywhere
- Responsive on all devices

Built with React 18, Vite, and lots of love 💜
