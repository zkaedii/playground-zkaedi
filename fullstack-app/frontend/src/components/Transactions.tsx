import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { motion } from 'framer-motion';
import { ArrowLeftRight, Filter, ExternalLink, ChevronLeft, ChevronRight } from 'lucide-react';
import { api } from '../services/api';
import { getChainById, CHAINS } from '../types';
import type { Transaction, TransactionType } from '../types';

const transactionTypes: TransactionType[] = [
  'transfer',
  'mint',
  'burn',
  'swap',
  'stake',
  'unstake',
  'claim',
];

const transactionTypeColors: Record<TransactionType, string> = {
  transfer: 'badge-primary',
  mint: 'badge-success',
  burn: 'badge-danger',
  swap: 'badge-warning',
  stake: 'badge-primary',
  unstake: 'badge-warning',
  claim: 'badge-success',
};

function TransactionRow({ transaction }: { transaction: Transaction }) {
  const chain = getChainById(transaction.chainId);

  return (
    <tr className="group">
      <td>
        <span className={transactionTypeColors[transaction.type]}>
          {transaction.type.charAt(0).toUpperCase() + transaction.type.slice(1)}
        </span>
      </td>
      <td>
        <div>
          <span className="font-medium text-white">{transaction.tokenSymbol}</span>
        </div>
      </td>
      <td className="font-mono">{parseFloat(transaction.amount).toLocaleString()}</td>
      <td>
        <span
          className="text-xs px-2 py-0.5 rounded bg-dark-700"
          style={{ color: chain?.color }}
        >
          {chain?.shortName || transaction.chainId}
        </span>
      </td>
      <td>
        <a
          href={`${chain?.explorerUrl}/tx/${transaction.txHash}`}
          target="_blank"
          rel="noopener noreferrer"
          className="font-mono text-xs text-dark-400 hover:text-primary-400 flex items-center gap-1"
        >
          {transaction.txHash.slice(0, 8)}...{transaction.txHash.slice(-6)}
          <ExternalLink className="w-3 h-3 opacity-0 group-hover:opacity-100" />
        </a>
      </td>
      <td className="text-dark-400">
        {new Date(transaction.timestamp).toLocaleString()}
      </td>
    </tr>
  );
}

export default function Transactions() {
  const [page, setPage] = useState(1);
  const [typeFilter, setTypeFilter] = useState<string>('');
  const [chainFilter, setChainFilter] = useState<string>('');
  const limit = 20;

  const { data, isLoading } = useQuery({
    queryKey: ['transactions', { page, type: typeFilter, chainId: chainFilter }],
    queryFn: () =>
      api.getTransactions({
        page,
        limit,
        type: typeFilter || undefined,
        chainId: chainFilter ? parseInt(chainFilter) : undefined,
      }),
  });

  const transactions = data?.data || [];
  const pagination = data?.pagination || { page: 1, limit: 20, total: 0, totalPages: 0 };

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-white">Transactions</h1>
          <p className="text-dark-400 mt-1">View your transaction history</p>
        </div>
      </div>

      {/* Filters */}
      <div className="card">
        <div className="flex items-center gap-2 mb-4">
          <Filter className="w-4 h-4 text-dark-400" />
          <span className="text-sm font-medium text-dark-300">Filters</span>
        </div>
        <div className="flex flex-wrap gap-4">
          <div>
            <label className="label text-xs">Type</label>
            <select
              value={typeFilter}
              onChange={(e) => {
                setTypeFilter(e.target.value);
                setPage(1);
              }}
              className="input py-1.5 text-sm w-36"
            >
              <option value="">All Types</option>
              {transactionTypes.map((type) => (
                <option key={type} value={type}>
                  {type.charAt(0).toUpperCase() + type.slice(1)}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="label text-xs">Chain</label>
            <select
              value={chainFilter}
              onChange={(e) => {
                setChainFilter(e.target.value);
                setPage(1);
              }}
              className="input py-1.5 text-sm w-40"
            >
              <option value="">All Chains</option>
              {CHAINS.map((chain) => (
                <option key={chain.id} value={chain.id}>
                  {chain.name}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Transactions Table */}
      {isLoading ? (
        <div className="card">
          <div className="space-y-3">
            {[1, 2, 3, 4, 5].map((i) => (
              <div key={i} className="skeleton h-12 rounded-lg" />
            ))}
          </div>
        </div>
      ) : transactions.length > 0 ? (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="card overflow-hidden"
        >
          <div className="overflow-x-auto -mx-6 -mt-6">
            <table className="table min-w-full">
              <thead>
                <tr>
                  <th className="rounded-tl-xl">Type</th>
                  <th>Token</th>
                  <th>Amount</th>
                  <th>Chain</th>
                  <th>Tx Hash</th>
                  <th className="rounded-tr-xl">Date</th>
                </tr>
              </thead>
              <tbody>
                {transactions.map((tx) => (
                  <TransactionRow key={tx.id} transaction={tx} />
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          {pagination.totalPages > 1 && (
            <div className="flex items-center justify-between pt-4 mt-4 border-t border-dark-700">
              <p className="text-sm text-dark-400">
                Showing {(pagination.page - 1) * pagination.limit + 1} -{' '}
                {Math.min(pagination.page * pagination.limit, pagination.total)} of{' '}
                {pagination.total}
              </p>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={page === 1}
                  className="btn-ghost p-2"
                >
                  <ChevronLeft className="w-4 h-4" />
                </button>
                <span className="text-sm text-dark-300">
                  Page {pagination.page} of {pagination.totalPages}
                </span>
                <button
                  onClick={() => setPage((p) => Math.min(pagination.totalPages, p + 1))}
                  disabled={page === pagination.totalPages}
                  className="btn-ghost p-2"
                >
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          )}
        </motion.div>
      ) : (
        <div className="card text-center py-12">
          <ArrowLeftRight className="w-16 h-16 text-dark-600 mx-auto mb-4" />
          <h3 className="text-lg font-semibold text-white mb-2">No transactions found</h3>
          <p className="text-dark-400">
            {typeFilter || chainFilter
              ? 'Try adjusting your filters'
              : 'Your transactions will appear here'}
          </p>
        </div>
      )}
    </div>
  );
}
