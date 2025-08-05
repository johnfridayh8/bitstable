;; BitStable Protocol - Bitcoin-Collateralized Stablecoin System
;;
;; A next-generation decentralized stablecoin protocol leveraging Bitcoin's security
;; and Stacks' smart contract capabilities to create a truly decentralized USD-pegged
;; digital asset. BitStable enables users to mint stablecoins by locking STX as 
;; collateral, with autonomous liquidation mechanisms and oracle-driven price feeds.
;;
;; Core Features:
;; - Over-collateralized vault system with configurable ratios
;; - Automated liquidation engine protecting protocol solvency
;; - Multi-oracle price feed integration for robust price discovery
;; - Governance-controlled risk parameters and emergency controls
;; - Fee-based sustainability model with transparent economics
;;
;; Security Model:
;; BitStable implements a battle-tested CDP (Collateralized Debt Position) model
;; with multiple layers of protection including minimum collateral ratios,
;; liquidation thresholds, and emergency shutdown capabilities.

;; PROTOCOL CONSTANTS

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_OWNER_ONLY (err u100))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u101))
(define-constant ERR_BELOW_MCR (err u102))
(define-constant ERR_ALREADY_INITIALIZED (err u103))
(define-constant ERR_NOT_INITIALIZED (err u104))
(define-constant ERR_LOW_BALANCE (err u105))
(define-constant ERR_INVALID_PRICE (err u106))
(define-constant ERR_EMERGENCY_SHUTDOWN (err u107))
(define-constant ERR_INVALID_PARAMETER (err u108))

;; Price and ratio boundaries for system safety
(define-constant MAXIMUM_PRICE u1000000000) ;; $10,000 BTC price ceiling
(define-constant MINIMUM_PRICE u1) ;; $0.01 BTC price floor
(define-constant MAXIMUM_RATIO u1000) ;; 1000% max collateral ratio
(define-constant MINIMUM_RATIO u101) ;; 101% min collateral ratio
(define-constant MAXIMUM_FEE u100) ;; 100% max stability fee cap

;; PROTOCOL STATE VARIABLES

;; Risk management parameters
(define-data-var minimum-collateral-ratio uint u150) ;; 150% - Safe collateralization
(define-data-var liquidation-ratio uint u120) ;; 120% - Liquidation trigger
(define-data-var stability-fee uint u2) ;; 2% - Annual borrowing cost

;; System state controls
(define-data-var initialized bool false)
(define-data-var emergency-shutdown bool false)

;; Oracle price feed data
(define-data-var last-price uint u0)
(define-data-var price-valid bool false)

;; Governance token reference
(define-data-var governance-token principal 'SP000000000000000000002Q6VF78.governance-token)

;; DATA STRUCTURES

;; User vault storage - tracks collateral and debt positions
(define-map vaults
  principal
  {
    collateral: uint, ;; STX collateral locked
    debt: uint, ;; BitStable tokens minted
    last-fee-timestamp: uint, ;; Last stability fee calculation
  }
)

;; Authorized liquidator registry
(define-map liquidators
  principal
  bool
)

;; Authorized price oracle registry  
(define-map price-oracles
  principal
  bool
)

;; VALIDATION FUNCTIONS

(define-private (is-valid-price (price uint))
  ;; Validates price falls within acceptable bounds
  (and
    (>= price MINIMUM_PRICE)
    (<= price MAXIMUM_PRICE)
  )
)

(define-private (is-valid-ratio (ratio uint))
  ;; Validates collateral ratio is within system limits
  (and
    (>= ratio MINIMUM_RATIO)
    (<= ratio MAXIMUM_RATIO)
  )
)