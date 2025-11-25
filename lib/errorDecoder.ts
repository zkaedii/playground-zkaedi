/**
 * Error Decoder Library
 *
 * Transforms cryptic blockchain and wallet errors into human-readable messages.
 * Provides actionable guidance for users encountering transaction failures.
 *
 * Features:
 * - Custom error decoding from contract ABIs
 * - Wallet/provider error translation
 * - Gas estimation error handling
 * - Revert reason extraction
 * - User-friendly error messages with suggested actions
 */

import { decodeErrorResult, type Abi } from 'viem';

// ═══════════════════════════════════════════════════════════════════════════
//                              TYPES
// ═══════════════════════════════════════════════════════════════════════════

/** Decoded error with human-readable information */
export interface DecodedError {
  /** Short error code/identifier */
  code: string;
  /** Human-readable error message */
  message: string;
  /** Detailed explanation */
  description?: string;
  /** Suggested action for user */
  suggestion?: string;
  /** Error severity level */
  severity: 'error' | 'warning' | 'info';
  /** Original error data (for debugging) */
  raw?: unknown;
}

/** Error category for grouping */
export type ErrorCategory =
  | 'user_rejected'
  | 'insufficient_funds'
  | 'network'
  | 'contract'
  | 'gas'
  | 'nonce'
  | 'slippage'
  | 'allowance'
  | 'unknown';

// ═══════════════════════════════════════════════════════════════════════════
//                         KNOWN ERROR PATTERNS
// ═══════════════════════════════════════════════════════════════════════════

/** Common wallet/provider error codes and their meanings */
const WALLET_ERRORS: Record<number | string, Omit<DecodedError, 'raw'>> = {
  // User rejection
  4001: {
    code: 'USER_REJECTED',
    message: 'Transaction rejected',
    description: 'You rejected the transaction in your wallet.',
    suggestion: 'Click confirm in your wallet to proceed.',
    severity: 'info',
  },
  ACTION_REJECTED: {
    code: 'USER_REJECTED',
    message: 'Action rejected',
    description: 'You cancelled the action in your wallet.',
    suggestion: 'Try again and confirm the action.',
    severity: 'info',
  },

  // Connection errors
  4100: {
    code: 'UNAUTHORIZED',
    message: 'Wallet not authorized',
    description: 'This site is not authorized to access your wallet.',
    suggestion: 'Connect your wallet and approve the connection.',
    severity: 'warning',
  },
  4200: {
    code: 'UNSUPPORTED_METHOD',
    message: 'Method not supported',
    description: 'Your wallet does not support this operation.',
    suggestion: 'Try using a different wallet.',
    severity: 'error',
  },
  4900: {
    code: 'DISCONNECTED',
    message: 'Wallet disconnected',
    description: 'Your wallet has disconnected.',
    suggestion: 'Reconnect your wallet to continue.',
    severity: 'warning',
  },
  4901: {
    code: 'CHAIN_DISCONNECTED',
    message: 'Chain disconnected',
    description: 'Your wallet is not connected to the required network.',
    suggestion: 'Switch to the correct network in your wallet.',
    severity: 'warning',
  },

  // Transaction errors
  '-32000': {
    code: 'INSUFFICIENT_FUNDS',
    message: 'Insufficient funds',
    description: 'Your wallet does not have enough tokens for this transaction.',
    suggestion: 'Add more tokens to your wallet or reduce the amount.',
    severity: 'error',
  },
  '-32001': {
    code: 'RESOURCE_NOT_FOUND',
    message: 'Resource not found',
    description: 'The requested resource was not found.',
    suggestion: 'Refresh the page and try again.',
    severity: 'error',
  },
  '-32002': {
    code: 'PENDING_REQUEST',
    message: 'Request pending',
    description: 'You have a pending wallet request.',
    suggestion: 'Check your wallet for pending requests.',
    severity: 'warning',
  },
  '-32003': {
    code: 'TRANSACTION_REJECTED',
    message: 'Transaction rejected',
    description: 'The transaction was rejected by the network.',
    suggestion: 'Check your transaction parameters and try again.',
    severity: 'error',
  },
  '-32602': {
    code: 'INVALID_PARAMS',
    message: 'Invalid parameters',
    description: 'The transaction parameters are invalid.',
    suggestion: 'Check your input values and try again.',
    severity: 'error',
  },
  '-32603': {
    code: 'INTERNAL_ERROR',
    message: 'Internal error',
    description: 'An internal error occurred in your wallet.',
    suggestion: 'Try refreshing the page or restarting your wallet.',
    severity: 'error',
  },
};

/** Common revert reason patterns */
const REVERT_PATTERNS: Array<{
  pattern: RegExp;
  getError: (match: RegExpMatchArray) => Omit<DecodedError, 'raw'>;
}> = [
  // ERC-20 errors
  {
    pattern: /insufficient\s*balance/i,
    getError: () => ({
      code: 'INSUFFICIENT_BALANCE',
      message: 'Insufficient token balance',
      description: "You don't have enough tokens for this transaction.",
      suggestion: 'Reduce the amount or add more tokens to your wallet.',
      severity: 'error',
    }),
  },
  {
    pattern: /insufficient\s*allowance/i,
    getError: () => ({
      code: 'INSUFFICIENT_ALLOWANCE',
      message: 'Approval required',
      description: 'You need to approve the contract to spend your tokens.',
      suggestion: 'Approve the token spending first.',
      severity: 'warning',
    }),
  },
  {
    pattern: /transfer\s*amount\s*exceeds\s*balance/i,
    getError: () => ({
      code: 'TRANSFER_EXCEEDS_BALANCE',
      message: 'Transfer exceeds balance',
      description: 'The transfer amount is more than your available balance.',
      suggestion: 'Check your balance and try a smaller amount.',
      severity: 'error',
    }),
  },

  // Gas errors
  {
    pattern: /out\s*of\s*gas/i,
    getError: () => ({
      code: 'OUT_OF_GAS',
      message: 'Transaction ran out of gas',
      description: 'The transaction needed more gas than was provided.',
      suggestion: 'Try increasing the gas limit.',
      severity: 'error',
    }),
  },
  {
    pattern: /gas\s*required\s*exceeds/i,
    getError: () => ({
      code: 'GAS_EXCEEDS_LIMIT',
      message: 'Gas limit too high',
      description: 'The estimated gas exceeds the block limit.',
      suggestion: 'Try splitting this into smaller transactions.',
      severity: 'error',
    }),
  },

  // Nonce errors
  {
    pattern: /nonce\s*too\s*low/i,
    getError: () => ({
      code: 'NONCE_TOO_LOW',
      message: 'Nonce too low',
      description: 'A transaction with this nonce was already processed.',
      suggestion: 'Wait for pending transactions or reset your wallet nonce.',
      severity: 'error',
    }),
  },
  {
    pattern: /nonce\s*too\s*high/i,
    getError: () => ({
      code: 'NONCE_TOO_HIGH',
      message: 'Nonce too high',
      description: 'There are missing transactions in the nonce sequence.',
      suggestion: 'Wait for previous transactions to confirm.',
      severity: 'error',
    }),
  },

  // Contract-specific
  {
    pattern: /execution\s*reverted/i,
    getError: () => ({
      code: 'EXECUTION_REVERTED',
      message: 'Transaction failed',
      description: 'The contract rejected this transaction.',
      suggestion: 'Check the transaction parameters and try again.',
      severity: 'error',
    }),
  },
  {
    pattern: /only\s*owner/i,
    getError: () => ({
      code: 'ONLY_OWNER',
      message: 'Owner only',
      description: 'Only the contract owner can perform this action.',
      suggestion: 'Connect with the owner wallet.',
      severity: 'error',
    }),
  },
  {
    pattern: /paused/i,
    getError: () => ({
      code: 'CONTRACT_PAUSED',
      message: 'Contract is paused',
      description: 'The contract has been temporarily paused.',
      suggestion: 'Try again later when the contract is unpaused.',
      severity: 'warning',
    }),
  },

  // Slippage and DEX
  {
    pattern: /slippage/i,
    getError: () => ({
      code: 'SLIPPAGE_EXCEEDED',
      message: 'Slippage too high',
      description: 'Price moved too much during the transaction.',
      suggestion: 'Increase slippage tolerance or try again.',
      severity: 'warning',
    }),
  },
  {
    pattern: /deadline/i,
    getError: () => ({
      code: 'DEADLINE_EXPIRED',
      message: 'Transaction expired',
      description: 'The transaction deadline has passed.',
      suggestion: 'Submit a new transaction.',
      severity: 'warning',
    }),
  },

  // Access control
  {
    pattern: /access\s*denied|unauthorized|not\s*authorized/i,
    getError: () => ({
      code: 'ACCESS_DENIED',
      message: 'Access denied',
      description: "You don't have permission for this action.",
      suggestion: 'Check if you have the required role or permissions.',
      severity: 'error',
    }),
  },

  // Overflow/underflow
  {
    pattern: /overflow|underflow/i,
    getError: () => ({
      code: 'MATH_ERROR',
      message: 'Math error',
      description: 'A mathematical overflow or underflow occurred.',
      suggestion: 'Try with different amounts.',
      severity: 'error',
    }),
  },

  // Zero values
  {
    pattern: /zero\s*amount|amount.*zero/i,
    getError: () => ({
      code: 'ZERO_AMOUNT',
      message: 'Amount cannot be zero',
      description: 'You must specify a non-zero amount.',
      suggestion: 'Enter a valid amount greater than zero.',
      severity: 'error',
    }),
  },
  {
    pattern: /zero\s*address|address.*zero/i,
    getError: () => ({
      code: 'ZERO_ADDRESS',
      message: 'Invalid address',
      description: 'The zero address is not allowed.',
      suggestion: 'Provide a valid wallet address.',
      severity: 'error',
    }),
  },
];

// ═══════════════════════════════════════════════════════════════════════════
//                         CORE DECODING FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Decodes any error into a user-friendly format
 * @param error - The error to decode
 * @param abi - Optional contract ABI for custom error decoding
 * @returns Decoded error information
 */
export function decodeError(error: unknown, abi?: Abi): DecodedError {
  // Handle null/undefined
  if (!error) {
    return createUnknownError('Unknown error occurred');
  }

  // Extract error info from various formats
  const errorInfo = extractErrorInfo(error);

  // Try wallet error codes first
  if (errorInfo.code !== undefined) {
    const walletError = WALLET_ERRORS[errorInfo.code] || WALLET_ERRORS[String(errorInfo.code)];
    if (walletError) {
      return { ...walletError, raw: error };
    }
  }

  // Try to decode custom contract errors
  if (errorInfo.data && abi) {
    try {
      const decoded = decodeErrorResult({ abi, data: errorInfo.data as `0x${string}` });
      if (decoded) {
        return {
          code: decoded.errorName,
          message: formatErrorName(decoded.errorName),
          description: `Contract error: ${decoded.errorName}`,
          severity: 'error',
          raw: { ...decoded, originalError: error },
        };
      }
    } catch {
      // Continue to other decoding methods
    }
  }

  // Try pattern matching on error message
  const message = errorInfo.message || String(error);
  for (const { pattern, getError } of REVERT_PATTERNS) {
    const match = message.match(pattern);
    if (match) {
      return { ...getError(match), raw: error };
    }
  }

  // Check for common error string patterns
  const shortMessage = errorInfo.shortMessage || errorInfo.message || '';
  if (shortMessage.toLowerCase().includes('user rejected')) {
    return { ...WALLET_ERRORS[4001], raw: error };
  }
  if (shortMessage.toLowerCase().includes('insufficient funds')) {
    return { ...WALLET_ERRORS['-32000'], raw: error };
  }

  // Return generic error
  return createUnknownError(message, error);
}

/**
 * Extracts error information from various error formats
 * @param error - The error object
 * @returns Normalized error information
 */
function extractErrorInfo(error: unknown): {
  code?: number | string;
  message?: string;
  shortMessage?: string;
  data?: string;
} {
  if (typeof error === 'string') {
    return { message: error };
  }

  if (error instanceof Error) {
    const anyError = error as Record<string, unknown>;
    return {
      code: anyError.code as number | string | undefined,
      message: error.message,
      shortMessage: anyError.shortMessage as string | undefined,
      data: anyError.data as string | undefined,
    };
  }

  if (typeof error === 'object' && error !== null) {
    const obj = error as Record<string, unknown>;
    return {
      code: obj.code as number | string | undefined,
      message: (obj.message as string) || (obj.reason as string) || undefined,
      shortMessage: obj.shortMessage as string | undefined,
      data: obj.data as string | undefined,
    };
  }

  return { message: String(error) };
}

/**
 * Formats a contract error name into a readable string
 * @param errorName - The error name (e.g., "InsufficientBalance")
 * @returns Human-readable string
 */
function formatErrorName(errorName: string): string {
  // Convert camelCase/PascalCase to spaces
  return errorName
    .replace(/([A-Z])/g, ' $1')
    .replace(/^./, (str) => str.toUpperCase())
    .trim();
}

/**
 * Creates an unknown error response
 * @param message - Error message
 * @param raw - Original error
 * @returns Decoded error object
 */
function createUnknownError(message: string, raw?: unknown): DecodedError {
  return {
    code: 'UNKNOWN_ERROR',
    message: 'Something went wrong',
    description: message.slice(0, 200),
    suggestion: 'Please try again or contact support if the issue persists.',
    severity: 'error',
    raw,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
//                         UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Determines the category of an error
 * @param error - Decoded error
 * @returns Error category
 */
export function getErrorCategory(error: DecodedError): ErrorCategory {
  const code = error.code.toUpperCase();

  if (code.includes('REJECT') || code === 'USER_REJECTED') return 'user_rejected';
  if (code.includes('BALANCE') || code.includes('FUNDS')) return 'insufficient_funds';
  if (code.includes('NETWORK') || code.includes('DISCONNECT')) return 'network';
  if (code.includes('GAS')) return 'gas';
  if (code.includes('NONCE')) return 'nonce';
  if (code.includes('SLIPPAGE')) return 'slippage';
  if (code.includes('ALLOWANCE') || code.includes('APPROVAL')) return 'allowance';

  return error.severity === 'error' ? 'contract' : 'unknown';
}

/**
 * Checks if an error is a user rejection
 * @param error - Error to check
 * @returns True if user rejected
 */
export function isUserRejection(error: unknown): boolean {
  const decoded = decodeError(error);
  return decoded.code === 'USER_REJECTED' || decoded.code === 'ACTION_REJECTED';
}

/**
 * Checks if an error is recoverable by the user
 * @param error - Error to check
 * @returns True if user can fix it
 */
export function isRecoverableError(error: unknown): boolean {
  const decoded = decodeError(error);
  const category = getErrorCategory(decoded);

  return ['user_rejected', 'insufficient_funds', 'slippage', 'allowance', 'nonce'].includes(
    category
  );
}

/**
 * Gets a short toast-friendly message
 * @param error - Error to format
 * @returns Short message
 */
export function getToastMessage(error: unknown): string {
  const decoded = decodeError(error);

  if (decoded.code === 'USER_REJECTED') {
    return 'Transaction cancelled';
  }

  return decoded.message;
}

/**
 * Logs error details for debugging
 * @param error - Error to log
 * @param context - Additional context
 */
export function logError(error: unknown, context?: string): void {
  const decoded = decodeError(error);

  console.error(
    `[${context || 'Error'}]`,
    {
      code: decoded.code,
      message: decoded.message,
      description: decoded.description,
      severity: decoded.severity,
    },
    decoded.raw
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//                         ERROR FORMATTING
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Formats an error for display in a UI component
 * @param error - Error to format
 * @returns Formatted error object
 */
export function formatErrorForUI(error: unknown): {
  title: string;
  description: string;
  action?: string;
  variant: 'destructive' | 'warning' | 'default';
} {
  const decoded = decodeError(error);

  return {
    title: decoded.message,
    description: decoded.description || 'An error occurred.',
    action: decoded.suggestion,
    variant: decoded.severity === 'error' ? 'destructive' : decoded.severity === 'warning' ? 'warning' : 'default',
  };
}

/**
 * Creates an error message for transaction failure
 * @param error - Error that occurred
 * @param action - What was being attempted (e.g., "transfer", "approve")
 * @returns Formatted message
 */
export function formatTransactionError(error: unknown, action: string): string {
  const decoded = decodeError(error);

  if (decoded.code === 'USER_REJECTED') {
    return `${action} cancelled`;
  }

  return `Failed to ${action.toLowerCase()}: ${decoded.message}`;
}

// ═══════════════════════════════════════════════════════════════════════════
//                         REACT HOOK HELPER
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Helper for handling transaction errors in React components
 * @param error - Error from transaction
 * @param callbacks - Optional callbacks for different error types
 */
export function handleTransactionError(
  error: unknown,
  callbacks?: {
    onUserRejected?: () => void;
    onInsufficientFunds?: () => void;
    onOtherError?: (decoded: DecodedError) => void;
  }
): DecodedError {
  const decoded = decodeError(error);
  const category = getErrorCategory(decoded);

  if (category === 'user_rejected' && callbacks?.onUserRejected) {
    callbacks.onUserRejected();
  } else if (category === 'insufficient_funds' && callbacks?.onInsufficientFunds) {
    callbacks.onInsufficientFunds();
  } else if (callbacks?.onOtherError) {
    callbacks.onOtherError(decoded);
  }

  return decoded;
}

// ═══════════════════════════════════════════════════════════════════════════
//                         EXPORTS
// ═══════════════════════════════════════════════════════════════════════════

export default {
  decodeError,
  getErrorCategory,
  isUserRejection,
  isRecoverableError,
  getToastMessage,
  logError,
  formatErrorForUI,
  formatTransactionError,
  handleTransactionError,
};
