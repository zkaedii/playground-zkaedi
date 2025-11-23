// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/UUPSTokenV3.sol";

contract UUPSTokenV3Test is Test {
    UUPSTokenV3 public implementation;
    UUPSTokenV3 public token;
    ERC1967Proxy public proxy;

    address public owner;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    string constant NAME = "UUPS Token V3";
    string constant SYMBOL = "UUPSV3";
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 constant MAX_SUPPLY = 10_000_000 * 1e18;
    uint16 constant BURN_RATE = 50; // 0.5%

    function setUp() public {
        owner = address(this);

        // Deploy implementation
        implementation = new UUPSTokenV3();

        // Encode initializer
        bytes memory initData = abi.encodeCall(
            UUPSTokenV3.initializeV3,
            (NAME, SYMBOL, INITIAL_SUPPLY, MAX_SUPPLY, BURN_RATE)
        );

        // Deploy proxy
        proxy = new ERC1967Proxy(address(implementation), initData);
        token = UUPSTokenV3(address(proxy));
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialization() public view {
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.maxSupply(), MAX_SUPPLY);
        assertEq(token.burnRate(), BURN_RATE);
        assertEq(token.owner(), owner);
        assertEq(token.version(), "3.0.0");
    }

    function test_OwnerIsWhitelisted() public view {
        (uint8 flags, , bool isWhitelisted) = token.accountData(owner);
        assertTrue(isWhitelisted);
        assertEq(flags & 1, 1); // FLAG_WHITELISTED = 1
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER WITH BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferWithBurn() public {
        uint256 amount = 10_000 * 1e18;

        // Owner transfers to Alice (owner whitelisted, no burn)
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);

        // Alice transfers to Bob (should burn 0.5%)
        vm.prank(alice);
        token.transfer(bob, amount);

        uint256 expectedBurn = (amount * BURN_RATE) / 10000; // 50 tokens
        uint256 expectedReceived = amount - expectedBurn;

        assertEq(token.balanceOf(bob), expectedReceived);
        assertEq(token.totalBurned(), expectedBurn);
    }

    function test_WhitelistedTransferNoBurn() public {
        uint256 amount = 10_000 * 1e18;

        // Whitelist Alice
        token.setAccountFlag(alice, 1, true); // FLAG_WHITELISTED

        token.transfer(alice, amount);

        vm.prank(alice);
        token.transfer(bob, amount);

        // No burn because Alice is whitelisted
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalBurned(), 0);
    }

    function test_PreviewTransfer() public {
        uint256 amount = 10_000 * 1e18;
        token.transfer(alice, amount);

        (uint256 netAmount, uint256 burnAmount, ) = token.previewTransfer(alice, bob, amount);

        assertEq(burnAmount, (amount * BURN_RATE) / 10000);
        assertEq(netAmount, amount - burnAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        DYNAMIC BURN RATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EffectiveBurnRateDecays() public {
        // Enable decay
        token.setConfigFlag(4, true); // FLAG_DECAY_ENABLED = 4

        uint16 initialRate = token.effectiveBurnRate();
        assertEq(initialRate, BURN_RATE);

        // Fast forward 6 months
        vm.warp(block.timestamp + 182 days);

        uint16 decayedRate = token.effectiveBurnRate();
        assertTrue(decayedRate < initialRate);

        // Fast forward 2 years (should be ~0)
        vm.warp(block.timestamp + 730 days);
        uint16 finalRate = token.effectiveBurnRate();
        assertEq(finalRate, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        FLASH LOAN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FlashLoanFee() public view {
        uint256 amount = 100_000 * 1e18;
        uint256 fee = token.flashFee(amount);

        // 0.1% fee = 100 tokens
        assertEq(fee, (amount * 10) / 10000);
    }

    function test_MaxFlashLoan() public view {
        uint256 maxLoan = token.maxFlashLoan();
        assertEq(maxLoan, MAX_SUPPLY - INITIAL_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                    HOLDING REWARDS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_HoldingRewardAccrues() public {
        uint256 amount = 100_000 * 1e18;
        token.transfer(alice, amount);

        // Fast forward 7 days (7 epochs)
        vm.warp(block.timestamp + 7 days);

        uint256 pending = token.pendingReward(alice);

        // 7 epochs * 0.5% * balance / 10000
        uint256 expectedReward = (amount * 50 * 7) / 10000 / 10000;
        assertEq(pending, expectedReward);
    }

    function test_ClaimHoldingReward() public {
        uint256 amount = 100_000 * 1e18;
        token.transfer(alice, amount);

        vm.warp(block.timestamp + 7 days);

        uint256 pendingBefore = token.pendingReward(alice);
        uint256 balanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        uint256 claimed = token.claimHoldingReward();

        assertEq(claimed, pendingBefore);
        assertEq(token.balanceOf(alice), balanceBefore + claimed);

        // Pending should reset to 0
        assertEq(token.pendingReward(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    MERKLE CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetMerkleRoot() public {
        bytes32 root = keccak256("test_root");
        token.setMerkleRoot(1, root);

        assertEq(token.merkleRoots(1), root);
    }

    function test_MerkleClaim() public {
        // Create a simple merkle tree with single leaf
        uint256 claimAmount = 1000 * 1e18;
        bytes32 leaf = keccak256(abi.encodePacked(uint256(0), alice, claimAmount));
        bytes32 root = leaf; // Single leaf tree

        token.setMerkleRoot(1, root);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        token.merkleClaim(1, 0, claimAmount, proof);

        assertEq(token.balanceOf(alice), claimAmount);
        assertTrue(token.isClaimed(1, 0));
    }

    function test_CannotClaimTwice() public {
        uint256 claimAmount = 1000 * 1e18;
        bytes32 leaf = keccak256(abi.encodePacked(uint256(0), alice, claimAmount));
        token.setMerkleRoot(1, leaf);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        token.merkleClaim(1, 0, claimAmount, proof);

        vm.prank(alice);
        vm.expectRevert(UUPSTokenV3.AlreadyClaimed.selector);
        token.merkleClaim(1, 0, claimAmount, proof);
    }

    /*//////////////////////////////////////////////////////////////
                    COMMIT-REVEAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CommitReveal() public {
        bytes memory data = abi.encode("test_action");
        bytes32 salt = keccak256("secret_salt");
        bytes32 commitHash = keccak256(abi.encodePacked(data, salt));

        // Commit
        vm.prank(alice);
        token.commit(commitHash);

        // Cannot reveal too early
        vm.prank(alice);
        vm.expectRevert(UUPSTokenV3.CooldownActive.selector);
        token.reveal(data, salt);

        // Fast forward past commit window
        vm.warp(block.timestamp + 2 hours);

        // Now can reveal
        vm.prank(alice);
        token.reveal(data, salt);
    }

    function test_CommitExpires() public {
        bytes memory data = abi.encode("test_action");
        bytes32 salt = keccak256("secret_salt");
        bytes32 commitHash = keccak256(abi.encodePacked(data, salt));

        vm.prank(alice);
        token.commit(commitHash);

        // Fast forward past reveal window
        vm.warp(block.timestamp + 25 hours);

        vm.prank(alice);
        vm.expectRevert(UUPSTokenV3.CommitExpired.selector);
        token.reveal(data, salt);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetBurnRate() public {
        token.setBurnRate(100); // 1%
        assertEq(token.burnRate(), 100);
    }

    function test_CannotSetInvalidBurnRate() public {
        vm.expectRevert(UUPSTokenV3.InvalidBPS.selector);
        token.setBurnRate(10001); // > 100%
    }

    function test_SetWhitelistBatch() public {
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = carol;

        token.setWhitelistBatch(accounts, true);

        (, , bool aliceWhitelisted) = token.accountData(alice);
        (, , bool bobWhitelisted) = token.accountData(bob);
        (, , bool carolWhitelisted) = token.accountData(carol);

        assertTrue(aliceWhitelisted);
        assertTrue(bobWhitelisted);
        assertTrue(carolWhitelisted);
    }

    function test_Pause() public {
        token.pause();
        assertTrue(token.paused());

        vm.expectRevert();
        token.transfer(alice, 100);

        token.unpause();
        assertFalse(token.paused());
    }

    /*//////////////////////////////////////////////////////////////
                        UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_OnlyOwnerCanUpgrade() public {
        UUPSTokenV3 newImpl = new UUPSTokenV3();

        vm.prank(alice);
        vm.expectRevert();
        token.upgradeToAndCall(address(newImpl), "");

        // Owner can upgrade
        token.upgradeToAndCall(address(newImpl), "");
    }

    function test_CannotUpgradeToZeroAddress() public {
        vm.expectRevert(UUPSTokenV3.InvalidAddress.selector);
        token.upgradeToAndCall(address(0), "");
    }

    /*//////////////////////////////////////////////////////////////
                        GAS BENCHMARKS
    //////////////////////////////////////////////////////////////*/

    function test_GasTransferWithBurn() public {
        token.transfer(alice, 10_000 * 1e18);

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        token.transfer(bob, 1000 * 1e18);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for transfer with burn", gasUsed);
        // Target: < 80,000 gas
    }

    function test_GasWhitelistedTransfer() public {
        token.setAccountFlag(alice, 1, true);
        token.transfer(alice, 10_000 * 1e18);

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        token.transfer(bob, 1000 * 1e18);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for whitelisted transfer", gasUsed);
        // Target: < 60,000 gas
    }

    function test_GasBatchWhitelist() public {
        address[] memory accounts = new address[](10);
        for (uint i = 0; i < 10; i++) {
            accounts[i] = address(uint160(i + 100));
        }

        uint256 gasBefore = gasleft();
        token.setWhitelistBatch(accounts, true);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for batch whitelist (10)", gasUsed);
        // Target: < 5,000 per address
    }
}

/*//////////////////////////////////////////////////////////////
                    V2 VS V3 GAS COMPARISON
//////////////////////////////////////////////////////////////*/

import "../src/UUPSTokenV2.sol";

contract GasComparisonTest is Test {
    UUPSTokenV2 public tokenV2;
    UUPSTokenV3 public tokenV3;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        // Deploy V2
        UUPSTokenV2 implV2 = new UUPSTokenV2();
        ERC1967Proxy proxyV2 = new ERC1967Proxy(
            address(implV2),
            abi.encodeCall(UUPSTokenV2.initializeV2, ("V2", "V2", 1_000_000e18, 50))
        );
        tokenV2 = UUPSTokenV2(address(proxyV2));

        // Deploy V3
        UUPSTokenV3 implV3 = new UUPSTokenV3();
        ERC1967Proxy proxyV3 = new ERC1967Proxy(
            address(implV3),
            abi.encodeCall(UUPSTokenV3.initializeV3, ("V3", "V3", 1_000_000e18, 10_000_000e18, 50))
        );
        tokenV3 = UUPSTokenV3(address(proxyV3));

        // Setup test accounts
        tokenV2.transfer(alice, 100_000e18);
        tokenV3.transfer(alice, 100_000e18);
    }

    function test_CompareTransferGas() public {
        // V2 Transfer
        vm.prank(alice);
        uint256 gasV2Before = gasleft();
        tokenV2.transfer(bob, 10_000e18);
        uint256 gasV2 = gasV2Before - gasleft();

        // V3 Transfer
        vm.prank(alice);
        uint256 gasV3Before = gasleft();
        tokenV3.transfer(bob, 10_000e18);
        uint256 gasV3 = gasV3Before - gasleft();

        emit log_named_uint("V2 transfer gas", gasV2);
        emit log_named_uint("V3 transfer gas", gasV3);
        emit log_named_int("Gas savings", int256(gasV2) - int256(gasV3));
    }

    function test_CompareWhitelistGas() public {
        // V2 Whitelist
        uint256 gasV2Before = gasleft();
        tokenV2.setWhitelist(alice, true);
        uint256 gasV2 = gasV2Before - gasleft();

        // V3 Whitelist
        uint256 gasV3Before = gasleft();
        tokenV3.setAccountFlag(alice, 1, true);
        uint256 gasV3 = gasV3Before - gasleft();

        emit log_named_uint("V2 whitelist gas", gasV2);
        emit log_named_uint("V3 whitelist gas", gasV3);
        emit log_named_int("Gas savings", int256(gasV2) - int256(gasV3));
    }

    function test_CompareBatchWhitelistGas() public {
        address[] memory accounts = new address[](5);
        for (uint i = 0; i < 5; i++) {
            accounts[i] = address(uint160(i + 200));
        }

        // V2 Batch
        uint256 gasV2Before = gasleft();
        tokenV2.setWhitelistBatch(accounts, true);
        uint256 gasV2 = gasV2Before - gasleft();

        // V3 Batch
        uint256 gasV3Before = gasleft();
        tokenV3.setWhitelistBatch(accounts, true);
        uint256 gasV3 = gasV3Before - gasleft();

        emit log_named_uint("V2 batch whitelist gas (5)", gasV2);
        emit log_named_uint("V3 batch whitelist gas (5)", gasV3);
        emit log_named_int("Gas savings", int256(gasV2) - int256(gasV3));
    }
}
