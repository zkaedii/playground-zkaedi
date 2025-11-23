'use client';

interface HUDProps {
  totalSupply: bigint;
  maxSupply: bigint;
  isConnected: boolean;
  isLoading: boolean;
}

export function HUD({ totalSupply, maxSupply, isConnected, isLoading }: HUDProps) {
  const formatNumber = (value: bigint) => {
    return (Number(value) / 1e18).toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  };
  
  const supplyRatio = maxSupply > 0n 
    ? (Number(totalSupply) / Number(maxSupply) * 100).toFixed(2)
    : '0.00';
  
  return (
    <div className="fixed inset-0 pointer-events-none">
      {/* Top HUD */}
      <div className="absolute top-8 left-1/2 -translate-x-1/2 pointer-events-auto">
        <div className="backdrop-blur-md bg-black/30 border border-cyan-500/30 rounded-2xl px-8 py-4 shadow-2xl shadow-cyan-500/20">
          <h1 className="text-4xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 via-purple-400 to-pink-400 text-center mb-2">
            The Orb
          </h1>
          <div className="text-cyan-300/70 text-sm text-center">
            {isConnected ? 'Connected to Arbitrum One' : 'Not Connected'}
          </div>
        </div>
      </div>
      
      {/* Bottom left stats */}
      <div className="absolute bottom-8 left-8 pointer-events-auto">
        <div className="backdrop-blur-md bg-black/30 border border-magenta-500/30 rounded-2xl px-6 py-4 shadow-2xl shadow-magenta-500/20 space-y-3">
          <div>
            <div className="text-magenta-300/70 text-xs uppercase tracking-wider mb-1">
              Total Supply
            </div>
            <div className="text-2xl font-mono text-magenta-300">
              {isLoading ? '...' : formatNumber(totalSupply)}
            </div>
          </div>
          
          <div>
            <div className="text-cyan-300/70 text-xs uppercase tracking-wider mb-1">
              Max Supply
            </div>
            <div className="text-2xl font-mono text-cyan-300">
              {isLoading ? '...' : formatNumber(maxSupply)}
            </div>
          </div>
          
          <div>
            <div className="text-purple-300/70 text-xs uppercase tracking-wider mb-1">
              Supply Ratio
            </div>
            <div className="text-2xl font-mono text-purple-300">
              {isLoading ? '...' : `${supplyRatio}%`}
            </div>
          </div>
        </div>
      </div>
      
      {/* Bottom right info */}
      <div className="absolute bottom-8 right-8 pointer-events-auto">
        <div className="backdrop-blur-md bg-black/30 border border-purple-500/30 rounded-2xl px-6 py-4 shadow-2xl shadow-purple-500/20">
          <div className="text-purple-300/70 text-xs uppercase tracking-wider mb-2">
            Status
          </div>
          <div className="flex items-center gap-2">
            <div className={`w-3 h-3 rounded-full ${isConnected ? 'bg-green-400 animate-pulse' : 'bg-red-400'}`} />
            <span className="text-sm text-purple-300">
              {isConnected ? 'Live' : 'Disconnected'}
            </span>
          </div>
        </div>
      </div>
      
      {/* Scanline effect overlay */}
      <div className="absolute inset-0 pointer-events-none opacity-5">
        <div className="w-full h-full" style={{
          backgroundImage: 'repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0, 255, 255, 0.1) 2px, rgba(0, 255, 255, 0.1) 4px)'
        }} />
      </div>
    </div>
  );
}
