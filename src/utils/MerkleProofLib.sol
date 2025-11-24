// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MerkleProofLib
 * @notice Advanced merkle proof utilities with batch verification and multi-proofs
 * @dev Provides comprehensive merkle tree operations for airdrops, whitelists, and verification
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
    // SINGLE PROOF VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify a merkle proof
     * @param proof Array of sibling hashes
     * @param root Merkle root
     * @param leaf Leaf hash to verify
     * @return True if proof is valid
     */
    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i; i < proof.length;) {
            computedHash = _hashPair(computedHash, proof[i]);
            unchecked { ++i; }
        }

        return computedHash == root;
    }

    /**
     * @notice Verify proof with calldata (more gas efficient)
     */
    function verifyCalldata(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i; i < proof.length;) {
            computedHash = _hashPair(computedHash, proof[i]);
            unchecked { ++i; }
        }

        return computedHash == root;
    }

    /**
     * @notice Verify and revert if invalid
     */
    function verifyOrRevert(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure {
        if (!verify(proof, root, leaf)) {
            revert InvalidProof();
        }
    }

    /**
     * @notice Compute root from leaf and proof
     */
    function computeRoot(
        bytes32[] memory proof,
        bytes32 leaf
    ) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;

        for (uint256 i; i < proof.length;) {
            computedHash = _hashPair(computedHash, proof[i]);
            unchecked { ++i; }
        }

        return computedHash;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-PROOF VERIFICATION (EIP-2930 style)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify multiple leaves with a single multi-proof
     * @param proof Combined proof elements
     * @param proofFlags Flags indicating how to combine elements
     * @param root Merkle root
     * @param leaves Array of leaves to verify
     * @return True if all leaves are verified
     */
    function multiProofVerify(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        return computeMultiProofRoot(proof, proofFlags, leaves) == root;
    }

    /**
     * @notice Compute root from multi-proof
     */
    function computeMultiProofRoot(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32[] memory leaves
    ) internal pure returns (bytes32) {
        uint256 leavesLen = leaves.length;
        uint256 totalHashes = proofFlags.length;

        if (leavesLen + proof.length - 1 != totalHashes) {
            revert InvalidMultiProof();
        }

        bytes32[] memory hashes = new bytes32[](totalHashes);
        uint256 leafPos;
        uint256 hashPos;
        uint256 proofPos;

        for (uint256 i; i < totalHashes;) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = proofFlags[i]
                ? (leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++])
                : proof[proofPos++];
            hashes[i] = _hashPair(a, b);
            unchecked { ++i; }
        }

        if (totalHashes > 0) {
            return hashes[totalHashes - 1];
        } else if (leavesLen > 0) {
            return leaves[0];
        } else {
            return proof[0];
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INDEXED PROOF (with position verification)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify proof with leaf index
     * @param proof Array of sibling hashes
     * @param root Merkle root
     * @param leaf Leaf hash
     * @param index Leaf index in tree
     * @return True if valid
     */
    function verifyWithIndex(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf,
        uint256 index
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i; i < proof.length;) {
            if (index & 1 == 0) {
                computedHash = _hashPair(computedHash, proof[i]);
            } else {
                computedHash = _hashPair(proof[i], computedHash);
            }
            index >>= 1;
            unchecked { ++i; }
        }

        return computedHash == root;
    }

    /**
     * @notice Get leaf position (left=0, right=1) at each level
     */
    function getLeafPath(
        uint256 index,
        uint256 treeDepth
    ) internal pure returns (bool[] memory path) {
        path = new bool[](treeDepth);
        for (uint256 i; i < treeDepth;) {
            path[i] = (index & 1) == 1; // true if right child
            index >>= 1;
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify multiple separate proofs
     * @param proofs Array of proofs
     * @param root Merkle root
     * @param leaves Array of leaves
     * @return True if all proofs are valid
     */
    function verifyBatch(
        bytes32[][] memory proofs,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        if (proofs.length != leaves.length) {
            revert InvalidProofLength();
        }

        for (uint256 i; i < proofs.length;) {
            if (!verify(proofs[i], root, leaves[i])) {
                return false;
            }
            unchecked { ++i; }
        }
        return true;
    }

    /**
     * @notice Verify batch and return individual results
     */
    function verifyBatchWithResults(
        bytes32[][] memory proofs,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool[] memory results) {
        results = new bool[](leaves.length);

        for (uint256 i; i < proofs.length;) {
            results[i] = verify(proofs[i], root, leaves[i]);
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LEAF CONSTRUCTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create leaf hash for address + amount (airdrop style)
     */
    function createLeaf(address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, amount));
    }

    /**
     * @notice Create leaf hash for address + index + amount
     */
    function createIndexedLeaf(
        address account,
        uint256 index,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(index, account, amount));
    }

    /**
     * @notice Create leaf hash for whitelist (address only)
     */
    function createWhitelistLeaf(address account) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account));
    }

    /**
     * @notice Create double-hashed leaf (prevents second preimage attack)
     */
    function createSecureLeaf(bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(keccak256(data)));
    }

    /**
     * @notice Create leaf from struct data
     */
    function createStructLeaf(
        address account,
        uint256 amount,
        uint256 nonce,
        bytes32 metadata
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, amount, nonce, metadata));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CLAIM TRACKING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if index is claimed in bitmap
     */
    function isClaimed(
        mapping(uint256 => uint256) storage claimedBitmap,
        uint256 index
    ) internal view returns (bool) {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        uint256 word = claimedBitmap[wordIndex];
        uint256 mask = (1 << bitIndex);
        return word & mask == mask;
    }

    /**
     * @notice Mark index as claimed in bitmap
     */
    function setClaimed(
        mapping(uint256 => uint256) storage claimedBitmap,
        uint256 index
    ) internal {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        claimedBitmap[wordIndex] = claimedBitmap[wordIndex] | (1 << bitIndex);
    }

    /**
     * @notice Verify and mark as claimed atomically
     */
    function verifyAndClaim(
        mapping(uint256 => uint256) storage claimedBitmap,
        bytes32[] memory proof,
        bytes32 root,
        uint256 index,
        address account,
        uint256 amount
    ) internal {
        if (isClaimed(claimedBitmap, index)) {
            revert LeafAlreadyClaimed();
        }

        bytes32 leaf = createIndexedLeaf(account, index, amount);
        if (!verify(proof, root, leaf)) {
            revert InvalidProof();
        }

        setClaimed(claimedBitmap, index);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TREE CONSTRUCTION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute merkle root from array of leaves
     * @dev Only for small trees (gas intensive for large arrays)
     */
    function computeRootFromLeaves(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 n = leaves.length;
        if (n == 0) revert EmptyProof();
        if (n == 1) return leaves[0];

        // Pad to power of 2
        uint256 size = 1;
        while (size < n) size <<= 1;

        bytes32[] memory tree = new bytes32[](size);
        for (uint256 i; i < n;) {
            tree[i] = leaves[i];
            unchecked { ++i; }
        }
        // Pad remaining with zero hashes
        for (uint256 i = n; i < size;) {
            tree[i] = bytes32(0);
            unchecked { ++i; }
        }

        // Build tree bottom-up
        while (size > 1) {
            for (uint256 i; i < size / 2;) {
                tree[i] = _hashPair(tree[2 * i], tree[2 * i + 1]);
                unchecked { ++i; }
            }
            size /= 2;
        }

        return tree[0];
    }

    /**
     * @notice Generate proof for a leaf at given index
     * @dev Only for small trees (gas intensive)
     */
    function generateProof(
        bytes32[] memory leaves,
        uint256 index
    ) internal pure returns (bytes32[] memory proof) {
        uint256 n = leaves.length;
        if (index >= n) revert InvalidLeafIndex();

        // Calculate tree depth
        uint256 depth;
        uint256 size = 1;
        while (size < n) {
            size <<= 1;
            depth++;
        }

        proof = new bytes32[](depth);

        // Pad leaves to power of 2
        bytes32[] memory tree = new bytes32[](size);
        for (uint256 i; i < n;) {
            tree[i] = leaves[i];
            unchecked { ++i; }
        }

        // Build tree and collect proof
        uint256 proofIndex;
        uint256 currentIndex = index;

        while (size > 1) {
            // Collect sibling
            uint256 siblingIndex = currentIndex ^ 1;
            if (siblingIndex < size) {
                proof[proofIndex++] = tree[siblingIndex];
            }

            // Build next level
            for (uint256 i; i < size / 2;) {
                tree[i] = _hashPair(tree[2 * i], tree[2 * i + 1]);
                unchecked { ++i; }
            }

            currentIndex /= 2;
            size /= 2;
        }

        // Resize proof array if needed
        assembly {
            mstore(proof, proofIndex)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Hash pair of nodes in sorted order
     */
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a <= b
            ? keccak256(abi.encodePacked(a, b))
            : keccak256(abi.encodePacked(b, a));
    }

    /**
     * @notice Hash pair with explicit ordering (left, right)
     */
    function _hashPairOrdered(bytes32 left, bytes32 right) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(left, right));
    }
}
