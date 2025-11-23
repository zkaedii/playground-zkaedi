# Multi-Chain DEX & Smart Oracle Architecture

## Table of Contents

1. [Overview](#overview)
2. [Architecture Diagram](#architecture-diagram)
3. [Smart Oracles](#smart-oracles)
4. [Cross-Chain DEX Router](#cross-chain-dex-router)
5. [Cross-Chain Messaging](#cross-chain-messaging)
6. [Integration Patterns](#integration-patterns)
7. [Security Considerations](#security-considerations)
8. [Deployment Guide](#deployment-guide)

---

## Overview

This architecture enables seamless cross-chain token swaps with intelligent oracle-based price protection. The system aggregates liquidity from multiple DEXs across chains while ensuring optimal execution through smart oracle integration.

### Core Components

| Component | Purpose |
|-----------|---------|
| **SmartOracleAggregator** | Multi-source price feeds with fallback logic |
| **CrossChainDEXRouter** | DEX aggregation + cross-chain swap execution |
| **Oracle Interfaces** | Unified access to Chainlink, Pyth, RedStone |
| **Cross-Chain Interfaces** | CCIP and LayerZero integration |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           USER / DAPP                                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      CrossChainDEXRouter                                     │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                    │
│  │ Single-Chain  │  │  Multi-Hop    │  │ Cross-Chain   │                    │
│  │    Swaps      │  │    Swaps      │  │    Swaps      │                    │
│  └───────────────┘  └───────────────┘  └───────────────┘                    │
│         │                   │                  │                             │
│         └───────────────────┴──────────────────┘                             │
│                             │                                                │
│                             ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    Smart Order Router                                │    │
│  │  • Quote aggregation from multiple DEXs                              │    │
│  │  • Price impact calculation                                          │    │
│  │  • Split order optimization                                          │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
         │                                              │
         ▼                                              ▼
┌─────────────────────────┐              ┌─────────────────────────────────────┐
│  SmartOracleAggregator  │              │     Cross-Chain Messaging Layer     │
│                         │              │                                     │
│  ┌───────────────────┐  │              │  ┌───────────┐   ┌───────────────┐  │
│  │  Chainlink Feeds  │  │              │  │   CCIP    │   │  LayerZero    │  │
│  │  (Push Model)     │  │              │  │  Router   │   │   Endpoint    │  │
│  └───────────────────┘  │              │  └───────────┘   └───────────────┘  │
│  ┌───────────────────┐  │              │        │               │            │
│  │   Pyth Network    │  │              │        └───────┬───────┘            │
│  │  (Pull Model)     │  │              │                │                    │
│  └───────────────────┘  │              │                ▼                    │
│  ┌───────────────────┐  │              │  ┌───────────────────────────────┐  │
│  │    RedStone       │  │              │  │    Destination Chain Router   │  │
│  │  (Modular)        │  │              │  │    (Same Contract)            │  │
│  └───────────────────┘  │              │  └───────────────────────────────┘  │
│  ┌───────────────────┐  │              └─────────────────────────────────────┘
│  │   TWAP Oracle     │  │
│  │  (DEX-based)      │  │
│  └───────────────────┘  │
└─────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DEX Adapters Layer                                   │
│                                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │Uniswap V3│  │Uniswap V2│  │  Curve   │  │ Balancer │  │ Camelot  │      │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Smart Oracles

### Oracle Types Comparison

| Feature | Chainlink | Pyth | RedStone |
|---------|-----------|------|----------|
| **Model** | Push | Pull | Modular (Push/Pull) |
| **Data Sources** | Third-party aggregators | First-party institutional | Multiple sources |
| **Update Frequency** | Heartbeat-based | On-demand | Configurable |
| **Latency** | ~1 block | Real-time | Variable |
| **Cost** | Free to read | Update fee | Gas for verification |
| **Chain Support** | Major EVMs | 100+ chains | Growing |

### SmartOracleAggregator Features

```solidity
// Priority-based oracle fallback
function getPrice(address base, address quote) external view returns (PriceData memory) {
    // 1. Try primary oracle (highest priority)
    // 2. If stale/invalid, try secondary oracle
    // 3. Continue through all configured oracles
    // 4. Fall back to TWAP if all external oracles fail
    // 5. Use emergency custom price as last resort
}
```

#### Configuration Example

```solidity
// Register Chainlink as primary oracle
registry.registerOracle(
    WETH,
    USDC,
    OracleConfig({
        oracle: 0x..., // Chainlink ETH/USD feed
        oracleType: OracleType.CHAINLINK,
        heartbeat: 3600, // 1 hour
        priority: 1, // Highest priority
        isActive: true
    })
);

// Register Pyth as fallback
registry.registerOracle(
    WETH,
    USDC,
    OracleConfig({
        oracle: address(0), // Uses pythOracle contract
        oracleType: OracleType.PYTH,
        heartbeat: 60, // 1 minute
        priority: 2, // Secondary
        isActive: true
    })
);
```

### TWAP Oracle

For DEX-native price discovery, the system maintains TWAP observations:

```solidity
// Record observations (called by keepers every 5 minutes)
function recordTWAPObservation(address base, address quote, uint256 price) external;

// Query TWAP over any period
function getTWAP(address base, address quote, uint32 period) external view returns (uint256);
```

---

## Cross-Chain DEX Router

### Swap Types

#### 1. Single-Chain Swap
```solidity
// Simple A → B swap with best route
router.swap(
    tokenIn: WETH,
    tokenOut: USDC,
    amountIn: 1 ether,
    minAmountOut: 3000e6, // $3000 min
    recipient: msg.sender,
    deadline: block.timestamp + 300
);
```

#### 2. Multi-Hop Swap
```solidity
// A → B → C through different pools
router.multiHopSwap(
    MultiHopSwap({
        hops: [
            SwapRoute(WETH, WBTC, 1 ether, DEXType.UNISWAP_V3, ...),
            SwapRoute(WBTC, USDC, 0, DEXType.CURVE, ...)
        ],
        minAmountOut: 3000e6,
        deadline: block.timestamp + 300
    }),
    recipient
);
```

#### 3. Split Swap
```solidity
// Split order across multiple DEXs for better execution
router.splitSwap(
    SplitSwap({
        routes: [
            SwapRoute(..., DEXType.UNISWAP_V3, ...),
            SwapRoute(..., DEXType.CURVE, ...),
            SwapRoute(..., DEXType.BALANCER, ...)
        ],
        portions: [5000, 3000, 2000], // 50%, 30%, 20%
        minAmountOut: 3000e6,
        deadline: block.timestamp + 300
    }),
    recipient
);
```

#### 4. Cross-Chain Swap
```solidity
// Swap on source chain → Bridge → Swap on destination chain
router.crossChainSwap{value: bridgeFee}(
    CrossChainSwap({
        tokenIn: WETH,           // Source token
        tokenOut: ARB,           // Destination token
        amountIn: 1 ether,
        minAmountOut: 1000e18,
        srcChainId: 1,           // Ethereum
        dstChainId: 42161,       // Arbitrum
        recipient: msg.sender,
        bridgeData: abi.encode(USDC), // Bridge via USDC
        swapData: abi.encode(...)     // Dest chain swap params
    })
);
```

### Price Impact Protection

The router validates all swaps against oracle prices:

```solidity
function _validatePriceImpact(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut
) internal view {
    PriceData memory price = oracle.getPrice(tokenIn, tokenOut);
    uint256 expectedOut = (amountIn * price.price) / (10 ** price.decimals);

    uint256 impactBps = ((expectedOut - amountOut) * 10000) / expectedOut;
    if (impactBps > maxPriceImpactBps) revert PriceImpactTooHigh();
}
```

---

## Cross-Chain Messaging

### Chainlink CCIP

**Advantages:**
- Level-5 security with Risk Management Network
- Native token transfer support
- Programmable token transfers (tokens + data)

**Flow:**
```
Source Chain                          Destination Chain
     │                                      │
     │  1. User calls crossChainSwap()      │
     │                                      │
     │  2. Execute source swap (if needed)  │
     │                                      │
     │  3. ccipRouter.ccipSend()            │
     │         │                            │
     │         └──────────────────────────► │
     │                                      │
     │                      4. ccipReceive()│
     │                                      │
     │                      5. Execute dest │
     │                         swap         │
     │                                      │
     │                      6. Transfer to  │
     │                         recipient    │
```

### LayerZero V2

**Advantages:**
- 100+ chain support
- Omnichain Fungible Token (OFT) standard
- Configurable security (DVNs)

**Flow:**
```
Source Chain                          Destination Chain
     │                                      │
     │  1. User calls crossChainSwap()      │
     │                                      │
     │  2. lzEndpoint.send()                │
     │         │                            │
     │         └──────────────────────────► │
     │              (via DVNs)              │
     │                                      │
     │                      3. lzReceive()  │
     │                                      │
     │                      4. Process swap │
```

### Chain Configuration

```solidity
// Configure Arbitrum for CCIP
router.configureChain(
    chainId: 42161,
    ccipSelector: 4949039107694359620, // Arbitrum CCIP selector
    lzEid: 30110, // Arbitrum LayerZero endpoint ID
    trustedRemote: bytes32(uint256(uint160(arbitrumRouterAddress)))
);
```

---

## Integration Patterns

### Pattern 1: DEX Integration

```solidity
// Implement DEX adapter interface
contract UniswapV3Adapter {
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256) {
        // Execute swap on Uniswap V3
        return uniswapRouter.exactInputSingle(
            IUniswapV3Router.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 3000, // 0.3%
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
    }
}
```

### Pattern 2: Oracle Integration

```solidity
// Add new oracle source
contract CustomOracleAdapter is ISmartOracle {
    function getPrice(address base, address quote)
        external view returns (PriceData memory)
    {
        // Fetch from custom source
        uint256 price = customSource.getPrice(base, quote);

        return PriceData({
            price: price,
            decimals: 18,
            timestamp: block.timestamp,
            confidence: 0,
            source: OracleType.CUSTOM
        });
    }
}
```

### Pattern 3: Cross-Chain Token Standard

```solidity
// Use LayerZero OFT for native cross-chain tokens
contract MyToken is OFT {
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint
    ) OFT(_name, _symbol, _lzEndpoint) {}
}
```

---

## Security Considerations

### Oracle Security

| Risk | Mitigation |
|------|------------|
| Stale prices | Staleness threshold checks |
| Price manipulation | Multi-oracle aggregation |
| Single point of failure | Priority-based fallback |
| Flash loan attacks | TWAP as additional check |

### Cross-Chain Security

| Risk | Mitigation |
|------|------------|
| Replay attacks | Message ID tracking |
| Unauthorized relayers | Trusted remote verification |
| Bridge failures | Timeout + refund mechanism |
| Price divergence | Oracle validation on both chains |

### Smart Contract Security

```solidity
// Reentrancy protection
contract CrossChainDEXRouter is ReentrancyGuardUpgradeable {
    function swap(...) external nonReentrant { ... }
}

// Access control
modifier onlyOwner() { ... }
modifier onlyTrustedRemote(uint32 srcEid, bytes32 sender) { ... }

// Safe token handling
using SafeERC20 for IERC20;
IERC20(token).safeTransfer(recipient, amount);
```

---

## Deployment Guide

### Prerequisites

```bash
# Install dependencies
forge install

# Set environment variables
export PRIVATE_KEY=...
export ARBITRUM_RPC_URL=...
export ARBISCAN_API_KEY=...
```

### Deployment Order

1. **Deploy Oracle Aggregator**
```bash
forge script script/DeployOracle.s.sol --rpc-url $ARBITRUM_RPC_URL --broadcast
```

2. **Configure Oracle Feeds**
```solidity
oracle.setTokenFeedId(WETH, 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace);
oracle.registerOracle(WETH, USDC, chainlinkConfig);
```

3. **Deploy DEX Router**
```bash
forge script script/DeployRouter.s.sol --rpc-url $ARBITRUM_RPC_URL --broadcast
```

4. **Configure DEX Adapters**
```solidity
router.registerDEXAdapter(DEXType.UNISWAP_V3, uniswapAdapterAddress);
router.registerDEXAdapter(DEXType.CURVE, curveAdapterAddress);
```

5. **Configure Cross-Chain**
```solidity
router.setCCIPRouter(ccipRouterAddress);
router.setLZEndpoint(lzEndpointAddress);
router.configureChain(1, ethCcipSelector, ethLzEid, trustedRemote);
```

### Verification

```bash
forge verify-contract \
    --chain-id 42161 \
    --compiler-version v0.8.26 \
    $CONTRACT_ADDRESS \
    src/oracles/SmartOracleAggregator.sol:SmartOracleAggregator
```

---

## Contract Addresses

### Mainnet Oracles

| Network | Chainlink Registry | Pyth | RedStone |
|---------|-------------------|------|----------|
| Ethereum | `0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf` | `0x4305FB66699C3B2702D4d05CF36551390A4c69C6` | TBD |
| Arbitrum | `0x...` | `0xff1a0f4744e8582DF1aE09D5611b887B6a12925C` | TBD |
| Polygon | `0x...` | `0xff1a0f4744e8582DF1aE09D5611b887B6a12925C` | TBD |

### Cross-Chain Infrastructure

| Network | CCIP Router | LayerZero Endpoint |
|---------|-------------|-------------------|
| Ethereum | `0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D` | `0x1a44076050125825900e736c501f859c50fE728c` |
| Arbitrum | `0x141fa059441E0ca23ce184B6A78bafD2A517DdE8` | `0x1a44076050125825900e736c501f859c50fE728c` |

---

## References

- [Chainlink CCIP Documentation](https://docs.chain.link/ccip)
- [LayerZero V2 Documentation](https://docs.layerzero.network/v2)
- [Pyth Network Documentation](https://docs.pyth.network/)
- [1inch Aggregation Protocol](https://docs.1inch.io/)
- [Uniswap V3 SDK](https://docs.uniswap.org/sdk/v3/overview)
