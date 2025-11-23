'use client';

import { useState, useEffect, useCallback } from 'react';
import { WagmiProvider, useReadContract, useWatchContractEvent } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { config } from '@/lib/wagmi';
import { CONTRACT_ADDRESS, CONTRACT_ABI } from '@/lib/contract';
import { ZERO_ADDRESS } from '@/lib/constants';
import { OrbScene } from './OrbScene';
import { HUD } from './HUD';
import { soundManager } from '@/lib/soundManager';

const queryClient = new QueryClient();

function OrbContent() {
  const [isBurning, setIsBurning] = useState(false);
  const [burnAmount, setBurnAmount] = useState(0);
  
  // Read total supply
  const { data: totalSupply, isLoading: isLoadingTotal, refetch: refetchTotal } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'totalSupply',
  });
  
  // Read max supply
  const { data: maxSupply, isLoading: isLoadingMax } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'maxSupply',
  });
  
  const isLoading = isLoadingTotal || isLoadingMax;
  const isConnected = !!totalSupply && !!maxSupply;
  
  // Calculate supply ratio
  const supplyRatio = totalSupply && maxSupply && maxSupply > 0n
    ? Number(totalSupply) / Number(maxSupply)
    : 0.5; // Default ratio when not connected
  
  // Watch for burn events (Transfer to address(0))
  useWatchContractEvent({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    eventName: 'Transfer',
    onLogs(logs) {
      logs.forEach((log) => {
        // Check if it's a burn (to address is 0x0)
        if (log.args.to === ZERO_ADDRESS) {
          const amount = Number(log.args.value || 0n);
          handleBurn(amount);
        }
      });
    },
  });
  
  const handleBurn = useCallback(async (amount: number) => {
    console.log('Burn detected:', amount);
    setIsBurning(true);
    setBurnAmount(amount);
    
    // Play sound with intensity based on burn amount
    const intensity = Math.min(1, amount / 1e18);
    soundManager.playBurnSound(intensity);
    
    // Refetch supply after a short delay
    setTimeout(() => {
      refetchTotal();
    }, 1000);
    
    // Reset burning state
    setTimeout(() => {
      setIsBurning(false);
      setBurnAmount(0);
    }, 2000);
  }, [refetchTotal]);
  
  // Initialize sound manager
  useEffect(() => {
    soundManager.initialize();
  }, []);
  
  return (
    <>
      <OrbScene 
        supplyRatio={supplyRatio}
        isBurning={isBurning}
        burnAmount={burnAmount}
      />
      <HUD 
        totalSupply={totalSupply || 0n}
        maxSupply={maxSupply || 0n}
        isConnected={isConnected}
        isLoading={isLoading}
      />
    </>
  );
}

export function OrbVisualization() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <OrbContent />
      </QueryClientProvider>
    </WagmiProvider>
  );
}
