# Trustless Escrow — 

My background is Java and full-stack development (MERN stack). I had one week
to prepare for a blockchain infrastructure interview. Instead of only reading
documentation, I built something working from scratch so I could learn through
real compiler errors and real deployment problems — not theory.

This is a decentralized escrow smart contract deployed on a local Hardhat EVM
node. It eliminates counterparty risk by locking funds inside the blockchain
itself until delivery conditions are met — no bank, no intermediary, no
trusted third party holding the money.

---

## The Problem It Solves

In traditional escrow, you trust a bank or lawyer to hold money between a
buyer and seller. That trust is centralized — the bank can freeze accounts,
make mistakes, or be corrupted.

This contract replaces that trust with math. The ETH is locked inside the
contract address on the blockchain. Nobody — not even the contract deployer —
can move it outside the rules encoded in Solidity. The arbiter can only refund
the buyer, not steal the funds.

---

## How I Mapped My Web2 Knowledge to Web3

Rather than treating this as a completely foreign domain, I mapped it to
backend concepts I already understood:

| Web2 Concept | Web3 Equivalent | What I Used |
|---|---|---|
| Database row | Contract state variables | `buyer`, `seller`, `amount` |
| Express.js middleware | Solidity modifiers | `onlyBuyer`, `inState` |
| Server process | Local EVM node | Hardhat Network |
| API client | Ethers.js deployment script | `deploy.ts` |
| Enum / state machine | Solidity `enum` | `State.AWAITING_PAYMENT` etc |
| try/catch | `require()` statements | Revert on invalid state |

This framing made the learning curve much less steep. The concepts were
familiar — the execution environment was what was new.

---

## Architecture

```
Buyer deploys contract
       │
       ▼
[AWAITING_PAYMENT]
       │
       │  buyer calls deposit() with ETH
       ▼
[AWAITING_DELIVERY] ◄── funds locked in contract address
       │
       ├── buyer confirms → releaseFunds() → seller receives ETH → [COMPLETE]
       │
       └── dispute → arbiter calls refundBuyer() → buyer gets ETH back → [REFUNDED]
```

The state machine ensures funds can only move forward through valid transitions.
You cannot call `releaseFunds()` before depositing. You cannot refund a
completed escrow. The enum and `inState` modifier enforce this at the EVM level.

---

## Contract: `TrustlessEscrow.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TrustlessEscrow is ReentrancyGuard {
    address public buyer;
    address public seller;
    address public arbiter;
    uint256 public amount;

    enum State { AWAITING_PAYMENT, AWAITING_DELIVERY, COMPLETE, REFUNDED }
    State public currentState;

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

    constructor(address _seller, address _arbiter) {
        buyer = msg.sender;
        seller = _seller;
        arbiter = _arbiter;
        currentState = State.AWAITING_PAYMENT;
    }

    function deposit() external payable onlyBuyer {
        require(currentState == State.AWAITING_PAYMENT, "Funds already deposited");
        require(msg.value > 0, "Deposit must be greater than 0");
        amount = msg.value;
        currentState = State.AWAITING_DELIVERY;
    }

    function releaseFunds() external onlyBuyer nonReentrant {
        require(currentState == State.AWAITING_DELIVERY, "Cannot release funds yet");
        currentState = State.COMPLETE;                        // state update FIRST
        (bool success, ) = seller.call{value: amount}("");   // transfer SECOND
        require(success, "Transfer failed");
    }

    function refundBuyer() external onlyArbiter nonReentrant inState(State.AWAITING_DELIVERY) {
        currentState = State.REFUNDED;
        (bool success, ) = buyer.call{value: amount}("");
        require(success, "Refund failed");
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
```

---

## Security: Two Layers Against Reentrancy

The biggest vulnerability in DeFi history is reentrancy — the DAO hack in
2016 lost $60M because a withdrawal function could be called recursively
before the state updated. I implemented two defenses:

**Layer 1 — Checks-Effects-Interactions (CEI) pattern**

The state is updated to `COMPLETE` before the ETH transfer happens:

```solidity
currentState = State.COMPLETE;                       // effects first
(bool success, ) = seller.call{value: amount}("");   // interaction second
```

If an attacker tries to re-enter `releaseFunds()` during the transfer, the
state is already `COMPLETE` so the function reverts immediately.

**Layer 2 — OpenZeppelin ReentrancyGuard**

The `nonReentrant` modifier adds a mutex lock as a fallback. Even if the CEI
pattern somehow failed, this prevents recursive entry entirely.

Learning this made me realize why smart contract security is its own
discipline. A reentrancy bug is not caught by a linter or a type system — you
have to reason about the execution order yourself.

---

## Deployment Script: `scripts/deploy.ts`

```typescript
import { network } from "hardhat";

async function main() {
    const connection = await network.connect();
    const ethers = connection.ethers;

    if (!ethers) {
        throw new Error("Ethers plugin not loaded. Check hardhat.config.ts");
    }

    const [buyer, seller, arbiter] = await ethers.getSigners();
    console.log("Buyer:", buyer.address);

    const EscrowFactory = await ethers.getContractFactory("TrustlessEscrow");
    const escrow = await EscrowFactory.deploy(seller.address, arbiter.address);

    await escrow.waitForDeployment();
    const address = await escrow.getAddress();
    console.log("Escrow deployed at:", address);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
```

---

## Local Execution Proof

**1. Booting the local Hardhat node:**

```
Started HTTP and WebSocket JSON-RPC server at http://127.0.0.1:8545/

Account #0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000 ETH)
Account #1: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000 ETH)
Account #2: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC (10000 ETH)
```

**2. Running `deploy.ts`:**

```
Buyer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Escrow deployed at: 0x5FbDB2315678afecb367f032d93F642f64180aa3
```

---

## How to Run

```bash
# Install dependencies
npm install

# Terminal 1 — start local EVM node
npx hardhat node

# Terminal 2 — compile and deploy
npx hardhat compile
npx hardhat run scripts/deploy.ts --network localhost
```

---

## Tech Stack

| Tool | Purpose |
|---|---|
| Solidity ^0.8.20 | Smart contract language |
| Hardhat 3 Beta | EVM development environment and local node |
| Ethers.js | TypeScript library to interact with contracts |
| OpenZeppelin | Audited security primitives (ReentrancyGuard) |
| TypeScript | Typed deployment scripts |

---

## What I Would Add Next

- Hardhat tests covering every state transition and invalid call
- Timeout mechanism — if seller never delivers, buyer can reclaim after N days
- Event emission on each state change for frontend indexing
- Deployment to Sepolia testnet with verified contract on Etherscan
- Frontend using Next.js + wagmi to interact with the contract in browser

---

## What This Taught Me

**State machines are the right mental model for blockchain.** Every transaction
either moves the state forward or reverts entirely. There is no partial
success. This is fundamentally different from a REST API where you can have
partial updates and rollbacks. The enum + modifier pattern enforces this.

**Security is not optional.** In Web2, a bug means downtime and a patch
deployment. In Web3, a bug in a deployed contract means permanently lost funds
with no recourse. Learning about reentrancy early changed how I read smart
contract code — I now instinctively look at the order of state updates versus
external calls.

**The toolchain matters.** Hardhat's local node with pre-funded test accounts
made iteration fast. TypeScript deployment scripts gave me type safety when
interacting with contract ABIs. These choices let me focus on learning
Solidity rather than fighting the environment.

---

*Built in one week while learning Solidity and Web3 tooling from scratch.
Java and MERN background. Motivated by understanding how trustless financial
infrastructure actually works at the code level.*