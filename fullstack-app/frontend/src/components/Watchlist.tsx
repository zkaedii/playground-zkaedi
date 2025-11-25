import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { motion, AnimatePresence } from 'framer-motion';
import { Star, Plus, Trash2, X, ExternalLink, Bell } from 'lucide-react';
import { useForm } from 'react-hook-form';
import { api } from '../services/api';
import toast from 'react-hot-toast';
import type { WatchlistItem, AddWatchlistInput } from '../types';
import { getChainById, CHAINS } from '../types';

function AddWatchlistModal({
  isOpen,
  onClose,
}: {
  isOpen: boolean;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<AddWatchlistInput>();

  const addMutation = useMutation({
    mutationFn: (data: AddWatchlistInput) =>
      api.addToWatchlist({
        ...data,
        chainId: Number(data.chainId),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['watchlist'] });
      toast.success('Added to watchlist');
      reset();
      onClose();
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : 'Failed to add to watchlist');
    },
  });

  const onSubmit = (data: AddWatchlistInput) => {
    addMutation.mutate(data);
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
            <h2 className="text-lg font-semibold text-white">Add to Watchlist</h2>
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
              </div>
              <div>
                <label className="label">Chain</label>
                <select
                  className={errors.chainId ? 'input-error' : 'input'}
                  {...register('chainId', { required: 'Chain is required' })}
                >
                  <option value="">Select</option>
                  {CHAINS.map((chain) => (
                    <option key={chain.id} value={chain.id}>
                      {chain.shortName}
                    </option>
                  ))}
                </select>
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
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="label">High Alert (optional)</label>
                <input
                  type="text"
                  className="input"
                  placeholder="$0.00"
                  {...register('priceAlertHigh')}
                />
              </div>
              <div>
                <label className="label">Low Alert (optional)</label>
                <input
                  type="text"
                  className="input"
                  placeholder="$0.00"
                  {...register('priceAlertLow')}
                />
              </div>
            </div>

            <div>
              <label className="label">Notes (optional)</label>
              <textarea
                className="input resize-none"
                rows={2}
                placeholder="Add notes..."
                {...register('notes')}
              />
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
                {addMutation.isPending ? 'Adding...' : 'Add to Watchlist'}
              </button>
            </div>
          </form>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}

function WatchlistCard({ item }: { item: WatchlistItem }) {
  const queryClient = useQueryClient();
  const chain = getChainById(item.chainId);

  const deleteMutation = useMutation({
    mutationFn: () => api.removeFromWatchlist(item.id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['watchlist'] });
      toast.success('Removed from watchlist');
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : 'Failed to remove');
    },
  });

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="card-hover"
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-full bg-gradient-to-br from-amber-500 to-orange-500 flex items-center justify-center">
            <Star className="w-5 h-5 text-white fill-white" />
          </div>
          <div>
            <h3 className="font-semibold text-white">{item.tokenSymbol}</h3>
            <p className="text-sm text-dark-400">{item.tokenName}</p>
          </div>
        </div>
        <button
          onClick={() => {
            if (confirm('Remove from watchlist?')) {
              deleteMutation.mutate();
            }
          }}
          className="p-1.5 hover:bg-red-500/20 rounded text-dark-500 hover:text-red-400 transition-colors"
        >
          <Trash2 className="w-4 h-4" />
        </button>
      </div>

      {(item.priceAlertHigh || item.priceAlertLow) && (
        <div className="flex items-center gap-2 mb-3">
          <Bell className="w-4 h-4 text-amber-400" />
          <span className="text-sm text-dark-400">
            {item.priceAlertLow && `Low: $${item.priceAlertLow}`}
            {item.priceAlertHigh && item.priceAlertLow && ' | '}
            {item.priceAlertHigh && `High: $${item.priceAlertHigh}`}
          </span>
        </div>
      )}

      {item.notes && (
        <p className="text-sm text-dark-400 mb-3 line-clamp-2">{item.notes}</p>
      )}

      <div className="flex items-center justify-between pt-3 border-t border-dark-700">
        <span
          className="text-xs px-2 py-0.5 rounded bg-dark-700"
          style={{ color: chain?.color }}
        >
          {chain?.shortName || item.chainId}
        </span>
        <a
          href={`${chain?.explorerUrl}/token/${item.tokenAddress}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-dark-500 hover:text-primary-400 flex items-center gap-1"
        >
          View
          <ExternalLink className="w-3 h-3" />
        </a>
      </div>
    </motion.div>
  );
}

export default function Watchlist() {
  const [isModalOpen, setIsModalOpen] = useState(false);

  const { data: watchlist, isLoading } = useQuery({
    queryKey: ['watchlist'],
    queryFn: () => api.getWatchlist(),
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Watchlist</h1>
          <p className="text-dark-400 mt-1">Track tokens you're interested in</p>
        </div>
        <button
          onClick={() => setIsModalOpen(true)}
          className="btn-primary flex items-center gap-2"
        >
          <Plus className="w-5 h-5" />
          <span className="hidden sm:inline">Add Token</span>
        </button>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className="card">
              <div className="skeleton h-6 w-24 mb-4" />
              <div className="skeleton h-16" />
            </div>
          ))}
        </div>
      ) : watchlist && watchlist.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {watchlist.map((item) => (
            <WatchlistCard key={item.id} item={item} />
          ))}
        </div>
      ) : (
        <div className="card text-center py-12">
          <Star className="w-16 h-16 text-dark-600 mx-auto mb-4" />
          <h3 className="text-lg font-semibold text-white mb-2">Watchlist is empty</h3>
          <p className="text-dark-400 mb-6">Add tokens to keep track of them</p>
          <button
            onClick={() => setIsModalOpen(true)}
            className="btn-primary inline-flex items-center gap-2"
          >
            <Plus className="w-5 h-5" />
            Add Token
          </button>
        </div>
      )}

      <AddWatchlistModal isOpen={isModalOpen} onClose={() => setIsModalOpen(false)} />
    </div>
  );
}
