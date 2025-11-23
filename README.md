# UUPSTokenV2 Proxy Deployment

Deploy an ERC1967 proxy pointing to the existing UUPSTokenV2 implementation on Arbitrum One.

**Implementation Address:** `0x74c2C1898578C04070F7aDa5d7CE0a40f3792db4`

## Features

- **UUPS Upgradeable** - Owner-controlled upgrades via `upgradeToAndCall`
- **Transaction Burn** - 0.5% default burn on transfers (configurable up to 10%)
- **Whitelist System** - Exempt addresses from burn fees
- **Pausable** - Emergency pause functionality
- **Governance Hooks** - Governance-only minting and emergency burn

## Quick Start

```bash
# Install Foundry (if not installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
make install

# Run tests
make test

# Generate calldata (for manual deployment)
make calldata
```

## Configuration

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

Required variables:
- `PRIVATE_KEY` - Your deployer wallet private key
- `ARBITRUM_RPC_URL` - Arbitrum One RPC endpoint
- `ARBISCAN_API_KEY` - For contract verification (optional)

## Deployment

### Option 1: Foundry Script (Recommended)

```bash
# Dry run (simulation)
make deploy-dry

# Deploy to Arbitrum One
make deploy

# Deploy + verify on Arbiscan
make deploy-verify
```

### Option 2: Manual via Remix/MetaMask

```bash
# Generate the initData hex
make calldata
```

Then in Remix:
1. Import `@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol`
2. Compile with Solidity 0.8.26
3. Deploy with constructor args:
   - `_implementation`: `0x74c2C1898578C04070F7aDa5d7CE0a40f3792db4`
   - `_data`: `[paste initData from calldata output]`

## Token Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Name | "UUPS Token" | ERC20 token name |
| Symbol | "UUPS" | ERC20 token symbol |
| Initial Supply | 1,000,000 | Minted to deployer (18 decimals) |
| Burn Rate | 50 bps | 0.5% burned on transfers |

## Contract Functions

### Admin (Owner Only)
- `setBurnRate(uint256)` - Update burn rate (max 1000 bps / 10%)
- `setWhitelist(address, bool)` - Add/remove from whitelist
- `setStakingContract(address)` - Set staking contract (auto-whitelisted)
- `setGovernanceContract(address)` - Set governance contract
- `pause()` / `unpause()` - Emergency controls
- `upgradeToAndCall(address, bytes)` - Upgrade implementation

### Governance Only
- `governanceMint(address, uint256)` - Mint new tokens
- `emergencyBurn(uint256)` - Burn from contract balance

### View Functions
- `calculateTransferAmounts(uint256, address, address)` - Preview burn
- `circulatingSupply()` - Total supply
- `totalBurned()` - Cumulative burned tokens

## Project Structure

```
├── src/
│   └── UUPSTokenV2.sol       # Token implementation
├── script/
│   ├── DeployProxy.s.sol     # Deployment script
│   └── GenerateCalldata.s.sol # Manual deployment helper
├── test/
│   └── UUPSTokenV2.t.sol     # Test suite
├── foundry.toml              # Foundry config
└── Makefile                  # Common commands
```

## License

MIT
