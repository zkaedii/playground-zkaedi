// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/examples/DeFiVault.sol";
import "../src/examples/SecurityManager.sol";
import "../src/examples/StakingRewardsHub.sol";
import "../src/utils/StakingLib.sol";
import "../src/utils/RewardLib.sol";

/*//////////////////////////////////////////////////////////////
                    MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/*//////////////////////////////////////////////////////////////
                    DEFI VAULT TESTS
//////////////////////////////////////////////////////////////*/

contract DeFiVaultTest is Test {
    DeFiVault public vault;
    MockERC20 public vaultToken;
    MockERC20 public rewardToken;

    address public owner;
    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 constant REWARD_RATE = 1e18; // 1 token per second
    uint256 constant INITIAL_BALANCE = 1000000e18;

    function setUp() public {
        owner = address(this);

        // Deploy tokens
        vaultToken = new MockERC20("Vault Token", "VT");
        rewardToken = new MockERC20("Reward Token", "RT");

        // Deploy vault
        vault = new DeFiVault(
            address(vaultToken),
            address(rewardToken),
            REWARD_RATE
        );

        // Setup balances
        vaultToken.mint(alice, INITIAL_BALANCE);
        vaultToken.mint(bob, INITIAL_BALANCE);
        rewardToken.mint(address(vault), INITIAL_BALANCE);

        // Approve vault
        vm.prank(alice);
        vaultToken.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        vaultToken.approve(address(vault), type(uint256).max);
    }

    function test_Initialization() public view {
        assertEq(vault.vaultToken(), address(vaultToken));
        assertEq(vault.rewardToken(), address(rewardToken));
        assertEq(vault.owner(), owner);
    }

    function test_Deposit() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount);

        assertTrue(shares > 0);
        assertEq(vaultToken.balanceOf(alice), INITIAL_BALANCE - depositAmount);
    }

    function test_DepositZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(0);
    }

    function test_GetPendingRewards() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        vault.deposit(depositAmount);

        // Fast forward 100 seconds
        vm.warp(block.timestamp + 100);

        uint256 pending = vault.getPendingRewards(alice);
        assertTrue(pending > 0);
    }

    function test_EmergencyMode() public {
        bytes32 reason = keccak256("Test emergency");

        // Activate emergency
        vault.activateEmergency(reason);
        assertTrue(vault.isEmergencyActive());

        // Deactivate emergency
        vault.deactivateEmergency();
        assertFalse(vault.isEmergencyActive());
    }

    function test_OnlyOwnerCanActivateEmergency() public {
        bytes32 reason = keccak256("Test emergency");

        vm.prank(alice);
        vm.expectRevert(DeFiVault.Unauthorized.selector);
        vault.activateEmergency(reason);
    }

    function test_Blacklist() public {
        vault.addToBlacklist(alice);
        assertTrue(vault.isBlacklisted(alice));

        vault.removeFromBlacklist(alice);
        assertFalse(vault.isBlacklisted(alice));
    }

    function test_BlacklistBlocksDeposit() public {
        uint256 depositAmount = 1000e18;

        vault.addToBlacklist(alice);

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(depositAmount);
    }

    function test_CreateRefund() public {
        bytes32 reason = keccak256("Failed tx");
        uint256 refundAmount = 100e18;

        // Fund vault with ETH
        vm.deal(address(vault), 10 ether);

        bytes32 refundId = vault.createRefund(
            alice,
            address(0), // ETH refund
            refundAmount,
            reason
        );

        assertTrue(refundId != bytes32(0));
    }

    function test_RateLimiting() public {
        uint256 depositAmount = 100e18;

        // Make 100 deposits (at the limit)
        for (uint i = 0; i < 100; i++) {
            vm.prank(alice);
            vault.deposit(depositAmount);
        }

        // 101st deposit should be rate limited
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(depositAmount);
    }

    function test_GetNonce() public view {
        uint256 nonce = vault.getNonce(alice);
        assertEq(nonce, 0);
    }

    function test_GetRemainingDeposits() public view {
        uint256 remaining = vault.getRemainingDeposits();
        assertEq(remaining, 100); // Initial limit
    }

    function test_ReceiveETH() public {
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        (bool success,) = address(vault).call{value: 1 ether}("");
        assertTrue(success);
    }

    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 1e15 && amount <= INITIAL_BALANCE);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount);

        assertTrue(shares > 0);
    }
}

/*//////////////////////////////////////////////////////////////
                    SECURITY MANAGER TESTS
//////////////////////////////////////////////////////////////*/

contract SecurityManagerTest is Test {
    SecurityManager public security;

    address public admin;
    address public guardian1 = address(0x10);
    address public guardian2 = address(0x20);
    address public operator = address(0x30);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    function setUp() public {
        admin = address(this);

        address[] memory guardians = new address[](2);
        guardians[0] = guardian1;
        guardians[1] = guardian2;

        security = new SecurityManager(guardians);
    }

    function test_Initialization() public view {
        assertTrue(security.hasRole(ADMIN_ROLE, admin));
        assertTrue(security.hasRole(GUARDIAN_ROLE, guardian1));
        assertTrue(security.hasRole(GUARDIAN_ROLE, guardian2));
        assertEq(security.getRoleMemberCount(GUARDIAN_ROLE), 2);
    }

    function test_GrantRole() public {
        security.grantRole(OPERATOR_ROLE, operator);
        assertTrue(security.hasRole(OPERATOR_ROLE, operator));
    }

    function test_RevokeRole() public {
        security.grantRole(OPERATOR_ROLE, operator);
        security.revokeRole(OPERATOR_ROLE, operator);
        assertFalse(security.hasRole(OPERATOR_ROLE, operator));
    }

    function test_OnlyAdminCanGrantRole() public {
        vm.prank(guardian1);
        vm.expectRevert(SecurityManager.Unauthorized.selector);
        security.grantRole(OPERATOR_ROLE, operator);
    }

    function test_QueueOperation() public {
        bytes memory data = abi.encodeWithSignature("mockFunction()");

        bytes32 operationId = security.queueOperation(
            address(this),
            data,
            0,
            1 days
        );

        assertTrue(operationId != bytes32(0));

        SecurityManager.PendingOperation memory op = security.getOperation(operationId);
        assertEq(op.target, address(this));
        assertFalse(op.executed);
        assertFalse(op.cancelled);
    }

    function test_SignOperation() public {
        bytes memory data = abi.encodeWithSignature("mockFunction()");

        bytes32 operationId = security.queueOperation(
            address(this),
            data,
            0,
            1 days
        );

        vm.prank(guardian1);
        security.signOperation(operationId);

        assertEq(security.getSignatureCount(operationId), 1);

        vm.prank(guardian2);
        security.signOperation(operationId);

        assertEq(security.getSignatureCount(operationId), 2);
    }

    function test_CannotSignTwice() public {
        bytes memory data = abi.encodeWithSignature("mockFunction()");

        bytes32 operationId = security.queueOperation(
            address(this),
            data,
            0,
            1 days
        );

        vm.prank(guardian1);
        security.signOperation(operationId);

        vm.prank(guardian1);
        vm.expectRevert(SecurityManager.AlreadySigned.selector);
        security.signOperation(operationId);
    }

    function test_CancelOperation() public {
        bytes memory data = abi.encodeWithSignature("mockFunction()");

        bytes32 operationId = security.queueOperation(
            address(this),
            data,
            0,
            1 days
        );

        security.cancelOperation(operationId);

        SecurityManager.PendingOperation memory op = security.getOperation(operationId);
        assertTrue(op.cancelled);
    }

    function test_EmergencyModeGuardianOnly() public {
        bytes32 reason = keccak256("Emergency test");

        vm.prank(guardian1);
        security.activateEmergency(reason);

        assertTrue(security.isEmergencyActive());
    }

    function test_DeactivateEmergencyAdminOnly() public {
        bytes32 reason = keccak256("Emergency test");

        vm.prank(guardian1);
        security.activateEmergency(reason);

        // Guardian cannot deactivate
        vm.prank(guardian1);
        vm.expectRevert(SecurityManager.Unauthorized.selector);
        security.deactivateEmergency();

        // Admin can deactivate
        security.deactivateEmergency();
        assertFalse(security.isEmergencyActive());
    }

    function test_Blacklist() public {
        security.blacklist(operator);
        assertTrue(security.isBlacklisted(operator));

        security.removeFromBlacklist(operator);
        assertFalse(security.isBlacklisted(operator));
    }

    function test_BlacklistRevokesRoles() public {
        security.grantRole(OPERATOR_ROLE, operator);
        assertTrue(security.hasRole(OPERATOR_ROLE, operator));

        security.blacklist(operator);

        assertFalse(security.hasRole(OPERATOR_ROLE, operator));
    }

    function test_RegisterProtocol() public {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("swap(address,uint256)"));
        selectors[1] = bytes4(keccak256("addLiquidity(uint256,uint256)"));

        bytes32 protocolId = security.registerProtocol(
            address(0x100),
            keccak256("TestDEX"),
            8000,
            selectors
        );

        assertTrue(protocolId != bytes32(0));
    }

    function test_UpdateProtocolTrustScore() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("test()"));

        bytes32 protocolId = security.registerProtocol(
            address(0x100),
            keccak256("Test"),
            5000,
            selectors
        );

        security.updateProtocolTrustScore(protocolId, 9000);

        SynergyLib.Protocol memory protocol = security.getProtocolInfo(protocolId);
        assertEq(protocol.trustScore, 9000);
    }

    function test_ManipulationCheck() public view {
        // Small change should be safe
        bool safe = security.checkManipulation(1000, 1040); // 4%
        assertTrue(safe);

        // Large change should not be safe
        safe = security.checkManipulation(1000, 1100); // 10%
        assertFalse(safe);
    }

    function test_GetNonce() public view {
        uint256 nonce = security.getNonce(admin);
        assertEq(nonce, 0);
    }

    function test_RateLimiting() public {
        bytes memory data = abi.encodeWithSignature("mockFunction()");

        // Make 10 queue operations (at the limit)
        for (uint i = 0; i < 10; i++) {
            security.queueOperation(
                address(this),
                data,
                0,
                1 days
            );
        }

        // 11th should be rate limited
        vm.expectRevert();
        security.queueOperation(
            address(this),
            data,
            0,
            1 days
        );
    }

    function test_InvalidDelayReverts() public {
        bytes memory data = abi.encodeWithSignature("mockFunction()");

        // Too short delay
        vm.expectRevert(SecurityManager.InvalidDelay.selector);
        security.queueOperation(
            address(this),
            data,
            0,
            1 hours // Below MIN_DELAY (1 day)
        );

        // Too long delay
        vm.expectRevert(SecurityManager.InvalidDelay.selector);
        security.queueOperation(
            address(this),
            data,
            0,
            60 days // Above MAX_DELAY (30 days)
        );
    }

    function test_ReceiveETH() public {
        vm.deal(admin, 1 ether);
        (bool success,) = address(security).call{value: 1 ether}("");
        assertTrue(success);
    }
}

/*//////////////////////////////////////////////////////////////
                    STAKING REWARDS HUB TESTS
//////////////////////////////////////////////////////////////*/

contract StakingRewardsHubTest is Test {
    StakingRewardsHub public hub;
    MockERC20 public stakingToken;
    MockERC20 public rewardToken;

    address public owner;
    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 constant REWARD_RATE = 1e18;
    uint256 constant INITIAL_BALANCE = 1000000e18;

    function setUp() public {
        owner = address(this);

        // Deploy tokens
        stakingToken = new MockERC20("Staking Token", "STK");
        rewardToken = new MockERC20("Reward Token", "RWD");

        // Deploy hub
        hub = new StakingRewardsHub();

        // Setup balances
        stakingToken.mint(alice, INITIAL_BALANCE);
        stakingToken.mint(bob, INITIAL_BALANCE);
        rewardToken.mint(address(hub), INITIAL_BALANCE);
    }

    function test_Initialization() public view {
        assertEq(hub.owner(), owner);
        assertEq(hub.poolCount(), 0);
        assertFalse(hub.paused());
    }

    function test_CreatePool() public {
        uint256 poolId = hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            type(uint256).max
        );

        assertEq(poolId, 0);
        assertEq(hub.poolCount(), 1);
        assertEq(hub.poolTokens(poolId), address(stakingToken));
    }

    function test_OnlyOwnerCanCreatePool() public {
        vm.prank(alice);
        vm.expectRevert(StakingRewardsHub.Unauthorized.selector);
        hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            0
        );
    }

    function test_Stake() public {
        uint256 poolId = hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            0
        );

        uint256 stakeAmount = 1000e18;

        vm.startPrank(alice);
        stakingToken.approve(address(hub), type(uint256).max);
        uint256 shares = hub.stake(poolId, stakeAmount);
        vm.stopPrank();

        assertTrue(shares > 0);
    }

    function test_StakeZeroReverts() public {
        uint256 poolId = hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            0
        );

        vm.prank(alice);
        vm.expectRevert();
        hub.stake(poolId, 0);
    }

    function test_StakeWithLock() public {
        uint256 poolId = hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            0
        );

        uint256 stakeAmount = 1000e18;
        uint256 lockDuration = 30 days;

        vm.startPrank(alice);
        stakingToken.approve(address(hub), type(uint256).max);
        uint256 shares = hub.stakeWithLock(poolId, stakeAmount, lockDuration);
        vm.stopPrank();

        assertTrue(shares > 0);

        // Check multiplier boost
        uint256 multiplier = hub.getUserMultiplier(alice);
        assertTrue(multiplier >= 1e18);
    }

    function test_GetPendingRewards() public {
        uint256 poolId = hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            0
        );

        uint256 stakeAmount = 1000e18;

        vm.startPrank(alice);
        stakingToken.approve(address(hub), type(uint256).max);
        hub.stake(poolId, stakeAmount);
        vm.stopPrank();

        // Fast forward
        vm.warp(block.timestamp + 100);

        uint256 pending = hub.getPendingRewards(poolId, alice);
        assertTrue(pending > 0);
    }

    function test_UserTierProgression() public {
        uint256 poolId = hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            0
        );

        // Initial tier is 0
        assertEq(hub.getUserTier(alice), 0);

        // Stake to reach silver tier (1000 tokens)
        uint256 silverAmount = 1000e18;
        vm.startPrank(alice);
        stakingToken.approve(address(hub), type(uint256).max);
        hub.stake(poolId, silverAmount);
        vm.stopPrank();

        assertEq(hub.getUserTier(alice), 1); // Silver tier
    }

    function test_CreateVesting() public {
        uint256 vestAmount = 10000e18;
        uint256 cliffDuration = 30 days;
        uint256 vestingDuration = 365 days;

        hub.createVesting(alice, vestAmount, cliffDuration, vestingDuration);

        // Before cliff, nothing vested
        assertEq(hub.getVestedAmount(alice), 0);

        // After cliff
        vm.warp(block.timestamp + cliffDuration + 1);
        assertTrue(hub.getVestedAmount(alice) > 0);
    }

    function test_GetClaimableVested() public {
        uint256 vestAmount = 10000e18;
        uint256 cliffDuration = 30 days;
        uint256 vestingDuration = 365 days;

        hub.createVesting(alice, vestAmount, cliffDuration, vestingDuration);

        // Before cliff
        assertEq(hub.getClaimableVested(alice), 0);

        // After cliff + some time
        vm.warp(block.timestamp + cliffDuration + 30 days);
        assertTrue(hub.getClaimableVested(alice) > 0);
    }

    function test_Pause() public {
        hub.pause();
        assertTrue(hub.paused());

        hub.unpause();
        assertFalse(hub.paused());
    }

    function test_PauseBlocksStaking() public {
        uint256 poolId = hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            0
        );

        hub.pause();

        vm.startPrank(alice);
        stakingToken.approve(address(hub), type(uint256).max);
        vm.expectRevert(StakingRewardsHub.Paused.selector);
        hub.stake(poolId, 1000e18);
        vm.stopPrank();
    }

    function test_TransferOwnership() public {
        hub.transferOwnership(alice);
        assertEq(hub.owner(), alice);
    }

    function test_GetPoolAPR() public {
        uint256 poolId = hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            0
        );

        // Stake some tokens first
        vm.startPrank(alice);
        stakingToken.approve(address(hub), type(uint256).max);
        hub.stake(poolId, 1000e18);
        vm.stopPrank();

        uint256 apr = hub.getPoolAPR(poolId);
        assertTrue(apr > 0);
    }

    function test_CalculateLockBoost() public view {
        uint256 boost30days = hub.calculateLockBoost(30 days);
        uint256 boost365days = hub.calculateLockBoost(365 days);

        assertTrue(boost365days > boost30days);
    }

    function test_GetCurrentEpoch() public view {
        uint256 epoch = hub.getCurrentEpoch();
        assertEq(epoch, 0);
    }

    function test_GetTierInfo() public view {
        RewardLib.RewardTier memory tier0 = hub.getTierInfo(0);
        assertEq(tier0.minStake, 0);
        assertEq(tier0.multiplierBps, 10000);
    }

    function test_InvalidPoolReverts() public {
        vm.expectRevert(StakingRewardsHub.InvalidPool.selector);
        hub.getPendingRewards(999, alice);
    }

    function testFuzz_Stake(uint256 amount) public {
        vm.assume(amount > 1e15 && amount <= INITIAL_BALANCE);

        uint256 poolId = hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            0
        );

        vm.startPrank(alice);
        stakingToken.approve(address(hub), type(uint256).max);
        uint256 shares = hub.stake(poolId, amount);
        vm.stopPrank();

        assertTrue(shares > 0);
    }

    function testFuzz_LockDuration(uint256 duration) public {
        vm.assume(duration >= 7 days && duration <= 4 * 365 days);

        uint256 poolId = hub.createPool(
            address(stakingToken),
            address(rewardToken),
            REWARD_RATE,
            0
        );

        vm.startPrank(alice);
        stakingToken.approve(address(hub), type(uint256).max);
        uint256 shares = hub.stakeWithLock(poolId, 1000e18, duration);
        vm.stopPrank();

        assertTrue(shares > 0);
    }
}

/*//////////////////////////////////////////////////////////////
                    GAS BENCHMARK TESTS
//////////////////////////////////////////////////////////////*/

contract ExampleGasBenchmarkTest is Test {
    DeFiVault public vault;
    SecurityManager public security;
    StakingRewardsHub public hub;
    MockERC20 public token;

    function setUp() public {
        token = new MockERC20("Test", "TEST");

        // Deploy vault
        MockERC20 rewardToken = new MockERC20("Reward", "RWD");
        vault = new DeFiVault(address(token), address(rewardToken), 1e18);

        // Deploy security
        address[] memory guardians = new address[](2);
        guardians[0] = address(0x10);
        guardians[1] = address(0x20);
        security = new SecurityManager(guardians);

        // Deploy hub
        hub = new StakingRewardsHub();

        // Setup
        token.mint(address(this), 1000000e18);
        token.approve(address(vault), type(uint256).max);
        token.approve(address(hub), type(uint256).max);
        rewardToken.mint(address(vault), 1000000e18);
    }

    function test_Gas_VaultDeposit() public {
        uint256 gasBefore = gasleft();
        vault.deposit(1000e18);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Vault deposit gas", gasUsed);
    }

    function test_Gas_SecurityQueueOperation() public {
        bytes memory data = abi.encodeWithSignature("test()");

        uint256 gasBefore = gasleft();
        security.queueOperation(address(this), data, 0, 1 days);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Security queue operation gas", gasUsed);
    }

    function test_Gas_HubCreatePool() public {
        MockERC20 rewardToken = new MockERC20("Reward", "RWD");

        uint256 gasBefore = gasleft();
        hub.createPool(address(token), address(rewardToken), 1e18, 0);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Hub create pool gas", gasUsed);
    }

    function test_Gas_HubStake() public {
        MockERC20 rewardToken = new MockERC20("Reward", "RWD");
        uint256 poolId = hub.createPool(address(token), address(rewardToken), 1e18, 0);

        uint256 gasBefore = gasleft();
        hub.stake(poolId, 1000e18);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Hub stake gas", gasUsed);
    }
}
