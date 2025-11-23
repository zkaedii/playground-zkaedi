'use client'

import { useReadContract } from 'wagmi'
import { motion } from 'framer-motion'
import dynamic from 'next/dynamic'
import ParticleTrails from '@/components/ParticleTrails'
import WalletConnect from '@/components/WalletConnect'
import TokenInfo from '@/components/TokenInfo'
import TokenActions from '@/components/TokenActions'
import { CONTRACT_ADDRESS, CONTRACT_ABI } from '@/lib/contract'

// Dynamic import for Three.js component to avoid SSR issues
const GlowingOrb = dynamic(() => import('@/components/GlowingOrb'), {
  ssr: false,
  loading: () => (
    <div className="w-full h-[400px] flex items-center justify-center">
      <div className="text-cyan-400 animate-pulse">Loading 3D Scene...</div>
    </div>
  ),
})

export default function Home() {
  const { data: totalSupply } = useReadContract({
    address: CONTRACT_ADDRESS as `0x${string}`,
    abi: CONTRACT_ABI,
    functionName: 'totalSupply',
  })
  
  return (
    <div className="min-h-screen relative overflow-hidden">
      {/* Particle trails background */}
      <ParticleTrails />
      
      {/* Cyber grid background */}
      <div className="fixed inset-0 cyber-grid opacity-20 pointer-events-none" />
      
      {/* Main content */}
      <div className="relative z-10">
        {/* Header */}
        <motion.header
          initial={{ y: -100, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ duration: 0.8 }}
          className="container mx-auto px-4 py-6"
        >
          <div className="flex items-center justify-between">
            <motion.h1
              className="text-4xl md:text-6xl font-bold neon-glow"
              animate={{
                textShadow: [
                  '0 0 10px rgba(255, 0, 128, 0.8), 0 0 20px rgba(255, 0, 128, 0.6)',
                  '0 0 20px rgba(0, 255, 255, 0.8), 0 0 40px rgba(0, 255, 255, 0.6)',
                  '0 0 10px rgba(255, 0, 128, 0.8), 0 0 20px rgba(255, 0, 128, 0.6)',
                ],
              }}
              transition={{ duration: 3, repeat: Infinity }}
            >
              UUPS<span className="text-transparent bg-clip-text bg-gradient-to-r from-pink-500 to-cyan-500">Token</span>
            </motion.h1>
            
            <motion.div
              initial={{ scale: 0 }}
              animate={{ scale: 1 }}
              transition={{ delay: 0.5, type: 'spring' }}
              className="hidden md:block"
            >
              <div className="px-4 py-2 bg-gradient-to-r from-pink-500/20 to-cyan-500/20 rounded-full border border-white/20">
                <p className="text-sm font-mono text-cyan-400">Arbitrum Network</p>
              </div>
            </motion.div>
          </div>
        </motion.header>
        
        {/* Main content area */}
        <main className="container mx-auto px-4 py-8">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 max-w-7xl mx-auto">
            {/* Left column - 3D Orb */}
            <motion.div
              initial={{ x: -100, opacity: 0 }}
              animate={{ x: 0, opacity: 1 }}
              transition={{ duration: 0.8, delay: 0.2 }}
              className="space-y-6"
            >
              <div className="relative">
                <GlowingOrb
                  totalSupply={totalSupply as bigint || BigInt(0)}
                  maxSupply={BigInt(1000000)}
                />
              </div>
              
              <TokenInfo />
            </motion.div>
            
            {/* Right column - Wallet & Actions */}
            <motion.div
              initial={{ x: 100, opacity: 0 }}
              animate={{ x: 0, opacity: 1 }}
              transition={{ duration: 0.8, delay: 0.4 }}
              className="space-y-6"
            >
              <WalletConnect />
              <TokenActions />
              
              {/* Info section */}
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.8 }}
                className="backdrop-blur-xl bg-gradient-to-br from-white/5 to-white/5 border border-white/10 rounded-2xl p-6"
              >
                <h3 className="text-lg font-bold text-cyan-400 mb-3">About</h3>
                <p className="text-sm text-white/70 leading-relaxed">
                  UUPSTokenV2 is a state-of-the-art ERC-20 token deployed on Arbitrum with UUPS proxy pattern for upgradability. 
                  Experience real-time interactions with stunning 3D visualizations and anime-cyberpunk aesthetics.
                </p>
                <div className="mt-4 flex flex-wrap gap-2">
                  <span className="px-3 py-1 bg-pink-500/20 rounded-full text-xs text-pink-400 border border-pink-500/30">
                    ERC-20
                  </span>
                  <span className="px-3 py-1 bg-cyan-500/20 rounded-full text-xs text-cyan-400 border border-cyan-500/30">
                    UUPS Proxy
                  </span>
                  <span className="px-3 py-1 bg-purple-500/20 rounded-full text-xs text-purple-400 border border-purple-500/30">
                    Arbitrum
                  </span>
                </div>
              </motion.div>
            </motion.div>
          </div>
        </main>
        
        {/* Footer */}
        <motion.footer
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1 }}
          className="container mx-auto px-4 py-8 mt-12"
        >
          <div className="text-center text-white/40 text-sm">
            <p className="mb-2">Built with Next.js, wagmi, Three.js & Framer Motion</p>
            <p className="text-xs">
              ⚠️ 21+ Content Warning: Interactive elements include mature audio effects
            </p>
          </div>
        </motion.footer>
      </div>
    </div>
  )
}
