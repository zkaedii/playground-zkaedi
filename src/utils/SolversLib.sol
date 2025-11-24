// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SolversLib
 * @notice Optimization solvers for DeFi applications
 * @dev Provides algorithms for intent solving, route optimization, liquidity balancing,
 *      portfolio optimization, and auction clearing mechanisms
 */
library SolversLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Maximum iterations for solver algorithms
    uint256 internal constant MAX_ITERATIONS = 100;

    /// @dev Convergence threshold (0.01%)
    uint256 internal constant CONVERGENCE_THRESHOLD = 1;

    /// @dev Maximum routes to consider
    uint256 internal constant MAX_ROUTES = 20;

    /// @dev Maximum hops in a route
    uint256 internal constant MAX_HOPS = 5;

    /// @dev Basis points denominator
    uint256 internal constant BPS_DENOMINATOR = 10000;

    /// @dev WAD precision (18 decimals)
    uint256 internal constant WAD = 1e18;

    /// @dev Newton-Raphson precision factor
    uint256 internal constant NEWTON_PRECISION = 1e12;

    /// @dev Binary search precision
    uint256 internal constant BINARY_SEARCH_PRECISION = 1e6;

    /// @dev Maximum assets in portfolio
    uint256 internal constant MAX_PORTFOLIO_ASSETS = 50;

    /// @dev Default slippage tolerance (0.5%)
    uint256 internal constant DEFAULT_SLIPPAGE = 50;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error SolverConvergenceFailed(uint256 iterations);
    error NoValidRouteFound();
    error MaxHopsExceeded(uint256 hops, uint256 max);
    error MaxRoutesExceeded(uint256 routes, uint256 max);
    error InsufficientLiquidity(uint256 required, uint256 available);
    error InvalidIntent(bytes32 intentId);
    error IntentExpired(bytes32 intentId, uint256 deadline);
    error IntentAlreadyFilled(bytes32 intentId);
    error SlippageExceeded(uint256 expected, uint256 actual, uint256 tolerance);
    error InvalidOptimizationTarget();
    error PortfolioSizeExceeded(uint256 size, uint256 max);
    error InvalidWeights(uint256 sum);
    error NegativeValue();
    error DivisionByZero();
    error OverflowDetected();
    error InvalidBounds(uint256 lower, uint256 upper);
    error AuctionNotCleared();
    error BidBelowMinimum(uint256 bid, uint256 minimum);
    error InsufficientBids(uint256 count, uint256 required);

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Optimization objective type
    enum OptimizationType {
        MinimizeCost,
        MaximizeReturn,
        MinimizeRisk,
        MaximizeSharpe,
        BalancedAllocation
    }

    /// @notice Intent status
    enum IntentStatus {
        Pending,
        PartiallyFilled,
        Filled,
        Cancelled,
        Expired
    }

    /// @notice Route hop type
    enum HopType {
        Swap,
        Bridge,
        Wrap,
        Unwrap,
        Deposit,
        Withdraw
    }

    /// @notice Single hop in a route
    struct RouteHop {
        HopType hopType;
        address protocol;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 expectedAmountOut;
        bytes extraData;
    }

    /// @notice Complete route from source to destination
    struct Route {
        bytes32 routeId;
        RouteHop[] hops;
        uint256 totalAmountIn;
        uint256 totalExpectedOut;
        uint256 estimatedGas;
        uint256 priceImpactBps;
        uint256 score;
    }

    /// @notice Intent for order matching
    struct Intent {
        bytes32 intentId;
        address maker;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
        IntentStatus status;
        uint256 filledAmount;
        bytes32 constraintHash;
    }

    /// @notice Intent matching result
    struct IntentMatch {
        bytes32 intentId1;
        bytes32 intentId2;
        uint256 matchedAmount;
        uint256 clearingPrice;
        bytes32 settlementRoute;
    }

    /// @notice Pool state for liquidity calculations
    struct PoolState {
        address pool;
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
        uint256 fee; // in basis points
        uint256 liquidity;
    }

    /// @notice Portfolio asset
    struct PortfolioAsset {
        address token;
        uint256 currentWeight;
        uint256 targetWeight;
        uint256 currentValue;
        uint256 expectedReturn;
        uint256 volatility;
    }

    /// @notice Rebalance action
    struct RebalanceAction {
        address token;
        bool isBuy;
        uint256 amount;
        uint256 priority;
    }

    /// @notice Auction bid
    struct AuctionBid {
        address bidder;
        uint256 price;
        uint256 quantity;
        uint256 timestamp;
    }

    /// @notice Auction clearing result
    struct AuctionClearing {
        uint256 clearingPrice;
        uint256 totalQuantity;
        uint256 filledBids;
        address[] winners;
        uint256[] allocations;
    }

    /// @notice Solver solution
    struct Solution {
        bytes32 solutionId;
        uint256 objectiveValue;
        uint256[] variables;
        bool isOptimal;
        uint256 iterations;
        uint256 computationGas;
    }

    /// @notice Linear constraint for optimization
    struct LinearConstraint {
        int256[] coefficients;
        int256 rhs;
        bool isEquality; // true = equality, false = less than or equal
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROUTE OPTIMIZATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Find optimal route among candidates
    /// @param routes Array of candidate routes
    /// @param optimizeFor Optimization objective
    /// @return bestRoute The optimal route
    /// @return bestIndex Index of the best route
    function findOptimalRoute(
        Route[] memory routes,
        OptimizationType optimizeFor
    ) internal pure returns (Route memory bestRoute, uint256 bestIndex) {
        if (routes.length == 0) {
            revert NoValidRouteFound();
        }

        uint256 bestScore;
        bool initialized;

        for (uint256 i; i < routes.length;) {
            uint256 score = _calculateRouteScore(routes[i], optimizeFor);

            if (!initialized || score > bestScore) {
                bestScore = score;
                bestIndex = i;
                initialized = true;
            }

            unchecked { ++i; }
        }

        bestRoute = routes[bestIndex];
        bestRoute.score = bestScore;
    }

    /// @notice Calculate route score based on optimization type
    /// @param route Route to score
    /// @param optimizeFor Optimization objective
    /// @return score Route score (higher is better)
    function _calculateRouteScore(
        Route memory route,
        OptimizationType optimizeFor
    ) private pure returns (uint256 score) {
        if (optimizeFor == OptimizationType.MaximizeReturn) {
            // Higher output = better
            score = route.totalExpectedOut;
        } else if (optimizeFor == OptimizationType.MinimizeCost) {
            // Lower gas and price impact = better
            // Invert so higher is better
            if (route.estimatedGas > 0) {
                score = WAD / (route.estimatedGas + route.priceImpactBps * 1000);
            }
        } else if (optimizeFor == OptimizationType.MinimizeRisk) {
            // Lower price impact = better
            if (route.priceImpactBps > 0) {
                score = WAD / route.priceImpactBps;
            } else {
                score = WAD;
            }
        } else {
            // Balanced: consider output, gas, and price impact
            uint256 outputScore = route.totalExpectedOut;
            uint256 costPenalty = route.estimatedGas + route.priceImpactBps * 1000;
            if (costPenalty > 0) {
                score = (outputScore * WAD) / (WAD + costPenalty);
            } else {
                score = outputScore;
            }
        }
    }

    /// @notice Calculate expected output for a swap through pools
    /// @param pools Array of pool states (in order of route)
    /// @param amountIn Input amount
    /// @param zeroForOne Direction (true = token0 to token1)
    /// @return amountOut Expected output amount
    /// @return priceImpactBps Price impact in basis points
    function calculateSwapOutput(
        PoolState[] memory pools,
        uint256 amountIn,
        bool zeroForOne
    ) internal pure returns (uint256 amountOut, uint256 priceImpactBps) {
        amountOut = amountIn;

        uint256 initialRate;
        uint256 finalRate;

        for (uint256 i; i < pools.length;) {
            PoolState memory pool = pools[i];

            (uint256 reserveIn, uint256 reserveOut) = zeroForOne
                ? (pool.reserve0, pool.reserve1)
                : (pool.reserve1, pool.reserve0);

            if (i == 0) {
                initialRate = (reserveOut * WAD) / reserveIn;
            }

            // Calculate output using constant product formula with fee
            uint256 amountInWithFee = amountOut * (BPS_DENOMINATOR - pool.fee);
            uint256 numerator = amountInWithFee * reserveOut;
            uint256 denominator = reserveIn * BPS_DENOMINATOR + amountInWithFee;

            amountOut = numerator / denominator;

            if (i == pools.length - 1) {
                uint256 newReserveIn = reserveIn + amountIn;
                uint256 newReserveOut = reserveOut - amountOut;
                finalRate = (newReserveOut * WAD) / newReserveIn;
            }

            unchecked { ++i; }
        }

        // Calculate price impact
        if (initialRate > finalRate) {
            priceImpactBps = ((initialRate - finalRate) * BPS_DENOMINATOR) / initialRate;
        }
    }

    /// @notice Split amount across multiple routes for better execution
    /// @param routes Available routes
    /// @param totalAmount Total amount to swap
    /// @param maxSplits Maximum number of splits
    /// @return splits Amount to route through each path
    /// @return totalExpectedOut Combined expected output
    function calculateOptimalSplit(
        Route[] memory routes,
        uint256 totalAmount,
        uint256 maxSplits
    ) internal pure returns (uint256[] memory splits, uint256 totalExpectedOut) {
        uint256 routeCount = routes.length < maxSplits ? routes.length : maxSplits;
        splits = new uint256[](routeCount);

        if (routeCount == 0) {
            revert NoValidRouteFound();
        }

        if (routeCount == 1) {
            splits[0] = totalAmount;
            totalExpectedOut = routes[0].totalExpectedOut;
            return (splits, totalExpectedOut);
        }

        // Calculate weights based on route scores
        uint256 totalScore;
        for (uint256 i; i < routeCount;) {
            totalScore += routes[i].score > 0 ? routes[i].score : 1;
            unchecked { ++i; }
        }

        // Allocate proportionally to scores
        uint256 allocated;
        for (uint256 i; i < routeCount;) {
            uint256 routeScore = routes[i].score > 0 ? routes[i].score : 1;
            splits[i] = (totalAmount * routeScore) / totalScore;
            allocated += splits[i];

            // Estimate output for this split (linear approximation)
            if (routes[i].totalAmountIn > 0) {
                totalExpectedOut += (routes[i].totalExpectedOut * splits[i]) / routes[i].totalAmountIn;
            }

            unchecked { ++i; }
        }

        // Handle rounding remainder
        if (allocated < totalAmount && splits.length > 0) {
            splits[0] += totalAmount - allocated;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTENT MATCHING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Match two intents for peer-to-peer settlement
    /// @param intent1 First intent
    /// @param intent2 Second intent
    /// @return canMatch True if intents can be matched
    /// @return matchedAmount Amount that can be matched
    /// @return clearingPrice Fair clearing price
    function matchIntents(
        Intent memory intent1,
        Intent memory intent2
    ) internal view returns (bool canMatch, uint256 matchedAmount, uint256 clearingPrice) {
        // Check basic compatibility
        if (intent1.tokenIn != intent2.tokenOut || intent1.tokenOut != intent2.tokenIn) {
            return (false, 0, 0);
        }

        // Check deadlines
        if (block.timestamp > intent1.deadline || block.timestamp > intent2.deadline) {
            return (false, 0, 0);
        }

        // Check status
        if (intent1.status != IntentStatus.Pending && intent1.status != IntentStatus.PartiallyFilled) {
            return (false, 0, 0);
        }
        if (intent2.status != IntentStatus.Pending && intent2.status != IntentStatus.PartiallyFilled) {
            return (false, 0, 0);
        }

        // Calculate remaining amounts
        uint256 remaining1 = intent1.amountIn - intent1.filledAmount;
        uint256 remaining2 = intent2.amountIn - intent2.filledAmount;

        // Calculate implied prices (price = amountOut / amountIn)
        uint256 price1 = (intent1.minAmountOut * WAD) / intent1.amountIn; // min price intent1 accepts
        uint256 price2 = (intent2.amountIn * WAD) / intent2.minAmountOut; // max price intent2 offers

        // Intents match if price2 >= price1
        if (price2 < price1) {
            return (false, 0, 0);
        }

        // Clearing price is the midpoint
        clearingPrice = (price1 + price2) / 2;

        // Calculate matched amount (limited by both sides)
        uint256 maxFromIntent1 = remaining1;
        uint256 maxFromIntent2 = (remaining2 * WAD) / clearingPrice;

        matchedAmount = maxFromIntent1 < maxFromIntent2 ? maxFromIntent1 : maxFromIntent2;

        canMatch = matchedAmount > 0;
    }

    /// @notice Find best matches for an intent from a pool of counter-intents
    /// @param intent The intent to match
    /// @param counterIntents Pool of potential counter-intents
    /// @return matches Array of matched intents
    /// @return totalFilled Total amount filled
    function findBestMatches(
        Intent memory intent,
        Intent[] memory counterIntents
    ) internal view returns (IntentMatch[] memory matches, uint256 totalFilled) {
        // First pass: find all compatible intents and score them
        uint256[] memory scores = new uint256[](counterIntents.length);
        uint256[] memory amounts = new uint256[](counterIntents.length);
        uint256 compatibleCount;

        for (uint256 i; i < counterIntents.length;) {
            (bool canMatch, uint256 matchedAmount, uint256 price) = matchIntents(intent, counterIntents[i]);

            if (canMatch) {
                scores[i] = matchedAmount * price / WAD; // Score by value
                amounts[i] = matchedAmount;
                unchecked { ++compatibleCount; }
            }

            unchecked { ++i; }
        }

        if (compatibleCount == 0) {
            return (new IntentMatch[](0), 0);
        }

        // Create matches array
        matches = new IntentMatch[](compatibleCount);
        uint256 remaining = intent.amountIn - intent.filledAmount;
        uint256 matchIndex;

        // Greedy matching: take best scores first
        while (remaining > 0 && matchIndex < compatibleCount) {
            uint256 bestIdx;
            uint256 bestScore;

            for (uint256 i; i < counterIntents.length;) {
                if (scores[i] > bestScore && amounts[i] > 0) {
                    bestScore = scores[i];
                    bestIdx = i;
                }
                unchecked { ++i; }
            }

            if (bestScore == 0) break;

            uint256 fillAmount = amounts[bestIdx] < remaining ? amounts[bestIdx] : remaining;

            (, , uint256 price) = matchIntents(intent, counterIntents[bestIdx]);

            matches[matchIndex] = IntentMatch({
                intentId1: intent.intentId,
                intentId2: counterIntents[bestIdx].intentId,
                matchedAmount: fillAmount,
                clearingPrice: price,
                settlementRoute: bytes32(0)
            });

            totalFilled += fillAmount;
            remaining -= fillAmount;
            amounts[bestIdx] = 0;
            scores[bestIdx] = 0;

            unchecked { ++matchIndex; }
        }

        // Resize array if needed
        if (matchIndex < compatibleCount) {
            assembly {
                mstore(matches, matchIndex)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PORTFOLIO OPTIMIZATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate rebalance actions to reach target weights
    /// @param assets Current portfolio assets
    /// @param totalValue Total portfolio value
    /// @return actions Required rebalance actions
    function calculateRebalanceActions(
        PortfolioAsset[] memory assets,
        uint256 totalValue
    ) internal pure returns (RebalanceAction[] memory actions) {
        if (assets.length > MAX_PORTFOLIO_ASSETS) {
            revert PortfolioSizeExceeded(assets.length, MAX_PORTFOLIO_ASSETS);
        }

        actions = new RebalanceAction[](assets.length);
        uint256 actionCount;

        for (uint256 i; i < assets.length;) {
            uint256 targetValue = (totalValue * assets[i].targetWeight) / BPS_DENOMINATOR;
            uint256 currentValue = assets[i].currentValue;

            if (targetValue > currentValue) {
                // Need to buy
                uint256 buyAmount = targetValue - currentValue;
                if (buyAmount > totalValue / 1000) { // Min 0.1% threshold
                    actions[actionCount] = RebalanceAction({
                        token: assets[i].token,
                        isBuy: true,
                        amount: buyAmount,
                        priority: assets[i].targetWeight // Higher weight = higher priority
                    });
                    unchecked { ++actionCount; }
                }
            } else if (currentValue > targetValue) {
                // Need to sell
                uint256 sellAmount = currentValue - targetValue;
                if (sellAmount > totalValue / 1000) {
                    actions[actionCount] = RebalanceAction({
                        token: assets[i].token,
                        isBuy: false,
                        amount: sellAmount,
                        priority: BPS_DENOMINATOR - assets[i].targetWeight
                    });
                    unchecked { ++actionCount; }
                }
            }

            unchecked { ++i; }
        }

        // Resize array
        assembly {
            mstore(actions, actionCount)
        }
    }

    /// @notice Calculate optimal weights using mean-variance optimization
    /// @param assets Portfolio assets with expected returns and volatility
    /// @param targetReturn Target portfolio return
    /// @return weights Optimal portfolio weights
    function calculateOptimalWeights(
        PortfolioAsset[] memory assets,
        uint256 targetReturn
    ) internal pure returns (uint256[] memory weights) {
        weights = new uint256[](assets.length);

        if (assets.length == 0) return weights;
        if (assets.length == 1) {
            weights[0] = BPS_DENOMINATOR;
            return weights;
        }

        // Simplified mean-variance: weight inversely to volatility, scaled by return
        uint256 totalScore;

        for (uint256 i; i < assets.length;) {
            uint256 returnScore = assets[i].expectedReturn > 0 ? assets[i].expectedReturn : 1;
            uint256 riskPenalty = assets[i].volatility > 0 ? assets[i].volatility : 1;

            // Score = return / risk (Sharpe-like)
            uint256 score = (returnScore * WAD) / riskPenalty;
            weights[i] = score;
            totalScore += score;

            unchecked { ++i; }
        }

        // Normalize to sum to BPS_DENOMINATOR
        uint256 totalWeight;
        for (uint256 i; i < assets.length;) {
            weights[i] = (weights[i] * BPS_DENOMINATOR) / totalScore;
            totalWeight += weights[i];
            unchecked { ++i; }
        }

        // Fix rounding
        if (totalWeight < BPS_DENOMINATOR && assets.length > 0) {
            weights[0] += BPS_DENOMINATOR - totalWeight;
        }
    }

    /// @notice Calculate portfolio variance
    /// @param assets Portfolio assets
    /// @param weights Current weights
    /// @return variance Portfolio variance
    function calculatePortfolioVariance(
        PortfolioAsset[] memory assets,
        uint256[] memory weights
    ) internal pure returns (uint256 variance) {
        // Simplified: assume uncorrelated assets
        // Variance = sum(weight_i^2 * volatility_i^2)

        for (uint256 i; i < assets.length;) {
            uint256 weightSquared = (weights[i] * weights[i]) / BPS_DENOMINATOR;
            uint256 volSquared = (assets[i].volatility * assets[i].volatility) / WAD;
            variance += (weightSquared * volSquared) / BPS_DENOMINATOR;
            unchecked { ++i; }
        }
    }

    /// @notice Calculate expected portfolio return
    /// @param assets Portfolio assets
    /// @param weights Current weights
    /// @return expectedReturn Weighted average expected return
    function calculateExpectedReturn(
        PortfolioAsset[] memory assets,
        uint256[] memory weights
    ) internal pure returns (uint256 expectedReturn) {
        for (uint256 i; i < assets.length;) {
            expectedReturn += (weights[i] * assets[i].expectedReturn) / BPS_DENOMINATOR;
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AUCTION CLEARING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Clear a uniform price auction
    /// @param bids Array of bids sorted by price descending
    /// @param totalSupply Total supply to allocate
    /// @param minPrice Minimum acceptable price
    /// @return clearing Auction clearing result
    function clearUniformPriceAuction(
        AuctionBid[] memory bids,
        uint256 totalSupply,
        uint256 minPrice
    ) internal pure returns (AuctionClearing memory clearing) {
        if (bids.length == 0) {
            revert InsufficientBids(0, 1);
        }

        // Find clearing price (price at which demand = supply)
        uint256 cumulativeQuantity;
        uint256 clearingIdx;

        for (uint256 i; i < bids.length;) {
            if (bids[i].price < minPrice) {
                break;
            }

            cumulativeQuantity += bids[i].quantity;

            if (cumulativeQuantity >= totalSupply) {
                clearingIdx = i;
                clearing.clearingPrice = bids[i].price;
                break;
            }

            unchecked { ++i; }
        }

        if (clearing.clearingPrice == 0) {
            // Not enough demand, clear at min price
            clearing.clearingPrice = minPrice;
            clearing.totalQuantity = cumulativeQuantity;
        } else {
            clearing.totalQuantity = totalSupply;
        }

        // Allocate to winners
        uint256 winnerCount;
        for (uint256 i; i < bids.length;) {
            if (bids[i].price >= clearing.clearingPrice) {
                unchecked { ++winnerCount; }
            } else {
                break;
            }
            unchecked { ++i; }
        }

        clearing.winners = new address[](winnerCount);
        clearing.allocations = new uint256[](winnerCount);
        clearing.filledBids = winnerCount;

        uint256 remaining = clearing.totalQuantity;

        for (uint256 i; i < winnerCount;) {
            clearing.winners[i] = bids[i].bidder;

            if (i == clearingIdx) {
                // Marginal bidder may get partial fill
                clearing.allocations[i] = remaining;
            } else if (bids[i].quantity <= remaining) {
                clearing.allocations[i] = bids[i].quantity;
                remaining -= bids[i].quantity;
            } else {
                clearing.allocations[i] = remaining;
                remaining = 0;
            }

            unchecked { ++i; }
        }
    }

    /// @notice Clear a Dutch auction
    /// @param startPrice Starting price
    /// @param endPrice Ending (reserve) price
    /// @param duration Auction duration
    /// @param elapsed Time elapsed
    /// @param totalSupply Total supply
    /// @param bidQuantity Quantity being bid
    /// @return currentPrice Current auction price
    /// @return allocation Amount allocated to bidder
    function clearDutchAuction(
        uint256 startPrice,
        uint256 endPrice,
        uint256 duration,
        uint256 elapsed,
        uint256 totalSupply,
        uint256 bidQuantity
    ) internal pure returns (uint256 currentPrice, uint256 allocation) {
        if (elapsed >= duration) {
            currentPrice = endPrice;
        } else {
            // Linear decay
            uint256 priceRange = startPrice - endPrice;
            uint256 decay = (priceRange * elapsed) / duration;
            currentPrice = startPrice - decay;
        }

        allocation = bidQuantity < totalSupply ? bidQuantity : totalSupply;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // NUMERICAL SOLVER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Find root using Newton-Raphson method
    /// @param initialGuess Starting point
    /// @param tolerance Convergence tolerance
    /// @param f Function value at x (provided externally)
    /// @param fPrime Derivative value at x (provided externally)
    /// @return root Approximate root
    function newtonRaphsonStep(
        uint256 initialGuess,
        uint256 tolerance,
        int256 f,
        int256 fPrime
    ) internal pure returns (uint256 root, bool converged) {
        if (fPrime == 0) {
            revert DivisionByZero();
        }

        int256 guess = int256(initialGuess);
        int256 delta = (f * int256(NEWTON_PRECISION)) / fPrime;
        int256 newGuess = guess - delta;

        if (newGuess < 0) {
            root = 0;
        } else {
            root = uint256(newGuess);
        }

        // Check convergence
        uint256 change = delta >= 0 ? uint256(delta) : uint256(-delta);
        converged = change < tolerance;
    }

    /// @notice Binary search for optimal value
    /// @param lowerBound Lower bound of search space
    /// @param upperBound Upper bound of search space
    /// @param targetValue Target value to find
    /// @param currentValue Current value at midpoint
    /// @param isIncreasing True if function is monotonically increasing
    /// @return newLower New lower bound
    /// @return newUpper New upper bound
    /// @return midpoint Current midpoint
    function binarySearchStep(
        uint256 lowerBound,
        uint256 upperBound,
        uint256 targetValue,
        uint256 currentValue,
        bool isIncreasing
    ) internal pure returns (uint256 newLower, uint256 newUpper, uint256 midpoint) {
        if (lowerBound > upperBound) {
            revert InvalidBounds(lowerBound, upperBound);
        }

        midpoint = (lowerBound + upperBound) / 2;

        if (currentValue == targetValue) {
            return (midpoint, midpoint, midpoint);
        }

        bool tooLow = isIncreasing
            ? currentValue < targetValue
            : currentValue > targetValue;

        if (tooLow) {
            newLower = midpoint + 1;
            newUpper = upperBound;
        } else {
            newLower = lowerBound;
            newUpper = midpoint > 0 ? midpoint - 1 : 0;
        }
    }

    /// @notice Solve for x in constant product AMM: x * y = k
    /// @param k Constant product
    /// @param otherReserve Other reserve amount
    /// @return reserve Computed reserve
    function solveConstantProduct(
        uint256 k,
        uint256 otherReserve
    ) internal pure returns (uint256 reserve) {
        if (otherReserve == 0) {
            revert DivisionByZero();
        }
        reserve = k / otherReserve;
    }

    /// @notice Calculate square root using Newton's method
    /// @param x Value to find square root of
    /// @return y Square root of x
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;

        uint256 z = (x + 1) / 2;
        y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /// @notice Calculate cube root approximation
    /// @param x Value to find cube root of
    /// @return y Approximate cube root
    function cbrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;

        // Initial guess
        y = x;

        // Newton's method for cube root: y = (2*y + x/y^2) / 3
        for (uint256 i; i < 50;) {
            uint256 ySquared = y * y;
            if (ySquared == 0) break;

            uint256 newY = (2 * y + x / ySquared) / 3;

            if (newY >= y) break;
            y = newY;

            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LIQUIDITY BALANCING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate optimal liquidity distribution across pools
    /// @param pools Array of pool states
    /// @param totalLiquidity Total liquidity to distribute
    /// @return distributions Liquidity per pool
    function calculateLiquidityDistribution(
        PoolState[] memory pools,
        uint256 totalLiquidity
    ) internal pure returns (uint256[] memory distributions) {
        distributions = new uint256[](pools.length);

        if (pools.length == 0 || totalLiquidity == 0) {
            return distributions;
        }

        // Weight by inverse of fee (lower fee = more liquidity)
        uint256 totalWeight;
        uint256[] memory weights = new uint256[](pools.length);

        for (uint256 i; i < pools.length;) {
            // Weight = 1 / (1 + fee)
            weights[i] = WAD / (WAD + pools[i].fee * WAD / BPS_DENOMINATOR);
            totalWeight += weights[i];
            unchecked { ++i; }
        }

        // Distribute proportionally
        uint256 distributed;
        for (uint256 i; i < pools.length;) {
            distributions[i] = (totalLiquidity * weights[i]) / totalWeight;
            distributed += distributions[i];
            unchecked { ++i; }
        }

        // Handle rounding
        if (distributed < totalLiquidity && pools.length > 0) {
            distributions[0] += totalLiquidity - distributed;
        }
    }

    /// @notice Calculate impermanent loss
    /// @param initialPrice Initial price ratio
    /// @param currentPrice Current price ratio
    /// @return ilBps Impermanent loss in basis points
    function calculateImpermanentLoss(
        uint256 initialPrice,
        uint256 currentPrice
    ) internal pure returns (uint256 ilBps) {
        if (initialPrice == 0) return 0;

        // IL = 2 * sqrt(priceRatio) / (1 + priceRatio) - 1

        uint256 priceRatio = (currentPrice * WAD) / initialPrice;
        uint256 sqrtRatio = sqrt(priceRatio * WAD);

        // 2 * sqrtRatio
        uint256 numerator = 2 * sqrtRatio;

        // 1 + priceRatio (in WAD)
        uint256 denominator = WAD + priceRatio;

        // Result
        uint256 result = (numerator * WAD) / denominator;

        if (result < WAD) {
            ilBps = ((WAD - result) * BPS_DENOMINATOR) / WAD;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Generate unique intent ID
    /// @param maker Intent maker
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @param nonce Maker's nonce
    /// @return intentId Generated intent ID
    function generateIntentId(
        address maker,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 nonce
    ) internal view returns (bytes32 intentId) {
        return keccak256(
            abi.encode(maker, tokenIn, tokenOut, amountIn, nonce, block.chainid)
        );
    }

    /// @notice Check if slippage is within tolerance
    /// @param expected Expected amount
    /// @param actual Actual amount
    /// @param toleranceBps Tolerance in basis points
    function checkSlippage(
        uint256 expected,
        uint256 actual,
        uint256 toleranceBps
    ) internal pure {
        if (expected == 0) return;

        uint256 minAcceptable = (expected * (BPS_DENOMINATOR - toleranceBps)) / BPS_DENOMINATOR;

        if (actual < minAcceptable) {
            revert SlippageExceeded(expected, actual, toleranceBps);
        }
    }

    /// @notice Calculate minimum output with slippage
    /// @param expectedOutput Expected output amount
    /// @param slippageBps Slippage tolerance in basis points
    /// @return minOutput Minimum acceptable output
    function calculateMinOutput(
        uint256 expectedOutput,
        uint256 slippageBps
    ) internal pure returns (uint256 minOutput) {
        return (expectedOutput * (BPS_DENOMINATOR - slippageBps)) / BPS_DENOMINATOR;
    }
}
