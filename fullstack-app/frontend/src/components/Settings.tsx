import { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { motion } from 'framer-motion';
import { useForm } from 'react-hook-form';
import { User, Lock, Wallet, Shield, Eye, EyeOff } from 'lucide-react';
import { useAuthStore } from '../store/auth';
import { api } from '../services/api';
import toast from 'react-hot-toast';

interface ProfileFormData {
  username: string;
  walletAddress: string;
}

interface PasswordFormData {
  currentPassword: string;
  newPassword: string;
  confirmPassword: string;
}

function ProfileSection() {
  const { user, updateUser } = useAuthStore();

  const {
    register,
    handleSubmit,
    formState: { errors, isDirty },
  } = useForm<ProfileFormData>({
    defaultValues: {
      username: user?.username || '',
      walletAddress: user?.walletAddress || '',
    },
  });

  const updateMutation = useMutation({
    mutationFn: (data: Partial<ProfileFormData>) =>
      api.updateProfile({
        username: data.username || undefined,
        walletAddress: data.walletAddress || undefined,
      }),
    onSuccess: (updatedUser) => {
      updateUser(updatedUser);
      toast.success('Profile updated');
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : 'Failed to update profile');
    },
  });

  const onSubmit = (data: ProfileFormData) => {
    updateMutation.mutate(data);
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="card"
    >
      <div className="flex items-center gap-3 mb-6">
        <div className="p-2 bg-primary-500/10 rounded-lg">
          <User className="w-5 h-5 text-primary-400" />
        </div>
        <div>
          <h2 className="text-lg font-semibold text-white">Profile</h2>
          <p className="text-sm text-dark-400">Update your personal information</p>
        </div>
      </div>

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <div>
          <label className="label">Email</label>
          <input
            type="email"
            value={user?.email || ''}
            disabled
            className="input bg-dark-800/50 text-dark-500 cursor-not-allowed"
          />
          <p className="text-xs text-dark-500 mt-1">Email cannot be changed</p>
        </div>

        <div>
          <label className="label">Username</label>
          <input
            type="text"
            className={errors.username ? 'input-error' : 'input'}
            {...register('username', {
              required: 'Username is required',
              minLength: { value: 3, message: 'Min 3 characters' },
              maxLength: { value: 30, message: 'Max 30 characters' },
              pattern: {
                value: /^[a-zA-Z0-9_]+$/,
                message: 'Only letters, numbers, and underscores',
              },
            })}
          />
          {errors.username && (
            <p className="text-sm text-red-400 mt-1">{errors.username.message}</p>
          )}
        </div>

        <div>
          <label className="label">Wallet Address</label>
          <input
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

        <div className="flex justify-end pt-2">
          <button
            type="submit"
            disabled={!isDirty || updateMutation.isPending}
            className="btn-primary"
          >
            {updateMutation.isPending ? 'Saving...' : 'Save Changes'}
          </button>
        </div>
      </form>
    </motion.div>
  );
}

function PasswordSection() {
  const [showPasswords, setShowPasswords] = useState({
    current: false,
    new: false,
    confirm: false,
  });

  const {
    register,
    handleSubmit,
    reset,
    watch,
    formState: { errors },
  } = useForm<PasswordFormData>();

  const newPassword = watch('newPassword');

  const changeMutation = useMutation({
    mutationFn: (data: PasswordFormData) =>
      api.changePassword(data.currentPassword, data.newPassword),
    onSuccess: () => {
      toast.success('Password changed successfully');
      reset();
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : 'Failed to change password');
    },
  });

  const onSubmit = (data: PasswordFormData) => {
    changeMutation.mutate(data);
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.1 }}
      className="card"
    >
      <div className="flex items-center gap-3 mb-6">
        <div className="p-2 bg-amber-500/10 rounded-lg">
          <Lock className="w-5 h-5 text-amber-400" />
        </div>
        <div>
          <h2 className="text-lg font-semibold text-white">Password</h2>
          <p className="text-sm text-dark-400">Update your password</p>
        </div>
      </div>

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <div>
          <label className="label">Current Password</label>
          <div className="relative">
            <input
              type={showPasswords.current ? 'text' : 'password'}
              className={errors.currentPassword ? 'input-error pr-10' : 'input pr-10'}
              {...register('currentPassword', { required: 'Current password is required' })}
            />
            <button
              type="button"
              onClick={() => setShowPasswords((s) => ({ ...s, current: !s.current }))}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-dark-500 hover:text-dark-300"
            >
              {showPasswords.current ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
            </button>
          </div>
          {errors.currentPassword && (
            <p className="text-sm text-red-400 mt-1">{errors.currentPassword.message}</p>
          )}
        </div>

        <div>
          <label className="label">New Password</label>
          <div className="relative">
            <input
              type={showPasswords.new ? 'text' : 'password'}
              className={errors.newPassword ? 'input-error pr-10' : 'input pr-10'}
              {...register('newPassword', {
                required: 'New password is required',
                minLength: { value: 8, message: 'Min 8 characters' },
                validate: {
                  hasUppercase: (v) => /[A-Z]/.test(v) || 'Needs uppercase',
                  hasLowercase: (v) => /[a-z]/.test(v) || 'Needs lowercase',
                  hasNumber: (v) => /[0-9]/.test(v) || 'Needs number',
                },
              })}
            />
            <button
              type="button"
              onClick={() => setShowPasswords((s) => ({ ...s, new: !s.new }))}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-dark-500 hover:text-dark-300"
            >
              {showPasswords.new ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
            </button>
          </div>
          {errors.newPassword && (
            <p className="text-sm text-red-400 mt-1">{errors.newPassword.message}</p>
          )}
        </div>

        <div>
          <label className="label">Confirm New Password</label>
          <div className="relative">
            <input
              type={showPasswords.confirm ? 'text' : 'password'}
              className={errors.confirmPassword ? 'input-error pr-10' : 'input pr-10'}
              {...register('confirmPassword', {
                required: 'Please confirm your password',
                validate: (v) => v === newPassword || 'Passwords do not match',
              })}
            />
            <button
              type="button"
              onClick={() => setShowPasswords((s) => ({ ...s, confirm: !s.confirm }))}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-dark-500 hover:text-dark-300"
            >
              {showPasswords.confirm ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
            </button>
          </div>
          {errors.confirmPassword && (
            <p className="text-sm text-red-400 mt-1">{errors.confirmPassword.message}</p>
          )}
        </div>

        <div className="flex justify-end pt-2">
          <button type="submit" disabled={changeMutation.isPending} className="btn-primary">
            {changeMutation.isPending ? 'Changing...' : 'Change Password'}
          </button>
        </div>
      </form>
    </motion.div>
  );
}

function SecuritySection() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.2 }}
      className="card"
    >
      <div className="flex items-center gap-3 mb-6">
        <div className="p-2 bg-emerald-500/10 rounded-lg">
          <Shield className="w-5 h-5 text-emerald-400" />
        </div>
        <div>
          <h2 className="text-lg font-semibold text-white">Security</h2>
          <p className="text-sm text-dark-400">Manage your account security</p>
        </div>
      </div>

      <div className="space-y-4">
        <div className="flex items-center justify-between p-4 rounded-lg bg-dark-800/50 border border-dark-700">
          <div className="flex items-center gap-3">
            <Wallet className="w-5 h-5 text-dark-400" />
            <div>
              <p className="font-medium text-white">Wallet Connection</p>
              <p className="text-sm text-dark-500">Connect your Web3 wallet</p>
            </div>
          </div>
          <button className="btn-secondary text-sm">Connect</button>
        </div>

        <div className="p-4 rounded-lg bg-dark-800/50 border border-dark-700">
          <div className="flex items-center gap-2 mb-2">
            <Lock className="w-4 h-4 text-dark-400" />
            <p className="font-medium text-white">Two-Factor Authentication</p>
          </div>
          <p className="text-sm text-dark-500 mb-3">
            Add an extra layer of security to your account
          </p>
          <span className="badge-warning">Coming Soon</span>
        </div>
      </div>
    </motion.div>
  );
}

export default function Settings() {
  const { user } = useAuthStore();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white">Settings</h1>
        <p className="text-dark-400 mt-1">Manage your account preferences</p>
      </div>

      {/* User Info Card */}
      <div className="card bg-gradient-to-br from-primary-500/10 to-violet-500/10 border-primary-500/20">
        <div className="flex items-center gap-4">
          <div className="w-16 h-16 rounded-full bg-gradient-to-br from-primary-500 to-violet-500 flex items-center justify-center">
            <span className="text-2xl font-bold text-white">
              {user?.username.charAt(0).toUpperCase()}
            </span>
          </div>
          <div>
            <h2 className="text-xl font-bold text-white">{user?.username}</h2>
            <p className="text-dark-400">{user?.email}</p>
            <p className="text-xs text-dark-500 mt-1">
              Member since {new Date(user?.createdAt || '').toLocaleDateString()}
            </p>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ProfileSection />
        <PasswordSection />
        <SecuritySection />
      </div>
    </div>
  );
}
