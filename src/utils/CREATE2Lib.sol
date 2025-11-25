// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CREATE2Lib
 * @notice Library for deterministic contract deployment using CREATE2
 * @dev Provides utilities for:
 *      - Computing deterministic addresses before deployment
 *      - Deploying contracts with CREATE2
 *      - Factory pattern implementations
 *      - Salt generation and management
 *
 *      CREATE2 address formula: keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))[12:]
 */
library CREATE2Lib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev CREATE2 prefix byte
    bytes1 private constant CREATE2_PREFIX = 0xff;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error DeploymentFailed();
    error ContractAlreadyDeployed();
    error InsufficientBalance();
    error ZeroAddress();
    error EmptyBytecode();

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDRESS COMPUTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Computes the CREATE2 address for a contract
     * @param deployer The address that will deploy (factory address)
     * @param salt The salt for deployment
     * @param initCodeHash The keccak256 hash of the init code
     * @return addr The deterministic address
     */
    function computeAddress(
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address addr) {
        assembly {
            // Load free memory pointer
            let ptr := mload(0x40)

            // Store CREATE2 prefix (1 byte)
            mstore8(ptr, 0xff)

            // Store deployer address (20 bytes at offset 1)
            mstore(add(ptr, 1), shl(96, deployer))

            // Store salt (32 bytes at offset 21)
            mstore(add(ptr, 21), salt)

            // Store init code hash (32 bytes at offset 53)
            mstore(add(ptr, 53), initCodeHash)

            // Compute address: keccak256(0xff ++ deployer ++ salt ++ initCodeHash)[12:]
            addr := and(
                keccak256(ptr, 85),
                0xffffffffffffffffffffffffffffffffffffffff
            )
        }
    }

    /**
     * @notice Computes the CREATE2 address using init code directly
     * @param deployer The address that will deploy
     * @param salt The salt for deployment
     * @param initCode The full init code (bytecode + constructor args)
     * @return addr The deterministic address
     */
    function computeAddressFromCode(
        address deployer,
        bytes32 salt,
        bytes memory initCode
    ) internal pure returns (address addr) {
        return computeAddress(deployer, salt, keccak256(initCode));
    }

    /**
     * @notice Computes address for contract deployed from this contract
     * @param salt The salt for deployment
     * @param initCodeHash The keccak256 hash of the init code
     * @return addr The deterministic address
     */
    function computeAddressSelf(
        bytes32 salt,
        bytes32 initCodeHash
    ) internal view returns (address addr) {
        return computeAddress(address(this), salt, initCodeHash);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deploys a contract using CREATE2
     * @param salt The salt for deployment
     * @param initCode The full init code (bytecode + constructor args)
     * @return deployed The address of the deployed contract
     */
    function deploy(
        bytes32 salt,
        bytes memory initCode
    ) internal returns (address deployed) {
        if (initCode.length == 0) revert EmptyBytecode();

        assembly {
            deployed := create2(
                0,                      // No value sent
                add(initCode, 0x20),    // Init code starts after length prefix
                mload(initCode),        // Init code length
                salt
            )
        }

        if (deployed == address(0)) revert DeploymentFailed();
    }

    /**
     * @notice Deploys a contract using CREATE2 with ETH value
     * @param salt The salt for deployment
     * @param initCode The full init code
     * @param value The ETH value to send to the constructor
     * @return deployed The address of the deployed contract
     */
    function deployWithValue(
        bytes32 salt,
        bytes memory initCode,
        uint256 value
    ) internal returns (address deployed) {
        if (initCode.length == 0) revert EmptyBytecode();
        if (address(this).balance < value) revert InsufficientBalance();

        assembly {
            deployed := create2(
                value,
                add(initCode, 0x20),
                mload(initCode),
                salt
            )
        }

        if (deployed == address(0)) revert DeploymentFailed();
    }

    /**
     * @notice Safely deploys a contract, reverting if already deployed
     * @param salt The salt for deployment
     * @param initCode The full init code
     * @return deployed The address of the deployed contract
     */
    function safeDeployCreate2(
        bytes32 salt,
        bytes memory initCode
    ) internal returns (address deployed) {
        address predicted = computeAddressFromCode(address(this), salt, initCode);

        if (isContract(predicted)) {
            revert ContractAlreadyDeployed();
        }

        deployed = deploy(salt, initCode);

        // Verify deployment at predicted address
        if (deployed != predicted) revert DeploymentFailed();
    }

    /**
     * @notice Deploys a contract or returns existing address if already deployed
     * @param salt The salt for deployment
     * @param initCode The full init code
     * @return deployed The address of the (existing or new) contract
     * @return isNew True if this was a new deployment
     */
    function deployOrGet(
        bytes32 salt,
        bytes memory initCode
    ) internal returns (address deployed, bool isNew) {
        deployed = computeAddressFromCode(address(this), salt, initCode);

        if (isContract(deployed)) {
            return (deployed, false);
        }

        deployed = deploy(salt, initCode);
        return (deployed, true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SALT GENERATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Generates a salt from multiple parameters
     * @param deployer The deployer address (for namespacing)
     * @param name A name/identifier for the contract
     * @param nonce A nonce for uniqueness
     * @return salt The generated salt
     */
    function generateSalt(
        address deployer,
        string memory name,
        uint256 nonce
    ) internal pure returns (bytes32 salt) {
        salt = keccak256(abi.encodePacked(deployer, name, nonce));
    }

    /**
     * @notice Generates a salt from an address and identifier
     * @param account The account address
     * @param identifier A unique identifier
     * @return salt The generated salt
     */
    function saltFromAddress(
        address account,
        bytes32 identifier
    ) internal pure returns (bytes32 salt) {
        salt = keccak256(abi.encodePacked(account, identifier));
    }

    /**
     * @notice Generates a chain-specific salt
     * @dev Useful for cross-chain deployments where you want different addresses
     * @param baseSalt The base salt
     * @return salt The chain-specific salt
     */
    function chainSpecificSalt(bytes32 baseSalt) internal view returns (bytes32 salt) {
        salt = keccak256(abi.encodePacked(baseSalt, block.chainid));
    }

    /**
     * @notice Generates a salt that results in a vanity address
     * @dev Warning: This can be expensive! Consider doing off-chain
     * @param deployer The deployer address
     * @param initCodeHash The init code hash
     * @param prefix The desired prefix (up to 4 bytes)
     * @param maxIterations Maximum iterations to try
     * @return salt The salt that produces a matching address
     * @return found True if a matching salt was found
     */
    function findVanitySalt(
        address deployer,
        bytes32 initCodeHash,
        bytes4 prefix,
        uint256 maxIterations
    ) internal pure returns (bytes32 salt, bool found) {
        for (uint256 i = 0; i < maxIterations; i++) {
            salt = bytes32(i);
            address addr = computeAddress(deployer, salt, initCodeHash);

            // Check if address starts with desired prefix
            if (bytes4(bytes20(addr)) == prefix) {
                return (salt, true);
            }
        }
        return (bytes32(0), false);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INIT CODE HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Creates init code from bytecode and constructor arguments
     * @param bytecode The contract bytecode
     * @param constructorArgs ABI-encoded constructor arguments
     * @return initCode The complete init code
     */
    function createInitCode(
        bytes memory bytecode,
        bytes memory constructorArgs
    ) internal pure returns (bytes memory initCode) {
        initCode = abi.encodePacked(bytecode, constructorArgs);
    }

    /**
     * @notice Computes init code hash from bytecode and arguments
     * @param bytecode The contract bytecode
     * @param constructorArgs ABI-encoded constructor arguments
     * @return hash The keccak256 hash of the init code
     */
    function hashInitCode(
        bytes memory bytecode,
        bytes memory constructorArgs
    ) internal pure returns (bytes32 hash) {
        hash = keccak256(abi.encodePacked(bytecode, constructorArgs));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROXY DEPLOYMENT HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deploys a minimal proxy (EIP-1167 clone) using CREATE2
     * @param implementation The implementation address to clone
     * @param salt The salt for deployment
     * @return proxy The address of the deployed proxy
     */
    function deployMinimalProxy(
        address implementation,
        bytes32 salt
    ) internal returns (address proxy) {
        bytes memory initCode = getMinimalProxyInitCode(implementation);
        proxy = deploy(salt, initCode);
    }

    /**
     * @notice Computes the address of a minimal proxy before deployment
     * @param deployer The deployer address
     * @param implementation The implementation address
     * @param salt The salt for deployment
     * @return proxy The predicted proxy address
     */
    function computeMinimalProxyAddress(
        address deployer,
        address implementation,
        bytes32 salt
    ) internal pure returns (address proxy) {
        bytes32 initCodeHash = keccak256(getMinimalProxyInitCode(implementation));
        proxy = computeAddress(deployer, salt, initCodeHash);
    }

    /**
     * @notice Gets the init code for a minimal proxy (EIP-1167)
     * @param implementation The implementation address
     * @return initCode The minimal proxy init code
     */
    function getMinimalProxyInitCode(
        address implementation
    ) internal pure returns (bytes memory initCode) {
        // EIP-1167 minimal proxy bytecode:
        // 3d602d80600a3d3981f3363d3d373d3d3d363d73<implementation>5af43d82803e903d91602b57fd5bf3

        initCode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if an address contains code
     * @param addr The address to check
     * @return hasCode True if the address has code
     */
    function isContract(address addr) internal view returns (bool hasCode) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    /**
     * @notice Checks if a contract can be deployed at an address
     * @param deployer The deployer address
     * @param salt The salt for deployment
     * @param initCodeHash The init code hash
     * @return canDeploy True if no contract exists at the address
     */
    function canDeployAt(
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal view returns (bool canDeploy) {
        address predicted = computeAddress(deployer, salt, initCodeHash);
        return !isContract(predicted);
    }

    /**
     * @notice Validates that a deployment would succeed at the expected address
     * @param expectedAddress The expected deployment address
     * @param deployer The deployer address
     * @param salt The salt
     * @param initCodeHash The init code hash
     * @return valid True if deployment would result in expected address
     */
    function validateDeployment(
        address expectedAddress,
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal view returns (bool valid) {
        address computed = computeAddress(deployer, salt, initCodeHash);
        return computed == expectedAddress && !isContract(computed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Computes multiple CREATE2 addresses
     * @param deployer The deployer address
     * @param salts Array of salts
     * @param initCodeHash The init code hash (same for all)
     * @return addresses Array of computed addresses
     */
    function computeAddresses(
        address deployer,
        bytes32[] memory salts,
        bytes32 initCodeHash
    ) internal pure returns (address[] memory addresses) {
        addresses = new address[](salts.length);
        for (uint256 i = 0; i < salts.length; i++) {
            addresses[i] = computeAddress(deployer, salts[i], initCodeHash);
        }
    }

    /**
     * @notice Deploys multiple contracts with CREATE2
     * @param salts Array of salts
     * @param initCodes Array of init codes
     * @return deployed Array of deployed addresses
     */
    function deployBatch(
        bytes32[] memory salts,
        bytes[] memory initCodes
    ) internal returns (address[] memory deployed) {
        require(salts.length == initCodes.length, "Length mismatch");

        deployed = new address[](salts.length);
        for (uint256 i = 0; i < salts.length; i++) {
            deployed[i] = deploy(salts[i], initCodes[i]);
        }
    }
}
