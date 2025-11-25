import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import db from '../db/index.js';
import type {
  User,
  UserPublic,
  CreateUserInput,
  LoginInput,
  JwtPayload,
} from '../types/index.js';

const JWT_SECRET = process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-in-production';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '24h';
const REFRESH_TOKEN_EXPIRES_IN = 7 * 24 * 60 * 60 * 1000; // 7 days

export class AuthService {
  /**
   * Register a new user
   */
  async register(input: CreateUserInput): Promise<{ user: UserPublic; token: string; refreshToken: string }> {
    // Check if email already exists
    const existingEmail = db.prepare('SELECT id FROM users WHERE email = ?').get(input.email);
    if (existingEmail) {
      throw new Error('Email already registered');
    }

    // Check if username already exists
    const existingUsername = db.prepare('SELECT id FROM users WHERE username = ?').get(input.username);
    if (existingUsername) {
      throw new Error('Username already taken');
    }

    // Hash password
    const passwordHash = await bcrypt.hash(input.password, 12);
    const userId = uuidv4();
    const now = new Date().toISOString();

    // Create user
    db.prepare(`
      INSERT INTO users (id, email, username, password_hash, wallet_address, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(userId, input.email, input.username, passwordHash, input.walletAddress || null, now, now);

    // Create default portfolio for the user
    const portfolioId = uuidv4();
    db.prepare(`
      INSERT INTO portfolios (id, user_id, name, description, is_default, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(portfolioId, userId, 'Main Portfolio', 'Your default portfolio', 1, now, now);

    // Generate tokens
    const token = this.generateToken({ userId, email: input.email });
    const refreshToken = this.generateRefreshToken(userId);

    // Store refresh token
    await this.storeRefreshToken(userId, refreshToken);

    return {
      user: {
        id: userId,
        email: input.email,
        username: input.username,
        walletAddress: input.walletAddress,
        createdAt: now,
      },
      token,
      refreshToken,
    };
  }

  /**
   * Login user
   */
  async login(input: LoginInput): Promise<{ user: UserPublic; token: string; refreshToken: string }> {
    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(input.email) as User | undefined;

    if (!user) {
      throw new Error('Invalid email or password');
    }

    const isValidPassword = await bcrypt.compare(input.password, user.passwordHash);
    if (!isValidPassword) {
      throw new Error('Invalid email or password');
    }

    // Generate tokens
    const token = this.generateToken({ userId: user.id, email: user.email });
    const refreshToken = this.generateRefreshToken(user.id);

    // Store refresh token (invalidate old ones)
    db.prepare('DELETE FROM sessions WHERE user_id = ?').run(user.id);
    await this.storeRefreshToken(user.id, refreshToken);

    return {
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        walletAddress: user.walletAddress,
        createdAt: user.createdAt,
      },
      token,
      refreshToken,
    };
  }

  /**
   * Refresh access token
   */
  async refreshAccessToken(refreshToken: string): Promise<{ token: string; refreshToken: string }> {
    const session = db.prepare(`
      SELECT * FROM sessions WHERE refresh_token = ? AND expires_at > datetime('now')
    `).get(refreshToken) as { id: string; user_id: string; refresh_token: string; expires_at: string } | undefined;

    if (!session) {
      throw new Error('Invalid or expired refresh token');
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(session.user_id) as User | undefined;
    if (!user) {
      throw new Error('User not found');
    }

    // Generate new tokens
    const newToken = this.generateToken({ userId: user.id, email: user.email });
    const newRefreshToken = this.generateRefreshToken(user.id);

    // Rotate refresh token
    db.prepare('DELETE FROM sessions WHERE id = ?').run(session.id);
    await this.storeRefreshToken(user.id, newRefreshToken);

    return {
      token: newToken,
      refreshToken: newRefreshToken,
    };
  }

  /**
   * Logout user
   */
  async logout(userId: string): Promise<void> {
    db.prepare('DELETE FROM sessions WHERE user_id = ?').run(userId);
  }

  /**
   * Get user by ID
   */
  getUserById(userId: string): UserPublic | null {
    const user = db.prepare(`
      SELECT id, email, username, wallet_address as walletAddress, created_at as createdAt
      FROM users WHERE id = ?
    `).get(userId) as UserPublic | undefined;

    return user || null;
  }

  /**
   * Update user profile
   */
  async updateProfile(userId: string, updates: { username?: string; walletAddress?: string }): Promise<UserPublic> {
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as User | undefined;
    if (!user) {
      throw new Error('User not found');
    }

    if (updates.username) {
      const existingUsername = db.prepare('SELECT id FROM users WHERE username = ? AND id != ?').get(updates.username, userId);
      if (existingUsername) {
        throw new Error('Username already taken');
      }
    }

    const now = new Date().toISOString();
    db.prepare(`
      UPDATE users SET
        username = COALESCE(?, username),
        wallet_address = COALESCE(?, wallet_address),
        updated_at = ?
      WHERE id = ?
    `).run(updates.username || null, updates.walletAddress || null, now, userId);

    return this.getUserById(userId)!;
  }

  /**
   * Change password
   */
  async changePassword(userId: string, currentPassword: string, newPassword: string): Promise<void> {
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as User | undefined;
    if (!user) {
      throw new Error('User not found');
    }

    const isValidPassword = await bcrypt.compare(currentPassword, user.passwordHash);
    if (!isValidPassword) {
      throw new Error('Current password is incorrect');
    }

    const newPasswordHash = await bcrypt.hash(newPassword, 12);
    const now = new Date().toISOString();

    db.prepare(`
      UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?
    `).run(newPasswordHash, now, userId);

    // Invalidate all sessions
    db.prepare('DELETE FROM sessions WHERE user_id = ?').run(userId);
  }

  /**
   * Verify JWT token
   */
  verifyToken(token: string): JwtPayload {
    try {
      return jwt.verify(token, JWT_SECRET) as JwtPayload;
    } catch {
      throw new Error('Invalid token');
    }
  }

  /**
   * Generate JWT token
   */
  private generateToken(payload: { userId: string; email: string }): string {
    return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
  }

  /**
   * Generate refresh token
   */
  private generateRefreshToken(userId: string): string {
    return jwt.sign({ userId, type: 'refresh' }, JWT_SECRET, { expiresIn: '7d' });
  }

  /**
   * Store refresh token in database
   */
  private async storeRefreshToken(userId: string, refreshToken: string): Promise<void> {
    const sessionId = uuidv4();
    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRES_IN).toISOString();

    db.prepare(`
      INSERT INTO sessions (id, user_id, refresh_token, expires_at)
      VALUES (?, ?, ?, ?)
    `).run(sessionId, userId, refreshToken, expiresAt);
  }
}

export const authService = new AuthService();
