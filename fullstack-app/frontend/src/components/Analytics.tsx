import { useQuery } from '@tanstack/react-query';
import { motion } from 'framer-motion';
import {
  BarChart3,
  PieChart,
  TrendingUp,
  ArrowLeftRight,
  Wallet,
  Calendar,
} from 'lucide-react';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart as RechartPie,
  Pie,
  Cell,
  LineChart,
  Line,
} from 'recharts';
import { api } from '../services/api';
import { getChainById } from '../types';

const COLORS = ['#0ea5e9', '#8b5cf6', '#10b981', '#f59e0b', '#ef4444', '#ec4899'];

function StatCard({
  title,
  value,
  icon: Icon,
  color = 'primary',
}: {
  title: string;
  value: string | number;
  icon: React.ElementType;
  color?: 'primary' | 'success' | 'warning' | 'violet';
}) {
  const colorClasses = {
    primary: 'bg-primary-500/10 text-primary-400',
    success: 'bg-emerald-500/10 text-emerald-400',
    warning: 'bg-amber-500/10 text-amber-400',
    violet: 'bg-violet-500/10 text-violet-400',
  };

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
        <div className={`p-2 rounded-lg ${colorClasses[color]}`}>
          <Icon className="w-5 h-5" />
        </div>
      </div>
    </motion.div>
  );
}

export default function Analytics() {
  const { data: userAnalytics, isLoading: userLoading } = useQuery({
    queryKey: ['user-analytics'],
    queryFn: () => api.getUserAnalytics(),
  });

  const { data: txStats, isLoading: txLoading } = useQuery({
    queryKey: ['transaction-stats'],
    queryFn: () => api.getTransactionStats(30),
  });

  const isLoading = userLoading || txLoading;

  // Prepare chart data
  const portfolioChartData = userAnalytics?.portfolioBreakdown.map((p) => ({
    name: p.portfolioName,
    value: p.value,
    allocation: p.allocation,
  })) || [];

  const txTypeData = txStats
    ? Object.entries(txStats.transactionsByType).map(([type, count]) => ({
        name: type.charAt(0).toUpperCase() + type.slice(1),
        count,
      }))
    : [];

  const chainData = txStats
    ? Object.entries(txStats.transactionsByChain).map(([chainId, count]) => {
        const chain = getChainById(parseInt(chainId));
        return {
          name: chain?.shortName || chainId,
          count,
          color: chain?.color || '#64748b',
        };
      })
    : [];

  const dailyVolumeData = txStats?.dailyVolume.slice(0, 14).reverse() || [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">Analytics</h1>
        <p className="text-dark-400 mt-1">Insights into your portfolio performance</p>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {isLoading ? (
          <>
            {[1, 2, 3, 4].map((i) => (
              <div key={i} className="stat-card">
                <div className="skeleton h-4 w-24 mb-2" />
                <div className="skeleton h-8 w-16" />
              </div>
            ))}
          </>
        ) : (
          <>
            <StatCard
              title="Total Portfolios"
              value={userAnalytics?.totalPortfolios || 0}
              icon={Wallet}
              color="primary"
            />
            <StatCard
              title="Total Assets"
              value={userAnalytics?.totalAssets || 0}
              icon={PieChart}
              color="violet"
            />
            <StatCard
              title="Total Transactions"
              value={txStats?.totalTransactions || 0}
              icon={ArrowLeftRight}
              color="success"
            />
            <StatCard
              title="Last 7 Days"
              value={userAnalytics?.activitySummary.transactionsLast7d || 0}
              icon={Calendar}
              color="warning"
            />
          </>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Portfolio Breakdown */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="card"
        >
          <div className="flex items-center gap-2 mb-6">
            <PieChart className="w-5 h-5 text-primary-400" />
            <h2 className="text-lg font-semibold text-white">Portfolio Breakdown</h2>
          </div>

          {isLoading ? (
            <div className="h-64 flex items-center justify-center">
              <div className="w-8 h-8 border-2 border-primary-500 border-t-transparent rounded-full animate-spin" />
            </div>
          ) : portfolioChartData.length > 0 ? (
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <RechartPie>
                  <Pie
                    data={portfolioChartData}
                    cx="50%"
                    cy="50%"
                    innerRadius={60}
                    outerRadius={80}
                    paddingAngle={5}
                    dataKey="value"
                    label={({ name, allocation }) => `${name} (${allocation.toFixed(1)}%)`}
                    labelLine={{ stroke: '#64748b' }}
                  >
                    {portfolioChartData.map((_, index) => (
                      <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip
                    contentStyle={{
                      backgroundColor: '#1e293b',
                      border: '1px solid #334155',
                      borderRadius: '8px',
                    }}
                    formatter={(value: number) => [`$${value.toLocaleString()}`, 'Value']}
                  />
                </RechartPie>
              </ResponsiveContainer>
            </div>
          ) : (
            <div className="h-64 flex items-center justify-center text-dark-500">
              No portfolio data available
            </div>
          )}
        </motion.div>

        {/* Transactions by Type */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
          className="card"
        >
          <div className="flex items-center gap-2 mb-6">
            <BarChart3 className="w-5 h-5 text-primary-400" />
            <h2 className="text-lg font-semibold text-white">Transactions by Type</h2>
          </div>

          {isLoading ? (
            <div className="h-64 flex items-center justify-center">
              <div className="w-8 h-8 border-2 border-primary-500 border-t-transparent rounded-full animate-spin" />
            </div>
          ) : txTypeData.length > 0 ? (
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={txTypeData} layout="vertical">
                  <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                  <XAxis type="number" stroke="#64748b" />
                  <YAxis type="category" dataKey="name" stroke="#64748b" width={80} />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: '#1e293b',
                      border: '1px solid #334155',
                      borderRadius: '8px',
                    }}
                  />
                  <Bar dataKey="count" fill="#0ea5e9" radius={[0, 4, 4, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          ) : (
            <div className="h-64 flex items-center justify-center text-dark-500">
              No transaction data available
            </div>
          )}
        </motion.div>

        {/* Daily Activity */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
          className="card lg:col-span-2"
        >
          <div className="flex items-center gap-2 mb-6">
            <TrendingUp className="w-5 h-5 text-primary-400" />
            <h2 className="text-lg font-semibold text-white">Daily Activity (Last 14 Days)</h2>
          </div>

          {isLoading ? (
            <div className="h-64 flex items-center justify-center">
              <div className="w-8 h-8 border-2 border-primary-500 border-t-transparent rounded-full animate-spin" />
            </div>
          ) : dailyVolumeData.length > 0 ? (
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={dailyVolumeData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                  <XAxis
                    dataKey="date"
                    stroke="#64748b"
                    tickFormatter={(value) =>
                      new Date(value).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
                    }
                  />
                  <YAxis stroke="#64748b" />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: '#1e293b',
                      border: '1px solid #334155',
                      borderRadius: '8px',
                    }}
                    labelFormatter={(value) => new Date(value).toLocaleDateString()}
                  />
                  <Line
                    type="monotone"
                    dataKey="count"
                    stroke="#0ea5e9"
                    strokeWidth={2}
                    dot={{ fill: '#0ea5e9', strokeWidth: 2 }}
                    activeDot={{ r: 6 }}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          ) : (
            <div className="h-64 flex items-center justify-center text-dark-500">
              No activity data available
            </div>
          )}
        </motion.div>

        {/* Chain Distribution */}
        {chainData.length > 0 && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3 }}
            className="card lg:col-span-2"
          >
            <div className="flex items-center gap-2 mb-6">
              <BarChart3 className="w-5 h-5 text-primary-400" />
              <h2 className="text-lg font-semibold text-white">Transactions by Chain</h2>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
              {chainData.map((chain) => (
                <div
                  key={chain.name}
                  className="p-4 rounded-lg bg-dark-800/50 border border-dark-700"
                >
                  <div className="flex items-center gap-2 mb-2">
                    <div
                      className="w-3 h-3 rounded-full"
                      style={{ backgroundColor: chain.color }}
                    />
                    <span className="font-medium text-white">{chain.name}</span>
                  </div>
                  <p className="text-2xl font-bold" style={{ color: chain.color }}>
                    {chain.count}
                  </p>
                  <p className="text-xs text-dark-500">transactions</p>
                </div>
              ))}
            </div>
          </motion.div>
        )}
      </div>
    </div>
  );
}
