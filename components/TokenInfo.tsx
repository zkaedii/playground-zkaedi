'use client'

import { useAccount, useReadContract } from 'wagmi'
import { formatEther } from 'viem'
import { motion } from 'framer-motion'
import GlassCard from './GlassCard'
import { CONTRACT_ADDRESS, CONTRACT_ABI } from '@/lib/contract'

export default function TokenInfo() {
  const { address, isConnected } = useAccount()
  
  // Read token data
  const { data: name } = useReadContract({
    address: CONTRACT_ADDRESS as `0x${string}`,
    abi: CONTRACT_ABI,
    functionName: 'name',
  })
  
  const { data: symbol } = useReadContract({
    address: CONTRACT_ADDRESS as `0x${string}`,
    abi: CONTRACT_ABI,
    functionName: 'symbol',
  })
  
  const { data: totalSupply } = useReadContract({
    address: CONTRACT_ADDRESS as `0x${string}`,
    abi: CONTRACT_ABI,
    functionName: 'totalSupply',
  })
  
  const { data: balance } = useReadContract({
    address: CONTRACT_ADDRESS as `0x${string}`,
    abi: CONTRACT_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })
  
  const { data: owner } = useReadContract({
    address: CONTRACT_ADDRESS as `0x${string}`,
    abi: CONTRACT_ABI,
    functionName: 'owner',
  })
  
  const isOwner = isConnected && address && owner && address.toLowerCase() === owner.toLowerCase()
  
  const formatBalance = (value: bigint | undefined) => {
    if (!value) return '0.00'
    const formatted = formatEther(value)
    return parseFloat(formatted).toFixed(2)
  }
  
  return (
    <GlassCard>
      <div className="flex items-start justify-between mb-4">
        <div>
          <h3 className="text-2xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-pink-500 to-cyan-500">
            {name || 'UUPSToken'}
          </h3>
          <p className="text-sm text-white/60 font-mono">{symbol || 'UUPS'}</p>
        </div>
        {isOwner && (
          <motion.div
            initial={{ rotate: -20, scale: 0 }}
            animate={{ rotate: 0, scale: 1 }}
            transition={{ type: 'spring', stiffness: 200 }}
            className="text-3xl"
            title="You are the Governor!"
          >
            👑
          </motion.div>
        )}
      </div>
      
      <div className="space-y-3">
        <div className="flex justify-between items-center p-3 bg-black/30 rounded-lg border border-white/10">
          <span className="text-sm text-cyan-400 font-semibold">Total Supply</span>
          <span className="text-lg font-bold text-white font-mono">
            {formatBalance(totalSupply as bigint | undefined)}
          </span>
        </div>
        
        {isConnected && balance !== undefined && (
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            className="flex justify-between items-center p-3 bg-gradient-to-r from-pink-500/10 to-cyan-500/10 rounded-lg border border-pink-500/30"
          >
            <span className="text-sm text-pink-400 font-semibold">Your Balance</span>
            <span className="text-lg font-bold text-white font-mono">
              {formatBalance(balance as bigint)}
            </span>
          </motion.div>
        )}
        
        <div className="pt-2 border-t border-white/10">
          <p className="text-xs text-white/40 font-mono break-all">
            Contract: {CONTRACT_ADDRESS}
          </p>
        </div>
      </div>
    </GlassCard>
  )
}
