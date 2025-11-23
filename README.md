# 🌌 UUPSToken V2 - Sultry Dark-Neon Cyberpunk Frontend

A stunning, anime-cyberpunk inspired Next.js frontend for interacting with UUPSTokenV2 ERC-20 smart contract on Arbitrum. Features a 3D glowing orb that pulses with token supply, glassmorphism UI, particle effects, and seamless wallet integration.

## ✨ Features

- 🎨 **Dark Neon Anime-Cyberpunk UI** - Stunning visual design with glassmorphism cards
- 🌐 **3D Glowing Orb** - Interactive Three.js visualization that pulses with totalSupply and tightens when tokens burn
- 💫 **Particle Trail Effects** - Dynamic particle system that follows cursor movement
- 🔗 **Wallet Integration** - Connect with MetaMask, WalletConnect, and other wagmi-supported wallets
- 💰 **Token Operations** - Mint, burn, and transfer tokens with real-time transaction notifications
- 👑 **Governor Detection** - Automatically detects contract owner and displays crown icon
- 🔊 **Interactive Audio** - Moaning hover sound effect on mint button (21+ warning)
- 📱 **Mobile Responsive** - Fully responsive design that works on all devices
- ⚡ **60fps Performance** - Optimized animations and rendering for smooth experience
- 🚀 **Vercel Ready** - Pre-configured for seamless deployment

## 🛠️ Tech Stack

- **Next.js 16** - React framework with App Router
- **TypeScript** - Type-safe development
- **wagmi** - React Hooks for Ethereum
- **viem** - TypeScript Ethereum library
- **Three.js** - 3D graphics library
- **@react-three/fiber & @react-three/drei** - React renderer for Three.js
- **Framer Motion** - Animation library
- **Tailwind CSS** - Utility-first CSS framework
- **React Hot Toast** - Beautiful toast notifications

## 🚀 Getting Started

### Prerequisites

- Node.js 18+ installed
- MetaMask or compatible Web3 wallet
- UUPSTokenV2 contract deployed on Arbitrum

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

3. Configure environment variables:
```bash
cp .env.example .env.local
```

Edit `.env.local` and add your configuration:
```env
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_project_id_here
NEXT_PUBLIC_CONTRACT_ADDRESS=0xYourContractAddressHere
```

4. Run the development server:
```bash
npm run dev
```

5. Open [http://localhost:3000](http://localhost:3000) in your browser

## 📦 Build & Deploy

### Build for Production

```bash
npm run build
npm start
```

### Deploy to Vercel

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/zkaedii/playground-zkaedi)

1. Push your code to GitHub
2. Import your repository in Vercel
3. Add environment variables in Vercel dashboard
4. Deploy!

## 🎮 How to Use

1. **Connect Wallet** - Click on the wallet connect button and choose your preferred wallet
2. **View Token Info** - See total supply, your balance, and contract details
3. **Mint Tokens** - Enter amount and click MINT (with special hover sound effect)
4. **Burn Tokens** - Enter amount and click BURN to destroy tokens
5. **Transfer Tokens** - Enter recipient address, amount, and click SEND
6. **Watch the Orb** - The 3D orb responds to totalSupply changes in real-time

## 🎨 Customization

### Changing Colors

Edit `app/globals.css` to customize the neon color scheme:
```css
--color-neon-pink: #ff0080;
--color-neon-cyan: #00ffff;
--color-neon-purple: #8000ff;
```

### Adjusting 3D Orb

Modify `components/GlowingOrb.tsx` to change:
- Scale behavior based on supply
- Particle count and distribution
- Shader colors and effects
- Animation speed

### Audio Effects

Replace `public/moan.mp3` with your preferred audio file for button hover effect.

## 🔧 Contract Configuration

The app expects a UUPS-upgradeable ERC-20 contract with these functions:
- `name()` - Token name
- `symbol()` - Token symbol
- `totalSupply()` - Total token supply
- `balanceOf(address)` - Get balance
- `mint(address, uint256)` - Mint tokens
- `burn(uint256)` - Burn tokens
- `transfer(address, uint256)` - Transfer tokens
- `owner()` - Contract owner/governor

Update `lib/contract.ts` if your contract ABI differs.

## 📱 Mobile Experience

The application is fully responsive and optimized for mobile devices:
- Touch-friendly controls
- Responsive grid layouts
- Optimized 3D performance on mobile GPUs
- Smooth scroll and interactions

## ⚠️ Content Warning

This application includes mature audio effects (moaning sound on hover). Intended for users 21+.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is open source and available under the MIT License.

## 🙏 Acknowledgments

- Built with ❤️ using Next.js, wagmi, and Three.js
- Inspired by anime and cyberpunk aesthetics
- Particle effects and glassmorphism design trends

## 📞 Support

For issues or questions:
- Open an issue on GitHub
- Check existing documentation
- Review wagmi and viem docs for wallet integration

---

**⚡ Powered by Arbitrum** | **🎨 Designed for the Future** | **💎 Built with Modern Web3**
