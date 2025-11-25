import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';
import dotenv from 'dotenv';

import { initializeDatabase } from './db/index.js';
import authRoutes from './routes/auth.js';
import portfolioRoutes from './routes/portfolio.js';
import transactionRoutes from './routes/transactions.js';
import analyticsRoutes from './routes/analytics.js';

// Load environment variables
dotenv.config();

// Initialize database
initializeDatabase();

const app = express();
const PORT = process.env.PORT || 3001;

// Security middleware
app.use(helmet());

// CORS configuration
app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:5173',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per window
  message: {
    success: false,
    error: 'Too many requests, please try again later.',
  },
  standardHeaders: true,
  legacyHeaders: false,
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10, // Limit auth attempts
  message: {
    success: false,
    error: 'Too many authentication attempts, please try again later.',
  },
});

app.use(limiter);

// Request logging
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));

// Body parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Health check endpoint
app.get('/health', (_req, res) => {
  res.json({
    success: true,
    data: {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: process.env.npm_package_version || '1.0.0',
    },
  });
});

// API routes
app.use('/api/auth', authLimiter, authRoutes);
app.use('/api/portfolios', portfolioRoutes);
app.use('/api/transactions', transactionRoutes);
app.use('/api/analytics', analyticsRoutes);

// API documentation endpoint
app.get('/api', (_req, res) => {
  res.json({
    success: true,
    data: {
      name: 'DeFi Portfolio Tracker API',
      version: '1.0.0',
      description: 'Backend API for tracking DeFi portfolios and transactions',
      endpoints: {
        auth: {
          'POST /api/auth/register': 'Register a new user',
          'POST /api/auth/login': 'Login user',
          'POST /api/auth/refresh': 'Refresh access token',
          'POST /api/auth/logout': 'Logout user',
          'GET /api/auth/me': 'Get current user profile',
          'PATCH /api/auth/profile': 'Update user profile',
          'POST /api/auth/change-password': 'Change password',
        },
        portfolios: {
          'GET /api/portfolios': 'Get all portfolios',
          'GET /api/portfolios/:id': 'Get portfolio by ID',
          'POST /api/portfolios': 'Create new portfolio',
          'PATCH /api/portfolios/:id': 'Update portfolio',
          'DELETE /api/portfolios/:id': 'Delete portfolio',
          'POST /api/portfolios/:id/default': 'Set default portfolio',
          'GET /api/portfolios/:id/assets': 'Get portfolio assets',
          'POST /api/portfolios/:id/assets': 'Add asset to portfolio',
          'PATCH /api/portfolios/:portfolioId/assets/:assetId': 'Update asset balance',
          'DELETE /api/portfolios/:portfolioId/assets/:assetId': 'Remove asset',
          'GET /api/portfolios/watchlist/items': 'Get watchlist',
          'POST /api/portfolios/watchlist/items': 'Add to watchlist',
          'PATCH /api/portfolios/watchlist/items/:id': 'Update watchlist item',
          'DELETE /api/portfolios/watchlist/items/:id': 'Remove from watchlist',
        },
        transactions: {
          'GET /api/transactions': 'Get transactions (paginated)',
          'POST /api/transactions': 'Record new transaction',
          'GET /api/transactions/recent': 'Get recent transactions',
          'GET /api/transactions/by-portfolio/:portfolioId': 'Get by portfolio',
          'GET /api/transactions/by-type/:type': 'Get by type',
          'GET /api/transactions/by-chain/:chainId': 'Get by chain',
        },
        analytics: {
          'GET /api/analytics/portfolio/:portfolioId': 'Get portfolio analytics',
          'GET /api/analytics/user': 'Get user analytics',
          'GET /api/analytics/transactions': 'Get transaction statistics',
          'POST /api/analytics/snapshot/:portfolioId': 'Create portfolio snapshot',
          'GET /api/analytics/leaderboard': 'Get portfolio leaderboard',
          'GET /api/analytics/summary': 'Get dashboard summary',
        },
      },
    },
  });
});

// 404 handler
app.use((_req, res) => {
  res.status(404).json({
    success: false,
    error: 'Endpoint not found',
  });
});

// Global error handler
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    success: false,
    error: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message,
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   🚀 DeFi Portfolio Tracker API                           ║
║                                                           ║
║   Server running on: http://localhost:${PORT}              ║
║   Environment: ${(process.env.NODE_ENV || 'development').padEnd(38)}║
║                                                           ║
║   API Documentation: http://localhost:${PORT}/api          ║
║   Health Check: http://localhost:${PORT}/health            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
  `);
});

export default app;
