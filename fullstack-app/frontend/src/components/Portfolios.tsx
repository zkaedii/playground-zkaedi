import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Plus,
  Wallet,
  Star,
  MoreVertical,
  Pencil,
  Trash2,
  X,
  ChevronRight,
} from 'lucide-react';
import { useForm } from 'react-hook-form';
import { api } from '../services/api';
import toast from 'react-hot-toast';
import clsx from 'clsx';
import type { Portfolio, CreatePortfolioInput } from '../types';

function CreatePortfolioModal({
  isOpen,
  onClose,
  editingPortfolio,
}: {
  isOpen: boolean;
  onClose: () => void;
  editingPortfolio?: Portfolio;
}) {
  const queryClient = useQueryClient();

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<CreatePortfolioInput>({
    defaultValues: editingPortfolio
      ? { name: editingPortfolio.name, description: editingPortfolio.description }
      : {},
  });

  const createMutation = useMutation({
    mutationFn: (data: CreatePortfolioInput) =>
      editingPortfolio
        ? api.updatePortfolio(editingPortfolio.id, data)
        : api.createPortfolio(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['portfolios'] });
      toast.success(editingPortfolio ? 'Portfolio updated' : 'Portfolio created');
      reset();
      onClose();
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : 'Failed to save portfolio');
    },
  });

  const onSubmit = (data: CreatePortfolioInput) => {
    createMutation.mutate(data);
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
          className="w-full max-w-md bg-dark-900 border border-dark-700 rounded-xl shadow-xl"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="flex items-center justify-between p-4 border-b border-dark-700">
            <h2 className="text-lg font-semibold text-white">
              {editingPortfolio ? 'Edit Portfolio' : 'Create Portfolio'}
            </h2>
            <button onClick={onClose} className="p-1 hover:bg-dark-800 rounded">
              <X className="w-5 h-5" />
            </button>
          </div>

          <form onSubmit={handleSubmit(onSubmit)} className="p-4 space-y-4">
            <div>
              <label className="label">Name</label>
              <input
                type="text"
                className={errors.name ? 'input-error' : 'input'}
                placeholder="My DeFi Portfolio"
                {...register('name', { required: 'Name is required' })}
              />
              {errors.name && (
                <p className="text-sm text-red-400 mt-1">{errors.name.message}</p>
              )}
            </div>

            <div>
              <label className="label">Description (optional)</label>
              <textarea
                className="input resize-none"
                rows={3}
                placeholder="A brief description..."
                {...register('description')}
              />
            </div>

            <div className="flex gap-3 pt-2">
              <button type="button" onClick={onClose} className="btn-secondary flex-1">
                Cancel
              </button>
              <button
                type="submit"
                disabled={createMutation.isPending}
                className="btn-primary flex-1"
              >
                {createMutation.isPending ? 'Saving...' : editingPortfolio ? 'Update' : 'Create'}
              </button>
            </div>
          </form>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}

function PortfolioCard({
  portfolio,
  onEdit,
  onDelete,
  onSetDefault,
}: {
  portfolio: Portfolio;
  onEdit: () => void;
  onDelete: () => void;
  onSetDefault: () => void;
}) {
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="card-hover group"
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-primary-500/10 rounded-lg">
            <Wallet className="w-5 h-5 text-primary-400" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="font-semibold text-white">{portfolio.name}</h3>
              {portfolio.isDefault && (
                <Star className="w-4 h-4 text-amber-400 fill-amber-400" />
              )}
            </div>
            {portfolio.description && (
              <p className="text-sm text-dark-400 mt-0.5">{portfolio.description}</p>
            )}
          </div>
        </div>

        <div className="relative">
          <button
            onClick={() => setMenuOpen(!menuOpen)}
            className="p-1.5 hover:bg-dark-700 rounded opacity-0 group-hover:opacity-100 transition-opacity"
          >
            <MoreVertical className="w-4 h-4" />
          </button>

          <AnimatePresence>
            {menuOpen && (
              <>
                <div className="fixed inset-0 z-10" onClick={() => setMenuOpen(false)} />
                <motion.div
                  initial={{ opacity: 0, scale: 0.95 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.95 }}
                  className="absolute right-0 top-full mt-1 w-40 bg-dark-800 border border-dark-700 rounded-lg shadow-lg z-20 overflow-hidden"
                >
                  {!portfolio.isDefault && (
                    <button
                      onClick={() => {
                        setMenuOpen(false);
                        onSetDefault();
                      }}
                      className="w-full flex items-center gap-2 px-3 py-2 text-sm text-dark-200 hover:bg-dark-700"
                    >
                      <Star className="w-4 h-4" />
                      Set as default
                    </button>
                  )}
                  <button
                    onClick={() => {
                      setMenuOpen(false);
                      onEdit();
                    }}
                    className="w-full flex items-center gap-2 px-3 py-2 text-sm text-dark-200 hover:bg-dark-700"
                  >
                    <Pencil className="w-4 h-4" />
                    Edit
                  </button>
                  {!portfolio.isDefault && (
                    <button
                      onClick={() => {
                        setMenuOpen(false);
                        onDelete();
                      }}
                      className="w-full flex items-center gap-2 px-3 py-2 text-sm text-red-400 hover:bg-dark-700"
                    >
                      <Trash2 className="w-4 h-4" />
                      Delete
                    </button>
                  )}
                </motion.div>
              </>
            )}
          </AnimatePresence>
        </div>
      </div>

      <div className="text-sm text-dark-500 mb-4">
        Created {new Date(portfolio.createdAt).toLocaleDateString()}
      </div>

      <Link
        to={`/portfolios/${portfolio.id}`}
        className="flex items-center justify-between p-3 -mx-3 -mb-3 mt-auto rounded-b-xl bg-dark-800/50 hover:bg-dark-800 transition-colors"
      >
        <span className="text-sm text-primary-400">View Details</span>
        <ChevronRight className="w-4 h-4 text-primary-400" />
      </Link>
    </motion.div>
  );
}

export default function Portfolios() {
  const queryClient = useQueryClient();
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingPortfolio, setEditingPortfolio] = useState<Portfolio | undefined>();

  const { data: portfolios, isLoading } = useQuery({
    queryKey: ['portfolios'],
    queryFn: () => api.getPortfolios(),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.deletePortfolio(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['portfolios'] });
      toast.success('Portfolio deleted');
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : 'Failed to delete portfolio');
    },
  });

  const setDefaultMutation = useMutation({
    mutationFn: (id: string) => api.setDefaultPortfolio(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['portfolios'] });
      toast.success('Default portfolio updated');
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : 'Failed to set default portfolio');
    },
  });

  const handleEdit = (portfolio: Portfolio) => {
    setEditingPortfolio(portfolio);
    setIsModalOpen(true);
  };

  const handleCloseModal = () => {
    setIsModalOpen(false);
    setEditingPortfolio(undefined);
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Portfolios</h1>
          <p className="text-dark-400 mt-1">Manage your crypto portfolios</p>
        </div>
        <button
          onClick={() => setIsModalOpen(true)}
          className="btn-primary flex items-center gap-2"
        >
          <Plus className="w-5 h-5" />
          <span className="hidden sm:inline">Create Portfolio</span>
        </button>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className="card">
              <div className="skeleton h-6 w-32 mb-2" />
              <div className="skeleton h-4 w-48 mb-4" />
              <div className="skeleton h-10 rounded-lg" />
            </div>
          ))}
        </div>
      ) : portfolios && portfolios.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {portfolios.map((portfolio) => (
            <PortfolioCard
              key={portfolio.id}
              portfolio={portfolio}
              onEdit={() => handleEdit(portfolio)}
              onDelete={() => {
                if (confirm('Are you sure you want to delete this portfolio?')) {
                  deleteMutation.mutate(portfolio.id);
                }
              }}
              onSetDefault={() => setDefaultMutation.mutate(portfolio.id)}
            />
          ))}
        </div>
      ) : (
        <div className="card text-center py-12">
          <Wallet className="w-16 h-16 text-dark-600 mx-auto mb-4" />
          <h3 className="text-lg font-semibold text-white mb-2">No portfolios yet</h3>
          <p className="text-dark-400 mb-6">Create your first portfolio to start tracking assets</p>
          <button
            onClick={() => setIsModalOpen(true)}
            className="btn-primary inline-flex items-center gap-2"
          >
            <Plus className="w-5 h-5" />
            Create Portfolio
          </button>
        </div>
      )}

      <CreatePortfolioModal
        isOpen={isModalOpen}
        onClose={handleCloseModal}
        editingPortfolio={editingPortfolio}
      />
    </div>
  );
}
