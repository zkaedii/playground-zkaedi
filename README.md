# UUPSToken - Optimized Upgradeable ERC20

Gas-optimized UUPS upgradeable token with novel DeFi mechanics.

## Versions

| Version | Gas (Transfer) | Features |
|---------|----------------|----------|
| V2 | ~75,000 | Basic burn, whitelist, pause |
| **V3** | **~65,000** | Custom types, packed storage, flash loans, holding rewards, merkle claims, commit-reveal |

## V3 Novel Features

### Custom Value Types (Type Safety + Gas Efficiency)

```solidity
type BPS is uint16;        // Basis points with safe math
type Timestamp is uint40;  // Overflow-safe timestamps
type TokenAmount is uint96; // Compact amounts (saves slots)
type PackedAccount is uint256; // Address + flags + timestamp in 1 slot
```

### Packed Storage Layout

```
SLOT 1 (PackedConfig):
├─ burnRate:     16 bits   // Transfer burn rate
├─ flashFee:     16 bits   // Flash loan fee
├─ rewardRate:   16 bits   // Holding reward rate
├─ maxSupply:    96 bits   // Hard cap
├─ configFlags:  16 bits   // Feature toggles
└─ reserved:     96 bits   // Future use

SLOT 2 (PackedState):
├─ totalBurned:      96 bits
├─ lastRewardEpoch:  40 bits
├─ deployTimestamp:  40 bits
└─ reserved:         80 bits

Per-Account (PackedAccount):
├─ address:    160 bits
├─ flags:        8 bits   // whitelist, blacklist, verified, etc.
├─ timestamp:   40 bits   // Holding start time
└─ data:        48 bits   // Custom data
```

### Dynamic Burn Curves

```solidity
// Exponential decay over time (1 year half-life)
BPS effectiveRate = DecayCurve.exponentialDecay(baseRate, elapsed, halfLife);

// Linear interpolation between rates
BPS transitionRate = BPSLib.lerp(fromRate, toRate, progress);
```

### Flash Loans (EIP-3156 Compatible)

```solidity
token.flashLoan(receiver, amount, data);
token.flashFee(amount);      // Preview fee
token.maxFlashLoan();        // Available liquidity
```

### Time-Weighted Holding Rewards

```solidity
// Check pending rewards
uint256 pending = token.pendingReward(account);

// Claim accrued rewards (mints new tokens)
uint256 claimed = token.claimHoldingReward();
```

### Merkle-Based Airdrops

```solidity
// Set merkle root for claim tranche
token.setMerkleRoot(tranche, root);

// Claim with proof
token.merkleClaim(tranche, index, amount, proof);

// Check claim status
bool claimed = token.isClaimed(tranche, index);
```

### Commit-Reveal Governance (MEV Protection)

```solidity
// Phase 1: Commit hash
bytes32 hash = keccak256(abi.encodePacked(data, salt));
token.commit(hash);

// Phase 2: Reveal after cooldown (1 hour)
token.reveal(data, salt);
```

## Quick Start

```bash
# Install dependencies
make install

# Run tests with gas report
make test-gas

# Deploy V3 to Arbitrum
make deploy-v3
```

## Gas Optimizations Applied

| Optimization | Savings |
|--------------|---------|
| Packed storage (5 slots → 2) | ~10,000 gas/tx |
| Custom value types | ~500 gas/operation |
| Unchecked math | ~100 gas/loop |
| Early returns in `_update()` | ~2,000 gas |
| Single SLOAD for account data | ~2,100 gas |
| Bitmap for merkle claims | ~20,000 gas vs mapping |

## Deployment

### Fresh Deploy (V3)

```bash
# Configure
cp .env.example .env
# Edit PRIVATE_KEY, MAX_SUPPLY, etc.

# Deploy
forge script script/DeployProxyV3.s.sol:DeployProxyV3 \
  --rpc-url arbitrum --broadcast --verify
```

### Upgrade V2 → V3

```bash
PROXY_ADDRESS=0x... forge script script/DeployProxyV3.s.sol:UpgradeToV3 \
  --rpc-url arbitrum --broadcast
```

## Configuration Flags

```solidity
FLAG_FLASH_ENABLED   = 1 << 0  // Enable flash loans
FLAG_REWARDS_ENABLED = 1 << 1  // Enable holding rewards
FLAG_DECAY_ENABLED   = 1 << 2  // Enable burn rate decay

// Toggle features
token.setConfigFlag(FLAG_DECAY_ENABLED, true);
```

## Account Flags

```solidity
FLAG_WHITELISTED = 1 << 0  // Exempt from transfer burn
FLAG_BLACKLISTED = 1 << 1  // Blocked from transfers
FLAG_IS_CONTRACT = 1 << 2  // Marked as contract
FLAG_VERIFIED    = 1 << 3  // KYC verified

// Set account flag
token.setAccountFlag(account, FLAG_WHITELISTED, true);
```

## Project Structure

```
├── src/
│   ├── UUPSTokenV2.sol        # Original implementation
│   └── UUPSTokenV3.sol        # Optimized with novel mechanics
├── script/
│   ├── DeployProxy.s.sol      # V2 deployment
│   ├── DeployProxyV3.s.sol    # V3 deployment + upgrade
│   └── GenerateCalldata.s.sol # Manual deployment helper
├── test/
│   ├── UUPSTokenV2.t.sol      # V2 tests
│   └── UUPSTokenV3.t.sol      # V3 tests + gas comparison
└── foundry.toml
```

## Security Considerations

- **Storage gap** included (`uint256[44] private __gap`)
- **Max supply cap** prevents unlimited minting
- **Commit-reveal** prevents governance front-running
- **Bitmap claims** prevents double-claiming
- **Reentrancy safe** - follows checks-effects-interactions

## License

MIT
