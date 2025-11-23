# Deployment Guide

## Prerequisites

Before deploying, ensure you have:
- A deployed UUPSTokenV2 contract on Arbitrum One
- The contract address

## Quick Deploy to Vercel

### Option 1: One-Click Deploy

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/zkaedii/playground-zkaedi)

1. Click the button above
2. Fork/clone the repository to your account
3. Add environment variable:
   - Name: `NEXT_PUBLIC_CONTRACT_ADDRESS`
   - Value: Your UUPSTokenV2 contract address
4. Click "Deploy"

### Option 2: Vercel CLI

```bash
# Install Vercel CLI
npm install -g vercel

# Login to Vercel
vercel login

# Deploy
vercel

# Follow prompts and add environment variable when asked
```

### Option 3: GitHub Integration

1. Push your code to GitHub
2. Go to [vercel.com/new](https://vercel.com/new)
3. Import your repository
4. Configure environment variable:
   ```
   NEXT_PUBLIC_CONTRACT_ADDRESS=0xYourContractAddress
   ```
5. Click "Deploy"

## Environment Variables

### Required

- `NEXT_PUBLIC_CONTRACT_ADDRESS` - Your UUPSTokenV2 contract address on Arbitrum One

### Optional

None at this time. All other configuration is hardcoded for Arbitrum One.

## Build Configuration

The project uses:
- **Framework**: Next.js 14 (App Router)
- **Build Command**: `npm run build`
- **Output Directory**: `.next` (default)
- **Install Command**: `npm install`
- **Node Version**: 18.x or higher

## Manual Deployment

### To Any Static Host

```bash
# Build the project
npm run build

# Export static files (if needed)
npm run export

# Deploy the .next folder to your host
```

### To Docker

Create a `Dockerfile`:

```dockerfile
FROM node:18-alpine AS base

# Install dependencies
FROM base AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

# Build
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# Production
FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
ENV PORT=3000

CMD ["node", "server.js"]
```

Build and run:
```bash
docker build -t orb-visualization .
docker run -p 3000:3000 -e NEXT_PUBLIC_CONTRACT_ADDRESS=0xYourAddress orb-visualization
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

### Vercel

1. Go to your project settings
2. Click "Domains"
3. Add your custom domain
4. Update DNS records as instructed

### Other Hosts

Configure your DNS to point to your hosting provider's IP or CNAME.

## Post-Deployment Checklist

- [ ] Verify the orb loads and displays correctly
- [ ] Check browser console for errors
- [ ] Confirm HUD shows "Not Connected" when no contract is set
- [ ] Test with a valid contract address
- [ ] Verify supply data loads correctly
- [ ] Test on mobile devices
- [ ] Check performance with DevTools

## Monitoring

### Vercel Analytics

Vercel provides built-in analytics:
1. Go to your project dashboard
2. Click "Analytics"
3. View page views, performance, and errors

### Custom Monitoring

Consider adding:
- Error tracking (e.g., Sentry)
- Analytics (e.g., Google Analytics, Plausible)
- Performance monitoring (e.g., Web Vitals)

## Troubleshooting

### Build Fails

**Issue**: TypeScript errors
```
Solution: Run `npm run build` locally first to catch errors
```

**Issue**: Missing environment variable
```
Solution: Add NEXT_PUBLIC_CONTRACT_ADDRESS in Vercel settings
```

### Runtime Issues

**Issue**: Orb not connecting
```
Solution: Verify contract address and network (must be Arbitrum One)
```

**Issue**: WebGL errors
```
Solution: Check browser compatibility, ensure hardware acceleration enabled
```

### Performance Issues

**Issue**: Slow initial load
```
Solution: Enable compression in your hosting provider settings
```

**Issue**: High CPU usage
```
Solution: Reduce particle count in BurnParticles.tsx or disable auto-rotation
```

## Production Optimizations

The build already includes:
- ✅ Minified JavaScript
- ✅ Optimized images
- ✅ Tree-shaking
- ✅ Code splitting
- ✅ Static asset caching

Optional improvements:
- Add CDN for assets
- Enable gzip/brotli compression
- Implement service worker for offline support
- Add loading states for better UX

## Security Considerations

- ✅ No private keys stored in code
- ✅ Environment variables for sensitive data
- ✅ HTTPS enforced (Vercel default)
- ✅ No backend API (pure frontend)
- ✅ Read-only blockchain interaction

## Cost Estimates

### Vercel (Hobby Plan - Free)
- Bandwidth: 100GB/month
- Build time: 100 hours/month
- Suitable for: Personal projects, demos

### Vercel (Pro - $20/month)
- Bandwidth: 1TB/month
- Build time: 400 hours/month
- Suitable for: Production apps with moderate traffic

## Support

For deployment issues:
- Check [Vercel Documentation](https://vercel.com/docs)
- Review [Next.js Documentation](https://nextjs.org/docs)
- Open an issue on GitHub

---

🎉 Once deployed, your orb will be live and ready to visualize token burns in real-time!
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
