import db from '../db/index.js';
import type {
  PortfolioAnalytics,
  UserAnalytics,
  AssetSummary,
  DailySnapshot,
  Transaction,
} from '../types/index.js';

export class AnalyticsService {
  /**
   * Get portfolio analytics
   */
  getPortfolioAnalytics(portfolioId: string, userId: string): PortfolioAnalytics | null {
    // Verify ownership
    const portfolio = db.prepare('SELECT id FROM portfolios WHERE id = ? AND user_id = ?').get(portfolioId, userId);
    if (!portfolio) {
      return null;
    }

    // Get assets
    const assets = db.prepare(`
      SELECT
        token_symbol as tokenSymbol, token_name as tokenName,
        balance, average_cost as averageCost
      FROM assets
      WHERE portfolio_id = ?
    `).all(portfolioId) as { tokenSymbol: string; tokenName: string; balance: string; averageCost: string | null }[];

    // Calculate totals (in production, you'd fetch actual prices)
    let totalValue = 0;
    let totalCost = 0;

    const topAssets: AssetSummary[] = assets.map(asset => {
      const balance = parseFloat(asset.balance) || 0;
      const avgCost = parseFloat(asset.averageCost || '0') || 0;
      const value = balance; // Simplified - in production, multiply by price
      const cost = avgCost * balance;

      totalValue += value;
      totalCost += cost;

      return {
        tokenSymbol: asset.tokenSymbol,
        tokenName: asset.tokenName,
        balance: asset.balance,
        value,
        allocation: 0, // Will be calculated after totals
        pnl: value - cost,
        pnlPercentage: cost > 0 ? ((value - cost) / cost) * 100 : 0,
      };
    });

    // Calculate allocations
    topAssets.forEach(asset => {
      asset.allocation = totalValue > 0 ? (asset.value / totalValue) * 100 : 0;
    });

    // Sort by value descending
    topAssets.sort((a, b) => b.value - a.value);

    // Get recent transactions
    const recentTransactions = db.prepare(`
      SELECT
        id, user_id as userId, portfolio_id as portfolioId, tx_hash as txHash,
        type, token_address as tokenAddress, token_symbol as tokenSymbol,
        amount, from_address as fromAddress, to_address as toAddress,
        chain_id as chainId, block_number as blockNumber,
        gas_used as gasUsed, gas_price as gasPrice,
        timestamp, created_at as createdAt
      FROM transactions
      WHERE portfolio_id = ?
      ORDER BY timestamp DESC
      LIMIT 10
    `).all(portfolioId) as Transaction[];

    // Get daily snapshots
    const dailySnapshots = db.prepare(`
      SELECT
        snapshot_date as date, total_value as totalValue
      FROM portfolio_snapshots
      WHERE portfolio_id = ?
      ORDER BY snapshot_date DESC
      LIMIT 30
    `).all(portfolioId) as { date: string; totalValue: string }[];

    const snapshots: DailySnapshot[] = dailySnapshots.map((snap, index, arr) => {
      const value = parseFloat(snap.totalValue);
      const prevValue = index < arr.length - 1 ? parseFloat(arr[index + 1].totalValue) : value;
      const change = value - prevValue;

      return {
        date: snap.date,
        totalValue: value,
        change,
        changePercentage: prevValue > 0 ? (change / prevValue) * 100 : 0,
      };
    });

    return {
      totalValue,
      totalCost,
      pnl: totalValue - totalCost,
      pnlPercentage: totalCost > 0 ? ((totalValue - totalCost) / totalCost) * 100 : 0,
      assetCount: assets.length,
      topAssets: topAssets.slice(0, 10),
      recentTransactions,
      dailySnapshots: snapshots,
    };
  }

  /**
   * Get user-level analytics
   */
  getUserAnalytics(userId: string): UserAnalytics {
    // Count portfolios
    const portfolioCount = (db.prepare('SELECT COUNT(*) as count FROM portfolios WHERE user_id = ?').get(userId) as { count: number }).count;

    // Count total assets
    const assetCount = (db.prepare(`
      SELECT COUNT(*) as count FROM assets a
      JOIN portfolios p ON a.portfolio_id = p.id
      WHERE p.user_id = ?
    `).get(userId) as { count: number }).count;

    // Count transactions
    const txCount = (db.prepare('SELECT COUNT(*) as count FROM transactions WHERE user_id = ?').get(userId) as { count: number }).count;

    // Get portfolio breakdown
    const portfolios = db.prepare(`
      SELECT p.id, p.name, COALESCE(SUM(CAST(a.balance AS REAL)), 0) as value
      FROM portfolios p
      LEFT JOIN assets a ON p.id = a.portfolio_id
      WHERE p.user_id = ?
      GROUP BY p.id
    `).all(userId) as { id: string; name: string; value: number }[];

    const totalValue = portfolios.reduce((sum, p) => sum + p.value, 0);

    const portfolioBreakdown = portfolios.map(p => ({
      portfolioId: p.id,
      portfolioName: p.name,
      value: p.value,
      allocation: totalValue > 0 ? (p.value / totalValue) * 100 : 0,
    }));

    // Activity summary
    const now = new Date();
    const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();

    const tx24h = (db.prepare(`
      SELECT COUNT(*) as count FROM transactions
      WHERE user_id = ? AND timestamp >= ?
    `).get(userId, oneDayAgo) as { count: number }).count;

    const tx7d = (db.prepare(`
      SELECT COUNT(*) as count FROM transactions
      WHERE user_id = ? AND timestamp >= ?
    `).get(userId, sevenDaysAgo) as { count: number }).count;

    const tx30d = (db.prepare(`
      SELECT COUNT(*) as count FROM transactions
      WHERE user_id = ? AND timestamp >= ?
    `).get(userId, thirtyDaysAgo) as { count: number }).count;

    const mostActiveChain = db.prepare(`
      SELECT chain_id, COUNT(*) as count FROM transactions
      WHERE user_id = ?
      GROUP BY chain_id
      ORDER BY count DESC
      LIMIT 1
    `).get(userId) as { chain_id: number; count: number } | undefined;

    return {
      totalPortfolios: portfolioCount,
      totalAssets: assetCount,
      totalTransactions: txCount,
      portfolioBreakdown,
      activitySummary: {
        transactionsLast24h: tx24h,
        transactionsLast7d: tx7d,
        transactionsLast30d: tx30d,
        mostActiveChain: mostActiveChain?.chain_id || 1,
      },
    };
  }

  /**
   * Get transaction statistics
   */
  getTransactionStats(userId: string, days: number = 30): {
    totalTransactions: number;
    transactionsByType: Record<string, number>;
    transactionsByChain: Record<number, number>;
    dailyVolume: { date: string; count: number; volume: string }[];
  } {
    const startDate = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();

    // Total transactions
    const total = (db.prepare(`
      SELECT COUNT(*) as count FROM transactions
      WHERE user_id = ? AND timestamp >= ?
    `).get(userId, startDate) as { count: number }).count;

    // By type
    const byType = db.prepare(`
      SELECT type, COUNT(*) as count FROM transactions
      WHERE user_id = ? AND timestamp >= ?
      GROUP BY type
    `).all(userId, startDate) as { type: string; count: number }[];

    const transactionsByType: Record<string, number> = {};
    byType.forEach(t => {
      transactionsByType[t.type] = t.count;
    });

    // By chain
    const byChain = db.prepare(`
      SELECT chain_id, COUNT(*) as count FROM transactions
      WHERE user_id = ? AND timestamp >= ?
      GROUP BY chain_id
    `).all(userId, startDate) as { chain_id: number; count: number }[];

    const transactionsByChain: Record<number, number> = {};
    byChain.forEach(c => {
      transactionsByChain[c.chain_id] = c.count;
    });

    // Daily volume
    const dailyVolume = db.prepare(`
      SELECT
        DATE(timestamp) as date,
        COUNT(*) as count,
        SUM(CAST(amount AS REAL)) as volume
      FROM transactions
      WHERE user_id = ? AND timestamp >= ?
      GROUP BY DATE(timestamp)
      ORDER BY date DESC
    `).all(userId, startDate) as { date: string; count: number; volume: number }[];

    return {
      totalTransactions: total,
      transactionsByType,
      transactionsByChain,
      dailyVolume: dailyVolume.map(d => ({
        date: d.date,
        count: d.count,
        volume: d.volume?.toString() || '0',
      })),
    };
  }

  /**
   * Create daily snapshot for portfolio
   */
  createPortfolioSnapshot(portfolioId: string): void {
    const assets = db.prepare(`
      SELECT balance FROM assets WHERE portfolio_id = ?
    `).all(portfolioId) as { balance: string }[];

    const totalValue = assets.reduce((sum, a) => sum + (parseFloat(a.balance) || 0), 0);
    const today = new Date().toISOString().split('T')[0];
    const snapshotId = `${portfolioId}-${today}`;

    db.prepare(`
      INSERT OR REPLACE INTO portfolio_snapshots (id, portfolio_id, total_value, snapshot_date)
      VALUES (?, ?, ?, ?)
    `).run(snapshotId, portfolioId, totalValue.toString(), today);
  }

  /**
   * Get leaderboard (top portfolios by value)
   */
  getLeaderboard(limit: number = 10): {
    rank: number;
    username: string;
    portfolioName: string;
    totalValue: number;
  }[] {
    const results = db.prepare(`
      SELECT
        u.username,
        p.name as portfolioName,
        COALESCE(SUM(CAST(a.balance AS REAL)), 0) as totalValue
      FROM portfolios p
      JOIN users u ON p.user_id = u.id
      LEFT JOIN assets a ON p.id = a.portfolio_id
      GROUP BY p.id
      ORDER BY totalValue DESC
      LIMIT ?
    `).all(limit) as { username: string; portfolioName: string; totalValue: number }[];

    return results.map((r, i) => ({
      rank: i + 1,
      username: r.username,
      portfolioName: r.portfolioName,
      totalValue: r.totalValue,
    }));
  }
}

export const analyticsService = new AnalyticsService();
