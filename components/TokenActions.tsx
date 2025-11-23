'use client'

import { useState, useRef, useEffect } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { parseEther } from 'viem'
import { motion } from 'framer-motion'
import toast from 'react-hot-toast'
import GlassCard from './GlassCard'
import { CONTRACT_ADDRESS, CONTRACT_ABI } from '@/lib/contract'

export default function TokenActions() {
  const { address, isConnected } = useAccount()
  const [amount, setAmount] = useState('')
  const [recipient, setRecipient] = useState('')
  const [isHovering, setIsHovering] = useState(false)
  const audioRef = useRef<HTMLAudioElement | null>(null)
  
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })
  
  useEffect(() => {
    // Create audio element for moaning sound (21+ content - replace /moan.mp3 with your audio file)
    audioRef.current = new Audio('/moan.mp3')
    audioRef.current.volume = 0.3
  }, [])
  
  useEffect(() => {
    if (isSuccess && hash) {
      toast.success(
        <div>
          <p className="font-bold">Transaction Confirmed! 🎉</p>
          <p className="text-xs mt-1 font-mono">{hash.slice(0, 10)}...{hash.slice(-8)}</p>
        </div>,
        {
          duration: 5000,
          style: {
            background: 'linear-gradient(135deg, rgba(236,72,153,0.9) 0%, rgba(6,182,212,0.9) 100%)',
            color: '#fff',
            border: '1px solid rgba(255,255,255,0.3)',
          },
        }
      )
    }
  }, [isSuccess, hash])
  
  const handleMint = async () => {
    if (!amount || !isConnected) return
    
    try {
      const amountInWei = parseEther(amount)
      
      writeContract({
        address: CONTRACT_ADDRESS as `0x${string}`,
        abi: CONTRACT_ABI,
        functionName: 'mint',
        args: [address!, amountInWei],
      })
      
      toast.loading('Minting tokens...', { id: 'mint' })
    } catch (error) {
      console.error('Mint error:', error)
      toast.error('Failed to mint tokens')
    }
  }
  
  const handleBurn = async () => {
    if (!amount || !isConnected) return
    
    try {
      const amountInWei = parseEther(amount)
      
      writeContract({
        address: CONTRACT_ADDRESS as `0x${string}`,
        abi: CONTRACT_ABI,
        functionName: 'burn',
        args: [amountInWei],
      })
      
      toast.loading('Burning tokens...', { id: 'burn' })
    } catch (error) {
      console.error('Burn error:', error)
      toast.error('Failed to burn tokens')
    }
  }
  
  const handleTransfer = async () => {
    if (!amount || !recipient || !isConnected) return
    
    try {
      const amountInWei = parseEther(amount)
      
      writeContract({
        address: CONTRACT_ADDRESS as `0x${string}`,
        abi: CONTRACT_ABI,
        functionName: 'transfer',
        args: [recipient as `0x${string}`, amountInWei],
      })
      
      toast.loading('Transferring tokens...', { id: 'transfer' })
    } catch (error) {
      console.error('Transfer error:', error)
      toast.error('Failed to transfer tokens')
    }
  }
  
  const playSound = () => {
    if (audioRef.current) {
      audioRef.current.currentTime = 0
      audioRef.current.play().catch(() => {
        // Ignore autoplay errors
      })
    }
  }
  
  if (!isConnected) {
    return null
  }
  
  return (
    <GlassCard>
      <h3 className="text-xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-pink-500 to-cyan-500 mb-4">
        Token Actions
      </h3>
      
      <div className="space-y-4">
        {/* Amount Input */}
        <div>
          <label className="block text-sm text-cyan-400 mb-2 font-semibold">Amount</label>
          <input
            type="text"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.0"
            className="w-full px-4 py-3 bg-black/40 border border-white/20 rounded-lg text-white placeholder-white/40 focus:outline-none focus:border-pink-500/50 transition-colors font-mono"
          />
        </div>
        
        {/* Recipient Input (for transfer) */}
        <div>
          <label className="block text-sm text-cyan-400 mb-2 font-semibold">Recipient (for transfer)</label>
          <input
            type="text"
            value={recipient}
            onChange={(e) => setRecipient(e.target.value)}
            placeholder="0x..."
            className="w-full px-4 py-3 bg-black/40 border border-white/20 rounded-lg text-white placeholder-white/40 focus:outline-none focus:border-cyan-500/50 transition-colors font-mono text-sm"
          />
        </div>
        
        {/* Action Buttons */}
        <div className="grid grid-cols-3 gap-3">
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onMouseEnter={() => {
              setIsHovering(true)
              playSound()
            }}
            onMouseLeave={() => setIsHovering(false)}
            onClick={handleMint}
            disabled={isPending || isConfirming || !amount}
            className="px-4 py-3 bg-gradient-to-r from-pink-500/30 to-purple-500/30 hover:from-pink-500/50 hover:to-purple-500/50 text-white rounded-lg border border-pink-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed text-sm font-bold relative overflow-hidden"
          >
            {isPending || isConfirming ? (
              <span className="flex items-center justify-center">
                <svg className="animate-spin h-4 w-4 mr-2" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                </svg>
              </span>
            ) : (
              'MINT'
            )}
            {isHovering && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="absolute inset-0 bg-pink-500/20 pointer-events-none"
              />
            )}
          </motion.button>
          
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={handleBurn}
            disabled={isPending || isConfirming || !amount}
            className="px-4 py-3 bg-gradient-to-r from-red-500/30 to-orange-500/30 hover:from-red-500/50 hover:to-orange-500/50 text-white rounded-lg border border-red-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed text-sm font-bold"
          >
            {isPending || isConfirming ? '...' : 'BURN'}
          </motion.button>
          
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={handleTransfer}
            disabled={isPending || isConfirming || !amount || !recipient}
            className="px-4 py-3 bg-gradient-to-r from-cyan-500/30 to-blue-500/30 hover:from-cyan-500/50 hover:to-blue-500/50 text-white rounded-lg border border-cyan-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed text-sm font-bold"
          >
            {isPending || isConfirming ? '...' : 'SEND'}
          </motion.button>
        </div>
        
        {isPending && (
          <p className="text-sm text-yellow-400 text-center animate-pulse">
            Waiting for wallet confirmation...
          </p>
        )}
        
        {isConfirming && (
          <p className="text-sm text-cyan-400 text-center animate-pulse">
            Confirming transaction...
          </p>
        )}
      </div>
    </GlassCard>
  )
}
