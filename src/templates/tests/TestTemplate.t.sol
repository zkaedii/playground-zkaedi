// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/**
 * @title TestTemplate
 * @notice Foundry test template with common patterns and helpers
 * @dev Copy this template and customize for your contract tests
 *
 * TEMPLATE INSTRUCTIONS:
 * 1. Update the import to your contract
 * 2. Rename the test contract
 * 3. Add your test cases following the patterns below
 * 4. Use the provided helper functions
 */

// TODO: Import your contract
// import {MyContract} from "../src/MyContract.sol";

contract TestTemplate is Test {
    // ============ CONSTANTS ============
    address constant ADMIN = address(0x1);
    address constant USER1 = address(0x2);
    address constant USER2 = address(0x3);
    address constant FEE_RECIPIENT = address(0x4);

    uint256 constant INITIAL_BALANCE = 1000 ether;
    uint256 constant DEFAULT_AMOUNT = 100 ether;

    // ============ STATE ============
    // TODO: Declare your contract instance
    // MyContract public myContract;

    // Mock tokens for testing
    MockERC20 public token;
    MockERC20 public rewardToken;

    // ============ EVENTS ============
    // TODO: Redeclare events from your contract for expectEmit
    // event Transfer(address indexed from, address indexed to, uint256 value);

    // ============ SETUP ============

    function setUp() public virtual {
        // Label addresses for better trace output
        vm.label(ADMIN, "Admin");
        vm.label(USER1, "User1");
        vm.label(USER2, "User2");
        vm.label(FEE_RECIPIENT, "FeeRecipient");

        // Deploy mock tokens
        token = new MockERC20("Mock Token", "MTK", 18);
        rewardToken = new MockERC20("Reward Token", "RWD", 18);

        // Mint tokens to test accounts
        token.mint(ADMIN, INITIAL_BALANCE);
        token.mint(USER1, INITIAL_BALANCE);
        token.mint(USER2, INITIAL_BALANCE);

        // TODO: Deploy your contract
        // vm.prank(ADMIN);
        // myContract = new MyContract(ADMIN, address(token));

        // TODO: Setup approvals if needed
        // vm.prank(USER1);
        // token.approve(address(myContract), type(uint256).max);
    }

    // ============ DEPLOYMENT TESTS ============

    function test_Deployment() public view {
        // TODO: Test initial state
        // assertEq(myContract.owner(), ADMIN);
        // assertEq(address(myContract.token()), address(token));
    }

    function test_RevertWhen_DeployWithZeroAddress() public {
        // TODO: Test deployment reverts
        // vm.expectRevert(MyContract.ZeroAddress.selector);
        // new MyContract(address(0), address(token));
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_OnlyAdminCanCall() public {
        // TODO: Test admin-only functions
        // vm.prank(USER1);
        // vm.expectRevert(MyContract.Unauthorized.selector);
        // myContract.adminFunction();
    }

    function test_AdminCanGrantRole() public {
        // TODO: Test role granting
        // vm.prank(ADMIN);
        // myContract.grantRole(OPERATOR_ROLE, USER1);
        // assertTrue(myContract.hasRole(OPERATOR_ROLE, USER1));
    }

    // ============ CORE FUNCTIONALITY TESTS ============

    function test_BasicOperation() public {
        // TODO: Test basic operation
        // vm.prank(USER1);
        // myContract.deposit(DEFAULT_AMOUNT);
        // assertEq(myContract.balanceOf(USER1), DEFAULT_AMOUNT);
    }

    function test_RevertWhen_InvalidInput() public {
        // TODO: Test invalid inputs
        // vm.prank(USER1);
        // vm.expectRevert(MyContract.ZeroAmount.selector);
        // myContract.deposit(0);
    }

    // ============ EVENT TESTS ============

    function test_EmitsEvent() public {
        // TODO: Test event emission
        // vm.expectEmit(true, true, false, true);
        // emit Transfer(USER1, USER2, DEFAULT_AMOUNT);
        //
        // vm.prank(USER1);
        // myContract.transfer(USER2, DEFAULT_AMOUNT);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_Deposit(uint256 amount) public {
        // Bound the fuzz input to reasonable values
        amount = bound(amount, 1, INITIAL_BALANCE);

        // TODO: Fuzz test
        // vm.prank(USER1);
        // myContract.deposit(amount);
        // assertEq(myContract.balanceOf(USER1), amount);
    }

    function testFuzz_Transfer(address to, uint256 amount) public {
        // Exclude invalid addresses
        vm.assume(to != address(0));
        vm.assume(to != USER1);
        amount = bound(amount, 1, INITIAL_BALANCE);

        // TODO: Fuzz test transfers
    }

    // ============ INVARIANT TESTS ============

    // function invariant_TotalSupplyMatchesBalances() public {
    //     uint256 totalBalances = myContract.balanceOf(USER1) + myContract.balanceOf(USER2);
    //     assertEq(myContract.totalSupply(), totalBalances);
    // }

    // ============ GAS TESTS ============

    function test_GasDeposit() public {
        // vm.prank(USER1);
        // uint256 gasBefore = gasleft();
        // myContract.deposit(DEFAULT_AMOUNT);
        // uint256 gasUsed = gasBefore - gasleft();
        // emit log_named_uint("Gas used for deposit", gasUsed);
    }

    // ============ INTEGRATION TESTS ============

    function test_FullWorkflow() public {
        // Test complete user journey
        // 1. User deposits
        // vm.prank(USER1);
        // myContract.deposit(DEFAULT_AMOUNT);

        // 2. Time passes
        // vm.warp(block.timestamp + 1 days);

        // 3. User claims rewards
        // vm.prank(USER1);
        // myContract.claimRewards();

        // 4. User withdraws
        // vm.prank(USER1);
        // myContract.withdraw(DEFAULT_AMOUNT);
    }

    // ============ EDGE CASE TESTS ============

    function test_MaxValues() public {
        // Test with maximum values
        // uint256 maxAmount = type(uint256).max;
    }

    function test_MinValues() public {
        // Test with minimum values
        // uint256 minAmount = 1;
    }

    function test_BoundaryConditions() public {
        // Test boundary conditions
        // myContract.setLimit(100);
        // assertEq(myContract.deposit(100), true); // exactly at limit
        // vm.expectRevert();
        // myContract.deposit(101); // just over limit
    }

    // ============ REENTRANCY TESTS ============

    function test_ReentrancyProtection() public {
        // Deploy attacker contract
        // ReentrancyAttacker attacker = new ReentrancyAttacker(address(myContract));
        // token.mint(address(attacker), INITIAL_BALANCE);

        // Attempt reentrancy attack
        // vm.expectRevert();
        // attacker.attack();
    }

    // ============ PAUSE TESTS ============

    function test_Pause() public {
        // vm.prank(ADMIN);
        // myContract.pause();

        // vm.prank(USER1);
        // vm.expectRevert(MyContract.Paused.selector);
        // myContract.deposit(DEFAULT_AMOUNT);
    }

    function test_Unpause() public {
        // vm.startPrank(ADMIN);
        // myContract.pause();
        // myContract.unpause();
        // vm.stopPrank();

        // vm.prank(USER1);
        // myContract.deposit(DEFAULT_AMOUNT); // Should work
    }

    // ============ HELPER FUNCTIONS ============

    function _depositAs(address user, uint256 amount) internal {
        vm.prank(user);
        // myContract.deposit(amount);
    }

    function _approveAndDeposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        // token.approve(address(myContract), amount);
        // myContract.deposit(amount);
        vm.stopPrank();
    }

    function _skipTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    function _skipBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }

    function _expectRevertWithMessage(string memory message) internal {
        vm.expectRevert(bytes(message));
    }
}

// ============ MOCK CONTRACTS ============

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @title MockOracle
 * @notice Mock price oracle for testing
 */
contract MockOracle {
    mapping(address => uint256) public prices;
    mapping(address => uint256) public timestamps;

    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
        timestamps[asset] = block.timestamp;
    }

    function getPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }

    function getLatestRoundData(address asset) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, int256(prices[asset]), timestamps[asset], timestamps[asset], 1);
    }
}

/**
 * @title ReentrancyAttacker
 * @notice Mock contract for testing reentrancy protection
 */
contract ReentrancyAttacker {
    address public target;
    bool public attacking;

    constructor(address _target) {
        target = _target;
    }

    function attack() external {
        attacking = true;
        // Call vulnerable function
        // ITarget(target).withdraw(amount);
    }

    receive() external payable {
        if (attacking) {
            // Attempt reentrant call
            // ITarget(target).withdraw(amount);
        }
    }
}

// ============ FORK TESTS TEMPLATE ============

contract ForkTestTemplate is Test {
    // For mainnet fork tests
    uint256 mainnetFork;

    // Known mainnet addresses
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public {
        // Create fork from RPC URL
        // mainnetFork = vm.createFork(vm.envString("ETH_RPC_URL"));
        // vm.selectFork(mainnetFork);

        // Or fork at specific block
        // mainnetFork = vm.createFork(vm.envString("ETH_RPC_URL"), 18000000);
    }

    function test_ForkInteraction() public {
        // Test against real mainnet state
        // uint256 wethBalance = IERC20(WETH).balanceOf(someWhale);
    }
}

// ============ STATEFUL FUZZ TEST TEMPLATE ============

contract StatefulFuzzTest is Test {
    // Target contract
    // MyContract public target;

    // Ghost variables for invariant tracking
    uint256 public ghost_totalDeposits;
    uint256 public ghost_totalWithdrawals;

    function setUp() public {
        // Deploy target
        // target = new MyContract();

        // Set target contract for invariant testing
        // targetContract(address(target));
    }

    // Handler function called by fuzzer
    function deposit(uint256 amount) public {
        amount = bound(amount, 1, 1e24);
        // target.deposit(amount);
        ghost_totalDeposits += amount;
    }

    // Handler function called by fuzzer
    function withdraw(uint256 amount) public {
        // uint256 balance = target.balanceOf(msg.sender);
        // amount = bound(amount, 0, balance);
        // target.withdraw(amount);
        ghost_totalWithdrawals += amount;
    }

    // Invariant: total supply should equal deposits minus withdrawals
    function invariant_accounting() public view {
        // assertEq(target.totalSupply(), ghost_totalDeposits - ghost_totalWithdrawals);
    }
}
