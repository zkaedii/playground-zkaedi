import { Router, Response } from 'express';
import { analyticsService } from '../services/analytics.js';
import { authenticate, optionalAuth } from '../middleware/auth.js';
import type {
  AuthenticatedRequest,
  ApiResponse,
  PortfolioAnalytics,
  UserAnalytics,
} from '../types/index.js';

const router = Router();

/**
 * GET /api/analytics/portfolio/:portfolioId
 * Get analytics for a specific portfolio
 */
router.get(
  '/portfolio/:portfolioId',
  authenticate,
  (req: AuthenticatedRequest, res: Response<ApiResponse<PortfolioAnalytics>>) => {
    try {
      const analytics = analyticsService.getPortfolioAnalytics(
        req.params.portfolioId,
        req.user!.userId
      );

      if (!analytics) {
        res.status(404).json({
          success: false,
          error: 'Portfolio not found',
        });
        return;
      }

      res.json({
        success: true,
        data: analytics,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get portfolio analytics';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * GET /api/analytics/user
 * Get user-level analytics
 */
router.get(
  '/user',
  authenticate,
  (req: AuthenticatedRequest, res: Response<ApiResponse<UserAnalytics>>) => {
    try {
      const analytics = analyticsService.getUserAnalytics(req.user!.userId);
      res.json({
        success: true,
        data: analytics,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get user analytics';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * GET /api/analytics/transactions
 * Get transaction statistics
 */
router.get(
  '/transactions',
  authenticate,
  (req: AuthenticatedRequest, res: Response<ApiResponse<{
    totalTransactions: number;
    transactionsByType: Record<string, number>;
    transactionsByChain: Record<number, number>;
    dailyVolume: { date: string; count: number; volume: string }[];
  }>>) => {
    try {
      const days = parseInt(req.query.days as string) || 30;
      const stats = analyticsService.getTransactionStats(req.user!.userId, days);
      res.json({
        success: true,
        data: stats,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get transaction stats';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * POST /api/analytics/snapshot/:portfolioId
 * Create daily snapshot for portfolio
 */
router.post(
  '/snapshot/:portfolioId',
  authenticate,
  (req: AuthenticatedRequest, res: Response<ApiResponse>) => {
    try {
      // Verify ownership first
      const analytics = analyticsService.getPortfolioAnalytics(
        req.params.portfolioId,
        req.user!.userId
      );

      if (!analytics) {
        res.status(404).json({
          success: false,
          error: 'Portfolio not found',
        });
        return;
      }

      analyticsService.createPortfolioSnapshot(req.params.portfolioId);
      res.json({
        success: true,
        message: 'Snapshot created successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to create snapshot';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * GET /api/analytics/leaderboard
 * Get portfolio leaderboard (public)
 */
router.get(
  '/leaderboard',
  optionalAuth,
  (_req: AuthenticatedRequest, res: Response<ApiResponse<{
    rank: number;
    username: string;
    portfolioName: string;
    totalValue: number;
  }[]>>) => {
    try {
      const leaderboard = analyticsService.getLeaderboard(10);
      res.json({
        success: true,
        data: leaderboard,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get leaderboard';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * GET /api/analytics/summary
 * Get quick summary for dashboard
 */
router.get(
  '/summary',
  authenticate,
  (req: AuthenticatedRequest, res: Response<ApiResponse<{
    totalPortfolioValue: number;
    portfolioCount: number;
    assetCount: number;
    recentTransactionCount: number;
    topPerformingAsset?: { symbol: string; pnl: number; pnlPercentage: number };
  }>>) => {
    try {
      const userAnalytics = analyticsService.getUserAnalytics(req.user!.userId);

      // Calculate total portfolio value
      const totalPortfolioValue = userAnalytics.portfolioBreakdown.reduce(
        (sum, p) => sum + p.value,
        0
      );

      // Get top performing asset across all portfolios
      // This would require iterating through portfolios in production
      const summary = {
        totalPortfolioValue,
        portfolioCount: userAnalytics.totalPortfolios,
        assetCount: userAnalytics.totalAssets,
        recentTransactionCount: userAnalytics.activitySummary.transactionsLast7d,
      };

      res.json({
        success: true,
        data: summary,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get summary';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

export default router;
