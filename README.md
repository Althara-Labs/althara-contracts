# Althara Contracts

A decentralized tender management system built on Ethereum, enabling transparent and secure government procurement processes through smart contracts.

## Overview

Althara Contracts provides a blockchain-based solution for government tender management, ensuring transparency, immutability, and trust in the procurement process. The system consists of two main contracts:

- **TenderContract**: Manages tender creation and lifecycle
- **BidSubmissionContract**: Handles bid submissions and evaluations

## Features

### 🔐 Role-Based Access Control
- **Government Role**: Can create tenders, accept/reject bids, and mark tenders as complete
- **Admin Role**: Can update service fees, platform wallet, and manage roles
- **Pauser Role**: Can pause/unpause contracts for emergency situations

### 📋 Tender Management
- Create tenders with descriptions, budgets, and IPFS-based requirements
- Track tender lifecycle from creation to completion
- Link bids to specific tenders
- Service fee collection for tender creation

### 💰 Bid Submission System
- Submit bids with pricing, descriptions, and IPFS-based proposals
- Automatic validation against tender requirements
- Bid status tracking (Pending, Accepted, Rejected)
- Service fee collection for bid submissions

### 🔒 Security Features
- Pausable contracts for emergency situations
- Comprehensive access control
- Input validation and error handling
- Secure fee collection and refund mechanisms

## Smart Contracts

### TenderContract

The main contract for managing government tenders.

**Key Functions:**
- `createTender()`: Create a new tender with description, budget, and requirements
- `getTenderDetails()`: Retrieve tender information
- `markTenderComplete()`: Mark a tender as completed
- `addBid()`: Link a bid to a tender (called by BidSubmissionContract)

**Events:**
- `TenderCreated`: Emitted when a new tender is created
- `TenderCompleted`: Emitted when a tender is marked as complete
- `BidAdded`: Emitted when a bid is linked to a tender

### BidSubmissionContract

Handles the bid submission and evaluation process.

**Key Functions:**
- `submitBid()`: Submit a bid for a specific tender
- `acceptBid()`: Accept a submitted bid (government only)
- `rejectBid()`: Reject a submitted bid (government only)
- `getBidDetails()`: Retrieve bid information
- `getTenderBids()`: Get all bids for a specific tender

**Events:**
- `BidSubmitted`: Emitted when a new bid is submitted
- `BidAccepted`: Emitted when a bid is accepted
- `BidRejected`: Emitted when a bid is rejected

## Architecture

```
┌─────────────────┐    ┌─────────────────────┐
│   Government    │    │      Vendors        │
│   (Government   │    │   (Bid Submitters)  │
│     Role)       │    │                     │
└─────────┬───────┘    └─────────┬───────────┘
          │                      │
          ▼                      ▼
┌─────────────────────────────────────────────┐
│              TenderContract                 │
│  • Create Tenders                          │
│  • Manage Tender Lifecycle                 │
│  • Link Bids to Tenders                    │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│           BidSubmissionContract             │
│  • Submit Bids                             │
│  • Accept/Reject Bids                      │
│  • Track Bid Status                        │
└─────────────────────────────────────────────┘
```

## Installation

### Prerequisites

- Node.js (v18 or higher)
- npm or yarn
- Git

### Setup

1. Clone the repository:
```bash
git clone https://github.com/Althara-Labs/althara-contracts.git
cd althara-contracts
```

2. Install dependencies:
```bash
npm install
```

3. Create a `.env` file in the root directory:
```env
PRIVATE_KEY=your_private_key_here
ALCHEMY_API_KEY=your_alchemy_api_key_here
SEPOLIA_RPC_URL=your_sepolia_rpc_url_here
```

## Usage

### Compilation

```bash
npx hardhat compile
```

### Testing

Run all tests:
```bash
npm test
```

Run Solidity tests:
```bash
npm run test:solidity
```

### Deployment

The project uses Hardhat Ignition for deployment. Deployment modules are located in the `ignition/modules/` directory.

## Contract Addresses

After deployment, contract addresses will be available in:
- `ignition/deployments/chain-{chainId}/deployed_addresses.json`

## Service Fees

- **Tender Creation**: 0.01 ETH
- **Bid Submission**: 0.005 ETH

These fees are collected by the platform wallet and can be updated by the admin role.

## Security

### Access Control
- All privileged functions are protected by role-based access control
- Only authorized addresses can perform administrative actions
- Emergency pause functionality available

### Input Validation
- Comprehensive validation for all inputs
- Custom error messages for better debugging
- Protection against invalid tender/bid IDs

### Fee Management
- Secure fee collection with automatic refunds for excess payments
- Configurable service fees
- Platform wallet can be updated by admin

## Development

### Project Structure

```
contracts/
├── TenderContract.sol           # Main tender management contract
├── BidSubmissionContract.sol    # Bid submission and evaluation contract
└── interfaces/
    └── ITenderContract.sol      # Interface for TenderContract

test/
├── TenderContract.t.sol         # Solidity tests for TenderContract
└── BidSubmissionContract.t.sol  # Solidity tests for BidSubmissionContract

ignition/
└── modules/
    ├── TenderContract.ts        # Deployment module for TenderContract
    └── BidSubmissionContract.ts # Deployment module for BidSubmissionContract
```

### Adding New Features

1. Create your contract in the `contracts/` directory
2. Add corresponding tests in the `test/` directory
3. Create deployment module in `ignition/modules/`
4. Update this README with new functionality

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request


