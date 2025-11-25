import { useQuery } from '@tanstack/react-query';
import { motion } from 'framer-motion';
import { Link } from 'react-router-dom';
import {
  Wallet,
  TrendingUp,
  TrendingDown,
  ArrowRight,
  Layers,
  ArrowLeftRight,
  Activity,
} from 'lucide-react';
import { api } from '../services/api';
import { useAuthStore } from '../store/auth';
import type { Transaction } from '../types';
import { getChainById } from '../types';

const transactionTypeColors: Record<string, string> = {
  transfer: 'badge-primary',
  mint: 'badge-success',
  burn: 'badge-danger',
  swap: 'badge-warning',
  stake: 'badge-primary',
  unstake: 'badge-warning',
  claim: 'badge-success',
};

function StatCard({
  title,
  value,
  change,
  changeType,
  icon: Icon,
}: {
  title: string;
  value: string;
  change?: string;
  changeType?: 'positive' | 'negative';
  icon: React.ElementType;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="stat-card"
    >
      <div className="flex items-start justify-between">
        <div>
          <p className="stat-label">{title}</p>
          <p className="stat-value mt-1">{value}</p>
        </div>
        <div className="p-2 bg-primary-500/10 rounded-lg">
          <Icon className="w-5 h-5 text-primary-400" />
        </div>
      </div>
      {change && (
        <div className="flex items-center gap-1 mt-3">
          {changeType === 'positive' ? (
            <TrendingUp className="w-4 h-4 text-emerald-400" />
          ) : (
            <TrendingDown className="w-4 h-4 text-red-400" />
          )}
          <span
            className={changeType === 'positive' ? 'stat-change-positive' : 'stat-change-negative'}
          >
            {change}
          </span>
          <span className="text-xs text-dark-500 ml-1">vs last week</span>
        </div>
      )}
    </motion.div>
  );
}

function TransactionRow({ transaction }: { transaction: Transaction }) {
  const chain = getChainById(transaction.chainId);

  return (
    <tr>
      <td>
        <span className={transactionTypeColors[transaction.type]}>
          {transaction.type.charAt(0).toUpperCase() + transaction.type.slice(1)}
        </span>
      </td>
      <td className="font-medium text-white">{transaction.tokenSymbol}</td>
      <td className="font-mono text-sm">{parseFloat(transaction.amount).toLocaleString()}</td>
      <td>
        <span className="text-xs px-2 py-0.5 rounded bg-dark-700" style={{ color: chain?.color }}>
          {chain?.shortName || transaction.chainId}
        </span>
      </td>
      <td className="text-dark-400 text-sm">
        {new Date(transaction.timestamp).toLocaleDateString()}
      </td>
    </tr>
  );
}

export default function Dashboard() {
  const { user } = useAuthStore();

  const { data: summary, isLoading: summaryLoading } = useQuery({
    queryKey: ['dashboard-summary'],
    queryFn: () => api.getDashboardSummary(),
  });

  const { data: transactions, isLoading: transactionsLoading } = useQuery({
    queryKey: ['recent-transactions'],
    queryFn: () => api.getRecentTransactions(),
  });

  const { data: leaderboard, isLoading: leaderboardLoading } = useQuery({
    queryKey: ['leaderboard'],
    queryFn: () => api.getLeaderboard(),
  });

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-white">
          Welcome back, {user?.username}
        </h1>
        <p className="text-dark-400 mt-1">
          Here's an overview of your DeFi portfolio
        </p>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {summaryLoading ? (
          <>
            {[1, 2, 3, 4].map((i) => (
              <div key={i} className="stat-card">
                <div className="skeleton h-4 w-24 mb-2" />
                <div className="skeleton h-8 w-32" />
              </div>
            ))}
          </>
        ) : (
          <>
            <StatCard
              title="Total Value"
              value={`$${(summary?.totalPortfolioValue || 0).toLocaleString()}`}
              change="+12.5%"
              changeType="positive"
              icon={Wallet}
            />
            <StatCard
              title="Portfolios"
              value={String(summary?.portfolioCount || 0)}
              icon={Layers}
            />
            <StatCard
              title="Assets"
              value={String(summary?.assetCount || 0)}
              icon={TrendingUp}
            />
            <StatCard
              title="Recent Transactions"
              value={String(summary?.recentTransactionCount || 0)}
              change="+3"
              changeType="positive"
              icon={ArrowLeftRight}
            />
          </>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Recent Transactions */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
          className="lg:col-span-2 card"
        >
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-2">
              <Activity className="w-5 h-5 text-primary-400" />
              <h2 className="text-lg font-semibold text-white">Recent Activity</h2>
            </div>
            <Link to="/transactions" className="btn-ghost text-sm py-1.5">
              View all
              <ArrowRight className="w-4 h-4 ml-1" />
            </Link>
          </div>

          {transactionsLoading ? (
            <div className="space-y-3">
              {[1, 2, 3, 4, 5].map((i) => (
                <div key={i} className="skeleton h-12 rounded-lg" />
              ))}
            </div>
          ) : transactions && transactions.length > 0 ? (
            <div className="overflow-x-auto -mx-6">
              <table className="table min-w-full">
                <thead>
                  <tr>
                    <th className="rounded-tl-lg">Type</th>
                    <th>Token</th>
                    <th>Amount</th>
                    <th>Chain</th>
                    <th className="rounded-tr-lg">Date</th>
                  </tr>
                </thead>
                <tbody>
                  {transactions.slice(0, 5).map((tx) => (
                    <TransactionRow key={tx.id} transaction={tx} />
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="text-center py-8">
              <ArrowLeftRight className="w-12 h-12 text-dark-600 mx-auto mb-3" />
              <p className="text-dark-400">No transactions yet</p>
              <Link to="/transactions" className="btn-primary mt-4 inline-flex">
                Record Transaction
              </Link>
            </div>
          )}
        </motion.div>

        {/* Leaderboard */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
          className="card"
        >
          <div className="flex items-center gap-2 mb-6">
            <TrendingUp className="w-5 h-5 text-primary-400" />
            <h2 className="text-lg font-semibold text-white">Leaderboard</h2>
          </div>

          {leaderboardLoading ? (
            <div className="space-y-3">
              {[1, 2, 3, 4, 5].map((i) => (
                <div key={i} className="skeleton h-12 rounded-lg" />
              ))}
            </div>
          ) : leaderboard && leaderboard.length > 0 ? (
            <div className="space-y-3">
              {leaderboard.slice(0, 5).map((entry) => (
                <div
                  key={`${entry.rank}-${entry.username}`}
                  className="flex items-center gap-3 p-3 rounded-lg bg-dark-800/50 hover:bg-dark-800 transition-colors"
                >
                  <div
                    className={`w-8 h-8 rounded-full flex items-center justify-center font-bold text-sm ${
                      entry.rank === 1
                        ? 'bg-amber-500/20 text-amber-400'
                        : entry.rank === 2
                        ? 'bg-gray-400/20 text-gray-300'
                        : entry.rank === 3
                        ? 'bg-orange-500/20 text-orange-400'
                        : 'bg-dark-700 text-dark-400'
                    }`}
                  >
                    {entry.rank}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-medium text-white truncate">{entry.username}</p>
                    <p className="text-xs text-dark-500 truncate">{entry.portfolioName}</p>
                  </div>
                  <div className="text-right">
                    <p className="font-mono text-sm text-white">
                      ${entry.totalValue.toLocaleString()}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-center py-8">
              <TrendingUp className="w-12 h-12 text-dark-600 mx-auto mb-3" />
              <p className="text-dark-400">No rankings yet</p>
            </div>
          )}
        </motion.div>
      </div>

      {/* Quick Actions */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.3 }}
        className="grid grid-cols-1 sm:grid-cols-3 gap-4"
      >
        <Link
          to="/portfolios"
          className="card-hover flex items-center gap-4 group"
        >
          <div className="p-3 bg-primary-500/10 rounded-xl group-hover:bg-primary-500/20 transition-colors">
            <Layers className="w-6 h-6 text-primary-400" />
          </div>
          <div>
            <p className="font-medium text-white">Create Portfolio</p>
            <p className="text-sm text-dark-400">Organize your assets</p>
          </div>
        </Link>

        <Link
          to="/transactions"
          className="card-hover flex items-center gap-4 group"
        >
          <div className="p-3 bg-emerald-500/10 rounded-xl group-hover:bg-emerald-500/20 transition-colors">
            <ArrowLeftRight className="w-6 h-6 text-emerald-400" />
          </div>
          <div>
            <p className="font-medium text-white">Record Transaction</p>
            <p className="text-sm text-dark-400">Track your activity</p>
          </div>
        </Link>

        <Link
          to="/analytics"
          className="card-hover flex items-center gap-4 group"
        >
          <div className="p-3 bg-violet-500/10 rounded-xl group-hover:bg-violet-500/20 transition-colors">
            <Activity className="w-6 h-6 text-violet-400" />
          </div>
          <div>
            <p className="font-medium text-white">View Analytics</p>
            <p className="text-sm text-dark-400">Analyze performance</p>
          </div>
        </Link>
      </motion.div>
    </div>
  );
}
