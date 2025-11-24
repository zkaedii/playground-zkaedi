// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SignatureUtils
 * @notice ECDSA signature verification and EIP-712 utilities
 * @dev Provides signature recovery, verification, and domain separator helpers
 */
library SignatureUtils {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev EIP-712 domain separator typehash
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev EIP-712 domain separator with salt
    bytes32 internal constant DOMAIN_TYPEHASH_WITH_SALT =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");

    /// @dev Malleability threshold for s value
    bytes32 internal constant MALLEABILITY_THRESHOLD =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidSignatureLength(uint256 length);
    error InvalidSignatureS();
    error InvalidSignatureV();
    error SignatureRecoveryFailed();
    error SignatureMismatch(address expected, address recovered);
    error SignatureExpired(uint256 deadline, uint256 currentTime);
    error NonceAlreadyUsed(uint256 nonce);
    error InvalidNonce(uint256 provided, uint256 expected);

    // ═══════════════════════════════════════════════════════════════════════════
    // SIGNATURE RECOVERY
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Recover signer address from signature
     * @param hash Message hash that was signed
     * @param signature ECDSA signature
     * @return Recovered signer address
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) {
            revert InvalidSignatureLength(signature.length);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        return recover(hash, v, r, s);
    }

    /**
     * @notice Recover signer from split signature components
     * @param hash Message hash
     * @param v Recovery id
     * @param r R component
     * @param s S component
     * @return Recovered signer address
     */
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        // Reject malleable signatures
        if (uint256(s) > uint256(MALLEABILITY_THRESHOLD)) {
            revert InvalidSignatureS();
        }

        // Normalize v
        if (v < 27) {
            v += 27;
        }

        if (v != 27 && v != 28) {
            revert InvalidSignatureV();
        }

        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) {
            revert SignatureRecoveryFailed();
        }

        return signer;
    }

    /**
     * @notice Try to recover signer, returns zero address on failure
     * @param hash Message hash
     * @param signature ECDSA signature
     * @return Recovered address or zero on failure
     */
    function tryRecover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) {
            return address(0);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        return tryRecover(hash, v, r, s);
    }

    /**
     * @notice Try to recover from split components
     */
    function tryRecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        if (uint256(s) > uint256(MALLEABILITY_THRESHOLD)) {
            return address(0);
        }

        if (v < 27) {
            v += 27;
        }

        if (v != 27 && v != 28) {
            return address(0);
        }

        return ecrecover(hash, v, r, s);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SIGNATURE VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify signature matches expected signer
     * @param hash Message hash
     * @param signature ECDSA signature
     * @param expectedSigner Expected signer address
     * @return True if signature is valid
     */
    function isValidSignature(
        bytes32 hash,
        bytes memory signature,
        address expectedSigner
    ) internal pure returns (bool) {
        address recovered = tryRecover(hash, signature);
        return recovered != address(0) && recovered == expectedSigner;
    }

    /**
     * @notice Verify signature and revert if invalid
     * @param hash Message hash
     * @param signature ECDSA signature
     * @param expectedSigner Expected signer address
     */
    function verifySignature(
        bytes32 hash,
        bytes memory signature,
        address expectedSigner
    ) internal pure {
        address recovered = recover(hash, signature);
        if (recovered != expectedSigner) {
            revert SignatureMismatch(expectedSigner, recovered);
        }
    }

    /**
     * @notice Check if signature is valid for eth_sign format
     * @dev Prepends "\x19Ethereum Signed Message:\n32" prefix
     * @param messageHash Original message hash
     * @param signature ECDSA signature
     * @param expectedSigner Expected signer
     * @return True if valid
     */
    function isValidEthSignature(
        bytes32 messageHash,
        bytes memory signature,
        address expectedSigner
    ) internal pure returns (bool) {
        bytes32 ethHash = toEthSignedMessageHash(messageHash);
        return isValidSignature(ethHash, signature, expectedSigner);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EIP-712 DOMAIN SEPARATOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Build EIP-712 domain separator
     * @param name Contract/protocol name
     * @param version Protocol version
     * @param verifyingContract Contract address
     * @return Domain separator hash
     */
    function buildDomainSeparator(
        string memory name,
        string memory version,
        address verifyingContract
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                verifyingContract
            )
        );
    }

    /**
     * @notice Build domain separator with custom chain ID
     * @param name Contract/protocol name
     * @param version Protocol version
     * @param chainId Chain ID
     * @param verifyingContract Contract address
     * @return Domain separator hash
     */
    function buildDomainSeparatorWithChainId(
        string memory name,
        string memory version,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
    }

    /**
     * @notice Build domain separator with salt
     * @param name Contract/protocol name
     * @param version Protocol version
     * @param verifyingContract Contract address
     * @param salt Additional uniqueness salt
     * @return Domain separator hash
     */
    function buildDomainSeparatorWithSalt(
        string memory name,
        string memory version,
        address verifyingContract,
        bytes32 salt
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH_WITH_SALT,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                verifyingContract,
                salt
            )
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EIP-712 TYPED DATA HASHING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Hash typed data according to EIP-712
     * @param domainSeparator Domain separator
     * @param structHash Struct hash
     * @return Typed data hash ready for signing
     */
    function toTypedDataHash(
        bytes32 domainSeparator,
        bytes32 structHash
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /**
     * @notice Create eth_sign compatible hash
     * @param messageHash Original message hash
     * @return Hash with Ethereum signed message prefix
     */
    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }

    /**
     * @notice Create eth_sign compatible hash from bytes
     * @param message Original message
     * @return Hash with Ethereum signed message prefix
     */
    function toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                toString(message.length),
                message
            )
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SIGNATURE WITH DEADLINE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify signature with deadline check
     * @param hash Message hash
     * @param signature ECDSA signature
     * @param expectedSigner Expected signer
     * @param deadline Signature deadline
     */
    function verifySignatureWithDeadline(
        bytes32 hash,
        bytes memory signature,
        address expectedSigner,
        uint256 deadline
    ) internal view {
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, block.timestamp);
        }
        verifySignature(hash, signature, expectedSigner);
    }

    /**
     * @notice Check signature validity with deadline
     * @param hash Message hash
     * @param signature ECDSA signature
     * @param expectedSigner Expected signer
     * @param deadline Signature deadline
     * @return True if valid and not expired
     */
    function isValidSignatureWithDeadline(
        bytes32 hash,
        bytes memory signature,
        address expectedSigner,
        uint256 deadline
    ) internal view returns (bool) {
        if (block.timestamp > deadline) {
            return false;
        }
        return isValidSignature(hash, signature, expectedSigner);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // NONCE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Hash data with nonce for replay protection
     * @param dataHash Original data hash
     * @param nonce Unique nonce
     * @return Hash including nonce
     */
    function hashWithNonce(bytes32 dataHash, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(dataHash, nonce));
    }

    /**
     * @notice Hash data with nonce and deadline
     * @param dataHash Original data hash
     * @param nonce Unique nonce
     * @param deadline Expiration timestamp
     * @return Hash including nonce and deadline
     */
    function hashWithNonceAndDeadline(
        bytes32 dataHash,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(dataHash, nonce, deadline));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-SIGNATURE SUPPORT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify multiple signatures
     * @param hash Message hash
     * @param signatures Array of signatures
     * @param signers Array of expected signers
     * @return True if all signatures are valid
     */
    function verifyMultipleSignatures(
        bytes32 hash,
        bytes[] memory signatures,
        address[] memory signers
    ) internal pure returns (bool) {
        if (signatures.length != signers.length) return false;

        for (uint256 i; i < signatures.length;) {
            if (!isValidSignature(hash, signatures[i], signers[i])) {
                return false;
            }
            unchecked { ++i; }
        }
        return true;
    }

    /**
     * @notice Recover multiple signers from signatures
     * @param hash Message hash
     * @param signatures Array of signatures
     * @return signers Array of recovered signers
     */
    function recoverMultiple(
        bytes32 hash,
        bytes[] memory signatures
    ) internal pure returns (address[] memory signers) {
        uint256 length = signatures.length;
        signers = new address[](length);

        for (uint256 i; i < length;) {
            signers[i] = recover(hash, signatures[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Check if enough valid signatures from unique signers
     * @param hash Message hash
     * @param signatures Array of signatures
     * @param validSigners Set of valid signer addresses
     * @param threshold Minimum required signatures
     * @return True if threshold met
     */
    function hasEnoughSignatures(
        bytes32 hash,
        bytes[] memory signatures,
        address[] memory validSigners,
        uint256 threshold
    ) internal pure returns (bool) {
        if (signatures.length < threshold) return false;

        uint256 validCount;
        address[] memory usedSigners = new address[](signatures.length);

        for (uint256 i; i < signatures.length;) {
            address recovered = tryRecover(hash, signatures[i]);
            if (recovered != address(0)) {
                // Check if signer is valid and not already used
                bool isValid;
                for (uint256 j; j < validSigners.length;) {
                    if (validSigners[j] == recovered) {
                        isValid = true;
                        break;
                    }
                    unchecked { ++j; }
                }

                if (isValid) {
                    bool alreadyUsed;
                    for (uint256 k; k < validCount;) {
                        if (usedSigners[k] == recovered) {
                            alreadyUsed = true;
                            break;
                        }
                        unchecked { ++k; }
                    }

                    if (!alreadyUsed) {
                        usedSigners[validCount] = recovered;
                        unchecked { ++validCount; }
                        if (validCount >= threshold) return true;
                    }
                }
            }
            unchecked { ++i; }
        }

        return validCount >= threshold;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Convert uint256 to string
     * @param value Value to convert
     * @return String representation
     */
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
