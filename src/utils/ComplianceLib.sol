// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ComplianceLib
/// @notice Compliance library for KYC/AML, sanctions screening, and regulatory requirements
/// @dev Implements tiered access, geographic restrictions, and attestation verification
/// @author playground-zkaedi
library ComplianceLib {
    // ============ Custom Errors ============
    error NotVerified();
    error VerificationExpired();
    error InsufficientTier();
    error RestrictedJurisdiction();
    error SanctionedAddress();
    error TransferLimitExceeded();
    error CooldownActive();
    error AttestationExpired();
    error InvalidAttestation();
    error InvalidProvider();
    error ProviderNotAuthorized();
    error AlreadyVerified();
    error AddressBlacklisted();
    error AddressNotWhitelisted();
    error InvalidTier();
    error InvalidExpiry();
    error DocumentHashMismatch();
    error AccreditationRequired();

    // ============ Constants ============
    uint256 internal constant MAX_TIER = 5;
    uint256 internal constant BPS = 10000;

    // Standard verification validity periods
    uint256 internal constant TIER1_VALIDITY = 365 days;   // Basic KYC
    uint256 internal constant TIER2_VALIDITY = 180 days;   // Enhanced KYC
    uint256 internal constant TIER3_VALIDITY = 90 days;    // Institutional
    uint256 internal constant TIER4_VALIDITY = 30 days;    // High-risk
    uint256 internal constant TIER5_VALIDITY = 7 days;     // Ultra-high-risk

    // Region codes (ISO 3166-1 numeric)
    uint16 internal constant REGION_US = 840;
    uint16 internal constant REGION_EU = 1;       // European Union (custom code)
    uint16 internal constant REGION_UK = 826;
    uint16 internal constant REGION_CN = 156;
    uint16 internal constant REGION_JP = 392;
    uint16 internal constant REGION_SG = 702;
    uint16 internal constant REGION_CH = 756;     // Switzerland
    uint16 internal constant REGION_GLOBAL = 0;   // No restriction

    // ============ Enums ============
    enum VerificationStatus {
        None,
        Pending,
        Verified,
        Expired,
        Revoked,
        Suspended
    }

    enum TierLevel {
        Unverified,      // Tier 0: No verification
        Basic,           // Tier 1: Basic KYC (email, phone)
        Standard,        // Tier 2: Standard KYC (ID verification)
        Enhanced,        // Tier 3: Enhanced KYC (source of funds)
        Institutional,   // Tier 4: Institutional (company verification)
        Accredited       // Tier 5: Accredited investor
    }

    enum RestrictionType {
        None,
        Blacklist,       // Explicitly blocked
        Whitelist,       // Must be explicitly allowed
        Geographic,      // Location-based
        Tiered,          // Tier-based limits
        Custom           // Custom rules
    }

    enum DocumentType {
        None,
        Passport,
        NationalID,
        DriversLicense,
        ProofOfAddress,
        BankStatement,
        TaxDocument,
        CompanyRegistration,
        AccreditationCertificate
    }

    // ============ Structs ============

    /// @notice User verification record
    struct VerificationRecord {
        address user;
        TierLevel tier;
        VerificationStatus status;
        uint256 verifiedAt;
        uint256 expiresAt;
        uint16 jurisdiction;          // ISO country code
        bytes32 attestationHash;      // Hash of attestation data
        address verifiedBy;           // Verification provider
        uint256 lastUpdated;
    }

    /// @notice Verification provider configuration
    struct Provider {
        address providerAddress;
        string name;
        TierLevel maxTier;            // Maximum tier this provider can issue
        uint16[] allowedJurisdictions;
        bool active;
        uint256 verificationsIssued;
        uint256 registeredAt;
    }

    /// @notice Transfer limits per tier
    struct TierLimits {
        uint256 dailyLimit;           // Max daily transfer amount
        uint256 transactionLimit;     // Max single transaction
        uint256 monthlyLimit;         // Max monthly transfer
        uint256 cooldownPeriod;       // Time between large transfers
    }

    /// @notice Geographic restriction configuration
    struct GeoRestriction {
        uint16[] blockedRegions;      // Blocked country codes
        uint16[] allowedRegions;      // Allowed country codes (if whitelist mode)
        bool isWhitelistMode;         // true = only allowed, false = all except blocked
    }

    /// @notice User transfer tracking
    struct TransferTracker {
        uint256 dailyTotal;
        uint256 monthlyTotal;
        uint256 lastTransferTime;
        uint256 lastDayReset;
        uint256 lastMonthReset;
        uint256 largeTransferCooldownEnd;
    }

    /// @notice Attestation for off-chain verification
    struct Attestation {
        bytes32 dataHash;             // Hash of KYC data
        address attester;             // Who signed the attestation
        uint256 issuedAt;
        uint256 expiresAt;
        TierLevel tier;
        bytes signature;              // ECDSA signature
    }

    /// @notice Main compliance registry
    struct ComplianceRegistry {
        mapping(address => VerificationRecord) verifications;
        mapping(address => Provider) providers;
        mapping(TierLevel => TierLimits) tierLimits;
        mapping(address => TransferTracker) transferTracking;
        GeoRestriction geoRestrictions;
        address[] blacklist;
        mapping(address => bool) isBlacklisted;
        address[] whitelist;
        mapping(address => bool) isWhitelisted;
        bool useWhitelist;            // Global whitelist mode
        bool initialized;
    }

    // ============ Initialization ============

    /// @notice Initialize compliance registry
    function initialize(ComplianceRegistry storage registry) internal {
        registry.initialized = true;

        // Set default tier limits
        registry.tierLimits[TierLevel.Unverified] = TierLimits({
            dailyLimit: 0,
            transactionLimit: 0,
            monthlyLimit: 0,
            cooldownPeriod: 0
        });

        registry.tierLimits[TierLevel.Basic] = TierLimits({
            dailyLimit: 1000 ether,
            transactionLimit: 500 ether,
            monthlyLimit: 5000 ether,
            cooldownPeriod: 0
        });

        registry.tierLimits[TierLevel.Standard] = TierLimits({
            dailyLimit: 10000 ether,
            transactionLimit: 5000 ether,
            monthlyLimit: 50000 ether,
            cooldownPeriod: 0
        });

        registry.tierLimits[TierLevel.Enhanced] = TierLimits({
            dailyLimit: 100000 ether,
            transactionLimit: 50000 ether,
            monthlyLimit: 500000 ether,
            cooldownPeriod: 1 hours
        });

        registry.tierLimits[TierLevel.Institutional] = TierLimits({
            dailyLimit: type(uint256).max,
            transactionLimit: type(uint256).max,
            monthlyLimit: type(uint256).max,
            cooldownPeriod: 0
        });

        registry.tierLimits[TierLevel.Accredited] = TierLimits({
            dailyLimit: type(uint256).max,
            transactionLimit: type(uint256).max,
            monthlyLimit: type(uint256).max,
            cooldownPeriod: 0
        });
    }

    // ============ Verification Functions ============

    /// @notice Register a verification provider
    function registerProvider(
        ComplianceRegistry storage registry,
        address providerAddress,
        string memory name,
        TierLevel maxTier,
        uint16[] memory jurisdictions
    ) internal {
        if (providerAddress == address(0)) revert InvalidProvider();

        registry.providers[providerAddress] = Provider({
            providerAddress: providerAddress,
            name: name,
            maxTier: maxTier,
            allowedJurisdictions: jurisdictions,
            active: true,
            verificationsIssued: 0,
            registeredAt: block.timestamp
        });
    }

    /// @notice Verify a user
    function verifyUser(
        ComplianceRegistry storage registry,
        address user,
        TierLevel tier,
        uint16 jurisdiction,
        bytes32 attestationHash,
        address provider
    ) internal {
        if (user == address(0)) revert NotVerified();
        if (uint8(tier) > MAX_TIER) revert InvalidTier();

        Provider storage p = registry.providers[provider];
        if (!p.active) revert ProviderNotAuthorized();
        if (uint8(tier) > uint8(p.maxTier)) revert InsufficientTier();

        // Check jurisdiction authorization
        bool jurisdictionAllowed = false;
        for (uint256 i = 0; i < p.allowedJurisdictions.length; i++) {
            if (p.allowedJurisdictions[i] == jurisdiction ||
                p.allowedJurisdictions[i] == REGION_GLOBAL) {
                jurisdictionAllowed = true;
                break;
            }
        }
        if (!jurisdictionAllowed) revert RestrictedJurisdiction();

        uint256 validity = _getValidityPeriod(tier);

        registry.verifications[user] = VerificationRecord({
            user: user,
            tier: tier,
            status: VerificationStatus.Verified,
            verifiedAt: block.timestamp,
            expiresAt: block.timestamp + validity,
            jurisdiction: jurisdiction,
            attestationHash: attestationHash,
            verifiedBy: provider,
            lastUpdated: block.timestamp
        });

        p.verificationsIssued++;
    }

    /// @notice Upgrade user tier
    function upgradeTier(
        ComplianceRegistry storage registry,
        address user,
        TierLevel newTier,
        bytes32 newAttestationHash,
        address provider
    ) internal {
        VerificationRecord storage record = registry.verifications[user];
        if (record.status != VerificationStatus.Verified) revert NotVerified();
        if (uint8(newTier) <= uint8(record.tier)) revert InvalidTier();

        Provider storage p = registry.providers[provider];
        if (!p.active) revert ProviderNotAuthorized();
        if (uint8(newTier) > uint8(p.maxTier)) revert InsufficientTier();

        uint256 validity = _getValidityPeriod(newTier);

        record.tier = newTier;
        record.attestationHash = newAttestationHash;
        record.verifiedBy = provider;
        record.expiresAt = block.timestamp + validity;
        record.lastUpdated = block.timestamp;

        p.verificationsIssued++;
    }

    /// @notice Revoke user verification
    function revokeVerification(
        ComplianceRegistry storage registry,
        address user,
        address revoker
    ) internal {
        VerificationRecord storage record = registry.verifications[user];
        if (record.status == VerificationStatus.None) revert NotVerified();

        record.status = VerificationStatus.Revoked;
        record.lastUpdated = block.timestamp;
    }

    /// @notice Renew user verification
    function renewVerification(
        ComplianceRegistry storage registry,
        address user,
        bytes32 newAttestationHash,
        address provider
    ) internal {
        VerificationRecord storage record = registry.verifications[user];
        if (record.status == VerificationStatus.Revoked) revert NotVerified();

        Provider storage p = registry.providers[provider];
        if (!p.active) revert ProviderNotAuthorized();

        uint256 validity = _getValidityPeriod(record.tier);

        record.status = VerificationStatus.Verified;
        record.attestationHash = newAttestationHash;
        record.verifiedBy = provider;
        record.expiresAt = block.timestamp + validity;
        record.lastUpdated = block.timestamp;

        p.verificationsIssued++;
    }

    // ============ Verification Checks ============

    /// @notice Check if user is verified
    function isVerified(
        ComplianceRegistry storage registry,
        address user
    ) internal view returns (bool) {
        VerificationRecord storage record = registry.verifications[user];
        return record.status == VerificationStatus.Verified &&
               block.timestamp < record.expiresAt;
    }

    /// @notice Check if user meets minimum tier
    function meetsMinimumTier(
        ComplianceRegistry storage registry,
        address user,
        TierLevel minTier
    ) internal view returns (bool) {
        if (!isVerified(registry, user)) return false;
        return uint8(registry.verifications[user].tier) >= uint8(minTier);
    }

    /// @notice Get user verification status
    function getVerificationStatus(
        ComplianceRegistry storage registry,
        address user
    ) internal view returns (
        VerificationStatus status,
        TierLevel tier,
        uint256 expiresAt,
        bool isValid
    ) {
        VerificationRecord storage record = registry.verifications[user];
        status = record.status;
        tier = record.tier;
        expiresAt = record.expiresAt;
        isValid = isVerified(registry, user);
    }

    /// @notice Require minimum tier (reverts if not met)
    function requireMinimumTier(
        ComplianceRegistry storage registry,
        address user,
        TierLevel minTier
    ) internal view {
        if (!isVerified(registry, user)) revert NotVerified();
        if (uint8(registry.verifications[user].tier) < uint8(minTier)) {
            revert InsufficientTier();
        }
    }

    // ============ Transfer Limit Functions ============

    /// @notice Check and update transfer limits
    function checkAndUpdateTransferLimits(
        ComplianceRegistry storage registry,
        address user,
        uint256 amount
    ) internal returns (bool allowed) {
        VerificationRecord storage record = registry.verifications[user];
        TierLimits storage limits = registry.tierLimits[record.tier];
        TransferTracker storage tracker = registry.transferTracking[user];

        // Reset daily/monthly counters if needed
        _resetCountersIfNeeded(tracker);

        // Check transaction limit
        if (amount > limits.transactionLimit) {
            revert TransferLimitExceeded();
        }

        // Check daily limit
        if (tracker.dailyTotal + amount > limits.dailyLimit) {
            revert TransferLimitExceeded();
        }

        // Check monthly limit
        if (tracker.monthlyTotal + amount > limits.monthlyLimit) {
            revert TransferLimitExceeded();
        }

        // Check cooldown for large transfers
        if (limits.cooldownPeriod > 0 &&
            amount > limits.transactionLimit / 2 &&
            block.timestamp < tracker.largeTransferCooldownEnd) {
            revert CooldownActive();
        }

        // Update tracking
        tracker.dailyTotal += amount;
        tracker.monthlyTotal += amount;
        tracker.lastTransferTime = block.timestamp;

        // Set cooldown for large transfers
        if (limits.cooldownPeriod > 0 && amount > limits.transactionLimit / 2) {
            tracker.largeTransferCooldownEnd = block.timestamp + limits.cooldownPeriod;
        }

        return true;
    }

    /// @notice Get remaining transfer limits
    function getRemainingLimits(
        ComplianceRegistry storage registry,
        address user
    ) internal view returns (
        uint256 dailyRemaining,
        uint256 monthlyRemaining,
        uint256 transactionMax
    ) {
        VerificationRecord storage record = registry.verifications[user];
        TierLimits storage limits = registry.tierLimits[record.tier];
        TransferTracker storage tracker = registry.transferTracking[user];

        // Check if counters should be reset
        uint256 currentDaily = tracker.dailyTotal;
        uint256 currentMonthly = tracker.monthlyTotal;

        if (block.timestamp >= tracker.lastDayReset + 1 days) {
            currentDaily = 0;
        }
        if (block.timestamp >= tracker.lastMonthReset + 30 days) {
            currentMonthly = 0;
        }

        dailyRemaining = limits.dailyLimit > currentDaily ?
            limits.dailyLimit - currentDaily : 0;
        monthlyRemaining = limits.monthlyLimit > currentMonthly ?
            limits.monthlyLimit - currentMonthly : 0;
        transactionMax = limits.transactionLimit;
    }

    /// @notice Update tier limits
    function setTierLimits(
        ComplianceRegistry storage registry,
        TierLevel tier,
        uint256 dailyLimit,
        uint256 transactionLimit,
        uint256 monthlyLimit,
        uint256 cooldownPeriod
    ) internal {
        registry.tierLimits[tier] = TierLimits({
            dailyLimit: dailyLimit,
            transactionLimit: transactionLimit,
            monthlyLimit: monthlyLimit,
            cooldownPeriod: cooldownPeriod
        });
    }

    // ============ Blacklist/Whitelist Functions ============

    /// @notice Add address to blacklist
    function addToBlacklist(
        ComplianceRegistry storage registry,
        address account
    ) internal {
        if (!registry.isBlacklisted[account]) {
            registry.isBlacklisted[account] = true;
            registry.blacklist.push(account);

            // Revoke any existing verification
            if (registry.verifications[account].status == VerificationStatus.Verified) {
                registry.verifications[account].status = VerificationStatus.Revoked;
            }
        }
    }

    /// @notice Remove address from blacklist
    function removeFromBlacklist(
        ComplianceRegistry storage registry,
        address account
    ) internal {
        registry.isBlacklisted[account] = false;
        // Note: Does not remove from array for gas efficiency
    }

    /// @notice Add address to whitelist
    function addToWhitelist(
        ComplianceRegistry storage registry,
        address account
    ) internal {
        if (!registry.isWhitelisted[account]) {
            registry.isWhitelisted[account] = true;
            registry.whitelist.push(account);
        }
    }

    /// @notice Remove address from whitelist
    function removeFromWhitelist(
        ComplianceRegistry storage registry,
        address account
    ) internal {
        registry.isWhitelisted[account] = false;
    }

    /// @notice Check if address is allowed (considering blacklist/whitelist)
    function isAllowed(
        ComplianceRegistry storage registry,
        address account
    ) internal view returns (bool) {
        if (registry.isBlacklisted[account]) return false;
        if (registry.useWhitelist) {
            return registry.isWhitelisted[account];
        }
        return true;
    }

    /// @notice Require address is allowed (reverts if not)
    function requireAllowed(
        ComplianceRegistry storage registry,
        address account
    ) internal view {
        if (registry.isBlacklisted[account]) revert SanctionedAddress();
        if (registry.useWhitelist && !registry.isWhitelisted[account]) {
            revert AddressNotWhitelisted();
        }
    }

    // ============ Geographic Restriction Functions ============

    /// @notice Set geographic restrictions
    function setGeoRestrictions(
        ComplianceRegistry storage registry,
        uint16[] memory blockedRegions,
        uint16[] memory allowedRegions,
        bool isWhitelistMode
    ) internal {
        registry.geoRestrictions = GeoRestriction({
            blockedRegions: blockedRegions,
            allowedRegions: allowedRegions,
            isWhitelistMode: isWhitelistMode
        });
    }

    /// @notice Check if jurisdiction is allowed
    function isJurisdictionAllowed(
        ComplianceRegistry storage registry,
        uint16 jurisdiction
    ) internal view returns (bool) {
        GeoRestriction storage geo = registry.geoRestrictions;

        if (geo.isWhitelistMode) {
            // Only allowed regions can participate
            for (uint256 i = 0; i < geo.allowedRegions.length; i++) {
                if (geo.allowedRegions[i] == jurisdiction) return true;
            }
            return false;
        } else {
            // All regions except blocked can participate
            for (uint256 i = 0; i < geo.blockedRegions.length; i++) {
                if (geo.blockedRegions[i] == jurisdiction) return false;
            }
            return true;
        }
    }

    /// @notice Require jurisdiction is allowed (reverts if not)
    function requireJurisdictionAllowed(
        ComplianceRegistry storage registry,
        address user
    ) internal view {
        VerificationRecord storage record = registry.verifications[user];
        if (!isJurisdictionAllowed(registry, record.jurisdiction)) {
            revert RestrictedJurisdiction();
        }
    }

    // ============ Attestation Functions ============

    /// @notice Verify an off-chain attestation
    function verifyAttestation(
        Attestation memory attestation,
        address expectedAttester
    ) internal view returns (bool) {
        if (attestation.attester != expectedAttester) return false;
        if (block.timestamp > attestation.expiresAt) return false;

        // Recreate the message hash
        bytes32 messageHash = keccak256(abi.encodePacked(
            attestation.dataHash,
            attestation.attester,
            attestation.issuedAt,
            attestation.expiresAt,
            uint8(attestation.tier)
        ));

        // Create EIP-191 signed message hash
        bytes32 ethSignedHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            messageHash
        ));

        // Recover signer
        address recovered = _recoverSigner(ethSignedHash, attestation.signature);
        return recovered == expectedAttester;
    }

    /// @notice Create attestation hash
    function createAttestationHash(
        bytes32 dataHash,
        address attester,
        uint256 issuedAt,
        uint256 expiresAt,
        TierLevel tier
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            dataHash,
            attester,
            issuedAt,
            expiresAt,
            uint8(tier)
        ));
    }

    // ============ Internal Helpers ============

    function _getValidityPeriod(TierLevel tier) private pure returns (uint256) {
        if (tier == TierLevel.Basic) return TIER1_VALIDITY;
        if (tier == TierLevel.Standard) return TIER2_VALIDITY;
        if (tier == TierLevel.Enhanced) return TIER3_VALIDITY;
        if (tier == TierLevel.Institutional) return TIER4_VALIDITY;
        if (tier == TierLevel.Accredited) return TIER5_VALIDITY;
        return 0;
    }

    function _resetCountersIfNeeded(TransferTracker storage tracker) private {
        if (block.timestamp >= tracker.lastDayReset + 1 days) {
            tracker.dailyTotal = 0;
            tracker.lastDayReset = block.timestamp;
        }
        if (block.timestamp >= tracker.lastMonthReset + 30 days) {
            tracker.monthlyTotal = 0;
            tracker.lastMonthReset = block.timestamp;
        }
    }

    function _recoverSigner(
        bytes32 hash,
        bytes memory signature
    ) private pure returns (address) {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) v += 27;

        if (v != 27 && v != 28) return address(0);

        return ecrecover(hash, v, r, s);
    }

    // ============ Batch Operations ============

    /// @notice Batch verify multiple users
    function batchVerify(
        ComplianceRegistry storage registry,
        address[] memory users,
        TierLevel tier,
        uint16 jurisdiction,
        bytes32[] memory attestationHashes,
        address provider
    ) internal {
        require(users.length == attestationHashes.length, "Array length mismatch");

        for (uint256 i = 0; i < users.length; i++) {
            verifyUser(registry, users[i], tier, jurisdiction, attestationHashes[i], provider);
        }
    }

    /// @notice Batch add to blacklist
    function batchBlacklist(
        ComplianceRegistry storage registry,
        address[] memory accounts
    ) internal {
        for (uint256 i = 0; i < accounts.length; i++) {
            addToBlacklist(registry, accounts[i]);
        }
    }

    // ============ Query Functions ============

    /// @notice Get full verification record
    function getVerificationRecord(
        ComplianceRegistry storage registry,
        address user
    ) internal view returns (VerificationRecord memory) {
        return registry.verifications[user];
    }

    /// @notice Get provider info
    function getProvider(
        ComplianceRegistry storage registry,
        address providerAddress
    ) internal view returns (Provider memory) {
        return registry.providers[providerAddress];
    }

    /// @notice Get tier limits
    function getTierLimits(
        ComplianceRegistry storage registry,
        TierLevel tier
    ) internal view returns (TierLimits memory) {
        return registry.tierLimits[tier];
    }

    /// @notice Check complete compliance (verification + allowed + jurisdiction)
    function isFullyCompliant(
        ComplianceRegistry storage registry,
        address user,
        TierLevel minTier
    ) internal view returns (bool compliant, string memory reason) {
        if (registry.isBlacklisted[user]) {
            return (false, "Blacklisted");
        }

        if (registry.useWhitelist && !registry.isWhitelisted[user]) {
            return (false, "Not whitelisted");
        }

        VerificationRecord storage record = registry.verifications[user];

        if (record.status != VerificationStatus.Verified) {
            return (false, "Not verified");
        }

        if (block.timestamp >= record.expiresAt) {
            return (false, "Verification expired");
        }

        if (uint8(record.tier) < uint8(minTier)) {
            return (false, "Insufficient tier");
        }

        if (!isJurisdictionAllowed(registry, record.jurisdiction)) {
            return (false, "Restricted jurisdiction");
        }

        return (true, "");
    }
}
