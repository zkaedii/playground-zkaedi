import { Router, Response } from 'express';
import { authService } from '../services/auth.js';
import { authenticate } from '../middleware/auth.js';
import {
  validate,
  registerSchema,
  loginSchema,
  refreshTokenSchema,
  updateProfileSchema,
  changePasswordSchema,
} from '../middleware/validation.js';
import type { AuthenticatedRequest, ApiResponse, UserPublic } from '../types/index.js';

const router = Router();

/**
 * POST /api/auth/register
 * Register a new user
 */
router.post(
  '/register',
  validate(registerSchema),
  async (req, res: Response<ApiResponse<{ user: UserPublic; token: string; refreshToken: string }>>) => {
    try {
      const result = await authService.register(req.body);
      res.status(201).json({
        success: true,
        data: result,
        message: 'User registered successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Registration failed';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * POST /api/auth/login
 * Login user
 */
router.post(
  '/login',
  validate(loginSchema),
  async (req, res: Response<ApiResponse<{ user: UserPublic; token: string; refreshToken: string }>>) => {
    try {
      const result = await authService.login(req.body);
      res.json({
        success: true,
        data: result,
        message: 'Login successful',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Login failed';
      res.status(401).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * POST /api/auth/refresh
 * Refresh access token
 */
router.post(
  '/refresh',
  validate(refreshTokenSchema),
  async (req, res: Response<ApiResponse<{ token: string; refreshToken: string }>>) => {
    try {
      const result = await authService.refreshAccessToken(req.body.refreshToken);
      res.json({
        success: true,
        data: result,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Token refresh failed';
      res.status(401).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * POST /api/auth/logout
 * Logout user (invalidate refresh tokens)
 */
router.post(
  '/logout',
  authenticate,
  async (req: AuthenticatedRequest, res: Response<ApiResponse>) => {
    try {
      await authService.logout(req.user!.userId);
      res.json({
        success: true,
        message: 'Logged out successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Logout failed';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * GET /api/auth/me
 * Get current user profile
 */
router.get(
  '/me',
  authenticate,
  (req: AuthenticatedRequest, res: Response<ApiResponse<UserPublic>>) => {
    try {
      const user = authService.getUserById(req.user!.userId);
      if (!user) {
        res.status(404).json({
          success: false,
          error: 'User not found',
        });
        return;
      }
      res.json({
        success: true,
        data: user,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get user';
      res.status(500).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * PATCH /api/auth/profile
 * Update user profile
 */
router.patch(
  '/profile',
  authenticate,
  validate(updateProfileSchema),
  async (req: AuthenticatedRequest, res: Response<ApiResponse<UserPublic>>) => {
    try {
      const user = await authService.updateProfile(req.user!.userId, req.body);
      res.json({
        success: true,
        data: user,
        message: 'Profile updated successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to update profile';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

/**
 * POST /api/auth/change-password
 * Change user password
 */
router.post(
  '/change-password',
  authenticate,
  validate(changePasswordSchema),
  async (req: AuthenticatedRequest, res: Response<ApiResponse>) => {
    try {
      await authService.changePassword(
        req.user!.userId,
        req.body.currentPassword,
        req.body.newPassword
      );
      res.json({
        success: true,
        message: 'Password changed successfully',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to change password';
      res.status(400).json({
        success: false,
        error: message,
      });
    }
  }
);

export default router;
