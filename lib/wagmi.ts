import { createConfig, http } from 'wagmi';
import { arbitrum } from 'wagmi/chains';

export const config = createConfig({
  chains: [arbitrum],
  transports: {
    [arbitrum.id]: http(),
  },
});
