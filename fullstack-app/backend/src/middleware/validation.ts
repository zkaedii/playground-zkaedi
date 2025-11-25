import { Request, Response, NextFunction } from 'express';
import { z, ZodSchema, ZodError } from 'zod';
import type { ApiResponse } from '../types/index.js';

/**
 * Validation middleware factory
 */
export function validate<T>(schema: ZodSchema<T>, source: 'body' | 'query' | 'params' = 'body') {
  return (req: Request, res: Response<ApiResponse>, next: NextFunction): void => {
    try {
      const data = source === 'body' ? req.body : source === 'query' ? req.query : req.params;
      schema.parse(data);
      next();
    } catch (error) {
      if (error instanceof ZodError) {
        res.status(400).json({
          success: false,
          error: 'Validation error',
          message: error.errors.map(e => `${e.path.join('.')}: ${e.message}`).join(', '),
        });
        return;
      }
      throw error;
    }
  };
}

// Auth schemas
export const registerSchema = z.object({
  email: z.string().email('Invalid email format'),
  username: z.string().min(3, 'Username must be at least 3 characters').max(30, 'Username must be at most 30 characters').regex(/^[a-zA-Z0-9_]+$/, 'Username can only contain letters, numbers, and underscores'),
  password: z.string().min(8, 'Password must be at least 8 characters').regex(/[A-Z]/, 'Password must contain at least one uppercase letter').regex(/[a-z]/, 'Password must contain at least one lowercase letter').regex(/[0-9]/, 'Password must contain at least one number'),
  walletAddress: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid wallet address').optional(),
});

export const loginSchema = z.object({
  email: z.string().email('Invalid email format'),
  password: z.string().min(1, 'Password is required'),
});

export const refreshTokenSchema = z.object({
  refreshToken: z.string().min(1, 'Refresh token is required'),
});

// Portfolio schemas
export const createPortfolioSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100, 'Name must be at most 100 characters'),
  description: z.string().max(500, 'Description must be at most 500 characters').optional(),
});

export const updatePortfolioSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
});

// Asset schemas
export const addAssetSchema = z.object({
  tokenAddress: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid token address'),
  tokenSymbol: z.string().min(1, 'Token symbol is required').max(20, 'Token symbol must be at most 20 characters'),
  tokenName: z.string().min(1, 'Token name is required').max(100, 'Token name must be at most 100 characters'),
  tokenDecimals: z.number().int().min(0).max(18),
  chainId: z.number().int().positive(),
  balance: z.string().regex(/^\d+(\.\d+)?$/, 'Invalid balance format'),
  averageCost: z.string().regex(/^\d+(\.\d+)?$/, 'Invalid average cost format').optional(),
});

export const updateBalanceSchema = z.object({
  balance: z.string().regex(/^\d+(\.\d+)?$/, 'Invalid balance format'),
});

// Transaction schemas
export const recordTransactionSchema = z.object({
  portfolioId: z.string().uuid('Invalid portfolio ID'),
  txHash: z.string().regex(/^0x[a-fA-F0-9]{64}$/, 'Invalid transaction hash'),
  type: z.enum(['transfer', 'mint', 'burn', 'swap', 'stake', 'unstake', 'claim']),
  tokenAddress: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid token address'),
  tokenSymbol: z.string().min(1).max(20),
  amount: z.string().regex(/^\d+(\.\d+)?$/, 'Invalid amount format'),
  fromAddress: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid from address'),
  toAddress: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid to address'),
  chainId: z.number().int().positive(),
  blockNumber: z.number().int().nonnegative(),
  gasUsed: z.string().optional(),
  gasPrice: z.string().optional(),
  timestamp: z.string().datetime('Invalid timestamp format'),
});

// Watchlist schemas
export const addWatchlistSchema = z.object({
  tokenAddress: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid token address'),
  tokenSymbol: z.string().min(1).max(20),
  tokenName: z.string().min(1).max(100),
  chainId: z.number().int().positive(),
  priceAlertHigh: z.string().regex(/^\d+(\.\d+)?$/).optional(),
  priceAlertLow: z.string().regex(/^\d+(\.\d+)?$/).optional(),
  notes: z.string().max(500).optional(),
});

export const updateWatchlistSchema = z.object({
  priceAlertHigh: z.string().regex(/^\d+(\.\d+)?$/).optional().nullable(),
  priceAlertLow: z.string().regex(/^\d+(\.\d+)?$/).optional().nullable(),
  notes: z.string().max(500).optional().nullable(),
});

// Query schemas
export const paginationSchema = z.object({
  page: z.string().regex(/^\d+$/).transform(Number).optional(),
  limit: z.string().regex(/^\d+$/).transform(Number).optional(),
});

export const transactionQuerySchema = z.object({
  portfolioId: z.string().uuid().optional(),
  type: z.enum(['transfer', 'mint', 'burn', 'swap', 'stake', 'unstake', 'claim']).optional(),
  chainId: z.string().regex(/^\d+$/).transform(Number).optional(),
  page: z.string().regex(/^\d+$/).transform(Number).optional(),
  limit: z.string().regex(/^\d+$/).transform(Number).optional(),
});

// Profile schemas
export const updateProfileSchema = z.object({
  username: z.string().min(3).max(30).regex(/^[a-zA-Z0-9_]+$/).optional(),
  walletAddress: z.string().regex(/^0x[a-fA-F0-9]{40}$/).optional().nullable(),
});

export const changePasswordSchema = z.object({
  currentPassword: z.string().min(1, 'Current password is required'),
  newPassword: z.string().min(8).regex(/[A-Z]/).regex(/[a-z]/).regex(/[0-9]/),
});
