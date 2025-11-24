# Smart Contract Templates

This directory contains production-ready smart contract templates for common DeFi patterns and use cases.

## Directory Structure

```
templates/
├── tokens/           # Token contract templates
│   ├── ERC20Template.sol
│   └── ERC721Template.sol
├── defi/             # DeFi protocol templates
│   ├── StakingTemplate.sol
│   └── VaultTemplate.sol
├── governance/       # Governance templates
│   └── GovernorTemplate.sol
├── interfaces/       # Interface templates
│   └── ITemplate.sol
└── tests/            # Test templates
    └── TestTemplate.t.sol
```

## Usage

1. Copy the desired template to your contracts directory
2. Rename the contract and update the SPDX license if needed
3. Customize the template parameters marked with `// TODO:` comments
4. Update import paths as needed
5. Run tests to ensure functionality

## Template Features

### ERC20Template
- Standard ERC20 implementation
- Optional minting/burning capabilities
- Pausable functionality
- Access control via roles
- Permit support (EIP-2612)

### ERC721Template
- Standard ERC721 implementation
- Enumerable extension
- URI storage for metadata
- Royalty support (EIP-2981)
- Batch minting support

### StakingTemplate
- Flexible staking with customizable rewards
- Time-locked staking options
- Reward distribution mechanisms
- Emergency withdrawal support
- Compound rewards functionality

### VaultTemplate
- ERC-4626 compliant tokenized vault
- Deposit/withdrawal with shares
- Strategy pattern for yield generation
- Fee management
- Emergency shutdown capabilities

### GovernorTemplate
- Proposal creation and voting
- Timelock integration
- Quorum and threshold configuration
- Vote delegation
- Cross-chain governance support

## Best Practices

1. Always audit templates before production deployment
2. Customize security parameters based on your requirements
3. Test thoroughly on testnets first
4. Consider using upgradeable patterns for production
5. Implement proper access control and emergency stops
