// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/WeedVending.sol";

contract WeedVendingTest is Test {
    WeedVending public vending;
    address public admin = address(0xABCD);
    address public user1 = address(0xBEEF);
    address public user2 = address(0xCAFE);
    address public nonWhitelisted = address(0xDEAD);

    uint256 constant SATIVA_PRICE = 0.005 ether;
    uint256 constant INDICA_PRICE = 0.006 ether;
    uint256 constant HYBRID_PRICE = 0.007 ether;
    uint256 constant INITIAL_BALANCE = 100;

    function setUp() public {
        vm.prank(admin);
        vending = new WeedVending();

        vm.startPrank(admin);
        vending.addToWhitelist(user1);
        vending.addToWhitelist(user2);
        vm.stopPrank();

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(nonWhitelisted, 100 ether);
    }

    // ========== Constructor Tests ==========
    function test_Constructor_SetsAdmin() public view {
        assertTrue(vending.hasRole(vending.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(vending.hasRole(vending.ADMIN_ROLE(), admin));
    }

    function test_Constructor_InitializesStrains() public view {
        assertEq(vending.getStock("Sativa"), INITIAL_BALANCE);
        assertEq(vending.getStock("Indica"), INITIAL_BALANCE);
        assertEq(vending.getStock("Hybrid"), INITIAL_BALANCE);
    }

    // ========== Buy Function Tests ==========
    function test_Buy_Success() public {
        uint256 amount = 1;
        uint256 price = vending.getPrice("Sativa", amount);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit WeedVending.Purchased(user1, amount, "Sativa");
        vending.buy{value: price}("Sativa", amount);

        assertEq(vending.getStock("Sativa"), INITIAL_BALANCE - amount);
        assertEq(vending.getPurchaseHistoryLength(), 1);
    }

    function test_Buy_WithDiscount() public {
        uint256 amount = 5;
        uint256 expectedPrice = (SATIVA_PRICE * amount * 90) / 100;

        vm.prank(user1);
        vending.buy{value: expectedPrice}("Sativa", amount);

        assertEq(vending.getStock("Sativa"), INITIAL_BALANCE - amount);
    }

    function test_Buy_RefundExcess() public {
        uint256 amount = 1;
        uint256 price = vending.getPrice("Sativa", amount);
        uint256 excessPayment = price + 0.1 ether;

        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        vending.buy{value: excessPayment}("Sativa", amount);

        assertEq(user1.balance, balanceBefore - price);
    }

    function test_Buy_RevertIfNotWhitelisted() public {
        vm.prank(nonWhitelisted);
        vm.expectRevert("Not whitelisted");
        vending.buy{value: SATIVA_PRICE}("Sativa", 1);
    }

    function test_Buy_RevertIfInvalidStrain() public {
        vm.prank(user1);
        vm.expectRevert("Invalid strain");
        vending.buy{value: SATIVA_PRICE}("InvalidStrain", 1);
    }

    function test_Buy_RevertIfZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Amount must be positive");
        vending.buy{value: SATIVA_PRICE}("Sativa", 0);
    }

    function test_Buy_RevertIfInsufficientStock() public {
        vm.prank(user1);
        vm.expectRevert("Insufficient stock");
        vending.buy{value: SATIVA_PRICE * (INITIAL_BALANCE + 1)}("Sativa", INITIAL_BALANCE + 1);
    }

    function test_Buy_RevertIfIncorrectPayment() public {
        vm.prank(user1);
        vm.expectRevert("Incorrect payment");
        vending.buy{value: SATIVA_PRICE - 1}("Sativa", 1);
    }

    function test_Buy_RevertIfPaused() public {
        vm.prank(admin);
        vending.togglePause();

        vm.prank(user1);
        vm.expectRevert("Contract is paused");
        vending.buy{value: SATIVA_PRICE}("Sativa", 1);
    }

    // ========== Restock Function Tests ==========
    function test_Restock_Success() public {
        uint256 amount = 50;

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit WeedVending.Restocked("Sativa", amount);
        vending.restock("Sativa", amount);

        assertEq(vending.getStock("Sativa"), INITIAL_BALANCE + amount);
    }

    function test_Restock_RevertIfInvalidStrain() public {
        vm.prank(admin);
        vm.expectRevert("Invalid strain");
        vending.restock("InvalidStrain", 50);
    }

    function test_Restock_RevertIfZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert("Amount must be positive");
        vending.restock("Sativa", 0);
    }

    function test_Restock_RevertIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        vending.restock("Sativa", 50);
    }

    // ========== AddStrain Function Tests ==========
    function test_AddStrain_Success() public {
        string memory name = "NewStrain";
        uint256 price = 0.008 ether;
        uint256 balance = 200;

        vm.prank(admin);
        vending.addStrain(name, price, balance);

        assertEq(vending.getStock(name), balance);
        assertEq(vending.getPrice(name, 1), price);
    }

    function test_AddStrain_RevertIfExists() public {
        vm.prank(admin);
        vm.expectRevert("Strain exists");
        vending.addStrain("Sativa", 0.008 ether, 200);
    }

    function test_AddStrain_RevertIfInvalidInputs() public {
        vm.startPrank(admin);
        vm.expectRevert("Invalid inputs");
        vending.addStrain("NewStrain", 0, 200);

        vm.expectRevert("Invalid inputs");
        vending.addStrain("NewStrain", 0.008 ether, 0);
        vm.stopPrank();
    }

    function test_AddStrain_RevertIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        vending.addStrain("NewStrain", 0.008 ether, 200);
    }

    // ========== Withdrawal Function Tests ==========
    function test_WithdrawalFlow_Success() public {
        vm.prank(user1);
        vending.buy{value: SATIVA_PRICE}("Sativa", 1);

        vm.prank(admin);
        vending.requestWithdrawal();
        assertGt(vending.withdrawalRequestTime(), block.timestamp);

        vm.warp(block.timestamp + vending.WITHDRAWAL_TIMELOCK() + 1);

        uint256 adminBalanceBefore = admin.balance;
        vm.prank(admin);
        vending.executeWithdrawal();

        assertEq(admin.balance, adminBalanceBefore + SATIVA_PRICE);
        assertEq(vending.withdrawalRequestTime(), 0);
    }

    function test_ExecuteWithdrawal_RevertIfTimelockNotExpired() public {
        vm.prank(admin);
        vending.requestWithdrawal();

        vm.prank(admin);
        vm.expectRevert("Timelock not expired");
        vending.executeWithdrawal();
    }

    function test_ExecuteWithdrawal_RevertIfNoRequest() public {
    // Setup - ensure contract has balance
    vm.prank(user1);
    vending.buy{value: SATIVA_PRICE}("Sativa", 1);

    // Test - should revert with new message
    vm.prank(admin);
    vm.expectRevert("No withdrawal requested");
    vending.executeWithdrawal();
    
    // Verification - ensure state unchanged
    assertEq(vending.withdrawalRequestTime(), 0);
}

    function test_Withdrawal_RevertIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        vending.requestWithdrawal();

        vm.expectRevert();
        vending.executeWithdrawal();
    }

    // ========== Whitelist Function Tests ==========
    function test_WhitelistManagement() public {
        address newUser = address(0x1234);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit WeedVending.Whitelisted(newUser);
        vending.addToWhitelist(newUser);
        assertTrue(vending.whitelist(newUser));

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit WeedVending.RemovedFromWhitelist(newUser);
        vending.removeFromWhitelist(newUser);
        assertFalse(vending.whitelist(newUser));
    }

    function test_Whitelist_RevertIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        vending.addToWhitelist(address(0x1234));

        vm.expectRevert();
        vending.removeFromWhitelist(user1);
    }

    // ========== Pause Function Tests ==========
    function test_TogglePause() public {
        vm.prank(admin);
        vending.togglePause();
        assertTrue(vending.paused());

        vm.prank(admin);
        vending.togglePause();
        assertFalse(vending.paused());
    }

    function test_TogglePause_RevertIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        vending.togglePause();
    }

    // ========== Purchase History Tests ==========
    function test_PurchaseHistoryOverflow() public {
        // First restock to have enough supply
        vm.prank(admin);
        vending.restock("Sativa", 1000); // Add 1000 more to initial 100

        vm.startPrank(user1);
        uint256 price = vending.getPrice("Sativa", 1);

        // Fill history to capacity
        for (uint256 i = 0; i < 1000; i++) {
            vending.buy{value: price}("Sativa", 1);
        }
        vm.stopPrank();

        assertEq(vending.getPurchaseHistoryLength(), 1000);

        // Add one more purchase
        vm.prank(user1);
        vending.buy{value: price}("Sativa", 1);

        // Should maintain max capacity
        assertEq(vending.getPurchaseHistoryLength(), 1000);
    }

    // ========== View Function Tests ==========
    function test_GetPrice() public view {
        assertEq(vending.getPrice("Sativa", 1), SATIVA_PRICE);
        assertEq(vending.getPrice("Indica", 1), INDICA_PRICE);
        assertEq(vending.getPrice("Hybrid", 1), HYBRID_PRICE);
        assertEq(vending.getPrice("Sativa", 5), (SATIVA_PRICE * 5 * 90) / 100);
    }

    function test_GetPrice_RevertIfInvalidStrain() public {
        vm.expectRevert("Invalid strain");
        vending.getPrice("InvalidStrain", 1);
    }

    function test_GetStock() public view {
        assertEq(vending.getStock("Sativa"), INITIAL_BALANCE);
        assertEq(vending.getStock("Indica"), INITIAL_BALANCE);
        assertEq(vending.getStock("Hybrid"), INITIAL_BALANCE);
    }

    function test_GetPurchaseHistoryLength() public {
        assertEq(vending.getPurchaseHistoryLength(), 0);

        vm.prank(user1);
        vending.buy{value: SATIVA_PRICE}("Sativa", 1);

        assertEq(vending.getPurchaseHistoryLength(), 1);
    }
}
