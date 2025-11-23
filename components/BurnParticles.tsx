'use client';

import { useRef, useMemo, useEffect } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';

interface BurnParticlesProps {
  isActive: boolean;
  intensity: number;
}

export function BurnParticles({ isActive, intensity }: BurnParticlesProps) {
  const pointsRef = useRef<THREE.Points>(null);
  const particleCount = 1000;
  
  const [positions, velocities] = useMemo(() => {
    const pos = new Float32Array(particleCount * 3);
    const vel = new Float32Array(particleCount * 3);
    
    for (let i = 0; i < particleCount; i++) {
      const i3 = i * 3;
      // Start at sphere surface
      // eslint-disable-next-line react-hooks/purity
      const theta = Math.random() * Math.PI * 2;
      // eslint-disable-next-line react-hooks/purity
      const phi = Math.acos(2 * Math.random() - 1);
      const r = 1.0;
      
      pos[i3] = r * Math.sin(phi) * Math.cos(theta);
      pos[i3 + 1] = r * Math.sin(phi) * Math.sin(theta);
      pos[i3 + 2] = r * Math.cos(phi);
      
      // Velocity pointing outward
      vel[i3] = pos[i3] * 0.02;
      vel[i3 + 1] = pos[i3 + 1] * 0.02;
      vel[i3 + 2] = pos[i3 + 2] * 0.02;
    }
    
    return [pos, vel];
  }, [particleCount]);
  
  const particleOpacity = useRef(0);
  
  useEffect(() => {
    if (isActive) {
      particleOpacity.current = intensity;
    }
  }, [isActive, intensity]);
  
  useFrame(() => {
    if (!pointsRef.current) return;
    
    // Fade out particles
    particleOpacity.current *= 0.95;
    
    if (particleOpacity.current > 0.01) {
      const positions = pointsRef.current.geometry.attributes.position.array as Float32Array;
      
      // Update particle positions
      for (let i = 0; i < particleCount; i++) {
        const i3 = i * 3;
        positions[i3] += velocities[i3];
        positions[i3 + 1] += velocities[i3 + 1];
        positions[i3 + 2] += velocities[i3 + 2];
      }
      
      pointsRef.current.geometry.attributes.position.needsUpdate = true;
    }
    
    // Update material opacity
    const material = pointsRef.current.material as THREE.PointsMaterial;
    material.opacity = particleOpacity.current;
  });
  
  return (
    <points ref={pointsRef}>
      <bufferGeometry>
        <bufferAttribute
          attach="attributes-position"
          args={[positions, 3]}
        />
      </bufferGeometry>
      <pointsMaterial
        size={0.03}
        color="#ff0044"
        transparent
        opacity={0}
        blending={THREE.AdditiveBlending}
        depthWrite={false}
      />
    </points>
  );
}
