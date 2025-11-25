import { Router, Response } from 'express';
import { portfolioService } from '../services/portfolio.js';
import { authenticate } from '../middleware/auth.js';
import {
  validate,
  createPortfolioSchema,
  updatePortfolioSchema,
  addAssetSchema,
  updateBalanceSchema,
  addWatchlistSchema,
  updateWatchlistSchema,
} from '../middleware/validation.js';
import type {
  AuthenticatedRequest,
  ApiResponse,
  Portfolio,
  PortfolioWithAssets,
  Asset,
  WatchlistItem,
} from '../types/index.js';

const router = Router();

// All routes require authentication
router.use(authenticate);

// Portfolio Management

/**
 * GET /api/portfolios
 * Get all portfolios for current user
 */
router.get(
  '/',
  (req: AuthenticatedRequest, res: Response<ApiResponse<Portfolio[]>>) => {
    try {
      const portfolios = portfolioService.getPortfolios(req.user!.userId);
      res.json({
        success: true,
        data: portfolios,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get portfolios';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * GET /api/portfolios/:id
 * Get portfolio by ID with assets
 */
router.get(
  '/:id',
  (req: AuthenticatedRequest, res: Response<ApiResponse<PortfolioWithAssets>>) => {
    try {
      const portfolio = portfolioService.getPortfolioById(req.params.id, req.user!.userId);
      if (!portfolio) {
        res.status(404).json({
          success: false,
          error: 'Portfolio not found',
        });
        return;
      }
      res.json({
        success: true,
        data: portfolio,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get portfolio';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * POST /api/portfolios
 * Create a new portfolio
 */
router.post(
  '/',
  validate(createPortfolioSchema),
  (req: AuthenticatedRequest, res: Response<ApiResponse<Portfolio>>) => {
    try {
      const portfolio = portfolioService.createPortfolio(req.user!.userId, req.body);
      res.status(201).json({
        success: true,
        data: portfolio,
        message: 'Portfolio created successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to create portfolio';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * PATCH /api/portfolios/:id
 * Update portfolio
 */
router.patch(
  '/:id',
  validate(updatePortfolioSchema),
  (req: AuthenticatedRequest, res: Response<ApiResponse<Portfolio>>) => {
    try {
      const portfolio = portfolioService.updatePortfolio(req.params.id, req.user!.userId, req.body);
      if (!portfolio) {
        res.status(404).json({
          success: false,
          error: 'Portfolio not found',
        });
        return;
      }
      res.json({
        success: true,
        data: portfolio,
        message: 'Portfolio updated successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to update portfolio';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * DELETE /api/portfolios/:id
 * Delete portfolio
 */
router.delete(
  '/:id',
  (req: AuthenticatedRequest, res: Response<ApiResponse>) => {
    try {
      const deleted = portfolioService.deletePortfolio(req.params.id, req.user!.userId);
      if (!deleted) {
        res.status(404).json({
          success: false,
          error: 'Portfolio not found',
        });
        return;
      }
      res.json({
        success: true,
        message: 'Portfolio deleted successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to delete portfolio';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * POST /api/portfolios/:id/default
 * Set portfolio as default
 */
router.post(
  '/:id/default',
  (req: AuthenticatedRequest, res: Response<ApiResponse<Portfolio>>) => {
    try {
      const portfolio = portfolioService.setDefaultPortfolio(req.params.id, req.user!.userId);
      if (!portfolio) {
        res.status(404).json({
          success: false,
          error: 'Portfolio not found',
        });
        return;
      }
      res.json({
        success: true,
        data: portfolio,
        message: 'Default portfolio updated',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to set default portfolio';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

// Asset Management

/**
 * GET /api/portfolios/:id/assets
 * Get assets for portfolio
 */
router.get(
  '/:id/assets',
  (req: AuthenticatedRequest, res: Response<ApiResponse<Asset[]>>) => {
    try {
      // Verify ownership
      const portfolio = portfolioService.getPortfolioById(req.params.id, req.user!.userId);
      if (!portfolio) {
        res.status(404).json({
          success: false,
          error: 'Portfolio not found',
        });
        return;
      }
      res.json({
        success: true,
        data: portfolio.assets,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get assets';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * POST /api/portfolios/:id/assets
 * Add asset to portfolio
 */
router.post(
  '/:id/assets',
  validate(addAssetSchema),
  (req: AuthenticatedRequest, res: Response<ApiResponse<Asset>>) => {
    try {
      const asset = portfolioService.addAsset(req.params.id, req.user!.userId, req.body);
      res.status(201).json({
        success: true,
        data: asset,
        message: 'Asset added successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to add asset';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * PATCH /api/portfolios/:portfolioId/assets/:assetId
 * Update asset balance
 */
router.patch(
  '/:portfolioId/assets/:assetId',
  validate(updateBalanceSchema),
  (req: AuthenticatedRequest, res: Response<ApiResponse<Asset>>) => {
    try {
      const asset = portfolioService.updateAssetBalance(
        req.params.assetId,
        req.user!.userId,
        req.body.balance
      );
      if (!asset) {
        res.status(404).json({
          success: false,
          error: 'Asset not found',
        });
        return;
      }
      res.json({
        success: true,
        data: asset,
        message: 'Asset balance updated',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to update asset';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * DELETE /api/portfolios/:portfolioId/assets/:assetId
 * Remove asset from portfolio
 */
router.delete(
  '/:portfolioId/assets/:assetId',
  (req: AuthenticatedRequest, res: Response<ApiResponse>) => {
    try {
      const deleted = portfolioService.removeAsset(req.params.assetId, req.user!.userId);
      if (!deleted) {
        res.status(404).json({
          success: false,
          error: 'Asset not found',
        });
        return;
      }
      res.json({
        success: true,
        message: 'Asset removed successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to remove asset';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

// Watchlist Management

/**
 * GET /api/portfolios/watchlist
 * Get user's watchlist
 */
router.get(
  '/watchlist/items',
  (req: AuthenticatedRequest, res: Response<ApiResponse<WatchlistItem[]>>) => {
    try {
      const watchlist = portfolioService.getWatchlist(req.user!.userId);
      res.json({
        success: true,
        data: watchlist,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get watchlist';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * POST /api/portfolios/watchlist
 * Add to watchlist
 */
router.post(
  '/watchlist/items',
  validate(addWatchlistSchema),
  (req: AuthenticatedRequest, res: Response<ApiResponse<WatchlistItem>>) => {
    try {
      const item = portfolioService.addToWatchlist(req.user!.userId, req.body);
      res.status(201).json({
        success: true,
        data: item,
        message: 'Added to watchlist',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to add to watchlist';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * PATCH /api/portfolios/watchlist/:id
 * Update watchlist item
 */
router.patch(
  '/watchlist/items/:id',
  validate(updateWatchlistSchema),
  (req: AuthenticatedRequest, res: Response<ApiResponse<WatchlistItem>>) => {
    try {
      const item = portfolioService.updateWatchlistItem(req.params.id, req.user!.userId, req.body);
      if (!item) {
        res.status(404).json({
          success: false,
          error: 'Watchlist item not found',
        });
        return;
      }
      res.json({
        success: true,
        data: item,
        message: 'Watchlist item updated',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to update watchlist item';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * DELETE /api/portfolios/watchlist/:id
 * Remove from watchlist
 */
router.delete(
  '/watchlist/items/:id',
  (req: AuthenticatedRequest, res: Response<ApiResponse>) => {
    try {
      const deleted = portfolioService.removeFromWatchlist(req.params.id, req.user!.userId);
      if (!deleted) {
        res.status(404).json({
          success: false,
          error: 'Watchlist item not found',
        });
        return;
      }
      res.json({
        success: true,
        message: 'Removed from watchlist',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to remove from watchlist';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

export default router;
