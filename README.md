# The Orb - UUPSTokenV2 Visualization 🌀

A hypnotic 3D dark-neon orb visualization that represents the token supply of UUPSTokenV2 on Arbitrum One. The orb visually reacts to token burns with stunning animations and immersive audio effects.

## ✨ Features

- **Real-time Supply Visualization**: The orb's size dynamically reflects the ratio of current supply to max supply
- **On-chain Burn Detection**: Listens for Transfer events to address(0) and triggers visual effects within <1s
- **Cyberpunk Aesthetics**: Dark background with electric magenta/cyan rim lighting and subtle scanline effects
- **Burn Animation Suite**:
  - Smooth shrinking animation
  - Crimson particle explosion
  - Shockwave effect
  - Low-frequency audio "moan" (intensity scaled to burn amount)
- **Interactive Elements**: Orb pulses in response to mouse movement
- **Glassmorphism HUD**: Live display of totalSupply, maxSupply, and connection status
- **Mobile Ready**: Optimized for touch and mobile displays

## 🛠 Tech Stack

- **Next.js 14** (App Router)
- **React Three Fiber** (@react-three/fiber + @react-three/drei)
- **Three.js** - 3D graphics and custom GLSL shaders
- **wagmi + viem** - Arbitrum One blockchain integration
- **Tailwind CSS** - Styling and glassmorphism effects
- **Web Audio API** - Synthetic sound generation
- **TypeScript** - Type safety throughout

## 🚀 Getting Started

### Prerequisites

- Node.js 18+ 
- npm or yarn
- A deployed UUPSTokenV2 contract on Arbitrum One

### Installation

1. Clone the repository:
```bash
git clone https://github.com/zkaedii/playground-zkaedi.git
cd playground-zkaedi
```

2. Install dependencies:
```bash
npm install
```

3. Configure your contract address:
```bash
cp .env.example .env.local
```

Edit `.env.local` and set your contract address:
```
NEXT_PUBLIC_CONTRACT_ADDRESS=0xYourContractAddressHere
```

4. Run the development server:
```bash
npm run dev
```

5. Open [http://localhost:3000](http://localhost:3000) to see the orb come alive!

## 📦 Build for Production

```bash
npm run build
npm start
```

## 🚢 Deploy to Vercel

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/zkaedii/playground-zkaedi)

1. Push your code to GitHub
2. Import your repository in Vercel
3. Add the `NEXT_PUBLIC_CONTRACT_ADDRESS` environment variable
4. Deploy!

Alternatively, use the Vercel CLI:
```bash
npm install -g vercel
vercel
```

## 🎨 Architecture

```
├── app/
│   ├── globals.css       # Global styles and dark theme
│   ├── layout.tsx        # Root layout
│   └── page.tsx          # Main entry point
├── components/
│   ├── OrbVisualization.tsx  # Main container with wagmi provider
│   ├── OrbScene.tsx          # Three.js scene setup
│   ├── Orb.tsx               # Main orb with custom shaders
│   ├── BurnParticles.tsx     # Particle system for burn effects
│   └── HUD.tsx               # Glassmorphism overlay UI
└── lib/
    ├── wagmi.ts          # Wagmi configuration
    ├── contract.ts       # Contract ABI and address
    └── soundManager.ts   # Audio synthesis
```

## 🎮 How It Works

1. **Supply Reading**: Uses wagmi's `useReadContract` to fetch `totalSupply()` and `maxSupply()` from the contract
2. **Event Listening**: `useWatchContractEvent` monitors Transfer events where `to === address(0)`
3. **Visual Mapping**: Orb radius = (currentSupply / maxSupply) * scale factor
4. **Burn Reaction**: 
   - Shader uniform `burnIntensity` spikes to 1.0
   - Particles spawn at orb surface and explode outward
   - Audio oscillator plays with volume proportional to burn amount
   - Scale smoothly animates to new target over ~1 second

## 🎯 Success Criteria Met

✅ Orb visually reacts within <1s of any burn on-chain  
✅ Cyberpunk aesthetics: dark background, magenta/cyan lighting, scanlines  
✅ Mobile-ready responsive design  
✅ Real-time blockchain connection via wagmi  
✅ Custom GLSL shaders for neon glow and heat distortion  
✅ Particle effects and audio synthesis  
✅ Glassmorphism HUD with live supply data  
✅ Production build ready for Vercel deployment  

## 📝 Contract Interface

The orb expects a contract with:

```solidity
function totalSupply() external view returns (uint256);
function maxSupply() external view returns (uint256);
event Transfer(address indexed from, address indexed to, uint256 value);
```

Burns are detected when `Transfer` events have `to == address(0)`.

## 🤝 Contributing

Contributions are welcome! Feel free to open issues or submit PRs.

## 📄 License

MIT License - see LICENSE file for details

---

Built with 💜 by the zkAedi team. Ready for Phase 2: The mint/claim interface.
