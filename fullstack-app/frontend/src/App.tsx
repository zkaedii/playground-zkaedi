import { useEffect } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuthStore } from './store/auth';
import { api } from './services/api';
import Layout from './components/Layout';
import Dashboard from './components/Dashboard';
import Portfolios from './components/Portfolios';
import PortfolioDetail from './components/PortfolioDetail';
import Transactions from './components/Transactions';
import Watchlist from './components/Watchlist';
import Analytics from './components/Analytics';
import Settings from './components/Settings';
import Login from './components/auth/Login';
import Register from './components/auth/Register';
import ProtectedRoute from './components/auth/ProtectedRoute';

function App() {
  const { isAuthenticated, isLoading, setAuth, logout, setLoading } = useAuthStore();

  useEffect(() => {
    const initAuth = async () => {
      const token = useAuthStore.getState().token;
      if (token) {
        try {
          const user = await api.getMe();
          setAuth(user, token, useAuthStore.getState().refreshToken || '');
        } catch {
          logout();
        }
      } else {
        setLoading(false);
      }
    };

    initAuth();
  }, [setAuth, logout, setLoading]);

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-dark-950">
        <div className="flex flex-col items-center gap-4">
          <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          <p className="text-dark-400">Loading...</p>
        </div>
      </div>
    );
  }

  return (
    <Routes>
      {/* Public routes */}
      <Route
        path="/login"
        element={isAuthenticated ? <Navigate to="/dashboard" replace /> : <Login />}
      />
      <Route
        path="/register"
        element={isAuthenticated ? <Navigate to="/dashboard" replace /> : <Register />}
      />

      {/* Protected routes */}
      <Route element={<ProtectedRoute />}>
        <Route element={<Layout />}>
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/portfolios" element={<Portfolios />} />
          <Route path="/portfolios/:id" element={<PortfolioDetail />} />
          <Route path="/transactions" element={<Transactions />} />
          <Route path="/watchlist" element={<Watchlist />} />
          <Route path="/analytics" element={<Analytics />} />
          <Route path="/settings" element={<Settings />} />
        </Route>
      </Route>

      {/* Default redirect */}
      <Route
        path="*"
        element={<Navigate to={isAuthenticated ? '/dashboard' : '/login'} replace />}
      />
    </Routes>
  );
}

export default App;
