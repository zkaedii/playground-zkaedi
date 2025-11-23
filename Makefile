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
