import { Request } from 'express';

// User types
export interface User {
  id: string;
  email: string;
  username: string;
  passwordHash: string;
  walletAddress?: string;
  createdAt: string;
  updatedAt: string;
}

export interface UserPublic {
  id: string;
  email: string;
  username: string;
  walletAddress?: string;
  createdAt: string;
}

export interface CreateUserInput {
  email: string;
  username: string;
  password: string;
  walletAddress?: string;
}

export interface LoginInput {
  email: string;
  password: string;
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

// Auth types
export interface JwtPayload {
  userId: string;
  email: string;
  iat?: number;
  exp?: number;
}

export interface AuthenticatedRequest extends Request {
  user?: JwtPayload;
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

// Price types (for external API integration)
export interface TokenPrice {
  tokenAddress: string;
  chainId: number;
  priceUsd: number;
  priceChange24h: number;
  marketCap?: number;
  volume24h?: number;
  lastUpdated: string;
}

// Notification types
export interface Notification {
  id: string;
  userId: string;
  type: NotificationType;
  title: string;
  message: string;
  metadata?: Record<string, unknown>;
  read: boolean;
  createdAt: string;
}

export type NotificationType = 'price_alert' | 'transaction' | 'portfolio_update' | 'system';

// Chain configuration
export interface ChainConfig {
  id: number;
  name: string;
  rpcUrl: string;
  explorerUrl: string;
  nativeCurrency: {
    name: string;
    symbol: string;
    decimals: number;
  };
}

// Supported chains
export const SUPPORTED_CHAINS: ChainConfig[] = [
  {
    id: 42161,
    name: 'Arbitrum One',
    rpcUrl: 'https://arb1.arbitrum.io/rpc',
    explorerUrl: 'https://arbiscan.io',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  },
  {
    id: 421614,
    name: 'Arbitrum Sepolia',
    rpcUrl: 'https://sepolia-rollup.arbitrum.io/rpc',
    explorerUrl: 'https://sepolia.arbiscan.io',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  },
  {
    id: 1,
    name: 'Ethereum',
    rpcUrl: 'https://eth.llamarpc.com',
    explorerUrl: 'https://etherscan.io',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  },
];
