import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { motion } from 'framer-motion';
import { Eye, EyeOff, Wallet, UserPlus } from 'lucide-react';
import { useAuthStore } from '../../store/auth';
import { api } from '../../services/api';
import toast from 'react-hot-toast';
import type { RegisterCredentials } from '../../types';

export default function Register() {
  const navigate = useNavigate();
  const { setAuth } = useAuthStore();
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<RegisterCredentials>();

  const onSubmit = async (data: RegisterCredentials) => {
    setIsLoading(true);
    try {
      const response = await api.register(data);
      setAuth(response.user, response.token, response.refreshToken);
      toast.success('Account created successfully!');
      navigate('/dashboard');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Registration failed';
      toast.error(message);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center px-4 py-12">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="w-full max-w-md"
      >
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-gradient-to-br from-primary-500 to-violet-500 mb-4">
            <Wallet className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-2xl font-bold text-white">Create an account</h1>
          <p className="text-dark-400 mt-2">Start tracking your DeFi portfolio today</p>
        </div>

        {/* Form */}
        <div className="card">
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
            <div>
              <label htmlFor="username" className="label">
                Username
              </label>
              <input
                id="username"
                type="text"
                className={errors.username ? 'input-error' : 'input'}
                placeholder="johndoe"
                {...register('username', {
                  required: 'Username is required',
                  minLength: {
                    value: 3,
                    message: 'Username must be at least 3 characters',
                  },
                  maxLength: {
                    value: 30,
                    message: 'Username must be at most 30 characters',
                  },
                  pattern: {
                    value: /^[a-zA-Z0-9_]+$/,
                    message: 'Username can only contain letters, numbers, and underscores',
                  },
                })}
              />
              {errors.username && (
                <p className="text-sm text-red-400 mt-1">{errors.username.message}</p>
              )}
            </div>

            <div>
              <label htmlFor="email" className="label">
                Email
              </label>
              <input
                id="email"
                type="email"
                className={errors.email ? 'input-error' : 'input'}
                placeholder="you@example.com"
                {...register('email', {
                  required: 'Email is required',
                  pattern: {
                    value: /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i,
                    message: 'Invalid email address',
                  },
                })}
              />
              {errors.email && (
                <p className="text-sm text-red-400 mt-1">{errors.email.message}</p>
              )}
            </div>

            <div>
              <label htmlFor="password" className="label">
                Password
              </label>
              <div className="relative">
                <input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  className={errors.password ? 'input-error pr-10' : 'input pr-10'}
                  placeholder="Create a strong password"
                  {...register('password', {
                    required: 'Password is required',
                    minLength: {
                      value: 8,
                      message: 'Password must be at least 8 characters',
                    },
                    validate: {
                      hasUppercase: (v) =>
                        /[A-Z]/.test(v) || 'Password must contain at least one uppercase letter',
                      hasLowercase: (v) =>
                        /[a-z]/.test(v) || 'Password must contain at least one lowercase letter',
                      hasNumber: (v) =>
                        /[0-9]/.test(v) || 'Password must contain at least one number',
                    },
                  })}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-dark-500 hover:text-dark-300"
                >
                  {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                </button>
              </div>
              {errors.password && (
                <p className="text-sm text-red-400 mt-1">{errors.password.message}</p>
              )}
            </div>

            <div>
              <label htmlFor="walletAddress" className="label">
                Wallet Address <span className="text-dark-500">(optional)</span>
              </label>
              <input
                id="walletAddress"
                type="text"
                className={errors.walletAddress ? 'input-error' : 'input'}
                placeholder="0x..."
                {...register('walletAddress', {
                  pattern: {
                    value: /^0x[a-fA-F0-9]{40}$/,
                    message: 'Invalid Ethereum address',
                  },
                })}
              />
              {errors.walletAddress && (
                <p className="text-sm text-red-400 mt-1">{errors.walletAddress.message}</p>
              )}
            </div>

            <button
              type="submit"
              disabled={isLoading}
              className="btn-primary w-full flex items-center justify-center gap-2"
            >
              {isLoading ? (
                <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              ) : (
                <>
                  <UserPlus className="w-5 h-5" />
                  Create account
                </>
              )}
            </button>
          </form>

          <div className="mt-6 text-center text-sm text-dark-400">
            Already have an account?{' '}
            <Link to="/login" className="link font-medium">
              Sign in
            </Link>
          </div>
        </div>
      </motion.div>
    </div>
  );
}
