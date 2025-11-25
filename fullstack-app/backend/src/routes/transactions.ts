import { Router, Response } from 'express';
import { portfolioService } from '../services/portfolio.js';
import { authenticate } from '../middleware/auth.js';
import { validate, recordTransactionSchema, transactionQuerySchema } from '../middleware/validation.js';
import type { AuthenticatedRequest, ApiResponse, Transaction, PaginatedResponse } from '../types/index.js';

const router = Router();

// All routes require authentication
router.use(authenticate);

/**
 * GET /api/transactions
 * Get transactions for current user
 */
router.get(
  '/',
  validate(transactionQuerySchema, 'query'),
  (req: AuthenticatedRequest, res: Response<PaginatedResponse<Transaction>>) => {
    try {
      const { portfolioId, type, chainId, page = 1, limit = 50 } = req.query as {
        portfolioId?: string;
        type?: string;
        chainId?: number;
        page?: number;
        limit?: number;
      };

      const offset = (page - 1) * limit;
      const { transactions, total } = portfolioService.getTransactions(req.user!.userId, {
        portfolioId,
        type,
        chainId,
        limit,
        offset,
      });

      res.json({
        success: true,
        data: transactions,
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
        },
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get transactions';
      res.status(500).json({
        success: false,
        error: message,
        pagination: { page: 1, limit: 50, total: 0, totalPages: 0 },
      });
    }
  }
);

/**
 * POST /api/transactions
 * Record a new transaction
 */
router.post(
  '/',
  validate(recordTransactionSchema),
  (req: AuthenticatedRequest, res: Response<ApiResponse<Transaction>>) => {
    try {
      const transaction = portfolioService.recordTransaction(req.user!.userId, req.body);
      res.status(201).json({
        success: true,
        data: transaction,
        message: 'Transaction recorded successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to record transaction';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * GET /api/transactions/recent
 * Get recent transactions (last 10)
 */
router.get(
  '/recent',
  (req: AuthenticatedRequest, res: Response<ApiResponse<Transaction[]>>) => {
    try {
      const { transactions } = portfolioService.getTransactions(req.user!.userId, { limit: 10 });
      res.json({
        success: true,
        data: transactions,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get recent transactions';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * GET /api/transactions/by-portfolio/:portfolioId
 * Get transactions for a specific portfolio
 */
router.get(
  '/by-portfolio/:portfolioId',
  (req: AuthenticatedRequest, res: Response<PaginatedResponse<Transaction>>) => {
    try {
      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 50;
      const offset = (page - 1) * limit;

      const { transactions, total } = portfolioService.getTransactions(req.user!.userId, {
        portfolioId: req.params.portfolioId,
        limit,
        offset,
      });

      res.json({
        success: true,
        data: transactions,
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
        },
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get transactions';
      res.status(500).json({
        success: false,
        error: message,
        pagination: { page: 1, limit: 50, total: 0, totalPages: 0 },
      });
    }
  }
);

/**
 * GET /api/transactions/by-type/:type
 * Get transactions by type
 */
router.get(
  '/by-type/:type',
  (req: AuthenticatedRequest, res: Response<PaginatedResponse<Transaction>>) => {
    try {
      const validTypes = ['transfer', 'mint', 'burn', 'swap', 'stake', 'unstake', 'claim'];
      if (!validTypes.includes(req.params.type)) {
        res.status(400).json({
          success: false,
          error: 'Invalid transaction type',
          pagination: { page: 1, limit: 50, total: 0, totalPages: 0 },
        });
        return;
      }

      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 50;
      const offset = (page - 1) * limit;

      const { transactions, total } = portfolioService.getTransactions(req.user!.userId, {
        type: req.params.type,
        limit,
        offset,
      });

      res.json({
        success: true,
        data: transactions,
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
        },
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get transactions';
      res.status(500).json({
        success: false,
        error: message,
        pagination: { page: 1, limit: 50, total: 0, totalPages: 0 },
      });
    }
  }
);

/**
 * GET /api/transactions/by-chain/:chainId
 * Get transactions by chain
 */
router.get(
  '/by-chain/:chainId',
  (req: AuthenticatedRequest, res: Response<PaginatedResponse<Transaction>>) => {
    try {
      const chainId = parseInt(req.params.chainId);
      if (isNaN(chainId)) {
        res.status(400).json({
          success: false,
          error: 'Invalid chain ID',
          pagination: { page: 1, limit: 50, total: 0, totalPages: 0 },
        });
        return;
      }

      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 50;
      const offset = (page - 1) * limit;

      const { transactions, total } = portfolioService.getTransactions(req.user!.userId, {
        chainId,
        limit,
        offset,
      });

      res.json({
        success: true,
        data: transactions,
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
        },
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get transactions';
      res.status(500).json({
        success: false,
        error: message,
        pagination: { page: 1, limit: 50, total: 0, totalPages: 0 },
      });
    }
  }
);

export default router;
