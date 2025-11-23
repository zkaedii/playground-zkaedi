'use client';

import { useRef, useMemo, useEffect } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import { Sphere } from '@react-three/drei';
import { BurnParticles } from './BurnParticles';

interface OrbProps {
  supplyRatio: number;
  isBurning: boolean;
  burnAmount: number;
}

export function Orb({ supplyRatio, isBurning, burnAmount }: OrbProps) {
  const meshRef = useRef<THREE.Mesh>(null);
  const shaderRef = useRef<THREE.ShaderMaterial>(null);
  const targetScale = useRef(1);
  const currentScale = useRef(1);
  
  // Calculate base radius from supply ratio (0.5 to 2.0 range)
  const baseRadius = Math.max(0.5, Math.min(2.0, 0.5 + supplyRatio * 1.5));
  
  // Vertex shader for the orb
  const vertexShader = `
    varying vec3 vNormal;
    varying vec3 vPosition;
    uniform float time;
    uniform float pulse;
    
    void main() {
      vNormal = normalize(normalMatrix * normal);
      vPosition = position;
      
      // Add subtle pulsing
      vec3 pos = position * (1.0 + pulse * 0.05 * sin(time * 2.0));
      
      gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
    }
  `;
  
  // Fragment shader for neon glow effect
  const fragmentShader = `
    varying vec3 vNormal;
    varying vec3 vPosition;
    uniform float time;
    uniform float burnIntensity;
    uniform vec3 color1;
    uniform vec3 color2;
    
    void main() {
      // Fresnel effect for rim lighting
      vec3 viewDirection = normalize(cameraPosition - vPosition);
      float fresnel = pow(1.0 - dot(viewDirection, vNormal), 3.0);
      
      // Oscillating colors
      vec3 color = mix(color1, color2, (sin(time * 0.5) + 1.0) * 0.5);
      
      // Add burn effect
      vec3 burnColor = vec3(0.8, 0.1, 0.1);
      color = mix(color, burnColor, burnIntensity);
      
      // Rim glow
      vec3 glow = color * fresnel * 2.0;
      
      // Semi-transparent core
      float alpha = 0.3 + fresnel * 0.7;
      
      gl_FragColor = vec4(color * 0.2 + glow, alpha);
    }
  `;
  
  const uniforms = useMemo(
    () => ({
      time: { value: 0 },
      pulse: { value: 0 },
      burnIntensity: { value: 0 },
      color1: { value: new THREE.Color('#ff00ff') }, // Magenta
      color2: { value: new THREE.Color('#00ffff') }, // Cyan
    }),
    []
  );
  
  // Update target scale when burning
  useEffect(() => {
    if (isBurning) {
      targetScale.current = baseRadius;
      
      // Trigger burn intensity
      if (shaderRef.current) {
        shaderRef.current.uniforms.burnIntensity.value = 1.0;
        
        // Fade out burn intensity
        setTimeout(() => {
          if (shaderRef.current) {
            shaderRef.current.uniforms.burnIntensity.value = 0;
          }
        }, 1000);
      }
    }
  }, [isBurning, burnAmount, baseRadius]);
  
  // Animation loop
  useFrame((state) => {
    if (!meshRef.current || !shaderRef.current) return;
    
    // Update time uniform
    shaderRef.current.uniforms.time.value = state.clock.elapsedTime;
    
    // Pulse based on mouse movement
    const mouseX = state.mouse.x;
    const mouseY = state.mouse.y;
    const mouseDist = Math.sqrt(mouseX * mouseX + mouseY * mouseY);
    shaderRef.current.uniforms.pulse.value = mouseDist * 0.5;
    
    // Smooth scale transition
    targetScale.current = baseRadius;
    currentScale.current += (targetScale.current - currentScale.current) * 0.05;
    meshRef.current.scale.setScalar(currentScale.current);
    
    // Gentle rotation
    meshRef.current.rotation.y += 0.001;
    
    // Fade burn intensity
    if (shaderRef.current.uniforms.burnIntensity.value > 0) {
      shaderRef.current.uniforms.burnIntensity.value *= 0.98;
    }
  });
  
  return (
    <group>
      <Sphere ref={meshRef} args={[1, 64, 64]}>
        <shaderMaterial
          ref={shaderRef}
          vertexShader={vertexShader}
          fragmentShader={fragmentShader}
          uniforms={uniforms}
          transparent
          side={THREE.DoubleSide}
        />
      </Sphere>
      <BurnParticles isActive={isBurning} intensity={burnAmount / 1000} />
    </group>
  );
}
