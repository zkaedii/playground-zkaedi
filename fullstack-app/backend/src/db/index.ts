import Database from 'better-sqlite3';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const dbPath = process.env.DATABASE_PATH || join(__dirname, '../../data/portfolio.db');

// Ensure data directory exists
import { mkdirSync } from 'fs';
try {
  mkdirSync(dirname(dbPath), { recursive: true });
} catch {
  // Directory already exists
}

export const db = new Database(dbPath);

// Enable foreign keys and WAL mode for better performance
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

// Initialize database schema
export function initializeDatabase(): void {
  db.exec(`
    -- Users table
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      wallet_address TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    -- Portfolios table
    CREATE TABLE IF NOT EXISTS portfolios (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      is_default INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    -- Assets table
    CREATE TABLE IF NOT EXISTS assets (
      id TEXT PRIMARY KEY,
      portfolio_id TEXT NOT NULL,
      token_address TEXT NOT NULL,
      token_symbol TEXT NOT NULL,
      token_name TEXT NOT NULL,
      token_decimals INTEGER NOT NULL,
      chain_id INTEGER NOT NULL,
      balance TEXT NOT NULL DEFAULT '0',
      average_cost TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (portfolio_id) REFERENCES portfolios(id) ON DELETE CASCADE,
      UNIQUE(portfolio_id, token_address, chain_id)
    );

    -- Transactions table
    CREATE TABLE IF NOT EXISTS transactions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      portfolio_id TEXT NOT NULL,
      tx_hash TEXT NOT NULL,
      type TEXT NOT NULL CHECK (type IN ('transfer', 'mint', 'burn', 'swap', 'stake', 'unstake', 'claim')),
      token_address TEXT NOT NULL,
      token_symbol TEXT NOT NULL,
      amount TEXT NOT NULL,
      from_address TEXT NOT NULL,
      to_address TEXT NOT NULL,
      chain_id INTEGER NOT NULL,
      block_number INTEGER NOT NULL,
      gas_used TEXT,
      gas_price TEXT,
      timestamp TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (portfolio_id) REFERENCES portfolios(id) ON DELETE CASCADE
    );

    -- Watchlist table
    CREATE TABLE IF NOT EXISTS watchlist (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      token_address TEXT NOT NULL,
      token_symbol TEXT NOT NULL,
      token_name TEXT NOT NULL,
      chain_id INTEGER NOT NULL,
      price_alert_high TEXT,
      price_alert_low TEXT,
      notes TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      UNIQUE(user_id, token_address, chain_id)
    );

    -- Portfolio snapshots for analytics
    CREATE TABLE IF NOT EXISTS portfolio_snapshots (
      id TEXT PRIMARY KEY,
      portfolio_id TEXT NOT NULL,
      total_value TEXT NOT NULL,
      snapshot_date TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (portfolio_id) REFERENCES portfolios(id) ON DELETE CASCADE,
      UNIQUE(portfolio_id, snapshot_date)
    );

    -- Notifications table
    CREATE TABLE IF NOT EXISTS notifications (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      type TEXT NOT NULL CHECK (type IN ('price_alert', 'transaction', 'portfolio_update', 'system')),
      title TEXT NOT NULL,
      message TEXT NOT NULL,
      metadata TEXT,
      read INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    -- Sessions table for token management
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      refresh_token TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    -- Create indexes for better query performance
    CREATE INDEX IF NOT EXISTS idx_portfolios_user_id ON portfolios(user_id);
    CREATE INDEX IF NOT EXISTS idx_assets_portfolio_id ON assets(portfolio_id);
    CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id);
    CREATE INDEX IF NOT EXISTS idx_transactions_portfolio_id ON transactions(portfolio_id);
    CREATE INDEX IF NOT EXISTS idx_transactions_timestamp ON transactions(timestamp);
    CREATE INDEX IF NOT EXISTS idx_watchlist_user_id ON watchlist(user_id);
    CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
    CREATE INDEX IF NOT EXISTS idx_portfolio_snapshots_portfolio_id ON portfolio_snapshots(portfolio_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
  `);

  console.log('Database initialized successfully');
}

// Helper to run transactions
export function runTransaction<T>(fn: () => T): T {
  return db.transaction(fn)();
}

export default db;
