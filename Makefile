# Load .env file if it exists
-include .env

.PHONY: all test clean deploy install build

# Default target
all: install build test

# Install dependencies
install:
	forge install foundry-rs/forge-std --no-commit
	forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-commit
	forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.2 --no-commit

# Build contracts
build:
	forge build

# Run tests
test:
	forge test -vvv

# Run tests with gas report
test-gas:
	forge test -vvv --gas-report

# Generate calldata for manual deployment
calldata:
	forge script script/GenerateCalldata.s.sol -vvv

# Dry run deployment (simulation)
deploy-dry:
	forge script script/DeployProxy.s.sol:DeployProxyDryRun --rpc-url arbitrum -vvv

# Deploy to Arbitrum One (LIVE)
deploy:
	forge script script/DeployProxy.s.sol:DeployProxy --rpc-url arbitrum --broadcast -vvv

# Deploy and verify on Arbiscan
deploy-verify:
	forge script script/DeployProxy.s.sol:DeployProxy --rpc-url arbitrum --broadcast --verify -vvv

# Deploy to Arbitrum Sepolia (testnet)
deploy-testnet:
	forge script script/DeployProxy.s.sol:DeployProxy --rpc-url arbitrum_sepolia --broadcast -vvv

# ============ V3 DEPLOYMENT ============

# Deploy V3 to Arbitrum One
deploy-v3:
	forge script script/DeployProxyV3.s.sol:DeployProxyV3 --rpc-url arbitrum --broadcast -vvv

# Deploy V3 with verification
deploy-v3-verify:
	forge script script/DeployProxyV3.s.sol:DeployProxyV3 --rpc-url arbitrum --broadcast --verify -vvv

# Upgrade existing proxy to V3
upgrade-v3:
	forge script script/DeployProxyV3.s.sol:UpgradeToV3 --rpc-url arbitrum --broadcast -vvv

# Deploy V3 to testnet
deploy-v3-testnet:
	forge script script/DeployProxyV3.s.sol:DeployProxyV3 --rpc-url arbitrum_sepolia --broadcast -vvv

# ============ GAS COMPARISON ============

# Compare V2 vs V3 gas usage
gas-compare:
	forge test --match-contract GasComparisonTest -vvv --gas-report

# Clean build artifacts
clean:
	forge clean
	rm -rf cache out broadcast

# Format code
fmt:
	forge fmt

# Check formatting
fmt-check:
	forge fmt --check

# Slither security analysis (requires slither installed)
slither:
	slither src/

# Show gas snapshot
snapshot:
	forge snapshot
