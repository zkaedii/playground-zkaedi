'use client'

import { motion } from 'framer-motion'
import { ReactNode } from 'react'

interface GlassCardProps {
  children: ReactNode
  className?: string
  animate?: boolean
}

export default function GlassCard({ children, className = '', animate = true }: GlassCardProps) {
  const Component = animate ? motion.div : 'div'
  
  const animationProps = animate ? {
    initial: { opacity: 0, y: 20 },
    animate: { opacity: 1, y: 0 },
    transition: { duration: 0.5 },
    whileHover: { scale: 1.02, transition: { duration: 0.2 } },
  } : {}
  
  return (
    <Component
      className={`
        relative backdrop-blur-xl bg-gradient-to-br from-white/10 to-white/5
        border border-white/20 rounded-2xl p-6 shadow-2xl
        before:absolute before:inset-0 before:rounded-2xl 
        before:bg-gradient-to-br before:from-pink-500/10 before:to-cyan-500/10
        before:opacity-50 before:-z-10
        ${className}
      `}
      {...animationProps}
    >
      {children}
    </Component>
  )
}
