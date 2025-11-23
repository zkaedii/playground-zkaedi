# Deployment Guide

## Prerequisites

Before deploying, you'll need:

1. **Smart Contract Deployed on Arbitrum**
   - Deploy your UUPSTokenV2 ERC-20 contract to Arbitrum
   - Note down the contract address

2. **WalletConnect Project ID** (Optional but recommended)
   - Go to https://cloud.walletconnect.com/
   - Create a new project
   - Copy your Project ID

## Environment Variables

Create a `.env.local` file (for local development) or set environment variables in your deployment platform:

```env
NEXT_PUBLIC_CONTRACT_ADDRESS=0xYourContractAddressHere
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_project_id_here
```

## Deploy to Vercel

### Method 1: Using Vercel CLI

1. Install Vercel CLI:
```bash
npm i -g vercel
```

2. Login to Vercel:
```bash
vercel login
```

3. Deploy:
```bash
vercel
```

4. Add environment variables in Vercel dashboard:
   - Go to your project settings
   - Navigate to "Environment Variables"
   - Add `NEXT_PUBLIC_CONTRACT_ADDRESS` and `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`

### Method 2: Using Vercel Dashboard

1. Push your code to GitHub
2. Go to https://vercel.com/new
3. Import your repository
4. Configure:
   - **Framework Preset**: Next.js
   - **Build Command**: `npm run build`
   - **Output Directory**: `.next`
5. Add environment variables:
   - `NEXT_PUBLIC_CONTRACT_ADDRESS`
   - `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`
6. Click "Deploy"

## Deploy to Other Platforms

### Netlify

1. Build command: `npm run build`
2. Publish directory: `.next`
3. Add environment variables in Netlify dashboard

### Railway

1. Connect your GitHub repository
2. Railway will auto-detect Next.js
3. Add environment variables in Railway dashboard

### Docker

Build and run with Docker:

```bash
# Build
docker build -t uups-token-frontend .

# Run
docker run -p 3000:3000 \
  -e NEXT_PUBLIC_CONTRACT_ADDRESS=0xYourAddress \
  -e NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_id \
  uups-token-frontend
```

## Custom Domain

1. Add your domain in Vercel dashboard
2. Update DNS records as instructed
3. SSL certificate will be automatically provisioned

## Post-Deployment Checklist

- [ ] Verify contract address is correct
- [ ] Test wallet connection on production
- [ ] Test mint/burn/transfer operations
- [ ] Verify 3D orb loads and animates
- [ ] Check mobile responsiveness
- [ ] Test on different browsers
- [ ] Verify Arbitrum network detection

## Troubleshooting

### "Cannot read properties of undefined" error
- Check that your contract address is correctly set
- Ensure you're connected to Arbitrum network

### 3D Scene not loading
- Check browser console for WebGL errors
- Ensure device supports WebGL 2.0

### Wallet won't connect
- Verify WalletConnect project ID is valid
- Check that MetaMask or wallet extension is installed
- Ensure wallet is set to Arbitrum network

## Performance Optimization

The application is already optimized for:
- 60fps animations
- Code splitting with dynamic imports
- Optimized Three.js rendering
- Minimal bundle size

## Security Notes

- Never commit `.env.local` to git
- Keep your WalletConnect project ID secure
- Regularly update dependencies
- Monitor contract interactions

## Support

For issues or questions:
- Check GitHub Issues
- Review wagmi documentation: https://wagmi.sh
- Review viem documentation: https://viem.sh
