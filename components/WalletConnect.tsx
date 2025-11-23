'use client'

import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { motion } from 'framer-motion'
import GlassCard from './GlassCard'

export default function WalletConnect() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()
  
  if (isConnected && address) {
    return (
      <GlassCard className="flex items-center justify-between gap-4">
        <div className="flex-1">
          <p className="text-xs text-cyan-400 font-semibold mb-1">CONNECTED</p>
          <p className="text-sm font-mono text-white/80 truncate">
            {address.slice(0, 6)}...{address.slice(-4)}
          </p>
        </div>
        <motion.button
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          onClick={() => disconnect()}
          className="px-4 py-2 bg-red-500/20 hover:bg-red-500/30 text-red-400 rounded-lg border border-red-500/50 transition-colors text-sm font-semibold"
        >
          Disconnect
        </motion.button>
      </GlassCard>
    )
  }
  
  return (
    <GlassCard>
      <p className="text-sm text-cyan-400 mb-4 font-semibold">Connect your wallet to start</p>
      <div className="space-y-2">
        {connectors.map((connector) => (
          <motion.button
            key={connector.id}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            onClick={() => connect({ connector })}
            className="w-full px-4 py-3 bg-gradient-to-r from-pink-500/20 to-cyan-500/20 hover:from-pink-500/30 hover:to-cyan-500/30 text-white rounded-lg border border-white/20 transition-all text-sm font-semibold"
          >
            {connector.name}
          </motion.button>
        ))}
      </div>
    </GlassCard>
  )
}
