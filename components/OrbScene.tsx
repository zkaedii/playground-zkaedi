'use client';

import { Canvas } from '@react-three/fiber';
import { OrbitControls, Stars } from '@react-three/drei';
import { Orb } from './Orb';
import { Suspense } from 'react';

interface OrbSceneProps {
  supplyRatio: number;
  isBurning: boolean;
  burnAmount: number;
}

export function OrbScene({ supplyRatio, isBurning, burnAmount }: OrbSceneProps) {
  return (
    <div className="w-full h-screen bg-black">
      <Canvas
        camera={{ position: [0, 0, 5], fov: 50 }}
        gl={{ antialias: true, alpha: true }}
      >
        <Suspense fallback={null}>
          {/* Ambient lighting */}
          <ambientLight intensity={0.2} />
          
          {/* Main point lights for rim lighting */}
          <pointLight position={[3, 3, 3]} intensity={1} color="#ff00ff" />
          <pointLight position={[-3, -3, 3]} intensity={1} color="#00ffff" />
          
          {/* Background stars */}
          <Stars radius={100} depth={50} count={5000} factor={4} saturation={0} fade speed={1} />
          
          {/* The main orb */}
          <Orb supplyRatio={supplyRatio} isBurning={isBurning} burnAmount={burnAmount} />
          
          {/* Controls */}
          <OrbitControls
            enableZoom={false}
            enablePan={false}
            autoRotate
            autoRotateSpeed={0.5}
          />
        </Suspense>
      </Canvas>
    </div>
  );
}
