import axios, { AxiosError, AxiosInstance } from 'axios';
import { useAuthStore } from '../store/auth';
import type {
  ApiResponse,
  PaginatedResponse,
  AuthResponse,
  LoginCredentials,
  RegisterCredentials,
  User,
  Portfolio,
  PortfolioWithAssets,
  CreatePortfolioInput,
  Asset,
  AddAssetInput,
  Transaction,
  RecordTransactionInput,
  WatchlistItem,
  AddWatchlistInput,
  PortfolioAnalytics,
  UserAnalytics,
  DashboardSummary,
  TransactionStats,
  LeaderboardEntry,
} from '../types';

const API_BASE_URL = import.meta.env.VITE_API_URL || '/api';

class ApiService {
  private client: AxiosInstance;

  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    // Request interceptor to add auth token
    this.client.interceptors.request.use((config) => {
      const token = useAuthStore.getState().token;
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
      }
      return config;
    });

    // Response interceptor to handle token refresh
    this.client.interceptors.response.use(
      (response) => response,
      async (error: AxiosError<ApiResponse>) => {
        const originalRequest = error.config;

        if (error.response?.status === 401 && originalRequest) {
          const refreshToken = useAuthStore.getState().refreshToken;

          if (refreshToken) {
            try {
              const response = await axios.post<ApiResponse<{ token: string; refreshToken: string }>>(
                `${API_BASE_URL}/auth/refresh`,
                { refreshToken }
              );

              if (response.data.success && response.data.data) {
                useAuthStore.getState().updateTokens(
                  response.data.data.token,
                  response.data.data.refreshToken
                );

                originalRequest.headers.Authorization = `Bearer ${response.data.data.token}`;
                return this.client(originalRequest);
              }
            } catch {
              useAuthStore.getState().logout();
            }
          } else {
            useAuthStore.getState().logout();
          }
        }

        throw error;
      }
    );
  }

  // Auth endpoints
  async register(credentials: RegisterCredentials): Promise<AuthResponse> {
    const response = await this.client.post<ApiResponse<AuthResponse>>('/auth/register', credentials);
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Registration failed');
    }
    return response.data.data;
  }

  async login(credentials: LoginCredentials): Promise<AuthResponse> {
    const response = await this.client.post<ApiResponse<AuthResponse>>('/auth/login', credentials);
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Login failed');
    }
    return response.data.data;
  }

  async logout(): Promise<void> {
    await this.client.post('/auth/logout');
  }

  async getMe(): Promise<User> {
    const response = await this.client.get<ApiResponse<User>>('/auth/me');
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to get user');
    }
    return response.data.data;
  }

  async updateProfile(updates: { username?: string; walletAddress?: string }): Promise<User> {
    const response = await this.client.patch<ApiResponse<User>>('/auth/profile', updates);
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to update profile');
    }
    return response.data.data;
  }

  async changePassword(currentPassword: string, newPassword: string): Promise<void> {
    const response = await this.client.post<ApiResponse>('/auth/change-password', {
      currentPassword,
      newPassword,
    });
    if (!response.data.success) {
      throw new Error(response.data.error || 'Failed to change password');
    }
  }

  // Portfolio endpoints
  async getPortfolios(): Promise<Portfolio[]> {
    const response = await this.client.get<ApiResponse<Portfolio[]>>('/portfolios');
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to get portfolios');
    }
    return response.data.data;
  }

  async getPortfolio(id: string): Promise<PortfolioWithAssets> {
    const response = await this.client.get<ApiResponse<PortfolioWithAssets>>(`/portfolios/${id}`);
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to get portfolio');
    }
    return response.data.data;
  }

  async createPortfolio(input: CreatePortfolioInput): Promise<Portfolio> {
    const response = await this.client.post<ApiResponse<Portfolio>>('/portfolios', input);
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to create portfolio');
    }
    return response.data.data;
  }

  async updatePortfolio(id: string, input: Partial<CreatePortfolioInput>): Promise<Portfolio> {
    const response = await this.client.patch<ApiResponse<Portfolio>>(`/portfolios/${id}`, input);
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to update portfolio');
    }
    return response.data.data;
  }

  async deletePortfolio(id: string): Promise<void> {
    const response = await this.client.delete<ApiResponse>(`/portfolios/${id}`);
    if (!response.data.success) {
      throw new Error(response.data.error || 'Failed to delete portfolio');
    }
  }

  async setDefaultPortfolio(id: string): Promise<Portfolio> {
    const response = await this.client.post<ApiResponse<Portfolio>>(`/portfolios/${id}/default`);
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to set default portfolio');
    }
    return response.data.data;
  }

  // Asset endpoints
  async addAsset(portfolioId: string, input: AddAssetInput): Promise<Asset> {
    const response = await this.client.post<ApiResponse<Asset>>(`/portfolios/${portfolioId}/assets`, input);
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to add asset');
    }
    return response.data.data;
  }

  async updateAssetBalance(portfolioId: string, assetId: string, balance: string): Promise<Asset> {
    const response = await this.client.patch<ApiResponse<Asset>>(
      `/portfolios/${portfolioId}/assets/${assetId}`,
      { balance }
    );
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to update asset');
    }
    return response.data.data;
  }

  async removeAsset(portfolioId: string, assetId: string): Promise<void> {
    const response = await this.client.delete<ApiResponse>(`/portfolios/${portfolioId}/assets/${assetId}`);
    if (!response.data.success) {
      throw new Error(response.data.error || 'Failed to remove asset');
    }
  }

  // Transaction endpoints
  async getTransactions(params?: {
    portfolioId?: string;
    type?: string;
    chainId?: number;
    page?: number;
    limit?: number;
  }): Promise<PaginatedResponse<Transaction>> {
    const response = await this.client.get<PaginatedResponse<Transaction>>('/transactions', { params });
    if (!response.data.success) {
      throw new Error(response.data.error || 'Failed to get transactions');
    }
    return response.data;
  }

  async recordTransaction(input: RecordTransactionInput): Promise<Transaction> {
    const response = await this.client.post<ApiResponse<Transaction>>('/transactions', input);
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to record transaction');
    }
    return response.data.data;
  }

  async getRecentTransactions(): Promise<Transaction[]> {
    const response = await this.client.get<ApiResponse<Transaction[]>>('/transactions/recent');
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to get recent transactions');
    }
    return response.data.data;
  }

  // Watchlist endpoints
  async getWatchlist(): Promise<WatchlistItem[]> {
    const response = await this.client.get<ApiResponse<WatchlistItem[]>>('/portfolios/watchlist/items');
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to get watchlist');
    }
    return response.data.data;
  }

  async addToWatchlist(input: AddWatchlistInput): Promise<WatchlistItem> {
    const response = await this.client.post<ApiResponse<WatchlistItem>>('/portfolios/watchlist/items', input);
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to add to watchlist');
    }
    return response.data.data;
  }

  async updateWatchlistItem(id: string, input: Partial<AddWatchlistInput>): Promise<WatchlistItem> {
    const response = await this.client.patch<ApiResponse<WatchlistItem>>(
      `/portfolios/watchlist/items/${id}`,
      input
    );
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to update watchlist item');
    }
    return response.data.data;
  }

  async removeFromWatchlist(id: string): Promise<void> {
    const response = await this.client.delete<ApiResponse>(`/portfolios/watchlist/items/${id}`);
    if (!response.data.success) {
      throw new Error(response.data.error || 'Failed to remove from watchlist');
    }
  }

  // Analytics endpoints
  async getPortfolioAnalytics(portfolioId: string): Promise<PortfolioAnalytics> {
    const response = await this.client.get<ApiResponse<PortfolioAnalytics>>(
      `/analytics/portfolio/${portfolioId}`
    );
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to get portfolio analytics');
    }
    return response.data.data;
  }

  async getUserAnalytics(): Promise<UserAnalytics> {
    const response = await this.client.get<ApiResponse<UserAnalytics>>('/analytics/user');
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to get user analytics');
    }
    return response.data.data;
  }

  async getDashboardSummary(): Promise<DashboardSummary> {
    const response = await this.client.get<ApiResponse<DashboardSummary>>('/analytics/summary');
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to get dashboard summary');
    }
    return response.data.data;
  }

  async getTransactionStats(days?: number): Promise<TransactionStats> {
    const response = await this.client.get<ApiResponse<TransactionStats>>('/analytics/transactions', {
      params: { days },
    });
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to get transaction stats');
    }
    return response.data.data;
  }

  async getLeaderboard(): Promise<LeaderboardEntry[]> {
    const response = await this.client.get<ApiResponse<LeaderboardEntry[]>>('/analytics/leaderboard');
    if (!response.data.success || !response.data.data) {
      throw new Error(response.data.error || 'Failed to get leaderboard');
    }
    return response.data.data;
  }

  async createPortfolioSnapshot(portfolioId: string): Promise<void> {
    const response = await this.client.post<ApiResponse>(`/analytics/snapshot/${portfolioId}`);
    if (!response.data.success) {
      throw new Error(response.data.error || 'Failed to create snapshot');
    }
  }
}

export const api = new ApiService();
