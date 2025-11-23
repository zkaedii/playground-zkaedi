import { createConfig, http } from 'wagmi';
import { arbitrum } from 'wagmi/chains';

export const config = createConfig({
  chains: [arbitrum],
  transports: {
    [arbitrum.id]: http(),
  },
});
import { http, createConfig } from 'wagmi'
import { arbitrum } from 'wagmi/chains'
import { injected } from 'wagmi/connectors'

export const config = createConfig({
  chains: [arbitrum],
  connectors: [
    injected(),
  ],
  transports: {
    [arbitrum.id]: http(),
  },
})
