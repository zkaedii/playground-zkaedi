// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MerkleProofLib
 * @notice Advanced merkle proof utilities for airdrops, whitelists, and verification
 * @dev Gas-optimized merkle tree operations with multi-proof support
 */
library MerkleProofLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidProof();
    error InvalidProofLength();
    error InvalidMultiProof();
    error LeafAlreadyClaimed();
    error InvalidLeafIndex();
    error EmptyProof();

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Multi-proof structure for batch verification
    struct MultiProof {
        bytes32[] proof;
        bool[] flags;
    }

    /// @notice Proof with leaf index for sorted tree verification
    struct IndexedProof {
        bytes32[] proof;
        uint256 leafIndex;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STANDARD VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify a merkle proof
    /// @param proof Array of sibling hashes
    /// @param root The merkle root
    /// @param leaf The leaf to verify
    /// @return True if proof is valid
    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        return processProof(proof, leaf) == root;
    }

    /// @notice Verify proof using calldata (gas optimized)
    function verifyCalldata(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        return processProofCalldata(proof, leaf) == root;
    }

    /// @notice Process merkle proof and return computed root
    function processProof(
        bytes32[] memory proof,
        bytes32 leaf
    ) internal pure returns (bytes32 computedHash) {
        computedHash = leaf;
        unchecked {
            for (uint256 i; i < proof.length; ++i) {
                computedHash = _hashPair(computedHash, proof[i]);
            }
        }
    }

    /// @notice Process proof from calldata
    function processProofCalldata(
        bytes32[] calldata proof,
        bytes32 leaf
    ) internal pure returns (bytes32 computedHash) {
        computedHash = leaf;
        unchecked {
            for (uint256 i; i < proof.length; ++i) {
                computedHash = _hashPair(computedHash, proof[i]);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INDEXED VERIFICATION (WITH LEAF POSITION)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify proof with leaf index (for sorted merkle trees)
    /// @param proof The merkle proof
    /// @param root The merkle root
    /// @param leaf The leaf hash
    /// @param index The index of the leaf in the tree
    function verifyWithIndex(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf,
        uint256 index
    ) internal pure returns (bool) {
        return processProofWithIndex(proof, leaf, index) == root;
    }

    /// @notice Process proof using leaf index to determine hashing order
    function processProofWithIndex(
        bytes32[] memory proof,
        bytes32 leaf,
        uint256 index
    ) internal pure returns (bytes32 computedHash) {
        computedHash = leaf;

        unchecked {
            for (uint256 i; i < proof.length; ++i) {
                if (index & 1 == 0) {
                    // Leaf is on left
                    computedHash = _efficientHash(computedHash, proof[i]);
                } else {
                    // Leaf is on right
                    computedHash = _efficientHash(proof[i], computedHash);
                }
                index >>= 1;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-PROOF VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify multiple leaves with a single multi-proof
    /// @param proof The multi-proof elements
    /// @param proofFlags Flags indicating how to combine elements
    /// @param root The merkle root
    /// @param leaves The leaves to verify
    function verifyMultiProof(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        return processMultiProof(proof, proofFlags, leaves) == root;
    }

    /// @notice Process multi-proof and return computed root
    function processMultiProof(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32[] memory leaves
    ) internal pure returns (bytes32 merkleRoot) {
        uint256 leavesLen = leaves.length;
        uint256 proofLen = proof.length;
        uint256 totalHashes = proofFlags.length;

        if (leavesLen + proofLen != totalHashes + 1) {
            revert InvalidMultiProof();
        }

        bytes32[] memory hashes = new bytes32[](totalHashes);
        uint256 leafPos;
        uint256 hashPos;
        uint256 proofPos;

        unchecked {
            for (uint256 i; i < totalHashes; ++i) {
                bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
                bytes32 b = proofFlags[i]
                    ? (leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++])
                    : proof[proofPos++];
                hashes[i] = _hashPair(a, b);
            }
        }

        if (totalHashes > 0) {
            if (proofPos != proofLen) revert InvalidMultiProof();
            return hashes[totalHashes - 1];
        } else if (leavesLen > 0) {
            return leaves[0];
        } else {
            return proof[0];
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LEAF GENERATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create leaf hash from address
    function createLeaf(address account) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account));
    }

    /// @notice Create leaf hash from address and amount
    function createLeaf(address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, amount));
    }

    /// @notice Create leaf hash from address, amount, and index
    function createLeaf(
        address account,
        uint256 amount,
        uint256 index
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(index, account, amount));
    }

    /// @notice Create double-hashed leaf (prevents second preimage attacks)
    function createSecureLeaf(address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
    }

    /// @notice Create leaf with arbitrary data
    function createLeafFromData(bytes memory data) internal pure returns (bytes32) {
        return keccak256(data);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CLAIM TRACKING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Check if index has been claimed in bitmap
    function isClaimed(
        mapping(uint256 => uint256) storage claimedBitmap,
        uint256 index
    ) internal view returns (bool) {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        uint256 word = claimedBitmap[wordIndex];
        uint256 mask = 1 << bitIndex;
        return word & mask != 0;
    }

    /// @notice Mark index as claimed in bitmap
    function setClaimed(
        mapping(uint256 => uint256) storage claimedBitmap,
        uint256 index
    ) internal {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        claimedBitmap[wordIndex] |= (1 << bitIndex);
    }

    /// @notice Verify and claim in single operation
    function verifyAndClaim(
        bytes32[] calldata proof,
        bytes32 root,
        uint256 index,
        address account,
        uint256 amount,
        mapping(uint256 => uint256) storage claimedBitmap
    ) internal returns (bool) {
        if (isClaimed(claimedBitmap, index)) {
            revert LeafAlreadyClaimed();
        }

        bytes32 leaf = createLeaf(account, amount, index);
        if (!verifyCalldata(proof, root, leaf)) {
            revert InvalidProof();
        }

        setClaimed(claimedBitmap, index);
        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify multiple independent proofs
    function verifyBatch(
        bytes32[][] memory proofs,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        if (proofs.length != leaves.length) revert InvalidProofLength();

        unchecked {
            for (uint256 i; i < proofs.length; ++i) {
                if (!verify(proofs[i], root, leaves[i])) {
                    return false;
                }
            }
        }
        return true;
    }

    /// @notice Get indices of valid proofs in batch
    function verifyBatchPartial(
        bytes32[][] memory proofs,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool[] memory results) {
        results = new bool[](proofs.length);

        unchecked {
            for (uint256 i; i < proofs.length; ++i) {
                results[i] = verify(proofs[i], root, leaves[i]);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TREE CONSTRUCTION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Compute merkle root from array of leaves
    /// @dev Only for small trees (high gas cost for large arrays)
    function computeRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 0) return bytes32(0);
        if (leaves.length == 1) return leaves[0];

        uint256 n = leaves.length;
        // Pad to power of 2
        uint256 size = 1;
        while (size < n) {
            size <<= 1;
        }

        bytes32[] memory tree = new bytes32[](size);
        for (uint256 i; i < n; ++i) {
            tree[i] = leaves[i];
        }
        // Pad with zero hashes
        for (uint256 i = n; i < size; ++i) {
            tree[i] = bytes32(0);
        }

        // Build tree bottom-up
        while (size > 1) {
            for (uint256 i; i < size / 2; ++i) {
                tree[i] = _hashPair(tree[2 * i], tree[2 * i + 1]);
            }
            size /= 2;
        }

        return tree[0];
    }

    /// @notice Get proof for leaf at index (for testing)
    /// @dev Only for small trees, used for generating proofs
    function getProof(
        bytes32[] memory leaves,
        uint256 index
    ) internal pure returns (bytes32[] memory proof) {
        if (index >= leaves.length) revert InvalidLeafIndex();

        uint256 n = leaves.length;
        // Pad to power of 2
        uint256 size = 1;
        uint256 depth;
        while (size < n) {
            size <<= 1;
            depth++;
        }

        bytes32[] memory tree = new bytes32[](size * 2);

        // Fill leaves
        for (uint256 i; i < n; ++i) {
            tree[size + i] = leaves[i];
        }

        // Build tree bottom-up
        for (uint256 i = size - 1; i > 0; --i) {
            tree[i] = _hashPair(tree[2 * i], tree[2 * i + 1]);
        }

        // Extract proof
        proof = new bytes32[](depth);
        uint256 idx = size + index;

        unchecked {
            for (uint256 i; i < depth; ++i) {
                proof[i] = tree[idx ^ 1]; // Sibling
                idx /= 2;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Hash pair in sorted order (for unordered trees)
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    /// @dev Efficient keccak256 of two bytes32 values
    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 result) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            result := keccak256(0x00, 0x40)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROOF VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Check if proof length is valid for tree size
    function isValidProofLength(
        uint256 proofLength,
        uint256 treeSize
    ) internal pure returns (bool) {
        if (treeSize == 0) return proofLength == 0;
        uint256 expectedDepth;
        uint256 size = 1;
        while (size < treeSize) {
            size <<= 1;
            expectedDepth++;
        }
        return proofLength == expectedDepth;
    }

    /// @notice Estimate tree depth from leaf count
    function treeDepth(uint256 leafCount) internal pure returns (uint256 depth) {
        if (leafCount <= 1) return 0;
        uint256 size = 1;
        while (size < leafCount) {
            size <<= 1;
            depth++;
        }
    }

    /// @notice Get maximum leaves for tree depth
    function maxLeaves(uint256 depth) internal pure returns (uint256) {
        return 1 << depth;
    }
}
