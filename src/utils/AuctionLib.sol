// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title AuctionLib
/// @notice Comprehensive auction library supporting multiple auction types
/// @dev Implements Dutch, English, sealed-bid, batch, and Vickrey auctions
/// @author playground-zkaedi
library AuctionLib {
    // ============ Custom Errors ============
    error AuctionNotInitialized();
    error AuctionNotStarted();
    error AuctionEnded();
    error AuctionNotEnded();
    error AuctionAlreadyStarted();
    error InvalidStartTime();
    error InvalidDuration();
    error InvalidPrice();
    error InvalidBid();
    error BidTooLow(uint256 required, uint256 provided);
    error BidTooHigh();
    error AlreadyBid();
    error NotBidder();
    error NotSeller();
    error NoBids();
    error InvalidReveal();
    error RevealPeriodNotStarted();
    error RevealPeriodEnded();
    error AlreadyRevealed();
    error NotRevealed();
    error AlreadySettled();
    error NotSettled();
    error InsufficientFunds();
    error WithdrawalFailed();

    // ============ Constants ============
    uint256 internal constant BPS = 10000;
    uint256 internal constant MIN_BID_INCREMENT_BPS = 100; // 1% minimum bid increment
    uint256 internal constant MAX_BATCH_SIZE = 100;

    // ============ Enums ============
    enum AuctionType {
        Dutch,         // Price decreases over time
        English,       // Price increases with bids
        SealedBid,     // Hidden bids revealed later
        Vickrey,       // Second-price sealed-bid
        Batch,         // Batch auction with clearing price
        Candle         // Random end time (like English but unpredictable)
    }

    enum AuctionState {
        Created,
        Active,
        RevealPhase,   // For sealed-bid auctions
        Ended,
        Settled,
        Cancelled
    }

    // ============ Structs ============

    /// @notice Base auction configuration
    struct AuctionConfig {
        AuctionType auctionType;
        address seller;
        address tokenAddress;       // Token being auctioned
        uint256 tokenId;            // For NFTs (0 for fungible)
        uint256 tokenAmount;        // Amount being auctioned
        uint256 startTime;
        uint256 endTime;
        uint256 startPrice;         // Starting price (Dutch/English)
        uint256 reservePrice;       // Minimum acceptable price
        uint256 minBidIncrement;    // Minimum bid increment (English)
        uint256 revealDuration;     // For sealed-bid auctions
    }

    /// @notice Dutch auction specific data
    struct DutchAuction {
        AuctionConfig config;
        uint256 endPrice;           // Final price at end time
        uint256 decayRate;          // Price decay per second
        address winner;
        uint256 winningPrice;
        AuctionState state;
        bool initialized;
    }

    /// @notice English auction specific data
    struct EnglishAuction {
        AuctionConfig config;
        address highestBidder;
        uint256 highestBid;
        uint256 extensionTime;      // Time added on late bids
        uint256 extensionThreshold; // Time before end to trigger extension
        mapping(address => uint256) pendingReturns;
        AuctionState state;
        bool initialized;
    }

    /// @notice Sealed bid entry
    struct SealedBid {
        bytes32 commitment;         // keccak256(bid, salt)
        uint256 deposit;            // Deposited amount
        uint256 revealedBid;        // Actual bid after reveal
        bool revealed;
        bool refunded;
    }

    /// @notice Sealed-bid auction data
    struct SealedBidAuction {
        AuctionConfig config;
        mapping(address => SealedBid) bids;
        address[] bidders;
        address winner;
        uint256 winningBid;
        uint256 secondHighestBid;   // For Vickrey
        AuctionState state;
        bool initialized;
    }

    /// @notice Batch auction bid
    struct BatchBid {
        address bidder;
        uint256 amount;             // Token amount wanted
        uint256 price;              // Max price per token
        uint256 filled;             // Amount actually filled
    }

    /// @notice Batch auction data
    struct BatchAuction {
        AuctionConfig config;
        BatchBid[] bids;
        mapping(address => uint256) bidIndices;
        uint256 totalDemand;
        uint256 clearingPrice;
        AuctionState state;
        bool initialized;
    }

    /// @notice Candle auction data (English with random end)
    struct CandleAuction {
        EnglishAuction base;
        uint256 candleStart;        // When candle period begins
        bytes32 randomSeed;         // Commit for random end
        uint256 actualEndTime;      // Revealed random end time
        bool endRevealed;
    }

    // ============ Dutch Auction Functions ============

    /// @notice Initialize a Dutch auction
    function initializeDutch(
        DutchAuction storage auction,
        address seller,
        address tokenAddress,
        uint256 tokenId,
        uint256 tokenAmount,
        uint256 startTime,
        uint256 duration,
        uint256 startPrice,
        uint256 endPrice
    ) internal {
        if (startTime < block.timestamp) revert InvalidStartTime();
        if (duration == 0) revert InvalidDuration();
        if (startPrice <= endPrice) revert InvalidPrice();

        auction.config = AuctionConfig({
            auctionType: AuctionType.Dutch,
            seller: seller,
            tokenAddress: tokenAddress,
            tokenId: tokenId,
            tokenAmount: tokenAmount,
            startTime: startTime,
            endTime: startTime + duration,
            startPrice: startPrice,
            reservePrice: endPrice,
            minBidIncrement: 0,
            revealDuration: 0
        });

        auction.endPrice = endPrice;
        auction.decayRate = (startPrice - endPrice) / duration;
        auction.state = AuctionState.Created;
        auction.initialized = true;
    }

    /// @notice Get current Dutch auction price
    function getDutchPrice(DutchAuction storage auction) internal view returns (uint256) {
        _checkDutchActive(auction);

        if (block.timestamp <= auction.config.startTime) {
            return auction.config.startPrice;
        }

        if (block.timestamp >= auction.config.endTime) {
            return auction.endPrice;
        }

        uint256 elapsed = block.timestamp - auction.config.startTime;
        uint256 priceDecay = auction.decayRate * elapsed;

        return auction.config.startPrice - priceDecay;
    }

    /// @notice Execute purchase in Dutch auction
    function buyDutch(
        DutchAuction storage auction,
        address buyer,
        uint256 payment
    ) internal returns (uint256 price) {
        _checkDutchActive(auction);

        price = getDutchPrice(auction);

        if (payment < price) revert BidTooLow(price, payment);

        auction.winner = buyer;
        auction.winningPrice = price;
        auction.state = AuctionState.Settled;

        return price;
    }

    function _checkDutchActive(DutchAuction storage auction) private view {
        if (!auction.initialized) revert AuctionNotInitialized();
        if (auction.state == AuctionState.Settled) revert AlreadySettled();
        if (block.timestamp < auction.config.startTime) revert AuctionNotStarted();
        if (block.timestamp > auction.config.endTime) revert AuctionEnded();
    }

    // ============ English Auction Functions ============

    /// @notice Initialize an English auction
    function initializeEnglish(
        EnglishAuction storage auction,
        address seller,
        address tokenAddress,
        uint256 tokenId,
        uint256 tokenAmount,
        uint256 startTime,
        uint256 duration,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 minBidIncrement,
        uint256 extensionTime,
        uint256 extensionThreshold
    ) internal {
        if (startTime < block.timestamp) revert InvalidStartTime();
        if (duration == 0) revert InvalidDuration();

        auction.config = AuctionConfig({
            auctionType: AuctionType.English,
            seller: seller,
            tokenAddress: tokenAddress,
            tokenId: tokenId,
            tokenAmount: tokenAmount,
            startTime: startTime,
            endTime: startTime + duration,
            startPrice: startPrice,
            reservePrice: reservePrice,
            minBidIncrement: minBidIncrement,
            revealDuration: 0
        });

        auction.extensionTime = extensionTime;
        auction.extensionThreshold = extensionThreshold;
        auction.state = AuctionState.Created;
        auction.initialized = true;
    }

    /// @notice Place bid in English auction
    function bidEnglish(
        EnglishAuction storage auction,
        address bidder,
        uint256 bidAmount
    ) internal returns (bool isHighest) {
        _checkEnglishActive(auction);

        uint256 minBid = auction.highestBid == 0
            ? auction.config.startPrice
            : auction.highestBid + auction.config.minBidIncrement;

        if (bidAmount < minBid) revert BidTooLow(minBid, bidAmount);

        // Refund previous highest bidder
        if (auction.highestBidder != address(0)) {
            auction.pendingReturns[auction.highestBidder] += auction.highestBid;
        }

        auction.highestBidder = bidder;
        auction.highestBid = bidAmount;

        // Extend auction if bid is near end
        if (auction.config.endTime - block.timestamp < auction.extensionThreshold) {
            auction.config.endTime = block.timestamp + auction.extensionTime;
        }

        return true;
    }

    /// @notice Withdraw pending returns from English auction
    function withdrawEnglish(
        EnglishAuction storage auction,
        address bidder
    ) internal returns (uint256 amount) {
        amount = auction.pendingReturns[bidder];
        if (amount == 0) revert InsufficientFunds();

        auction.pendingReturns[bidder] = 0;
        return amount;
    }

    /// @notice End English auction
    function endEnglish(
        EnglishAuction storage auction
    ) internal returns (address winner, uint256 winningBid) {
        if (!auction.initialized) revert AuctionNotInitialized();
        if (block.timestamp < auction.config.endTime) revert AuctionNotEnded();
        if (auction.state == AuctionState.Settled) revert AlreadySettled();

        auction.state = AuctionState.Ended;

        if (auction.highestBid >= auction.config.reservePrice) {
            auction.state = AuctionState.Settled;
            return (auction.highestBidder, auction.highestBid);
        }

        // Reserve not met - return bid
        if (auction.highestBidder != address(0)) {
            auction.pendingReturns[auction.highestBidder] += auction.highestBid;
        }

        return (address(0), 0);
    }

    function _checkEnglishActive(EnglishAuction storage auction) private view {
        if (!auction.initialized) revert AuctionNotInitialized();
        if (auction.state == AuctionState.Settled) revert AlreadySettled();
        if (block.timestamp < auction.config.startTime) revert AuctionNotStarted();
        if (block.timestamp > auction.config.endTime) revert AuctionEnded();
    }

    /// @notice Get English auction info
    function getEnglishInfo(
        EnglishAuction storage auction
    ) internal view returns (
        address highestBidder,
        uint256 highestBid,
        uint256 timeRemaining,
        uint256 minNextBid
    ) {
        highestBidder = auction.highestBidder;
        highestBid = auction.highestBid;
        timeRemaining = block.timestamp >= auction.config.endTime
            ? 0
            : auction.config.endTime - block.timestamp;
        minNextBid = highestBid == 0
            ? auction.config.startPrice
            : highestBid + auction.config.minBidIncrement;
    }

    // ============ Sealed-Bid Auction Functions ============

    /// @notice Initialize sealed-bid auction
    function initializeSealedBid(
        SealedBidAuction storage auction,
        address seller,
        address tokenAddress,
        uint256 tokenId,
        uint256 tokenAmount,
        uint256 startTime,
        uint256 biddingDuration,
        uint256 revealDuration,
        uint256 reservePrice,
        bool isVickrey
    ) internal {
        if (startTime < block.timestamp) revert InvalidStartTime();
        if (biddingDuration == 0 || revealDuration == 0) revert InvalidDuration();

        auction.config = AuctionConfig({
            auctionType: isVickrey ? AuctionType.Vickrey : AuctionType.SealedBid,
            seller: seller,
            tokenAddress: tokenAddress,
            tokenId: tokenId,
            tokenAmount: tokenAmount,
            startTime: startTime,
            endTime: startTime + biddingDuration,
            startPrice: 0,
            reservePrice: reservePrice,
            minBidIncrement: 0,
            revealDuration: revealDuration
        });

        auction.state = AuctionState.Created;
        auction.initialized = true;
    }

    /// @notice Submit sealed bid commitment
    function commitBid(
        SealedBidAuction storage auction,
        address bidder,
        bytes32 commitment,
        uint256 deposit
    ) internal {
        if (!auction.initialized) revert AuctionNotInitialized();
        if (block.timestamp < auction.config.startTime) revert AuctionNotStarted();
        if (block.timestamp > auction.config.endTime) revert AuctionEnded();
        if (auction.bids[bidder].commitment != bytes32(0)) revert AlreadyBid();
        if (deposit < auction.config.reservePrice) revert BidTooLow(auction.config.reservePrice, deposit);

        auction.bids[bidder] = SealedBid({
            commitment: commitment,
            deposit: deposit,
            revealedBid: 0,
            revealed: false,
            refunded: false
        });

        auction.bidders.push(bidder);
        auction.state = AuctionState.Active;
    }

    /// @notice Create bid commitment hash
    function createCommitment(
        uint256 bidAmount,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bidAmount, salt));
    }

    /// @notice Reveal sealed bid
    function revealBid(
        SealedBidAuction storage auction,
        address bidder,
        uint256 bidAmount,
        bytes32 salt
    ) internal returns (bool valid) {
        if (!auction.initialized) revert AuctionNotInitialized();

        uint256 revealStart = auction.config.endTime;
        uint256 revealEnd = revealStart + auction.config.revealDuration;

        if (block.timestamp < revealStart) revert RevealPeriodNotStarted();
        if (block.timestamp > revealEnd) revert RevealPeriodEnded();

        SealedBid storage bid = auction.bids[bidder];
        if (bid.commitment == bytes32(0)) revert NotBidder();
        if (bid.revealed) revert AlreadyRevealed();

        bytes32 computed = createCommitment(bidAmount, salt);
        if (computed != bid.commitment) revert InvalidReveal();
        if (bidAmount > bid.deposit) revert BidTooHigh();

        bid.revealedBid = bidAmount;
        bid.revealed = true;

        // Update highest/second highest for Vickrey
        if (bidAmount > auction.winningBid) {
            auction.secondHighestBid = auction.winningBid;
            auction.winningBid = bidAmount;
            auction.winner = bidder;
        } else if (bidAmount > auction.secondHighestBid) {
            auction.secondHighestBid = bidAmount;
        }

        auction.state = AuctionState.RevealPhase;
        return true;
    }

    /// @notice Finalize sealed-bid auction
    function finalizeSealedBid(
        SealedBidAuction storage auction
    ) internal returns (address winner, uint256 price) {
        if (!auction.initialized) revert AuctionNotInitialized();

        uint256 revealEnd = auction.config.endTime + auction.config.revealDuration;
        if (block.timestamp < revealEnd) revert AuctionNotEnded();
        if (auction.state == AuctionState.Settled) revert AlreadySettled();

        auction.state = AuctionState.Ended;

        if (auction.winner == address(0) || auction.winningBid < auction.config.reservePrice) {
            return (address(0), 0);
        }

        // Vickrey: winner pays second-highest price
        if (auction.config.auctionType == AuctionType.Vickrey) {
            price = auction.secondHighestBid > auction.config.reservePrice
                ? auction.secondHighestBid
                : auction.config.reservePrice;
        } else {
            price = auction.winningBid;
        }

        auction.state = AuctionState.Settled;
        return (auction.winner, price);
    }

    /// @notice Withdraw refund from sealed-bid auction
    function withdrawSealedBid(
        SealedBidAuction storage auction,
        address bidder
    ) internal returns (uint256 refund) {
        SealedBid storage bid = auction.bids[bidder];
        if (bid.refunded) return 0;

        if (auction.state != AuctionState.Settled && auction.state != AuctionState.Ended) {
            revert NotSettled();
        }

        if (bidder == auction.winner) {
            // Winner gets deposit minus winning price
            uint256 price = auction.config.auctionType == AuctionType.Vickrey
                ? (auction.secondHighestBid > auction.config.reservePrice
                    ? auction.secondHighestBid
                    : auction.config.reservePrice)
                : auction.winningBid;
            refund = bid.deposit - price;
        } else {
            // Non-winners get full deposit back
            refund = bid.deposit;
        }

        bid.refunded = true;
        return refund;
    }

    // ============ Batch Auction Functions ============

    /// @notice Initialize batch auction
    function initializeBatch(
        BatchAuction storage auction,
        address seller,
        address tokenAddress,
        uint256 tokenAmount,
        uint256 startTime,
        uint256 duration,
        uint256 reservePrice
    ) internal {
        if (startTime < block.timestamp) revert InvalidStartTime();
        if (duration == 0) revert InvalidDuration();
        if (tokenAmount == 0) revert InvalidPrice();

        auction.config = AuctionConfig({
            auctionType: AuctionType.Batch,
            seller: seller,
            tokenAddress: tokenAddress,
            tokenId: 0,
            tokenAmount: tokenAmount,
            startTime: startTime,
            endTime: startTime + duration,
            startPrice: 0,
            reservePrice: reservePrice,
            minBidIncrement: 0,
            revealDuration: 0
        });

        auction.state = AuctionState.Created;
        auction.initialized = true;
    }

    /// @notice Place bid in batch auction
    function bidBatch(
        BatchAuction storage auction,
        address bidder,
        uint256 amount,
        uint256 maxPrice
    ) internal returns (uint256 bidIndex) {
        if (!auction.initialized) revert AuctionNotInitialized();
        if (block.timestamp < auction.config.startTime) revert AuctionNotStarted();
        if (block.timestamp > auction.config.endTime) revert AuctionEnded();
        if (amount == 0 || maxPrice == 0) revert InvalidBid();
        if (maxPrice < auction.config.reservePrice) revert BidTooLow(auction.config.reservePrice, maxPrice);

        auction.bids.push(BatchBid({
            bidder: bidder,
            amount: amount,
            price: maxPrice,
            filled: 0
        }));

        bidIndex = auction.bids.length - 1;
        auction.bidIndices[bidder] = bidIndex;
        auction.totalDemand += amount;
        auction.state = AuctionState.Active;

        return bidIndex;
    }

    /// @notice Calculate clearing price for batch auction
    function calculateClearingPrice(
        BatchAuction storage auction
    ) internal view returns (uint256 clearingPrice, uint256 totalFilled) {
        if (auction.bids.length == 0) return (0, 0);

        // Sort bids by price (descending) - simplified bubble sort for on-chain
        uint256[] memory prices = new uint256[](auction.bids.length);
        uint256[] memory amounts = new uint256[](auction.bids.length);

        for (uint256 i = 0; i < auction.bids.length; i++) {
            prices[i] = auction.bids[i].price;
            amounts[i] = auction.bids[i].amount;
        }

        // Sort descending by price
        for (uint256 i = 0; i < prices.length - 1; i++) {
            for (uint256 j = 0; j < prices.length - i - 1; j++) {
                if (prices[j] < prices[j + 1]) {
                    (prices[j], prices[j + 1]) = (prices[j + 1], prices[j]);
                    (amounts[j], amounts[j + 1]) = (amounts[j + 1], amounts[j]);
                }
            }
        }

        // Find clearing price where demand meets supply
        uint256 supply = auction.config.tokenAmount;
        uint256 cumulative = 0;

        for (uint256 i = 0; i < prices.length; i++) {
            cumulative += amounts[i];
            if (cumulative >= supply) {
                clearingPrice = prices[i];
                totalFilled = supply;
                break;
            }
        }

        // If not enough demand, clearing price is reserve
        if (clearingPrice == 0 && cumulative > 0) {
            clearingPrice = auction.config.reservePrice;
            totalFilled = cumulative;
        }

        return (clearingPrice, totalFilled);
    }

    /// @notice Settle batch auction
    function settleBatch(
        BatchAuction storage auction
    ) internal returns (uint256 clearingPrice, uint256 totalFilled) {
        if (!auction.initialized) revert AuctionNotInitialized();
        if (block.timestamp < auction.config.endTime) revert AuctionNotEnded();
        if (auction.state == AuctionState.Settled) revert AlreadySettled();

        (clearingPrice, totalFilled) = calculateClearingPrice(auction);
        auction.clearingPrice = clearingPrice;

        if (clearingPrice == 0) {
            auction.state = AuctionState.Ended;
            return (0, 0);
        }

        // Calculate fills for each bidder
        uint256 remaining = auction.config.tokenAmount;

        for (uint256 i = 0; i < auction.bids.length && remaining > 0; i++) {
            BatchBid storage bid = auction.bids[i];

            if (bid.price >= clearingPrice) {
                uint256 fill = bid.amount > remaining ? remaining : bid.amount;
                bid.filled = fill;
                remaining -= fill;
            }
        }

        auction.state = AuctionState.Settled;
        return (clearingPrice, totalFilled);
    }

    /// @notice Get batch auction bid info
    function getBatchBidInfo(
        BatchAuction storage auction,
        address bidder
    ) internal view returns (uint256 amount, uint256 price, uint256 filled) {
        uint256 index = auction.bidIndices[bidder];
        if (index >= auction.bids.length) return (0, 0, 0);

        BatchBid storage bid = auction.bids[index];
        if (bid.bidder != bidder) return (0, 0, 0);

        return (bid.amount, bid.price, bid.filled);
    }

    // ============ Utility Functions ============

    /// @notice Check if auction is active
    function isActive(AuctionConfig storage config, AuctionState state) internal view returns (bool) {
        return state == AuctionState.Active &&
               block.timestamp >= config.startTime &&
               block.timestamp <= config.endTime;
    }

    /// @notice Get time remaining in auction
    function getTimeRemaining(AuctionConfig storage config) internal view returns (uint256) {
        if (block.timestamp >= config.endTime) return 0;
        return config.endTime - block.timestamp;
    }

    /// @notice Calculate minimum bid increment
    function calculateMinIncrement(uint256 currentBid, uint256 incrementBps) internal pure returns (uint256) {
        uint256 increment = (currentBid * incrementBps) / BPS;
        return increment > 0 ? increment : 1;
    }

    /// @notice Validate bid amount
    function validateBid(
        uint256 bidAmount,
        uint256 currentHighest,
        uint256 minIncrement,
        uint256 reservePrice
    ) internal pure returns (bool valid, string memory reason) {
        if (bidAmount < reservePrice) {
            return (false, "Below reserve");
        }
        if (currentHighest > 0 && bidAmount < currentHighest + minIncrement) {
            return (false, "Increment too low");
        }
        return (true, "");
    }

    // ============ Price Discovery Helpers ============

    /// @notice Calculate Dutch auction price at specific timestamp
    function getDutchPriceAt(
        uint256 startPrice,
        uint256 endPrice,
        uint256 startTime,
        uint256 endTime,
        uint256 timestamp
    ) internal pure returns (uint256) {
        if (timestamp <= startTime) return startPrice;
        if (timestamp >= endTime) return endPrice;

        uint256 elapsed = timestamp - startTime;
        uint256 duration = endTime - startTime;
        uint256 priceRange = startPrice - endPrice;

        return startPrice - (priceRange * elapsed / duration);
    }

    /// @notice Estimate final price based on current trajectory
    function estimateFinalPrice(
        EnglishAuction storage auction,
        uint256 avgBidFrequency,
        uint256 avgBidIncrement
    ) internal view returns (uint256) {
        uint256 remaining = getTimeRemaining(auction.config);
        uint256 expectedBids = remaining / avgBidFrequency;
        return auction.highestBid + (expectedBids * avgBidIncrement);
    }
}
