import { v4 as uuidv4 } from 'uuid';
import db from '../db/index.js';
import type {
  Portfolio,
  PortfolioWithAssets,
  CreatePortfolioInput,
  Asset,
  AddAssetInput,
  Transaction,
  RecordTransactionInput,
  WatchlistItem,
  AddWatchlistInput,
} from '../types/index.js';

export class PortfolioService {
  /**
   * Get all portfolios for a user
   */
  getPortfolios(userId: string): Portfolio[] {
    return db.prepare(`
      SELECT
        id, user_id as userId, name, description,
        is_default as isDefault, created_at as createdAt, updated_at as updatedAt
      FROM portfolios
      WHERE user_id = ?
      ORDER BY is_default DESC, created_at ASC
    `).all(userId) as Portfolio[];
  }

  /**
   * Get portfolio by ID with assets
   */
  getPortfolioById(portfolioId: string, userId: string): PortfolioWithAssets | null {
    const portfolio = db.prepare(`
      SELECT
        id, user_id as userId, name, description,
        is_default as isDefault, created_at as createdAt, updated_at as updatedAt
      FROM portfolios
      WHERE id = ? AND user_id = ?
    `).get(portfolioId, userId) as Portfolio | undefined;

    if (!portfolio) {
      return null;
    }

    const assets = this.getAssetsByPortfolio(portfolioId);
    const totalValue = assets.reduce((sum, asset) => {
      // In production, you'd fetch actual prices here
      return sum + parseFloat(asset.balance);
    }, 0);

    return {
      ...portfolio,
      assets,
      totalValue,
    };
  }

  /**
   * Create a new portfolio
   */
  createPortfolio(userId: string, input: CreatePortfolioInput): Portfolio {
    const portfolioId = uuidv4();
    const now = new Date().toISOString();

    db.prepare(`
      INSERT INTO portfolios (id, user_id, name, description, is_default, created_at, updated_at)
      VALUES (?, ?, ?, ?, 0, ?, ?)
    `).run(portfolioId, userId, input.name, input.description || null, now, now);

    return this.getPortfolioById(portfolioId, userId)!;
  }

  /**
   * Update portfolio
   */
  updatePortfolio(portfolioId: string, userId: string, updates: Partial<CreatePortfolioInput>): Portfolio | null {
    const existing = db.prepare('SELECT id FROM portfolios WHERE id = ? AND user_id = ?').get(portfolioId, userId);
    if (!existing) {
      return null;
    }

    const now = new Date().toISOString();
    db.prepare(`
      UPDATE portfolios SET
        name = COALESCE(?, name),
        description = COALESCE(?, description),
        updated_at = ?
      WHERE id = ?
    `).run(updates.name || null, updates.description || null, now, portfolioId);

    return this.getPortfolioById(portfolioId, userId);
  }

  /**
   * Delete portfolio
   */
  deletePortfolio(portfolioId: string, userId: string): boolean {
    const portfolio = db.prepare('SELECT is_default FROM portfolios WHERE id = ? AND user_id = ?').get(portfolioId, userId) as { is_default: number } | undefined;

    if (!portfolio) {
      return false;
    }

    if (portfolio.is_default) {
      throw new Error('Cannot delete default portfolio');
    }

    db.prepare('DELETE FROM portfolios WHERE id = ?').run(portfolioId);
    return true;
  }

  /**
   * Set default portfolio
   */
  setDefaultPortfolio(portfolioId: string, userId: string): Portfolio | null {
    const existing = db.prepare('SELECT id FROM portfolios WHERE id = ? AND user_id = ?').get(portfolioId, userId);
    if (!existing) {
      return null;
    }

    // Unset current default
    db.prepare('UPDATE portfolios SET is_default = 0 WHERE user_id = ?').run(userId);

    // Set new default
    const now = new Date().toISOString();
    db.prepare('UPDATE portfolios SET is_default = 1, updated_at = ? WHERE id = ?').run(now, portfolioId);

    return this.getPortfolioById(portfolioId, userId);
  }

  // Asset Management

  /**
   * Get assets by portfolio
   */
  getAssetsByPortfolio(portfolioId: string): Asset[] {
    return db.prepare(`
      SELECT
        id, portfolio_id as portfolioId, token_address as tokenAddress,
        token_symbol as tokenSymbol, token_name as tokenName,
        token_decimals as tokenDecimals, chain_id as chainId,
        balance, average_cost as averageCost,
        created_at as createdAt, updated_at as updatedAt
      FROM assets
      WHERE portfolio_id = ?
      ORDER BY created_at ASC
    `).all(portfolioId) as Asset[];
  }

  /**
   * Add or update asset
   */
  addAsset(portfolioId: string, userId: string, input: AddAssetInput): Asset {
    // Verify portfolio ownership
    const portfolio = db.prepare('SELECT id FROM portfolios WHERE id = ? AND user_id = ?').get(portfolioId, userId);
    if (!portfolio) {
      throw new Error('Portfolio not found');
    }

    const now = new Date().toISOString();

    // Check if asset already exists
    const existing = db.prepare(`
      SELECT id FROM assets
      WHERE portfolio_id = ? AND token_address = ? AND chain_id = ?
    `).get(portfolioId, input.tokenAddress, input.chainId) as { id: string } | undefined;

    if (existing) {
      // Update existing asset
      db.prepare(`
        UPDATE assets SET
          balance = ?,
          average_cost = COALESCE(?, average_cost),
          updated_at = ?
        WHERE id = ?
      `).run(input.balance, input.averageCost || null, now, existing.id);

      return db.prepare(`
        SELECT
          id, portfolio_id as portfolioId, token_address as tokenAddress,
          token_symbol as tokenSymbol, token_name as tokenName,
          token_decimals as tokenDecimals, chain_id as chainId,
          balance, average_cost as averageCost,
          created_at as createdAt, updated_at as updatedAt
        FROM assets WHERE id = ?
      `).get(existing.id) as Asset;
    }

    // Create new asset
    const assetId = uuidv4();
    db.prepare(`
      INSERT INTO assets (
        id, portfolio_id, token_address, token_symbol, token_name,
        token_decimals, chain_id, balance, average_cost, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      assetId, portfolioId, input.tokenAddress, input.tokenSymbol, input.tokenName,
      input.tokenDecimals, input.chainId, input.balance, input.averageCost || null, now, now
    );

    return db.prepare(`
      SELECT
        id, portfolio_id as portfolioId, token_address as tokenAddress,
        token_symbol as tokenSymbol, token_name as tokenName,
        token_decimals as tokenDecimals, chain_id as chainId,
        balance, average_cost as averageCost,
        created_at as createdAt, updated_at as updatedAt
      FROM assets WHERE id = ?
    `).get(assetId) as Asset;
  }

  /**
   * Update asset balance
   */
  updateAssetBalance(assetId: string, userId: string, balance: string): Asset | null {
    const asset = db.prepare(`
      SELECT a.id FROM assets a
      JOIN portfolios p ON a.portfolio_id = p.id
      WHERE a.id = ? AND p.user_id = ?
    `).get(assetId, userId) as { id: string } | undefined;

    if (!asset) {
      return null;
    }

    const now = new Date().toISOString();
    db.prepare('UPDATE assets SET balance = ?, updated_at = ? WHERE id = ?').run(balance, now, assetId);

    return db.prepare(`
      SELECT
        id, portfolio_id as portfolioId, token_address as tokenAddress,
        token_symbol as tokenSymbol, token_name as tokenName,
        token_decimals as tokenDecimals, chain_id as chainId,
        balance, average_cost as averageCost,
        created_at as createdAt, updated_at as updatedAt
      FROM assets WHERE id = ?
    `).get(assetId) as Asset;
  }

  /**
   * Remove asset from portfolio
   */
  removeAsset(assetId: string, userId: string): boolean {
    const asset = db.prepare(`
      SELECT a.id FROM assets a
      JOIN portfolios p ON a.portfolio_id = p.id
      WHERE a.id = ? AND p.user_id = ?
    `).get(assetId, userId);

    if (!asset) {
      return false;
    }

    db.prepare('DELETE FROM assets WHERE id = ?').run(assetId);
    return true;
  }

  // Transaction Management

  /**
   * Record a new transaction
   */
  recordTransaction(userId: string, input: RecordTransactionInput): Transaction {
    // Verify portfolio ownership
    const portfolio = db.prepare('SELECT id FROM portfolios WHERE id = ? AND user_id = ?').get(input.portfolioId, userId);
    if (!portfolio) {
      throw new Error('Portfolio not found');
    }

    const txId = uuidv4();
    const now = new Date().toISOString();

    db.prepare(`
      INSERT INTO transactions (
        id, user_id, portfolio_id, tx_hash, type, token_address, token_symbol,
        amount, from_address, to_address, chain_id, block_number,
        gas_used, gas_price, timestamp, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      txId, userId, input.portfolioId, input.txHash, input.type, input.tokenAddress,
      input.tokenSymbol, input.amount, input.fromAddress, input.toAddress,
      input.chainId, input.blockNumber, input.gasUsed || null, input.gasPrice || null,
      input.timestamp, now
    );

    return db.prepare(`
      SELECT
        id, user_id as userId, portfolio_id as portfolioId, tx_hash as txHash,
        type, token_address as tokenAddress, token_symbol as tokenSymbol,
        amount, from_address as fromAddress, to_address as toAddress,
        chain_id as chainId, block_number as blockNumber,
        gas_used as gasUsed, gas_price as gasPrice,
        timestamp, created_at as createdAt
      FROM transactions WHERE id = ?
    `).get(txId) as Transaction;
  }

  /**
   * Get transactions for user
   */
  getTransactions(userId: string, options?: {
    portfolioId?: string;
    type?: string;
    chainId?: number;
    limit?: number;
    offset?: number;
  }): { transactions: Transaction[]; total: number } {
    const params: (string | number)[] = [userId];
    let whereClause = 'WHERE user_id = ?';

    if (options?.portfolioId) {
      whereClause += ' AND portfolio_id = ?';
      params.push(options.portfolioId);
    }
    if (options?.type) {
      whereClause += ' AND type = ?';
      params.push(options.type);
    }
    if (options?.chainId) {
      whereClause += ' AND chain_id = ?';
      params.push(options.chainId);
    }

    const total = (db.prepare(`SELECT COUNT(*) as count FROM transactions ${whereClause}`).get(...params) as { count: number }).count;

    const limit = options?.limit || 50;
    const offset = options?.offset || 0;

    const transactions = db.prepare(`
      SELECT
        id, user_id as userId, portfolio_id as portfolioId, tx_hash as txHash,
        type, token_address as tokenAddress, token_symbol as tokenSymbol,
        amount, from_address as fromAddress, to_address as toAddress,
        chain_id as chainId, block_number as blockNumber,
        gas_used as gasUsed, gas_price as gasPrice,
        timestamp, created_at as createdAt
      FROM transactions
      ${whereClause}
      ORDER BY timestamp DESC
      LIMIT ? OFFSET ?
    `).all(...params, limit, offset) as Transaction[];

    return { transactions, total };
  }

  // Watchlist Management

  /**
   * Get user's watchlist
   */
  getWatchlist(userId: string): WatchlistItem[] {
    return db.prepare(`
      SELECT
        id, user_id as userId, token_address as tokenAddress,
        token_symbol as tokenSymbol, token_name as tokenName,
        chain_id as chainId, price_alert_high as priceAlertHigh,
        price_alert_low as priceAlertLow, notes,
        created_at as createdAt, updated_at as updatedAt
      FROM watchlist
      WHERE user_id = ?
      ORDER BY created_at DESC
    `).all(userId) as WatchlistItem[];
  }

  /**
   * Add to watchlist
   */
  addToWatchlist(userId: string, input: AddWatchlistInput): WatchlistItem {
    // Check if already watching
    const existing = db.prepare(`
      SELECT id FROM watchlist
      WHERE user_id = ? AND token_address = ? AND chain_id = ?
    `).get(userId, input.tokenAddress, input.chainId);

    if (existing) {
      throw new Error('Token already in watchlist');
    }

    const itemId = uuidv4();
    const now = new Date().toISOString();

    db.prepare(`
      INSERT INTO watchlist (
        id, user_id, token_address, token_symbol, token_name,
        chain_id, price_alert_high, price_alert_low, notes, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      itemId, userId, input.tokenAddress, input.tokenSymbol, input.tokenName,
      input.chainId, input.priceAlertHigh || null, input.priceAlertLow || null,
      input.notes || null, now, now
    );

    return db.prepare(`
      SELECT
        id, user_id as userId, token_address as tokenAddress,
        token_symbol as tokenSymbol, token_name as tokenName,
        chain_id as chainId, price_alert_high as priceAlertHigh,
        price_alert_low as priceAlertLow, notes,
        created_at as createdAt, updated_at as updatedAt
      FROM watchlist WHERE id = ?
    `).get(itemId) as WatchlistItem;
  }

  /**
   * Update watchlist item
   */
  updateWatchlistItem(itemId: string, userId: string, updates: Partial<AddWatchlistInput>): WatchlistItem | null {
    const existing = db.prepare('SELECT id FROM watchlist WHERE id = ? AND user_id = ?').get(itemId, userId);
    if (!existing) {
      return null;
    }

    const now = new Date().toISOString();
    db.prepare(`
      UPDATE watchlist SET
        price_alert_high = COALESCE(?, price_alert_high),
        price_alert_low = COALESCE(?, price_alert_low),
        notes = COALESCE(?, notes),
        updated_at = ?
      WHERE id = ?
    `).run(
      updates.priceAlertHigh || null,
      updates.priceAlertLow || null,
      updates.notes || null,
      now, itemId
    );

    return db.prepare(`
      SELECT
        id, user_id as userId, token_address as tokenAddress,
        token_symbol as tokenSymbol, token_name as tokenName,
        chain_id as chainId, price_alert_high as priceAlertHigh,
        price_alert_low as priceAlertLow, notes,
        created_at as createdAt, updated_at as updatedAt
      FROM watchlist WHERE id = ?
    `).get(itemId) as WatchlistItem;
  }

  /**
   * Remove from watchlist
   */
  removeFromWatchlist(itemId: string, userId: string): boolean {
    const existing = db.prepare('SELECT id FROM watchlist WHERE id = ? AND user_id = ?').get(itemId, userId);
    if (!existing) {
      return false;
    }

    db.prepare('DELETE FROM watchlist WHERE id = ?').run(itemId);
    return true;
  }
}

export const portfolioService = new PortfolioService();
