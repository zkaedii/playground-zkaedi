'use client'

import { useRef, useMemo } from 'react'
import { Canvas, useFrame } from '@react-three/fiber'
import { OrbitControls, Sphere } from '@react-three/drei'
import * as THREE from 'three'

interface OrbProps {
  totalSupply: bigint
  maxSupply?: bigint
}

function AnimatedOrb({ totalSupply, maxSupply = BigInt(1000000) }: OrbProps) {
  const meshRef = useRef<THREE.Mesh>(null)
  const glowRef = useRef<THREE.Mesh>(null)
  
  // Calculate scale based on supply (1.0 to 2.0 range)
  const supplyRatio = Number(totalSupply) / Number(maxSupply)
  const targetScale = 1.0 + supplyRatio * 1.0
  
  // Pulse animation
  useFrame((state) => {
    if (meshRef.current && glowRef.current) {
      const pulse = Math.sin(state.clock.elapsedTime * 2) * 0.1 + 1
      const scale = targetScale * pulse
      meshRef.current.scale.setScalar(scale)
      glowRef.current.scale.setScalar(scale * 1.2)
      
      // Rotate slowly
      meshRef.current.rotation.y = state.clock.elapsedTime * 0.2
      meshRef.current.rotation.x = Math.sin(state.clock.elapsedTime * 0.1) * 0.2
    }
  })
  
  // Neon gradient shader material
  const shaderMaterial = useMemo(() => {
    return new THREE.ShaderMaterial({
      uniforms: {
        time: { value: 0 },
        color1: { value: new THREE.Color('#ff00ff') },
        color2: { value: new THREE.Color('#00ffff') },
        color3: { value: new THREE.Color('#ff0080') },
      },
      vertexShader: `
        varying vec3 vNormal;
        varying vec3 vPosition;
        void main() {
          vNormal = normalize(normalMatrix * normal);
          vPosition = position;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: `
        uniform vec3 color1;
        uniform vec3 color2;
        uniform vec3 color3;
        uniform float time;
        varying vec3 vNormal;
        varying vec3 vPosition;
        
        void main() {
          float intensity = pow(0.7 - dot(vNormal, vec3(0.0, 0.0, 1.0)), 2.0);
          vec3 glow = color1 * intensity;
          
          // Animated gradient
          float mixer = sin(vPosition.y * 2.0 + time) * 0.5 + 0.5;
          vec3 finalColor = mix(color2, color3, mixer) + glow;
          
          gl_FragColor = vec4(finalColor, 1.0);
        }
      `,
      transparent: false,
    })
  }, [])
  
  useFrame((state) => {
    shaderMaterial.uniforms.time.value = state.clock.elapsedTime
  })
  
  return (
    <>
      {/* Main orb */}
      <Sphere ref={meshRef} args={[1, 64, 64]}>
        <primitive object={shaderMaterial} attach="material" />
      </Sphere>
      
      {/* Outer glow */}
      <Sphere ref={glowRef} args={[1, 32, 32]}>
        <meshBasicMaterial
          color="#ff00ff"
          transparent
          opacity={0.2}
          side={THREE.BackSide}
        />
      </Sphere>
      
      {/* Particles */}
      <Points count={100} />
    </>
  )
}

function Points({ count }: { count: number }) {
  const points = useRef<THREE.Points>(null)
  
  const particlesPosition = useMemo(() => {
    const positions = new Float32Array(count * 3)
    for (let i = 0; i < count; i++) {
      const theta = Math.random() * Math.PI * 2
      const phi = Math.acos(Math.random() * 2 - 1)
      const radius = 2 + Math.random() * 1
      
      positions[i * 3] = radius * Math.sin(phi) * Math.cos(theta)
      positions[i * 3 + 1] = radius * Math.sin(phi) * Math.sin(theta)
      positions[i * 3 + 2] = radius * Math.cos(phi)
    }
    return positions
  }, [count])
  
  useFrame((state) => {
    if (points.current) {
      points.current.rotation.y = state.clock.elapsedTime * 0.05
    }
  })
  
  const geometry = useMemo(() => {
    const geo = new THREE.BufferGeometry()
    geo.setAttribute('position', new THREE.Float32BufferAttribute(particlesPosition, 3))
    return geo
  }, [particlesPosition])
  
  return (
    <points ref={points} geometry={geometry}>
      <pointsMaterial
        size={0.05}
        color="#00ffff"
        sizeAttenuation
        transparent
        opacity={0.8}
        blending={THREE.AdditiveBlending}
      />
    </points>
  )
}

export default function GlowingOrb({ totalSupply, maxSupply }: OrbProps) {
  return (
    <div className="w-full h-[400px] relative">
      <Canvas
        camera={{ position: [0, 0, 5], fov: 50 }}
        gl={{ antialias: true, alpha: true }}
        className="cursor-grab active:cursor-grabbing"
      >
        <ambientLight intensity={0.5} />
        <pointLight position={[10, 10, 10]} intensity={1} />
        <AnimatedOrb totalSupply={totalSupply} maxSupply={maxSupply} />
        <OrbitControls
          enableZoom={false}
          enablePan={false}
          autoRotate
          autoRotateSpeed={0.5}
        />
      </Canvas>
      
      {/* Glow effect overlay */}
      <div className="absolute inset-0 bg-gradient-radial from-pink-500/20 via-transparent to-transparent pointer-events-none blur-3xl" />
    </div>
  )
}
