// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "openzeppelin-contracts/contracts/access/AccessControl.sol";

contract WeedVending is AccessControl {
    // ========== STRUCTS & MAPPINGS ==========
    struct Strain {
        uint256 price;
        uint256 balance;
        string name;
    }

    struct Purchase {
        address buyer;
        uint256 amount;
        uint256 timestamp;
        string strain;
    }

    mapping(string => Strain) public strains;
    Purchase[] public purchaseHistory;
    mapping(address => bool) public whitelist;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bool public paused;
    bool private locked;
    uint256 public withdrawalRequestTime;
    uint256 public constant WITHDRAWAL_TIMELOCK = 1 days;

    // ========== EVENTS ==========
    event Purchased(address indexed buyer, uint256 amount, string strain);
    event Restocked(string strain, uint256 amount);
    event Whitelisted(address user);
    event RemovedFromWhitelist(address user);
    event WithdrawalRequested(uint256 amount, uint256 unlockTime);

    // ========== MODIFIERS ==========
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier noReentrant() {
        require(!locked, "No reentrancy");
        locked = true;
        _;
        locked = false;
    }

    // ========== CONSTRUCTOR ==========
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        strains["Sativa"] = Strain(0.005 ether, 100, "Sativa");
        strains["Indica"] = Strain(0.006 ether, 100, "Indica");
        strains["Hybrid"] = Strain(0.007 ether, 100, "Hybrid");
    }

    // ========== CORE FUNCTIONS ==========
    function buy(string memory strain, uint256 amount) public payable whenNotPaused noReentrant {
        require(whitelist[msg.sender], "Not whitelisted");
        require(strains[strain].price > 0, "Invalid strain");
        require(amount > 0, "Amount must be positive");
        require(strains[strain].balance >= amount, "Insufficient stock");

        uint256 totalCost = strains[strain].price * amount;
        if (amount >= 5) {
            totalCost = (totalCost * 90) / 100; // 10% off
        }
        require(msg.value >= totalCost, "Incorrect payment");

        // Refund excess
        if (msg.value > totalCost) {
            (bool success,) = payable(msg.sender).call{value: msg.value - totalCost}("");
            require(success, "Refund failed");
        }

        strains[strain].balance -= amount;
        if (purchaseHistory.length >= 1000) {
            purchaseHistory.pop();
        }
        purchaseHistory.push(Purchase(msg.sender, amount, block.timestamp, strain));
        emit Purchased(msg.sender, amount, strain);
    }

    // ========== ADMIN FUNCTIONS ==========
    function restock(string memory strain, uint256 amount) public onlyRole(ADMIN_ROLE) {
        require(strains[strain].price > 0, "Invalid strain");
        require(amount > 0, "Amount must be positive");
        strains[strain].balance += amount;
        emit Restocked(strain, amount);
    }

    function addStrain(string memory name, uint256 price, uint256 balance) public onlyRole(ADMIN_ROLE) {
        require(strains[name].price == 0, "Strain exists");
        require(price > 0 && balance > 0, "Invalid inputs");
        strains[name] = Strain(price, balance, name);
    }

    function requestWithdrawal() public onlyRole(ADMIN_ROLE) {
        withdrawalRequestTime = block.timestamp + WITHDRAWAL_TIMELOCK;
        emit WithdrawalRequested(address(this).balance, withdrawalRequestTime);
    }

    function executeWithdrawal() public onlyRole(ADMIN_ROLE) {
    require(withdrawalRequestTime != 0, "No withdrawal requested");
    require(block.timestamp >= withdrawalRequestTime, "Timelock not expired");
    (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
    require(success, "Transfer failed");
    withdrawalRequestTime = 0;
}

    function togglePause() public onlyRole(ADMIN_ROLE) {
        paused = !paused;
    }

    function addToWhitelist(address user) public onlyRole(ADMIN_ROLE) {
        whitelist[user] = true;
        emit Whitelisted(user);
    }

    function removeFromWhitelist(address user) public onlyRole(ADMIN_ROLE) {
        whitelist[user] = false;
        emit RemovedFromWhitelist(user);
    }

    // ========== VIEW FUNCTIONS ==========
    function getStock(string memory strain) public view returns (uint256) {
        return strains[strain].balance;
    }

    function getPrice(string memory strain, uint256 amount) public view returns (uint256) {
        require(strains[strain].price > 0, "Invalid strain");
        uint256 price = strains[strain].price * amount;
        if (amount >= 5) price = (price * 90) / 100;
        return price;
    }

    function getPurchaseHistoryLength() public view returns (uint256) {
        return purchaseHistory.length;
    }
}
