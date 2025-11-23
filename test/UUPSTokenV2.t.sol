// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/UUPSTokenV2.sol";

contract UUPSTokenV2Test is Test {
    UUPSTokenV2 public implementation;
    UUPSTokenV2 public token;
    ERC1967Proxy public proxy;

    address public owner = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    string constant NAME = "UUPS Token";
    string constant SYMBOL = "UUPS";
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 constant BURN_RATE = 50; // 0.5%

    function setUp() public {
        // Deploy implementation
        implementation = new UUPSTokenV2();

        // Encode initializer
        bytes memory initData = abi.encodeCall(
            UUPSTokenV2.initializeV2,
            (NAME, SYMBOL, INITIAL_SUPPLY, BURN_RATE)
        );

        // Deploy proxy
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Get token interface
        token = UUPSTokenV2(address(proxy));
    }

    function test_Initialization() public view {
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.burnRate(), BURN_RATE);
        assertEq(token.owner(), owner);
        assertTrue(token.isWhitelisted(owner));
    }

    function test_Version() public view {
        assertEq(token.version(), "2.0.0");
    }

    function test_TransferWithBurn() public {
        uint256 transferAmount = 1000 * 1e18;
        uint256 expectedBurn = (transferAmount * BURN_RATE) / 10000; // 5 tokens
        uint256 expectedReceived = transferAmount - expectedBurn;

        // Transfer to alice (owner is whitelisted, so no burn from owner)
        token.transfer(alice, transferAmount);
        assertEq(token.balanceOf(alice), transferAmount);

        // Alice transfers to bob (should burn 0.5%)
        vm.prank(alice);
        token.transfer(bob, transferAmount);

        assertEq(token.balanceOf(bob), expectedReceived);
        assertEq(token.totalBurned(), expectedBurn);
    }

    function test_WhitelistExemptFromBurn() public {
        uint256 transferAmount = 1000 * 1e18;

        // Whitelist alice
        token.setWhitelist(alice, true);

        // Transfer to alice
        token.transfer(alice, transferAmount);

        // Alice transfers to bob - no burn because alice is whitelisted
        vm.prank(alice);
        token.transfer(bob, transferAmount);

        assertEq(token.balanceOf(bob), transferAmount);
        assertEq(token.totalBurned(), 0);
    }

    function test_SetBurnRate() public {
        uint256 newRate = 100; // 1%
        token.setBurnRate(newRate);
        assertEq(token.burnRate(), newRate);
    }

    function test_RevertBurnRateTooHigh() public {
        vm.expectRevert("Burn rate too high");
        token.setBurnRate(1001); // > 10%
    }

    function test_Pause() public {
        token.pause();
        assertTrue(token.paused());

        vm.expectRevert();
        token.transfer(alice, 100);

        token.unpause();
        assertFalse(token.paused());
    }

    function test_CalculateTransferAmounts() public view {
        uint256 amount = 1000 * 1e18;
        (uint256 netAmount, uint256 burnAmount) = token.calculateTransferAmounts(amount, alice, bob);

        assertEq(burnAmount, (amount * BURN_RATE) / 10000);
        assertEq(netAmount, amount - burnAmount);
    }

    function test_OnlyOwnerCanUpgrade() public {
        UUPSTokenV2 newImpl = new UUPSTokenV2();

        // Non-owner cannot upgrade
        vm.prank(alice);
        vm.expectRevert();
        token.upgradeToAndCall(address(newImpl), "");

        // Owner can upgrade
        token.upgradeToAndCall(address(newImpl), "");
    }
}
