/**
 * Token Utilities Library
 *
 * Type-safe utilities for handling token amounts, conversions, and formatting
 * in the playground-zkaedi frontend.
 *
 * Features:
 * - Type-safe wei/decimal conversions
 * - Human-readable formatting with abbreviations
 * - Input validation and sanitization
 * - Percentage calculations
 * - Comparison utilities
 */

// ═══════════════════════════════════════════════════════════════════════════
//                              TYPES
// ═══════════════════════════════════════════════════════════════════════════

/** Token amount in smallest unit (wei) */
export type WeiAmount = bigint;

/** Token amount in decimal form */
export type DecimalAmount = string;

/** Formatting options for token display */
export interface FormatOptions {
  /** Number of decimal places to show (default: 4) */
  decimals?: number;
  /** Whether to show thousands separators (default: true) */
  separator?: boolean;
  /** Symbol to append (e.g., "ETH", "UUPS") */
  symbol?: string;
  /** Whether to abbreviate large numbers (K, M, B, T) */
  abbreviate?: boolean;
  /** Trim trailing zeros (default: true) */
  trimZeros?: boolean;
}

/** Result of parsing a user input */
export interface ParseResult {
  success: boolean;
  wei: WeiAmount | null;
  error?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
//                              CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/** Standard token decimals (ERC-20 default) */
export const DEFAULT_DECIMALS = 18;

/** Common decimal configurations */
export const DECIMALS = {
  ETH: 18,
  USDC: 6,
  USDT: 6,
  WBTC: 8,
  DAI: 18,
} as const;

/** Multipliers for abbreviations */
const ABBREVIATIONS = [
  { threshold: 1e12, suffix: 'T', divisor: 1e12 },
  { threshold: 1e9, suffix: 'B', divisor: 1e9 },
  { threshold: 1e6, suffix: 'M', divisor: 1e6 },
  { threshold: 1e3, suffix: 'K', divisor: 1e3 },
] as const;

/** Regex for validating numeric input */
const NUMERIC_REGEX = /^[0-9]*\.?[0-9]*$/;

/** Maximum safe integer for display calculations */
const MAX_SAFE_DISPLAY = 1e15;

// ═══════════════════════════════════════════════════════════════════════════
//                         CONVERSION FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Converts a decimal amount string to wei (bigint)
 * @param amount - Decimal amount as string (e.g., "1.5")
 * @param decimals - Token decimals (default: 18)
 * @returns Wei amount as bigint
 */
export function toWei(amount: string, decimals: number = DEFAULT_DECIMALS): WeiAmount {
  if (!amount || amount === '.' || amount === '') {
    return 0n;
  }

  // Remove any whitespace
  const cleaned = amount.trim();

  // Validate input
  if (!NUMERIC_REGEX.test(cleaned)) {
    throw new Error(`Invalid numeric input: ${amount}`);
  }

  // Split into integer and fractional parts
  const [integerPart, fractionalPart = ''] = cleaned.split('.');

  // Pad or truncate fractional part to match decimals
  const paddedFractional = fractionalPart.padEnd(decimals, '0').slice(0, decimals);

  // Combine and convert to bigint
  const combined = integerPart + paddedFractional;
  return BigInt(combined || '0');
}

/**
 * Converts wei to a decimal string
 * @param wei - Wei amount as bigint
 * @param decimals - Token decimals (default: 18)
 * @returns Decimal string representation
 */
export function fromWei(wei: WeiAmount, decimals: number = DEFAULT_DECIMALS): DecimalAmount {
  if (wei === 0n) return '0';

  const isNegative = wei < 0n;
  const absWei = isNegative ? -wei : wei;

  const weiString = absWei.toString().padStart(decimals + 1, '0');
  const integerPart = weiString.slice(0, -decimals) || '0';
  const fractionalPart = weiString.slice(-decimals);

  // Remove trailing zeros from fractional part
  const trimmedFractional = fractionalPart.replace(/0+$/, '');

  const result = trimmedFractional ? `${integerPart}.${trimmedFractional}` : integerPart;

  return isNegative ? `-${result}` : result;
}

/**
 * Converts between different decimal precisions
 * @param amount - Wei amount in source decimals
 * @param fromDecimals - Source token decimals
 * @param toDecimals - Target token decimals
 * @returns Converted wei amount
 */
export function convertDecimals(
  amount: WeiAmount,
  fromDecimals: number,
  toDecimals: number
): WeiAmount {
  if (fromDecimals === toDecimals) return amount;

  if (fromDecimals > toDecimals) {
    // Reduce precision (divide)
    const factor = 10n ** BigInt(fromDecimals - toDecimals);
    return amount / factor;
  } else {
    // Increase precision (multiply)
    const factor = 10n ** BigInt(toDecimals - fromDecimals);
    return amount * factor;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//                         FORMATTING FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Formats a wei amount for display
 * @param wei - Wei amount as bigint
 * @param options - Formatting options
 * @returns Formatted string
 */
export function formatTokenAmount(wei: WeiAmount, options: FormatOptions = {}): string {
  const {
    decimals = DEFAULT_DECIMALS,
    separator = true,
    symbol,
    abbreviate = false,
    trimZeros = true,
  } = options;

  // Convert to decimal string
  const decimalStr = fromWei(wei, decimals);
  const numericValue = parseFloat(decimalStr);

  // Handle abbreviation
  if (abbreviate && Math.abs(numericValue) >= 1000) {
    for (const { threshold, suffix, divisor } of ABBREVIATIONS) {
      if (Math.abs(numericValue) >= threshold) {
        const abbreviated = (numericValue / divisor).toFixed(2);
        const result = trimZeros ? parseFloat(abbreviated).toString() : abbreviated;
        return symbol ? `${result}${suffix} ${symbol}` : `${result}${suffix}`;
      }
    }
  }

  // Format with fixed decimals
  const [intPart, fracPart = ''] = decimalStr.split('.');

  // Add thousands separators
  let formattedInt = intPart;
  if (separator && intPart.length > 3) {
    formattedInt = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  // Handle fractional part
  let formattedFrac = fracPart;
  if (options.decimals !== undefined) {
    formattedFrac = fracPart.padEnd(options.decimals, '0').slice(0, options.decimals);
  }

  if (trimZeros) {
    formattedFrac = formattedFrac.replace(/0+$/, '');
  }

  const formatted = formattedFrac ? `${formattedInt}.${formattedFrac}` : formattedInt;

  return symbol ? `${formatted} ${symbol}` : formatted;
}

/**
 * Formats a token amount with smart abbreviation
 * @param wei - Wei amount
 * @param symbol - Token symbol
 * @param decimals - Token decimals
 * @returns Human-readable string
 */
export function formatSmart(
  wei: WeiAmount,
  symbol?: string,
  decimals: number = DEFAULT_DECIMALS
): string {
  const numericValue = parseFloat(fromWei(wei, decimals));

  // Use abbreviation for very large numbers
  if (numericValue >= 1e6) {
    return formatTokenAmount(wei, { decimals, abbreviate: true, symbol });
  }

  // Use 4 decimals for medium numbers
  if (numericValue >= 1) {
    return formatTokenAmount(wei, { decimals, symbol, trimZeros: true });
  }

  // Show more precision for small numbers
  if (numericValue > 0) {
    // Find first significant digit
    const decStr = fromWei(wei, decimals);
    const match = decStr.match(/^0\.0*/);
    const leadingZeros = match ? match[0].length - 2 : 0;
    const precision = Math.min(leadingZeros + 4, decimals);

    return formatTokenAmount(wei, {
      decimals: precision,
      symbol,
      trimZeros: true,
    });
  }

  return symbol ? `0 ${symbol}` : '0';
}

/**
 * Formats a percentage value
 * @param value - Percentage as number or basis points
 * @param isBasisPoints - Whether value is in basis points (default: false)
 * @returns Formatted percentage string
 */
export function formatPercent(value: number, isBasisPoints: boolean = false): string {
  const percent = isBasisPoints ? value / 100 : value;

  if (percent >= 100) {
    return `${percent.toFixed(0)}%`;
  } else if (percent >= 1) {
    return `${percent.toFixed(2)}%`;
  } else if (percent >= 0.01) {
    return `${percent.toFixed(4)}%`;
  } else if (percent > 0) {
    return '<0.01%';
  }
  return '0%';
}

// ═══════════════════════════════════════════════════════════════════════════
//                         PARSING FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Safely parses user input to wei
 * @param input - User input string
 * @param decimals - Token decimals
 * @returns Parse result with success status
 */
export function parseTokenInput(input: string, decimals: number = DEFAULT_DECIMALS): ParseResult {
  if (!input || input.trim() === '') {
    return { success: false, wei: null, error: 'Empty input' };
  }

  const cleaned = input.trim().replace(/,/g, '');

  // Check for valid numeric format
  if (!NUMERIC_REGEX.test(cleaned)) {
    return { success: false, wei: null, error: 'Invalid number format' };
  }

  // Check for too many decimal places
  const parts = cleaned.split('.');
  if (parts[1] && parts[1].length > decimals) {
    return {
      success: false,
      wei: null,
      error: `Too many decimal places (max: ${decimals})`,
    };
  }

  try {
    const wei = toWei(cleaned, decimals);
    return { success: true, wei };
  } catch (error) {
    return {
      success: false,
      wei: null,
      error: error instanceof Error ? error.message : 'Parse error',
    };
  }
}

/**
 * Sanitizes user input for token amounts
 * @param input - Raw user input
 * @param decimals - Maximum decimal places allowed
 * @returns Sanitized input string
 */
export function sanitizeTokenInput(input: string, decimals: number = DEFAULT_DECIMALS): string {
  // Remove non-numeric characters except decimal point
  let sanitized = input.replace(/[^0-9.]/g, '');

  // Handle multiple decimal points - keep only the first
  const parts = sanitized.split('.');
  if (parts.length > 2) {
    sanitized = parts[0] + '.' + parts.slice(1).join('');
  }

  // Limit decimal places
  if (parts[1] && parts[1].length > decimals) {
    sanitized = parts[0] + '.' + parts[1].slice(0, decimals);
  }

  // Remove leading zeros (except for "0." case)
  if (sanitized.length > 1 && sanitized[0] === '0' && sanitized[1] !== '.') {
    sanitized = sanitized.replace(/^0+/, '') || '0';
  }

  return sanitized;
}

// ═══════════════════════════════════════════════════════════════════════════
//                         COMPARISON FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Compares two wei amounts
 * @param a - First amount
 * @param b - Second amount
 * @returns -1 if a < b, 0 if equal, 1 if a > b
 */
export function compareWei(a: WeiAmount, b: WeiAmount): -1 | 0 | 1 {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

/**
 * Returns the larger of two wei amounts
 * @param a - First amount
 * @param b - Second amount
 * @returns Larger amount
 */
export function maxWei(a: WeiAmount, b: WeiAmount): WeiAmount {
  return a > b ? a : b;
}

/**
 * Returns the smaller of two wei amounts
 * @param a - First amount
 * @param b - Second amount
 * @returns Smaller amount
 */
export function minWei(a: WeiAmount, b: WeiAmount): WeiAmount {
  return a < b ? a : b;
}

/**
 * Checks if amount is zero
 * @param wei - Amount to check
 * @returns True if zero
 */
export function isZero(wei: WeiAmount): boolean {
  return wei === 0n;
}

/**
 * Checks if amount is positive
 * @param wei - Amount to check
 * @returns True if positive
 */
export function isPositive(wei: WeiAmount): boolean {
  return wei > 0n;
}

// ═══════════════════════════════════════════════════════════════════════════
//                         MATH FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Calculates percentage of an amount
 * @param amount - Base amount
 * @param percent - Percentage (e.g., 50 for 50%)
 * @returns Calculated amount
 */
export function percentOf(amount: WeiAmount, percent: number): WeiAmount {
  if (percent < 0 || percent > 100) {
    throw new Error('Percentage must be between 0 and 100');
  }
  // Use basis points for precision
  const bps = BigInt(Math.round(percent * 100));
  return (amount * bps) / 10000n;
}

/**
 * Calculates what percentage one amount is of another
 * @param part - The part amount
 * @param whole - The whole amount
 * @returns Percentage value
 */
export function percentageOf(part: WeiAmount, whole: WeiAmount): number {
  if (whole === 0n) return 0;
  // Calculate with high precision then convert to float
  const bps = (part * 1000000n) / whole;
  return Number(bps) / 10000;
}

/**
 * Adds a percentage increase to an amount
 * @param amount - Base amount
 * @param percent - Percentage to add (e.g., 5 for +5%)
 * @returns Increased amount
 */
export function addPercent(amount: WeiAmount, percent: number): WeiAmount {
  const increase = percentOf(amount, percent);
  return amount + increase;
}

/**
 * Subtracts a percentage from an amount
 * @param amount - Base amount
 * @param percent - Percentage to subtract (e.g., 5 for -5%)
 * @returns Decreased amount
 */
export function subtractPercent(amount: WeiAmount, percent: number): WeiAmount {
  const decrease = percentOf(amount, percent);
  return amount - decrease;
}

/**
 * Multiplies a wei amount by a decimal multiplier
 * @param amount - Base amount
 * @param multiplier - Decimal multiplier (e.g., 1.5 for 150%)
 * @param precision - Decimal places for precision (default: 18)
 * @returns Multiplied amount
 */
export function multiplyWei(
  amount: WeiAmount,
  multiplier: number,
  precision: number = 18
): WeiAmount {
  const scale = 10n ** BigInt(precision);
  const scaledMultiplier = BigInt(Math.round(multiplier * Number(scale)));
  return (amount * scaledMultiplier) / scale;
}

/**
 * Divides a wei amount by a divisor
 * @param amount - Dividend
 * @param divisor - Divisor
 * @param roundUp - Whether to round up (default: false)
 * @returns Quotient
 */
export function divideWei(amount: WeiAmount, divisor: WeiAmount, roundUp: boolean = false): WeiAmount {
  if (divisor === 0n) throw new Error('Division by zero');

  if (roundUp) {
    return (amount + divisor - 1n) / divisor;
  }
  return amount / divisor;
}

// ═══════════════════════════════════════════════════════════════════════════
//                         VALIDATION FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Validates a token amount against constraints
 * @param amount - Amount to validate
 * @param constraints - Validation constraints
 * @returns Validation result
 */
export function validateAmount(
  amount: WeiAmount,
  constraints: {
    min?: WeiAmount;
    max?: WeiAmount;
    balance?: WeiAmount;
  }
): { valid: boolean; error?: string } {
  if (amount <= 0n) {
    return { valid: false, error: 'Amount must be positive' };
  }

  if (constraints.min !== undefined && amount < constraints.min) {
    return { valid: false, error: `Amount below minimum` };
  }

  if (constraints.max !== undefined && amount > constraints.max) {
    return { valid: false, error: `Amount exceeds maximum` };
  }

  if (constraints.balance !== undefined && amount > constraints.balance) {
    return { valid: false, error: 'Insufficient balance' };
  }

  return { valid: true };
}

/**
 * Checks if a string is a valid token amount
 * @param input - Input string
 * @returns True if valid
 */
export function isValidAmountString(input: string): boolean {
  if (!input || input.trim() === '') return false;
  const cleaned = input.trim().replace(/,/g, '');
  return NUMERIC_REGEX.test(cleaned) && !isNaN(parseFloat(cleaned));
}

// ═══════════════════════════════════════════════════════════════════════════
//                         DISPLAY HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Truncates an address for display
 * @param address - Full address
 * @param startChars - Characters to show at start (default: 6)
 * @param endChars - Characters to show at end (default: 4)
 * @returns Truncated address
 */
export function truncateAddress(
  address: string,
  startChars: number = 6,
  endChars: number = 4
): string {
  if (address.length <= startChars + endChars) return address;
  return `${address.slice(0, startChars)}...${address.slice(-endChars)}`;
}

/**
 * Gets the display name for a chain ID
 * @param chainId - Chain ID
 * @returns Human-readable chain name
 */
export function getChainName(chainId: number): string {
  const chains: Record<number, string> = {
    1: 'Ethereum',
    42161: 'Arbitrum One',
    421614: 'Arbitrum Sepolia',
    137: 'Polygon',
    10: 'Optimism',
    8453: 'Base',
  };
  return chains[chainId] || `Chain ${chainId}`;
}

/**
 * Formats a transaction hash for display
 * @param hash - Full transaction hash
 * @returns Truncated hash
 */
export function formatTxHash(hash: string): string {
  return truncateAddress(hash, 10, 8);
}

// ═══════════════════════════════════════════════════════════════════════════
//                         EXPORTS
// ═══════════════════════════════════════════════════════════════════════════

export default {
  toWei,
  fromWei,
  convertDecimals,
  formatTokenAmount,
  formatSmart,
  formatPercent,
  parseTokenInput,
  sanitizeTokenInput,
  compareWei,
  maxWei,
  minWei,
  isZero,
  isPositive,
  percentOf,
  percentageOf,
  addPercent,
  subtractPercent,
  multiplyWei,
  divideWei,
  validateAmount,
  isValidAmountString,
  truncateAddress,
  getChainName,
  formatTxHash,
};
