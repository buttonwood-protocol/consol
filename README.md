# Consol Protocol

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C)](https://book.getfoundry.sh/)

**Consol Protocol** is a decentralized mortgage lending platform developed by [Buttonwood Protocol](https://github.com/buttonwood-protocol). It enables on-chain mortgage origination, servicing, and conversion with features like origination pools, lender queues, and collateral management.

## Features

- **Mortgage Origination** - Create and manage on-chain mortgage positions with customizable terms
- **Origination Pools** - Lender pools for deploying capital to mortgage origination with epoch-based lifecycle
- **Multi-Token Vaults** - ERC4626-compliant vaults supporting multiple collateral types (USDX, SubConsol)
- **Lender Queues** - Fair withdrawal queue system for lenders
- **Conversion System** - Convert mortgage positions between collateral types
- **Order Pool** - Matching system for mortgage orders
- **Yield Strategies** - Pluggable yield strategies for collateral management

## Architecture

```
src/
├── Consol.sol              # Main vault for USDX deposits
├── SubConsol.sol           # Collateral-specific sub-vaults
├── LoanManager.sol         # Mortgage lifecycle management
├── GeneralManager.sol      # Protocol configuration and settings
├── OriginationPool.sol     # Epoch-based lending pools
├── OriginationPoolScheduler.sol  # Pool deployment scheduling
├── OrderPool.sol           # Order matching system
├── LenderQueue.sol         # Withdrawal queue for lenders
├── ConversionQueue.sol     # Collateral conversion queue
├── MortgageNFT.sol         # NFT representation of mortgages
└── USDX.sol                # Multi-collateral stablecoin
```

## Security

Consol Protocol has been audited by Guardian. The audit report is available in the [`audits/`](audits/) directory.

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) (v18+)
- [pnpm](https://pnpm.io/)

### Installation

```shell
# Clone the repository
git clone https://github.com/buttonwood-protocol/consol.git
cd consol

# Install dependencies
pnpm install
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format & Lint

```shell
forge fmt
pnpm solhint
lintspec src --compact
```

### Gas Snapshots

```shell
forge snapshot
```

## Production Notes

> **Important:** Deployer should deposit at least $1 into USDX and then into Consol, and then transfer ownership to the contract to lock it in. This will help defend against donation attacks.

## Documentation

- [Foundry Book](https://book.getfoundry.sh/) - Development framework documentation

## Contributing

Contributions are welcome! Please see the [pull request template](pull_request_template.md) for guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
