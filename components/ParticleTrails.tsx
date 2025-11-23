'use client'

import { useEffect, useRef } from 'react'

export default function ParticleTrails() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    
    canvas.width = window.innerWidth
    canvas.height = window.innerHeight
    
    const particles: Array<{
      x: number
      y: number
      vx: number
      vy: number
      life: number
      maxLife: number
      color: string
    }> = []
    
    const colors = ['#ff00ff', '#00ffff', '#ff0080', '#8000ff']
    
    const createParticle = (x: number, y: number) => {
      particles.push({
        x,
        y,
        vx: (Math.random() - 0.5) * 2,
        vy: (Math.random() - 0.5) * 2,
        life: 1,
        maxLife: 60 + Math.random() * 60,
        color: colors[Math.floor(Math.random() * colors.length)],
      })
    }
    
    let animationFrame: number
    let mouseX = 0
    let mouseY = 0
    let isMouseMoving = false
    
    const handleMouseMove = (e: MouseEvent) => {
      mouseX = e.clientX
      mouseY = e.clientY
      isMouseMoving = true
    }
    
    const animate = () => {
      ctx.fillStyle = 'rgba(0, 0, 0, 0.05)'
      ctx.fillRect(0, 0, canvas.width, canvas.height)
      
      if (isMouseMoving && Math.random() > 0.7) {
        createParticle(mouseX, mouseY)
        isMouseMoving = false
      }
      
      // Random ambient particles
      if (Math.random() > 0.95) {
        createParticle(
          Math.random() * canvas.width,
          Math.random() * canvas.height
        )
      }
      
      for (let i = particles.length - 1; i >= 0; i--) {
        const p = particles[i]
        p.life--
        p.x += p.vx
        p.y += p.vy
        p.vx *= 0.98
        p.vy *= 0.98
        
        if (p.life <= 0) {
          particles.splice(i, 1)
          continue
        }
        
        const alpha = p.life / p.maxLife
        ctx.fillStyle = p.color
        ctx.globalAlpha = alpha
        ctx.beginPath()
        ctx.arc(p.x, p.y, 2 + alpha * 2, 0, Math.PI * 2)
        ctx.fill()
        
        // Trail
        ctx.strokeStyle = p.color
        ctx.lineWidth = 1
        ctx.globalAlpha = alpha * 0.5
        ctx.beginPath()
        ctx.moveTo(p.x, p.y)
        ctx.lineTo(p.x - p.vx * 3, p.y - p.vy * 3)
        ctx.stroke()
      }
      
      ctx.globalAlpha = 1
      animationFrame = requestAnimationFrame(animate)
    }
    
    window.addEventListener('mousemove', handleMouseMove)
    animate()
    
    const handleResize = () => {
      canvas.width = window.innerWidth
      canvas.height = window.innerHeight
    }
    window.addEventListener('resize', handleResize)
    
    return () => {
      window.removeEventListener('mousemove', handleMouseMove)
      window.removeEventListener('resize', handleResize)
      cancelAnimationFrame(animationFrame)
    }
  }, [])
  
  return (
    <canvas
      ref={canvasRef}
      className="fixed inset-0 pointer-events-none z-0"
      style={{ mixBlendMode: 'screen' }}
    />
  )
}
