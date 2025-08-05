# BitStable Protocol

**A next-generation Bitcoin-collateralized stablecoin system on Stacks**

[![Clarity](https://img.shields.io/badge/Clarity-v3-blue)](https://clarity-lang.org/)
[![Stacks](https://img.shields.io/badge/Stacks-Blockchain-orange)](https://stacks.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 🚀 Overview

BitStable is a decentralized stablecoin protocol that leverages Bitcoin's security and Stacks' smart contract capabilities to create a truly decentralized USD-pegged digital asset. Users can mint stablecoins by locking STX as collateral, with autonomous liquidation mechanisms and oracle-driven price feeds ensuring protocol stability and solvency.

### Key Features

- 🔒 **Over-collateralized Vault System** - Configurable collateral ratios for enhanced security
- ⚡ **Automated Liquidation Engine** - Protects protocol solvency through real-time monitoring
- 📊 **Multi-Oracle Price Integration** - Robust price discovery with multiple oracle sources
- 🎛️ **Governance Controls** - Community-controlled risk parameters and emergency mechanisms
- 💰 **Fee-based Sustainability** - Transparent economic model with stability fees

## 🏗️ Architecture

BitStable implements a battle-tested CDP (Collateralized Debt Position) model with multiple layers of protection:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   User Vaults   │────│  Price Oracles  │────│   Liquidators   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │ BitStable Core  │
                    └─────────────────┘
```

### Security Model

- **Minimum Collateral Ratios**: Enforced collateralization requirements
- **Liquidation Thresholds**: Automated liquidation below safety margins  
- **Emergency Shutdown**: Circuit breaker for extreme market conditions
- **Access Controls**: Multi-role authorization system

## 🛠️ Installation & Setup

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) v2.0+
- [Node.js](https://nodejs.org/) v18+
- [Stacks CLI](https://docs.stacks.org/stacks-cli)

### Quick Start

1. **Clone the repository**

   ```bash
   git clone https://github.com/johnfridayh8/bitstable.git
   cd bitstable
   ```

2. **Install dependencies**

   ```bash
   npm install
   ```

3. **Run tests**

   ```bash
   npm test
   ```

4. **Check contracts**

   ```bash
   clarinet check
   ```

5. **Start local development**

   ```bash
   clarinet integrate
   ```

## 📋 Contract Interface

### Core Functions

#### Vault Management

```clarity
;; Create or add collateral to vault
(define-public (create-vault (collateral-amount uint)))

;; Mint stablecoins against collateral
(define-public (mint-stablecoin (amount uint)))

;; Repay debt to reduce obligations
(define-public (repay-debt (amount uint)))

;; Withdraw collateral while maintaining ratios
(define-public (withdraw-collateral (amount uint)))
```

#### Liquidation System

```clarity
;; Liquidate undercollateralized vaults
(define-public (liquidate (vault-owner principal)))
```

#### Oracle Management

```clarity
;; Update BTC/USD price feed
(define-public (update-price (new-price uint)))
```

### Read-Only Functions

```clarity
;; Get vault details
(define-read-only (get-vault (owner principal)))

;; Calculate collateralization ratio
(define-read-only (get-collateral-ratio (owner principal)))

;; Get protocol parameters
(define-read-only (get-stability-parameters))
```

## 📊 Protocol Parameters

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| Minimum Collateral Ratio | 150% | Safe collateralization threshold |
| Liquidation Ratio | 120% | Liquidation trigger point |
| Stability Fee | 2% | Annual borrowing cost |
| Price Bounds | $0.01 - $10,000 | Valid BTC price range |

## 🧪 Testing

The project includes comprehensive test coverage using Vitest and Clarinet SDK:

```bash
# Run all tests
npm test

# Run tests with coverage
npm run test:report

# Watch mode for development
npm run test:watch

# Check contract syntax
clarinet check
```

### Test Structure

```
tests/
├── bitstable.test.ts       # Core protocol tests
├── liquidation.test.ts     # Liquidation mechanism tests
├── oracle.test.ts          # Price oracle tests
└── governance.test.ts      # Governance function tests
```

## 🚀 Deployment

### Testnet Deployment

1. **Configure network settings**

   ```bash
   # Edit settings/Testnet.toml
   clarinet integrate
   ```

2. **Deploy contracts**

   ```bash
   clarinet deploy --testnet
   ```

### Mainnet Deployment

1. **Prepare mainnet configuration**

   ```bash
   # Edit settings/Mainnet.toml
   ```

2. **Deploy to mainnet**

   ```bash
   clarinet deploy --mainnet
   ```

## 🔐 Security Considerations

### Audit Status

- [ ] Internal security review
- [ ] External audit (planned)
- [ ] Bug bounty program (TBD)

### Known Risks

- Oracle price manipulation
- Liquidation front-running
- Flash loan attacks (mitigated by block-based operations)

### Best Practices

- Always maintain collateral ratios above minimum requirements
- Monitor price feeds for accuracy
- Use authorized liquidators and oracles only

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Clarity best practices
- Add comprehensive tests for new features
- Update documentation for API changes
- Ensure all tests pass before submitting

## 📚 Documentation

- [Clarity Language Guide](https://docs.stacks.org/clarity)
- [Stacks Blockchain Docs](https://docs.stacks.org/)
- [Clarinet Documentation](https://docs.hiro.so/clarinet)
- [BitStable Technical Whitepaper](docs/whitepaper.md) *(coming soon)*

## 🐛 Bug Reports & Issues

Found a bug? Please [open an issue](https://github.com/johnfridayh8/bitstable/issues) with:

- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Environment details (Clarinet version, OS, etc.)

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🌟 Acknowledgments

- [Stacks Foundation](https://stacks.org/) for blockchain infrastructure
- [Hiro](https://hiro.so/) for development tools
- Bitcoin community for the underlying security layer
