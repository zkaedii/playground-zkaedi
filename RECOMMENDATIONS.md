# Recommendations

This document consolidates best practices, security guidelines, and integration patterns for the playground-zkaedi Web3 DeFi platform.

## Table of Contents

1. [Security Audit Roadmap](#1-security-audit-roadmap)
2. [Oracle System Best Practices](#2-oracle-system-best-practices)
3. [Cross-Chain Integration Guidelines](#3-cross-chain-integration-guidelines)
4. [Gas Optimization Strategies](#4-gas-optimization-strategies)
5. [Utility Library Usage Guide](#5-utility-library-usage-guide)
6. [Testing & QA Standards](#6-testing--qa-standards)
7. [Deployment & Operations Checklist](#7-deployment--operations-checklist)
8. [Frontend Development Guidelines](#8-frontend-development-guidelines)
9. [Template Customization Guide](#9-template-customization-guide)
10. [Emergency Response Procedures](#10-emergency-response-procedures)

---

## 1. Security Audit Roadmap

### Pre-Audit Preparation

- [ ] Complete internal code review with security focus
- [ ] Run automated security tools (Slither, Mythril, Echidna)
- [ ] Document all privileged functions and access controls
- [ ] Create threat model for each contract component
- [ ] Verify all external calls are checked for reentrancy

### Recommended Audit Scope

**High Priority (Critical Path)**
- `UUPSTokenV2.sol` - Core token functionality
- `UUPSTokenV3.sol` - Advanced features (flash loans, rewards)
- `SmartOracleAggregator.sol` - Oracle price feeds
- `CrossChainDEXRouter.sol` - Multi-DEX routing

**Medium Priority**
- Example contracts: `DeFiVault.sol`, `SecurityManager.sol`, `StakingRewardsHub.sol`
- Intent settlement system
- Cross-chain handlers (CCIP, LayerZero)

**Lower Priority**
- Utility libraries (already well-tested)
- Template contracts (general patterns)

### Security Checklist

```solidity
// Access Control Patterns
modifier onlyOwner() {
    require(msg.sender == owner, "Not owner");
    _;
}

// Reentrancy Protection
modifier nonReentrant() {
    require(!_locked, "Reentrant call");
    _locked = true;
    _;
    _locked = false;
}

// Input Validation
function transfer(address to, uint256 amount) external {
    require(to != address(0), "Zero address");
    require(amount > 0, "Zero amount");
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");
    // ... implementation
}
```

### Known Vulnerability Patterns to Check

| Vulnerability | Risk Level | Mitigation |
|--------------|------------|------------|
| Reentrancy | Critical | Use ReentrancyGuard, CEI pattern |
| Integer Overflow | High | Use Solidity 0.8+ built-in checks |
| Flash Loan Attacks | High | Implement EIP-3156 guards |
| Oracle Manipulation | High | Use TWAP, multiple sources |
| Front-Running/MEV | Medium | Commit-reveal schemes, private mempools |
| Access Control | Medium | Role-based with OpenZeppelin |

---

## 2. Oracle System Best Practices

### Multi-Source Oracle Strategy

The `SmartOracleAggregator` supports three oracle providers. Use them according to this priority:

| Priority | Provider | Use Case | Staleness Threshold |
|----------|----------|----------|---------------------|
| 1 | Chainlink | Primary for major pairs | 3600s (1 hour) |
| 2 | Pyth | High-frequency updates | 60s |
| 3 | RedStone | Backup/exotic pairs | 300s |

### Price Feed Configuration

```solidity
// Recommended deviation thresholds
uint256 constant MAX_DEVIATION_BPS = 500; // 5% max deviation between sources
uint256 constant STALENESS_THRESHOLD = 3600; // 1 hour for Chainlink
uint256 constant MIN_SOURCES_REQUIRED = 2; // Minimum oracles for consensus
```

### Fallback Hierarchy

1. **Primary**: Chainlink feed for the specific pair
2. **Secondary**: Pyth network real-time price
3. **Tertiary**: RedStone with attestation
4. **Emergency**: TWAP from on-chain DEX (Uniswap V3 oracle)

### Oracle Failure Scenarios

| Scenario | Detection | Response |
|----------|-----------|----------|
| Stale Price | `block.timestamp - updatedAt > threshold` | Switch to next oracle |
| Zero Price | `price == 0` | Reject and try fallback |
| Excessive Deviation | `abs(price1 - price2) > maxDeviation` | Use median of 3 sources |
| All Oracles Down | All sources return invalid | Pause price-dependent operations |

### TWAP Implementation

```solidity
// Use circular buffer for gas-efficient TWAP
struct Observation {
    uint32 timestamp;
    uint224 priceCumulative;
}

// Recommended observation window
uint256 constant TWAP_WINDOW = 30 minutes;
uint256 constant OBSERVATION_CARDINALITY = 100;
```

---

## 3. Cross-Chain Integration Guidelines

### Bridge Selection Matrix

| Bridge | Best For | Latency | Cost | Security Model |
|--------|----------|---------|------|----------------|
| Chainlink CCIP | High-value transfers | 15-20 min | Higher | DON consensus |
| LayerZero | Fast messaging | 2-5 min | Lower | Oracle + Relayer |
| Native Bridges | L1 <-> L2 | Variable | Variable | Chain-specific |

### When to Use Each Protocol

**Use Chainlink CCIP for:**
- Token transfers > $100k value
- Critical state synchronization
- Operations requiring strong finality guarantees

**Use LayerZero for:**
- Frequent low-value messages
- Non-critical notifications
- Time-sensitive operations

### Cross-Chain Security Patterns

```solidity
// Message Replay Protection
mapping(bytes32 => bool) public processedMessages;

function receiveMessage(bytes32 messageId, bytes calldata data) external {
    require(!processedMessages[messageId], "Already processed");
    processedMessages[messageId] = true;
    // Process message
}

// Source Chain Validation
mapping(uint16 => address) public trustedRemotes;

function _validateSource(uint16 srcChainId, address srcAddress) internal view {
    require(trustedRemotes[srcChainId] == srcAddress, "Untrusted source");
}
```

### Cross-Chain State Synchronization

1. **Eventual Consistency**: Accept that state may be temporarily inconsistent
2. **Idempotency**: All cross-chain handlers must be idempotent
3. **Ordering**: Don't assume message ordering; include sequence numbers
4. **Timeouts**: Implement deadline-based expiration for pending operations

### Bridge Failure Recovery

| Failure Type | Detection | Recovery Action |
|--------------|-----------|-----------------|
| Message Stuck | No confirmation after 2x expected latency | Retry with higher gas |
| Bridge Paused | Check bridge status endpoint | Queue messages locally |
| Invalid Route | Route check fails | Fallback to alternative bridge |
| Insufficient Liquidity | Slippage > tolerance | Split into smaller transfers |

---

## 4. Gas Optimization Strategies

### Current Gas Benchmarks

| Operation | V2 Gas | V3 Gas | Savings |
|-----------|--------|--------|---------|
| Transfer | ~75,000 | ~65,000 | 13% |
| Approve | ~46,000 | ~43,000 | 7% |
| Mint | ~52,000 | ~48,000 | 8% |
| Burn | ~35,000 | ~32,000 | 9% |

### Packed Storage Layout (V3)

```solidity
// Efficient packed account structure
struct PackedAccount {
    uint128 balance;      // 128 bits
    uint64 lastActivity;  // 64 bits
    uint32 rewardIndex;   // 32 bits
    uint32 flags;         // 32 bits (whitelist, frozen, etc.)
}
// Total: 256 bits = 1 storage slot
```

### Gas Optimization Checklist

- [ ] Use `uint256` for loop counters (avoid type conversion)
- [ ] Pack structs to fit in 32-byte slots
- [ ] Use `calldata` instead of `memory` for read-only arrays
- [ ] Cache storage variables in local variables
- [ ] Use `unchecked` blocks for safe arithmetic
- [ ] Prefer `++i` over `i++` in loops
- [ ] Use custom errors instead of revert strings
- [ ] Short-circuit boolean expressions

### Example: Optimized Transfer

```solidity
function transfer(address to, uint256 amount) external returns (bool) {
    // Cache storage reads
    PackedAccount storage senderAccount = _accounts[msg.sender];
    uint256 senderBalance = senderAccount.balance;

    // Validation
    if (senderBalance < amount) revert InsufficientBalance();
    if (to == address(0)) revert ZeroAddress();

    // Update in unchecked block (overflow impossible due to check above)
    unchecked {
        senderAccount.balance = uint128(senderBalance - amount);
        _accounts[to].balance += uint128(amount);
    }

    emit Transfer(msg.sender, to, amount);
    return true;
}
```

### V2 to V3 Migration Guide

1. Deploy V3 implementation contract
2. Call `upgradeToAndCall` on proxy with V3 address
3. Migrate packed storage (automatic via upgrade)
4. Verify all balances preserved
5. Update frontend ABI references

---

## 5. Utility Library Usage Guide

### Library Categories

| Category | Libraries | Use Case |
|----------|-----------|----------|
| **Staking** | StakingLib, RewardLib, EmissionsLib | Token staking mechanics |
| **Security** | HardenedSecurityLib, ValidatorsLib, GuardsLib | Input validation, access control |
| **DeFi** | SwapLib, LiquidityLib, YieldLib | DEX integration, yield farming |
| **Math** | FixedPointMathLib, ABDKMath64x64 | Precision calculations |
| **Cross-Chain** | BridgeLib, MessageLib | Cross-chain messaging |
| **Advanced** | SolversLib, SynergyLib, IntentLib | Intent-based trading |

### High-Impact Libraries

#### HardenedSecurityLib (37KB)

```solidity
import {HardenedSecurityLib} from "./utils/HardenedSecurityLib.sol";

contract SecureVault {
    using HardenedSecurityLib for address;
    using HardenedSecurityLib for uint256;

    function deposit(uint256 amount) external {
        // Validate inputs
        amount.validatePositive("amount");
        msg.sender.validateNotZero("sender");

        // Rate limiting
        HardenedSecurityLib.enforceRateLimit(msg.sender, 10, 1 hours);

        // ... implementation
    }
}
```

#### StakingLib & RewardLib

```solidity
import {StakingLib} from "./utils/StakingLib.sol";
import {RewardLib} from "./utils/RewardLib.sol";

contract Staking {
    using StakingLib for StakingLib.Pool;
    using RewardLib for RewardLib.RewardState;

    StakingLib.Pool private pool;
    RewardLib.RewardState private rewards;

    function stake(uint256 amount) external {
        rewards.updateReward(msg.sender);
        pool.stake(msg.sender, amount);
    }

    function claim() external returns (uint256) {
        return rewards.claim(msg.sender);
    }
}
```

#### SolversLib (Intent-Based Trading)

```solidity
import {SolversLib} from "./utils/SolversLib.sol";

contract IntentSettlement {
    using SolversLib for SolversLib.Intent;

    function submitIntent(SolversLib.Intent calldata intent) external {
        // Validate intent structure
        intent.validate();

        // Check solver reputation
        require(SolversLib.getSolverScore(intent.solver) >= MIN_SCORE, "Low reputation");

        // Queue for settlement
        _queueIntent(intent);
    }
}
```

### Library Compatibility Matrix

| Library A | Compatible With | Notes |
|-----------|----------------|-------|
| StakingLib | RewardLib, EmissionsLib | Use together for full staking |
| HardenedSecurityLib | All | Can be used anywhere |
| SwapLib | LiquidityLib, OracleLib | DEX integration stack |
| SolversLib | IntentLib, MessageLib | Intent settlement stack |

---

## 6. Testing & QA Standards

### Test Coverage Targets

| Component | Current | Target | Priority |
|-----------|---------|--------|----------|
| Core Contracts (V2/V3) | 90%+ | 95% | High |
| Oracle System | 80% | 90% | High |
| Cross-Chain | 70% | 85% | Medium |
| Utility Libraries | 85% | 90% | Medium |
| Frontend | 0% | 70% | High |

### Required Test Categories

#### Smart Contracts

```bash
# Unit tests
forge test --match-contract "UUPSTokenV2Test"

# Integration tests
forge test --match-contract "IntegrationTests"

# Fuzz tests
forge test --match-test "testFuzz"

# Gas benchmarks
forge test --match-test "testGas" --gas-report
```

#### Fuzz Testing Examples

```solidity
function testFuzzTransfer(address to, uint256 amount) public {
    vm.assume(to != address(0));
    vm.assume(amount > 0 && amount <= type(uint128).max);

    // Setup
    token.mint(address(this), amount);

    // Execute
    token.transfer(to, amount);

    // Assert
    assertEq(token.balanceOf(to), amount);
}

function testFuzzOracleDeviation(uint256 price1, uint256 price2) public {
    vm.assume(price1 > 0 && price1 < type(uint128).max);
    vm.assume(price2 > 0 && price2 < type(uint128).max);

    // Test deviation calculation
    uint256 deviation = oracle.calculateDeviation(price1, price2);

    // Assert bounds
    assertLe(deviation, 10000); // Max 100% deviation in BPS
}
```

#### Frontend Testing (Recommended Setup)

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./test/setup.ts'],
    coverage: {
      reporter: ['text', 'html'],
      threshold: { lines: 70 }
    }
  }
});
```

### Test Documentation Requirements

Each test file should include:
1. Purpose of the test suite
2. Setup requirements
3. Test data fixtures
4. Expected outcomes
5. Edge cases covered

---

## 7. Deployment & Operations Checklist

### Pre-Deployment

- [ ] All tests passing (`forge test`)
- [ ] Security scan clean (`slither .`)
- [ ] Gas optimization verified
- [ ] Constructor arguments documented
- [ ] Upgrade path tested on testnet

### Deployment Steps

```bash
# 1. Deploy to testnet first
make deploy-sepolia

# 2. Verify contract on Etherscan
make verify-sepolia

# 3. Run integration tests against testnet
forge test --fork-url $SEPOLIA_RPC

# 4. Deploy to mainnet
make deploy-arbitrum

# 5. Verify mainnet deployment
make verify-arbitrum
```

### Post-Deployment Verification

- [ ] Contract verified on block explorer
- [ ] Ownership transferred to multisig
- [ ] Initial parameters set correctly
- [ ] Frontend connected to correct addresses
- [ ] Monitoring alerts configured

### RPC Redundancy

Configure multiple RPC endpoints for reliability:

```typescript
// lib/wagmi.ts
const transports = {
  [arbitrum.id]: fallback([
    http('https://arb1.arbitrum.io/rpc'),           // Primary
    http('https://arbitrum-mainnet.infura.io/v3/'), // Backup 1
    http('https://arbitrum.llamarpc.com'),          // Backup 2
  ]),
};
```

### Monitoring & Alerting

| Metric | Threshold | Alert Level |
|--------|-----------|-------------|
| Transaction Failures | > 5% | Warning |
| Gas Price Spike | > 2x average | Info |
| Oracle Deviation | > 3% | Warning |
| Large Transfer | > $100k | Info |
| Pause Event | Any | Critical |

---

## 8. Frontend Development Guidelines

### Component Architecture

```
components/
├── OrbVisualization.tsx   # Main container (manages state)
├── OrbScene.tsx           # Three.js scene setup
├── Orb.tsx                # GLSL shaders, core visuals
├── BurnParticles.tsx      # Particle effects
├── TokenActions.tsx       # User interactions
├── TokenInfo.tsx          # Display components
├── WalletConnect.tsx      # Wallet integration
├── HUD.tsx                # Overlay UI
├── ParticleTrails.tsx     # Background effects
└── GlassCard.tsx          # Reusable card component
```

### Type Safety Recommendations

```typescript
// Use specific types instead of any
import type { Address, Hash } from 'viem';

interface TokenTransfer {
  from: Address;
  to: Address;
  amount: bigint;
  txHash: Hash;
}

// Type-safe contract reads
const { data: balance } = useReadContract({
  address: CONTRACT_ADDRESS as Address,
  abi: tokenAbi,
  functionName: 'balanceOf',
  args: [userAddress as Address],
}) satisfies { data: bigint | undefined };
```

### Error Handling Patterns

```typescript
// Wrap contract interactions
async function executeTransfer(to: Address, amount: bigint) {
  try {
    const hash = await writeContract({
      address: CONTRACT_ADDRESS,
      abi: tokenAbi,
      functionName: 'transfer',
      args: [to, amount],
    });

    return { success: true, hash };
  } catch (error) {
    if (error instanceof UserRejectedRequestError) {
      return { success: false, error: 'Transaction rejected by user' };
    }
    if (error instanceof ContractFunctionExecutionError) {
      return { success: false, error: parseContractError(error) };
    }
    return { success: false, error: 'Unknown error occurred' };
  }
}
```

### Performance Optimization

```typescript
// Throttle Three.js updates
const FRAME_RATE = 60;
const frameInterval = 1000 / FRAME_RATE;

useFrame((state, delta) => {
  if (delta < frameInterval) return;
  // Update logic
});

// Limit particle count
const MAX_PARTICLES = 1000;
const particles = useMemo(() =>
  Array(Math.min(count, MAX_PARTICLES)).fill(null).map(() => ({
    // particle config
  })),
  [count]
);
```

### Accessibility Improvements

```tsx
// Add ARIA labels to interactive elements
<button
  onClick={handleBurn}
  aria-label="Burn tokens"
  aria-describedby="burn-description"
>
  Burn
</button>
<span id="burn-description" className="sr-only">
  Permanently destroy tokens from your wallet
</span>

// Provide text alternative for 3D visualization
<div aria-live="polite" className="sr-only">
  Token supply visualization: {supplyPercentage}% of max supply
</div>
```

---

## 9. Template Customization Guide

### Available Templates

| Template | Location | Purpose |
|----------|----------|---------|
| ERC20Template | `src/templates/tokens/` | Standard fungible token |
| ERC721Template | `src/templates/tokens/` | NFT collection |
| StakingTemplate | `src/templates/defi/` | Token staking pool |
| VaultTemplate | `src/templates/defi/` | ERC-4626 vault |
| GovernorTemplate | `src/templates/governance/` | DAO governance |

### Customization Steps

1. **Copy template to your contract**
   ```bash
   cp src/templates/defi/StakingTemplate.sol src/MyStaking.sol
   ```

2. **Update contract name and imports**
   ```solidity
   // Before
   contract StakingTemplate is ...

   // After
   contract MyCustomStaking is ...
   ```

3. **Customize parameters**
   ```solidity
   // Staking configuration
   uint256 public constant LOCK_PERIOD = 7 days;
   uint256 public constant REWARD_RATE = 100; // BPS per year
   address public immutable REWARD_TOKEN;
   ```

4. **Add custom logic**
   ```solidity
   // Override hook functions
   function _beforeStake(address user, uint256 amount) internal override {
       // Custom validation
       require(amount >= MIN_STAKE, "Below minimum");
   }
   ```

5. **Write tests**
   ```solidity
   contract MyCustomStakingTest is Test {
       // Test custom functionality
   }
   ```

### Security Considerations per Template

| Template | Key Security Checks |
|----------|---------------------|
| ERC20 | Mint/burn access, transfer hooks |
| ERC721 | Ownership transfer, metadata URI |
| Staking | Reentrancy, reward calculation |
| Vault | Share manipulation, rounding |
| Governor | Voting power, timelock delays |

---

## 10. Emergency Response Procedures

### Emergency Contact Flow

1. **Identify Issue Severity**
   - Critical: Funds at risk, active exploit
   - High: Potential vulnerability, no active exploit
   - Medium: Functionality issue, no fund risk
   - Low: Minor bug, cosmetic issue

2. **Immediate Actions (Critical)**
   ```solidity
   // Pause contract if pausable
   contract.pause();

   // Revoke compromised roles
   contract.revokeRole(MINTER_ROLE, compromisedAddress);
   ```

3. **Communication**
   - Notify core team immediately
   - Draft public disclosure (if needed)
   - Coordinate with security researchers

### Emergency Pause Procedure

```bash
# Using cast (Foundry)
cast send $CONTRACT_ADDRESS "pause()" --private-key $ADMIN_KEY

# Verify pause state
cast call $CONTRACT_ADDRESS "paused()"
```

### Incident Response Checklist

- [ ] Identify and isolate the issue
- [ ] Pause affected contracts if possible
- [ ] Assess funds at risk
- [ ] Document timeline of events
- [ ] Prepare fix or mitigation
- [ ] Test fix on fork
- [ ] Deploy fix with multisig approval
- [ ] Resume operations gradually
- [ ] Post-mortem analysis

### Recovery Procedures

| Scenario | Recovery Action |
|----------|-----------------|
| Oracle Manipulation | Switch to backup oracle, pause price-dependent ops |
| Flash Loan Attack | Enable flash loan guards, adjust parameters |
| Bridge Exploit | Pause bridge, coordinate with bridge operators |
| Admin Key Compromise | Transfer to new multisig, revoke old keys |
| Smart Contract Bug | Upgrade via UUPS proxy, migrate state if needed |

### Rollback Procedures

```bash
# Revert to previous implementation (UUPS)
cast send $PROXY_ADDRESS "upgradeTo(address)" $PREVIOUS_IMPL --private-key $ADMIN_KEY

# Verify rollback
cast call $PROXY_ADDRESS "implementation()"
```

---

## Summary

This recommendations document provides comprehensive guidance for:

- **Security**: Audit preparation, vulnerability patterns, emergency response
- **Oracle Integration**: Multi-source strategy, failure handling, TWAP implementation
- **Cross-Chain**: Bridge selection, security patterns, recovery procedures
- **Gas Optimization**: Packed storage, efficient patterns, V2 to V3 migration
- **Library Usage**: 40+ utility libraries with examples and compatibility
- **Testing**: Coverage targets, fuzz testing, frontend testing setup
- **Deployment**: Checklists, RPC redundancy, monitoring
- **Frontend**: Type safety, error handling, accessibility
- **Templates**: Customization guide, security considerations
- **Emergency**: Response procedures, rollback mechanisms

Follow these recommendations to maintain a secure, efficient, and reliable DeFi platform.
