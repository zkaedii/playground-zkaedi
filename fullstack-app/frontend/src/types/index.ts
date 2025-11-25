// User types
export interface User {
  id: string;
  email: string;
  username: string;
  walletAddress?: string;
  createdAt: string;
}

// Auth types
export interface LoginCredentials {
  email: string;
  password: string;
}

export interface RegisterCredentials extends LoginCredentials {
  username: string;
  walletAddress?: string;
}

export interface AuthResponse {
  user: User;
  token: string;
  refreshToken: string;
}

// Portfolio types
export interface Portfolio {
  id: string;
  userId: string;
  name: string;
  description?: string;
  isDefault: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface PortfolioWithAssets extends Portfolio {
  assets: Asset[];
  totalValue: number;
}

export interface CreatePortfolioInput {
  name: string;
  description?: string;
}

// Asset types
export interface Asset {
  id: string;
  portfolioId: string;
  tokenAddress: string;
  tokenSymbol: string;
  tokenName: string;
  tokenDecimals: number;
  chainId: number;
  balance: string;
  averageCost?: string;
  createdAt: string;
  updatedAt: string;
}

export interface AddAssetInput {
  tokenAddress: string;
  tokenSymbol: string;
  tokenName: string;
  tokenDecimals: number;
  chainId: number;
  balance: string;
  averageCost?: string;
}

// Transaction types
export interface Transaction {
  id: string;
  userId: string;
  portfolioId: string;
  txHash: string;
  type: TransactionType;
  tokenAddress: string;
  tokenSymbol: string;
  amount: string;
  fromAddress: string;
  toAddress: string;
  chainId: number;
  blockNumber: number;
  gasUsed?: string;
  gasPrice?: string;
  timestamp: string;
  createdAt: string;
}

export type TransactionType = 'transfer' | 'mint' | 'burn' | 'swap' | 'stake' | 'unstake' | 'claim';

export interface RecordTransactionInput {
  portfolioId: string;
  txHash: string;
  type: TransactionType;
  tokenAddress: string;
  tokenSymbol: string;
  amount: string;
  fromAddress: string;
  toAddress: string;
  chainId: number;
  blockNumber: number;
  gasUsed?: string;
  gasPrice?: string;
  timestamp: string;
}

// Watchlist types
export interface WatchlistItem {
  id: string;
  userId: string;
  tokenAddress: string;
  tokenSymbol: string;
  tokenName: string;
  chainId: number;
  priceAlertHigh?: string;
  priceAlertLow?: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export interface AddWatchlistInput {
  tokenAddress: string;
  tokenSymbol: string;
  tokenName: string;
  chainId: number;
  priceAlertHigh?: string;
  priceAlertLow?: string;
  notes?: string;
}

// Analytics types
export interface PortfolioAnalytics {
  totalValue: number;
  totalCost: number;
  pnl: number;
  pnlPercentage: number;
  assetCount: number;
  topAssets: AssetSummary[];
  recentTransactions: Transaction[];
  dailySnapshots: DailySnapshot[];
}

export interface AssetSummary {
  tokenSymbol: string;
  tokenName: string;
  balance: string;
  value: number;
  allocation: number;
  pnl: number;
  pnlPercentage: number;
}

export interface DailySnapshot {
  date: string;
  totalValue: number;
  change: number;
  changePercentage: number;
}

export interface UserAnalytics {
  totalPortfolios: number;
  totalAssets: number;
  totalTransactions: number;
  portfolioBreakdown: PortfolioBreakdown[];
  activitySummary: ActivitySummary;
}

export interface PortfolioBreakdown {
  portfolioId: string;
  portfolioName: string;
  value: number;
  allocation: number;
}

export interface ActivitySummary {
  transactionsLast24h: number;
  transactionsLast7d: number;
  transactionsLast30d: number;
  mostActiveChain: number;
}

export interface DashboardSummary {
  totalPortfolioValue: number;
  portfolioCount: number;
  assetCount: number;
  recentTransactionCount: number;
  topPerformingAsset?: {
    symbol: string;
    pnl: number;
    pnlPercentage: number;
  };
}

export interface TransactionStats {
  totalTransactions: number;
  transactionsByType: Record<string, number>;
  transactionsByChain: Record<number, number>;
  dailyVolume: { date: string; count: number; volume: string }[];
}

export interface LeaderboardEntry {
  rank: number;
  username: string;
  portfolioName: string;
  totalValue: number;
}

// API Response types
export interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export interface PaginatedResponse<T> extends ApiResponse<T[]> {
  pagination: {
    page: number;
    limit: number;
    total: number;
    totalPages: number;
  };
}

// Chain configuration
export interface ChainConfig {
  id: number;
  name: string;
  shortName: string;
  explorerUrl: string;
  color: string;
}

export const CHAINS: ChainConfig[] = [
  {
    id: 42161,
    name: 'Arbitrum One',
    shortName: 'ARB',
    explorerUrl: 'https://arbiscan.io',
    color: '#28A0F0',
  },
  {
    id: 421614,
    name: 'Arbitrum Sepolia',
    shortName: 'ARB-SEP',
    explorerUrl: 'https://sepolia.arbiscan.io',
    color: '#28A0F0',
  },
  {
    id: 1,
    name: 'Ethereum',
    shortName: 'ETH',
    explorerUrl: 'https://etherscan.io',
    color: '#627EEA',
  },
];

export function getChainById(chainId: number): ChainConfig | undefined {
  return CHAINS.find(c => c.id === chainId);
}
