// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/WeedVending.sol";

contract WeedVendingScript is Script {
    function run() external {
        // Load admin private key from environment variable (safe for dev use)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Broadcast transactions using the deployer key
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract
        WeedVending vending = new WeedVending();

        // Add users to whitelist (example addresses)
        address testUser = vm.addr(1);
        vending.addToWhitelist(testUser);

        // Optionally add a new strain
        vending.addStrain("OGKush", 0.008 ether, 50);

        // Optionally restock a strain
        vending.restock("Sativa", 100);

        // Optionally toggle pause
        // vending.togglePause();

        vm.stopBroadcast();
    }
}