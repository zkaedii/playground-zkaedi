# The Orb - Usage Guide

## Quick Start

### 1. Prerequisites
- Node.js 18 or higher
- A deployed UUPSTokenV2 contract on Arbitrum One
- Your contract must implement:
  - `totalSupply()` - returns current supply
  - `maxSupply()` - returns maximum supply
  - `Transfer` event - emits when tokens are transferred

### 2. Configuration

Create a `.env.local` file in the root directory:

```bash
NEXT_PUBLIC_CONTRACT_ADDRESS=0xYourContractAddressHere
```

Replace `0xYourContractAddressHere` with your actual UUPSTokenV2 contract address on Arbitrum One.

### 3. Development

```bash
# Install dependencies
npm install

# Run development server
npm run dev

# Open http://localhost:3000
```

### 4. Production Build

```bash
# Build for production
npm run build

# Start production server
npm start
```

## Features Explained

### Visual Elements

#### The Orb
- **Size**: The orb's radius is dynamically calculated based on the supply ratio (currentSupply / maxSupply)
- **Colors**: Electric magenta (#ff00ff) and cyan (#00ffff) rim lighting
- **Animation**: Gentle rotation and pulse effect based on mouse movement
- **Interaction**: Responds to mouse position for interactive pulse effect

#### HUD (Heads-Up Display)
- **Top Center**: Title and connection status
- **Bottom Left**: Supply statistics
  - Total Supply: Current circulating supply
  - Max Supply: Maximum possible supply
  - Supply Ratio: Percentage of supply in circulation
- **Bottom Right**: Live connection status indicator

### Burn Detection

The orb listens for `Transfer` events where the recipient is the zero address (`0x0000...0000`), which indicates a burn.

When a burn is detected:
1. **Visual Effect**: The orb shrinks with a smooth animation
2. **Particle System**: Red/crimson particles explode outward from the orb
3. **Shader Effect**: Burn intensity uniform spikes, creating a red tint
4. **Sound Effect**: Low-frequency "moan" sound plays (volume proportional to burn amount)
5. **Data Refresh**: Supply data is refetched after 1 second

### Audio

The orb uses Web Audio API to generate synthetic sounds:
- **Frequency**: 80Hz oscillator that sweeps down to 60Hz
- **Duration**: 1 second fade
- **Volume**: Scales with burn amount (capped at 30% max volume)
- **Type**: Sine wave with low-pass filter for sultry effect

## Contract Interface

Your contract must expose these functions:

```solidity
// View functions
function totalSupply() external view returns (uint256);
function maxSupply() external view returns (uint256);

// Events
event Transfer(address indexed from, address indexed to, uint256 value);
```

### Burn Detection Logic

A transfer is considered a "burn" when:
```javascript
event.args.to === '0x0000000000000000000000000000000000000000'
```

## Customization

### Changing Colors

Edit `components/Orb.tsx` to modify the shader colors:

```typescript
const uniforms = useMemo(
  () => ({
    // ... other uniforms
    color1: { value: new THREE.Color('#ff00ff') }, // Magenta
    color2: { value: new THREE.Color('#00ffff') }, // Cyan
  }),
  []
);
```

### Adjusting Orb Size

Modify the radius calculation in `components/Orb.tsx`:

```typescript
// Current: 0.5 to 2.0 range
const baseRadius = Math.max(0.5, Math.min(2.0, 0.5 + supplyRatio * 1.5));

// For different size range (e.g., 1.0 to 3.0):
const baseRadius = Math.max(1.0, Math.min(3.0, 1.0 + supplyRatio * 2.0));
```

### Changing Particle Count

Edit `components/BurnParticles.tsx`:

```typescript
const particleCount = 1000; // Increase or decrease for more/fewer particles
```

### Audio Customization

Edit `lib/soundManager.ts` to change sound properties:

```typescript
// Change frequency range
oscillator.frequency.setValueAtTime(80, audioContext.currentTime); // Start
oscillator.frequency.exponentialRampToValueAtTime(60, audioContext.currentTime + 0.5); // End

// Change volume
const volume = Math.min(1, intensity * 0.3); // Multiply by different factor

// Change duration
oscillator.stop(audioContext.currentTime + 1.0); // Increase/decrease time
```

## Deployment

### Vercel (Recommended)

1. Push your code to GitHub
2. Import repository in Vercel
3. Add environment variable:
   - Key: `NEXT_PUBLIC_CONTRACT_ADDRESS`
   - Value: Your contract address
4. Deploy

### Manual Deployment

```bash
# Build
npm run build

# The output will be in .next folder
# Deploy the entire project folder to your hosting provider
```

## Troubleshooting

### Orb Not Connecting
- Verify your contract address in `.env.local`
- Ensure the contract is deployed on Arbitrum One
- Check browser console for errors

### Burn Events Not Detected
- Verify your contract emits `Transfer` events
- Ensure burns actually go to address(0), not another burn mechanism
- Check that wagmi is properly connected to Arbitrum One RPC

### Performance Issues
- Reduce particle count in `BurnParticles.tsx`
- Disable auto-rotation in `OrbScene.tsx`
- Lower the sphere segment count in `Orb.tsx` (currently 64x64)

### Audio Not Playing
- Some browsers block audio until user interaction
- Check browser console for AudioContext errors
- Ensure your browser supports Web Audio API

## Browser Support

- **Chrome/Edge**: Full support ✅
- **Firefox**: Full support ✅
- **Safari**: Full support (iOS 15+) ✅
- **Mobile**: Optimized for touch and small screens ✅

## Performance Notes

- The orb uses hardware-accelerated WebGL rendering
- Shaders run on GPU for optimal performance
- Particle system is optimized with Float32Arrays
- No external dependencies for 3D assets

## Next Steps

This is Phase 1. Phase 2 will add:
- Mint/claim interface
- Wallet connection UI
- Transaction handling
- More interactive features

---

For questions or issues, please open a GitHub issue.
