import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { motion, AnimatePresence } from 'framer-motion';
import {
  ArrowLeft,
  Plus,
  Trash2,
  X,
  Coins,
  TrendingUp,
  TrendingDown,
  ExternalLink,
} from 'lucide-react';
import { useForm } from 'react-hook-form';
import { api } from '../services/api';
import toast from 'react-hot-toast';
import type { AddAssetInput, Asset } from '../types';
import { getChainById, CHAINS } from '../types';

function AddAssetModal({
  isOpen,
  onClose,
  portfolioId,
}: {
  isOpen: boolean;
  onClose: () => void;
  portfolioId: string;
}) {
  const queryClient = useQueryClient();

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<AddAssetInput>();

  const addMutation = useMutation({
    mutationFn: (data: AddAssetInput) => api.addAsset(portfolioId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['portfolio', portfolioId] });
      toast.success('Asset added');
      reset();
      onClose();
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : 'Failed to add asset');
    },
  });

  const onSubmit = (data: AddAssetInput) => {
    addMutation.mutate({
      ...data,
      tokenDecimals: Number(data.tokenDecimals),
      chainId: Number(data.chainId),
    });
  };

  if (!isOpen) return null;

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4"
        onClick={onClose}
      >
        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.95 }}
          className="w-full max-w-md bg-dark-900 border border-dark-700 rounded-xl shadow-xl max-h-[90vh] overflow-y-auto"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="flex items-center justify-between p-4 border-b border-dark-700 sticky top-0 bg-dark-900">
            <h2 className="text-lg font-semibold text-white">Add Asset</h2>
            <button onClick={onClose} className="p-1 hover:bg-dark-800 rounded">
              <X className="w-5 h-5" />
            </button>
          </div>

          <form onSubmit={handleSubmit(onSubmit)} className="p-4 space-y-4">
            <div>
              <label className="label">Token Address</label>
              <input
                type="text"
                className={errors.tokenAddress ? 'input-error' : 'input'}
                placeholder="0x..."
                {...register('tokenAddress', {
                  required: 'Token address is required',
                  pattern: {
                    value: /^0x[a-fA-F0-9]{40}$/,
                    message: 'Invalid token address',
                  },
                })}
              />
              {errors.tokenAddress && (
                <p className="text-sm text-red-400 mt-1">{errors.tokenAddress.message}</p>
              )}
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="label">Token Symbol</label>
                <input
                  type="text"
                  className={errors.tokenSymbol ? 'input-error' : 'input'}
                  placeholder="ETH"
                  {...register('tokenSymbol', { required: 'Symbol is required' })}
                />
                {errors.tokenSymbol && (
                  <p className="text-sm text-red-400 mt-1">{errors.tokenSymbol.message}</p>
                )}
              </div>
              <div>
                <label className="label">Decimals</label>
                <input
                  type="number"
                  className={errors.tokenDecimals ? 'input-error' : 'input'}
                  placeholder="18"
                  {...register('tokenDecimals', {
                    required: 'Decimals is required',
                    min: { value: 0, message: 'Min 0' },
                    max: { value: 18, message: 'Max 18' },
                  })}
                />
                {errors.tokenDecimals && (
                  <p className="text-sm text-red-400 mt-1">{errors.tokenDecimals.message}</p>
                )}
              </div>
            </div>

            <div>
              <label className="label">Token Name</label>
              <input
                type="text"
                className={errors.tokenName ? 'input-error' : 'input'}
                placeholder="Ethereum"
                {...register('tokenName', { required: 'Name is required' })}
              />
              {errors.tokenName && (
                <p className="text-sm text-red-400 mt-1">{errors.tokenName.message}</p>
              )}
            </div>

            <div>
              <label className="label">Chain</label>
              <select
                className={errors.chainId ? 'input-error' : 'input'}
                {...register('chainId', { required: 'Chain is required' })}
              >
                <option value="">Select chain</option>
                {CHAINS.map((chain) => (
                  <option key={chain.id} value={chain.id}>
                    {chain.name}
                  </option>
                ))}
              </select>
              {errors.chainId && (
                <p className="text-sm text-red-400 mt-1">{errors.chainId.message}</p>
              )}
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="label">Balance</label>
                <input
                  type="text"
                  className={errors.balance ? 'input-error' : 'input'}
                  placeholder="0.0"
                  {...register('balance', {
                    required: 'Balance is required',
                    pattern: {
                      value: /^\d+(\.\d+)?$/,
                      message: 'Invalid balance',
                    },
                  })}
                />
                {errors.balance && (
                  <p className="text-sm text-red-400 mt-1">{errors.balance.message}</p>
                )}
              </div>
              <div>
                <label className="label">Avg Cost (optional)</label>
                <input
                  type="text"
                  className="input"
                  placeholder="0.0"
                  {...register('averageCost', {
                    pattern: {
                      value: /^\d+(\.\d+)?$/,
                      message: 'Invalid cost',
                    },
                  })}
                />
              </div>
            </div>

            <div className="flex gap-3 pt-2">
              <button type="button" onClick={onClose} className="btn-secondary flex-1">
                Cancel
              </button>
              <button
                type="submit"
                disabled={addMutation.isPending}
                className="btn-primary flex-1"
              >
                {addMutation.isPending ? 'Adding...' : 'Add Asset'}
              </button>
            </div>
          </form>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}

function AssetCard({
  asset,
  portfolioId,
}: {
  asset: Asset;
  portfolioId: string;
}) {
  const queryClient = useQueryClient();
  const chain = getChainById(asset.chainId);

  const deleteMutation = useMutation({
    mutationFn: () => api.removeAsset(portfolioId, asset.id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['portfolio', portfolioId] });
      toast.success('Asset removed');
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : 'Failed to remove asset');
    },
  });

  const balance = parseFloat(asset.balance);
  const avgCost = asset.averageCost ? parseFloat(asset.averageCost) : 0;
  const value = balance; // Simplified - in production, multiply by price
  const pnl = avgCost > 0 ? value - avgCost * balance : 0;
  const pnlPercentage = avgCost > 0 ? (pnl / (avgCost * balance)) * 100 : 0;

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="card-hover"
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-full bg-gradient-to-br from-primary-500 to-violet-500 flex items-center justify-center">
            <span className="text-sm font-bold text-white">{asset.tokenSymbol.slice(0, 2)}</span>
          </div>
          <div>
            <h3 className="font-semibold text-white">{asset.tokenSymbol}</h3>
            <p className="text-sm text-dark-400">{asset.tokenName}</p>
          </div>
        </div>
        <button
          onClick={() => {
            if (confirm('Remove this asset from your portfolio?')) {
              deleteMutation.mutate();
            }
          }}
          className="p-1.5 hover:bg-red-500/20 rounded text-dark-500 hover:text-red-400 transition-colors"
        >
          <Trash2 className="w-4 h-4" />
        </button>
      </div>

      <div className="space-y-3">
        <div className="flex justify-between items-center">
          <span className="text-dark-400 text-sm">Balance</span>
          <span className="font-mono text-white">{balance.toLocaleString()}</span>
        </div>
        <div className="flex justify-between items-center">
          <span className="text-dark-400 text-sm">Value</span>
          <span className="font-mono text-white">${value.toLocaleString()}</span>
        </div>
        {avgCost > 0 && (
          <div className="flex justify-between items-center">
            <span className="text-dark-400 text-sm">P&L</span>
            <div className="flex items-center gap-1">
              {pnl >= 0 ? (
                <TrendingUp className="w-4 h-4 text-emerald-400" />
              ) : (
                <TrendingDown className="w-4 h-4 text-red-400" />
              )}
              <span className={pnl >= 0 ? 'text-emerald-400' : 'text-red-400'}>
                {pnlPercentage >= 0 ? '+' : ''}{pnlPercentage.toFixed(2)}%
              </span>
            </div>
          </div>
        )}
      </div>

      <div className="mt-4 pt-4 border-t border-dark-700 flex items-center justify-between">
        <span
          className="text-xs px-2 py-0.5 rounded bg-dark-700"
          style={{ color: chain?.color }}
        >
          {chain?.shortName || asset.chainId}
        </span>
        <a
          href={`${chain?.explorerUrl}/token/${asset.tokenAddress}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-dark-500 hover:text-primary-400 flex items-center gap-1"
        >
          View on Explorer
          <ExternalLink className="w-3 h-3" />
        </a>
      </div>
    </motion.div>
  );
}

export default function PortfolioDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);

  const { data: portfolio, isLoading, error } = useQuery({
    queryKey: ['portfolio', id],
    queryFn: () => api.getPortfolio(id!),
    enabled: !!id,
  });

  if (isLoading) {
    return (
      <div className="space-y-6">
        <div className="skeleton h-8 w-48" />
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className="card">
              <div className="skeleton h-6 w-24 mb-4" />
              <div className="skeleton h-20" />
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (error || !portfolio) {
    return (
      <div className="card text-center py-12">
        <h3 className="text-lg font-semibold text-white mb-2">Portfolio not found</h3>
        <p className="text-dark-400 mb-4">The portfolio you're looking for doesn't exist.</p>
        <button onClick={() => navigate('/portfolios')} className="btn-primary">
          Back to Portfolios
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-4">
          <button
            onClick={() => navigate('/portfolios')}
            className="p-2 hover:bg-dark-800 rounded-lg transition-colors"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div>
            <h1 className="text-2xl font-bold text-white">{portfolio.name}</h1>
            {portfolio.description && (
              <p className="text-dark-400 mt-1">{portfolio.description}</p>
            )}
          </div>
        </div>
        <button
          onClick={() => setIsAddModalOpen(true)}
          className="btn-primary flex items-center gap-2"
        >
          <Plus className="w-5 h-5" />
          <span className="hidden sm:inline">Add Asset</span>
        </button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="stat-card">
          <p className="stat-label">Total Value</p>
          <p className="stat-value">${portfolio.totalValue.toLocaleString()}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Assets</p>
          <p className="stat-value">{portfolio.assets.length}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Last Updated</p>
          <p className="stat-value text-xl">
            {new Date(portfolio.updatedAt).toLocaleDateString()}
          </p>
        </div>
      </div>

      {/* Assets */}
      {portfolio.assets.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {portfolio.assets.map((asset) => (
            <AssetCard key={asset.id} asset={asset} portfolioId={portfolio.id} />
          ))}
        </div>
      ) : (
        <div className="card text-center py-12">
          <Coins className="w-16 h-16 text-dark-600 mx-auto mb-4" />
          <h3 className="text-lg font-semibold text-white mb-2">No assets yet</h3>
          <p className="text-dark-400 mb-6">Add your first asset to start tracking</p>
          <button
            onClick={() => setIsAddModalOpen(true)}
            className="btn-primary inline-flex items-center gap-2"
          >
            <Plus className="w-5 h-5" />
            Add Asset
          </button>
        </div>
      )}

      <AddAssetModal
        isOpen={isAddModalOpen}
        onClose={() => setIsAddModalOpen(false)}
        portfolioId={portfolio.id}
      />
    </div>
  );
}
