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

(define-private (is-valid-fee (fee uint))
  ;; Validates stability fee doesn\'t exceed maximum
  (<= fee MAXIMUM_FEE)
)

;; CORE PROTOCOL FUNCTIONS

(define-public (initialize (btc-price uint))
  ;; Initializes the BitStable protocol with starting BTC price
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (not (var-get initialized)) ERR_ALREADY_INITIALIZED)
    (asserts! (is-valid-price btc-price) ERR_INVALID_PARAMETER)
    (var-set last-price btc-price)
    (var-set price-valid true)
    (var-set initialized true)
    (ok true)
  )
)

(define-public (create-vault (collateral-amount uint))
  ;; Creates or adds collateral to a user\'s vault position
  (let ((existing-vault (default-to {
      collateral: u0,
      debt: u0,
      last-fee-timestamp: (unwrap-panic (get-block-info? time u0)),
    }
      (map-get? vaults tx-sender)
    )))
    (begin
      (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
      (asserts! (not (var-get emergency-shutdown)) ERR_EMERGENCY_SHUTDOWN)
      (try! (stx-transfer? collateral-amount tx-sender (as-contract tx-sender)))
      (map-set vaults tx-sender
        (merge existing-vault { collateral: (+ collateral-amount (get collateral existing-vault)) })
      )
      (ok true)
    )
  )
)

(define-public (mint-stablecoin (amount uint))
  ;; Mints BitStable tokens against vault collateral
  (let (
      (vault (unwrap! (map-get? vaults tx-sender) ERR_LOW_BALANCE))
      (current-collateral (get collateral vault))
      (current-debt (get debt vault))
      (new-debt (+ current-debt amount))
      (collateral-value (* current-collateral (var-get last-price)))
    )
    (begin
      (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
      (asserts! (not (var-get emergency-shutdown)) ERR_EMERGENCY_SHUTDOWN)
      (asserts! (var-get price-valid) ERR_INVALID_PRICE)
      ;; Enforce minimum collateralization ratio
      (asserts!
        (>= (* collateral-value u100)
          (* new-debt (var-get minimum-collateral-ratio))
        )
        ERR_BELOW_MCR
      )
      (map-set vaults tx-sender (merge vault { debt: new-debt }))
      (ok true)
    )
  )
)

(define-public (repay-debt (amount uint))
  ;; Repays BitStable debt to reduce vault obligation
  (let (
      (vault (unwrap! (map-get? vaults tx-sender) ERR_LOW_BALANCE))
      (current-debt (get debt vault))
    )
    (begin
      (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
      (asserts! (>= current-debt amount) ERR_LOW_BALANCE)
      (map-set vaults tx-sender (merge vault { debt: (- current-debt amount) }))
      (ok true)
    )
  )
)

(define-public (withdraw-collateral (amount uint))
  ;; Withdraws collateral while maintaining minimum ratios
  (let (
      (vault (unwrap! (map-get? vaults tx-sender) ERR_LOW_BALANCE))
      (current-collateral (get collateral vault))
      (current-debt (get debt vault))
      (new-collateral (- current-collateral amount))
      (collateral-value (* new-collateral (var-get last-price)))
    )
    (begin
      (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
      (asserts! (not (var-get emergency-shutdown)) ERR_EMERGENCY_SHUTDOWN)
      (asserts! (var-get price-valid) ERR_INVALID_PRICE)
      (asserts! (>= current-collateral amount) ERR_LOW_BALANCE)
      ;; Ensure withdrawal maintains safe collateralization
      (asserts!
        (or
          (is-eq current-debt u0)
          (>= (* collateral-value u100)
            (* current-debt (var-get minimum-collateral-ratio))
          )
        )
        ERR_BELOW_MCR
      )
      (try! (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender)))
      (map-set vaults tx-sender (merge vault { collateral: new-collateral }))
      (ok true)
    )
  )
)

;; LIQUIDATION SYSTEM

(define-public (liquidate (vault-owner principal))
  ;; Liquidates undercollateralized vaults to protect protocol
  (let (
      (vault (unwrap! (map-get? vaults vault-owner) ERR_LOW_BALANCE))
      (collateral (get collateral vault))
      (debt (get debt vault))
      (collateral-value (* collateral (var-get last-price)))
    )
    (begin
      ;; System health checks
      (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
      (asserts! (var-get price-valid) ERR_INVALID_PRICE)
      (asserts! (is-authorized-liquidator tx-sender) ERR_OWNER_ONLY)

      ;; Vault validation
      (asserts! (> debt u0) ERR_INVALID_PARAMETER)

      ;; Confirm vault is below liquidation threshold
      (asserts!
        (< (* collateral-value u100) (* debt (var-get liquidation-ratio)))
        ERR_INSUFFICIENT_COLLATERAL
      )

      ;; Execute liquidation with reentrancy protection
      (let ((collateral-to-transfer collateral))
        (map-delete vaults vault-owner)
        (try! (as-contract (stx-transfer? collateral-to-transfer (as-contract tx-sender) tx-sender)))
        (ok true)
      )
    )
  )
)

;; ORACLE PRICE MANAGEMENT

(define-public (update-price (new-price uint))
  ;; Updates BTC/USD price feed from authorized oracles
  (begin
    (asserts! (is-authorized-oracle tx-sender) ERR_OWNER_ONLY)
    (asserts! (is-valid-price new-price) ERR_INVALID_PARAMETER)
    (var-set last-price new-price)
    (var-set price-valid true)
    (ok true)
  )
)

;; GOVERNANCE & RISK MANAGEMENT

(define-public (set-minimum-collateral-ratio (new-ratio uint))
  ;; Updates minimum collateralization requirement
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (is-valid-ratio new-ratio) ERR_INVALID_PARAMETER)
    (asserts! (> new-ratio (var-get liquidation-ratio)) ERR_INVALID_PARAMETER)
    (var-set minimum-collateral-ratio new-ratio)
    (ok true)
  )
)

(define-public (set-liquidation-ratio (new-ratio uint))
  ;; Updates liquidation threshold ratio
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (is-valid-ratio new-ratio) ERR_INVALID_PARAMETER)
    (asserts! (< new-ratio (var-get minimum-collateral-ratio))
      ERR_INVALID_PARAMETER
    )
    (var-set liquidation-ratio new-ratio)
    (ok true)
  )
)

(define-public (set-stability-fee (new-fee uint))
  ;; Updates annual stability fee for borrowing
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (is-valid-fee new-fee) ERR_INVALID_PARAMETER)
    (var-set stability-fee new-fee)
    (ok true)
  )
)

;; ACCESS CONTROL MANAGEMENT

(define-public (add-liquidator (liquidator principal))
  ;; Authorizes new liquidator address
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (not (is-authorized-liquidator liquidator)) ERR_INVALID_PARAMETER)
    (map-set liquidators liquidator true)
    (ok true)
  )
)

(define-public (remove-liquidator (liquidator principal))
  ;; Revokes liquidator authorization
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (is-authorized-liquidator liquidator) ERR_INVALID_PARAMETER)
    (map-delete liquidators liquidator)
    (ok true)
  )
)