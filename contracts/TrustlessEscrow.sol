// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import a security module to prevent hackers from looping the withdraw function
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TrustlessEscrow is ReentrancyGuard {
    address public buyer;
    address public seller;
    address public arbiter; // The middleman (like Hashira)
    uint256 public amount;
    
    // A state machine to track where the money is
    enum State { AWAITING_PAYMENT, AWAITING_DELIVERY, COMPLETE , REFUNDED}
    State public currentState;

    // This makes sure random people can't click the "Deposit" or "Release" buttons
    modifier onlyBuyer() {
        require(msg.sender == buyer, "Only the buyer can call this function");
        _;
    }

    modifier onlyArbiter() {
        require(msg.sender == arbiter, "Only arbiter allowed");
        _;
    }

    modifier inState(State expectedState) {
        require(currentState == expectedState, "Invalid state");
        _;
    }


    // This runs ONCE when the contract is deployed to the blockchain
    constructor(address _seller, address _arbiter) {
        buyer = msg.sender; // The wallet that deploys this contract becomes the buyer
        seller = _seller;
        arbiter = _arbiter;
        currentState = State.AWAITING_PAYMENT;
    }

    // 1. Buyer locks the funds into the blockchain
    // The "payable" keyword means this function can receive real Ethereum
    function deposit() external payable onlyBuyer {
        require(currentState == State.AWAITING_PAYMENT, "Funds already deposited");
        require(msg.value > 0, "Deposit must be greater than 0");
        
        amount = msg.value;
        currentState = State.AWAITING_DELIVERY;
    }

    // 2. Buyer confirms they got the item, releasing funds to the seller
    function releaseFunds() external onlyBuyer nonReentrant {
        require(currentState == State.AWAITING_DELIVERY, "Cannot release funds yet");
        
        // Security Best Practice: Always update the state BEFORE sending money
        currentState = State.COMPLETE;
        
        // Transfer the actual ETH to the seller's wallet
        (bool success, ) = seller.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function refundBuyer() external onlyArbiter nonReentrant inState(State.AWAITING_DELIVERY){
        currentState = State.REFUNDED;
        (bool success, ) = buyer.call{value: amount}("");
        require(success, "Refund failed");
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }


}

