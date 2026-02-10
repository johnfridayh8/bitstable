;; BitStable Protocol - Bitcoin-Collateralized Stablecoin System
;;
;; Next-generation decentralized stablecoin leveraging BTC security and Stacks smart contracts.
;; Includes vaults, over-collateralization, automated liquidation, oracle feeds, governance, 
;; and time-weighted stability fee accrual.

;; ========================================
;; CONSTANTS & ERROR CODES
;; ========================================

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

;; Price & ratio boundaries
(define-constant MAXIMUM_PRICE u1000000000)
(define-constant MINIMUM_PRICE u1)
(define-constant MAXIMUM_RATIO u1000)
(define-constant MINIMUM_RATIO u101)
(define-constant MAXIMUM_FEE u100)

;; ========================================
;; STATE VARIABLES
;; ========================================

(define-data-var minimum-collateral-ratio uint u150)
(define-data-var liquidation-ratio uint u120)
(define-data-var stability-fee uint u2)

(define-data-var initialized bool false)
(define-data-var emergency-shutdown bool false)

(define-data-var last-price uint u0)
(define-data-var price-valid bool false)

(define-data-var governance-token principal 'SP000000000000000000002Q6VF78.governance-token)

;; Vault storage
(define-map vaults
  principal
  {
    collateral: uint
    debt: uint
    last-fee-timestamp: uint
  }
)

;; Authorized liquidators
(define-map liquidators
  principal
  bool
)

;; Authorized price oracles
(define-map price-oracles
  principal
  bool
)

;; ========================================
;; VALIDATION FUNCTIONS
;; ========================================

(define-private (is-valid-price (price uint))
  (and (>= price MINIMUM_PRICE) (<= price MAXIMUM_PRICE))
)

(define-private (is-valid-ratio (ratio uint))
  (and (>= ratio MINIMUM_RATIO) (<= ratio MAXIMUM_RATIO))
)

(define-private (is-valid-fee (fee uint))
  (<= fee MAXIMUM_FEE)
)

;; ========================================
;; HELPER: TIME-WEIGHTED STABILITY FEE ACCRUAL
;; ========================================

(define-private (accrue-stability-fee (vault-data {collateral: uint, debt: uint, last-fee-timestamp: uint}))
  (let (
        (blocks-passed (- stacks-block-height (get last-fee-timestamp vault-data)))
        (fee-rate (var-get stability-fee))
        (fee-accrued (/ (* (get debt vault-data) fee-rate blocks-passed) u10000))
        (new-debt (+ (get debt vault-data) fee-accrued))
  )
    (merge vault-data { debt: new-debt, last-fee-timestamp: stacks-block-height })
  )
)

;; ========================================
;; CORE PROTOCOL FUNCTIONS
;; ========================================

(define-public (initialize (btc-price uint))
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

;; Create or add collateral
(define-public (create-vault (collateral-amount uint))
  (let ((existing-vault (default-to {
      collateral: u0
      debt: u0
      last-fee-timestamp: stacks-block-height
    } (map-get? vaults tx-sender))))
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

;; Mint BitStable tokens with fee accrual
(define-public (mint-stablecoin (amount uint))
  (let (
        (vault (unwrap! (map-get? vaults tx-sender) ERR_LOW_BALANCE))
        (vault-with-fee (accrue-stability-fee vault))
        (current-collateral (get collateral vault-with-fee))
        (current-debt (get debt vault-with-fee))
        (new-debt (+ current-debt amount))
        (collateral-value (* current-collateral (var-get last-price)))
  )
    (begin
      (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
      (asserts! (not (var-get emergency-shutdown)) ERR_EMERGENCY_SHUTDOWN)
      (asserts! (var-get price-valid) ERR_INVALID_PRICE)
      (asserts! (>= (* collateral-value u100) (* new-debt (var-get minimum-collateral-ratio))) ERR_BELOW_MCR)
      (map-set vaults tx-sender (merge vault-with-fee { debt: new-debt }))
      (ok true)
    )
  )
)

;; Repay debt with fee accrual
(define-public (repay-debt (amount uint))
  (let (
        (vault (unwrap! (map-get? vaults tx-sender) ERR_LOW_BALANCE))
        (vault-with-fee (accrue-stability-fee vault))
        (current-debt (get debt vault-with-fee))
  )
    (begin
      (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
      (asserts! (>= current-debt amount) ERR_LOW_BALANCE)
      (map-set vaults tx-sender (merge vault-with-fee { debt: (- current-debt amount) }))
      (ok true)
    )
  )
)

;; Withdraw collateral with fee accrual
(define-public (withdraw-collateral (amount uint))
  (let (
        (vault (unwrap! (map-get? vaults tx-sender) ERR_LOW_BALANCE))
        (vault-with-fee (accrue-stability-fee vault))
        (current-collateral (get collateral vault-with-fee))
        (current-debt (get debt vault-with-fee))
        (new-collateral (- current-collateral amount))
        (collateral-value (* new-collateral (var-get last-price)))
  )
    (begin
      (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
      (asserts! (not (var-get emergency-shutdown)) ERR_EMERGENCY_SHUTDOWN)
      (asserts! (var-get price-valid) ERR_INVALID_PRICE)
      (asserts! (>= current-collateral amount) ERR_LOW_BALANCE)
      (asserts!
        (or
          (is-eq current-debt u0)
          (>= (* collateral-value u100) (* current-debt (var-get minimum-collateral-ratio)))
        )
        ERR_BELOW_MCR
      )
      (try! (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender)))
      (map-set vaults tx-sender (merge vault-with-fee { collateral: new-collateral }))
      (ok true)
    )
  )
)

;; ========================================
;; LIQUIDATION
;; ========================================

(define-public (liquidate (vault-owner principal))
  (let (
        (vault (unwrap! (map-get? vaults vault-owner) ERR_LOW_BALANCE))
        (collateral (get collateral vault))
        (debt (get debt vault))
        (collateral-value (* collateral (var-get last-price)))
  )
    (begin
      (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
      (asserts! (var-get price-valid) ERR_INVALID_PRICE)
      (asserts! (is-authorized-liquidator tx-sender) ERR_OWNER_ONLY)
      (asserts! (> debt u0) ERR_INVALID_PARAMETER)
      (asserts! (< (* collateral-value u100) (* debt (var-get liquidation-ratio))) ERR_INSUFFICIENT_COLLATERAL)
      (let ((collateral-to-transfer collateral))
        (map-delete vaults vault-owner)
        (try! (as-contract (stx-transfer? collateral-to-transfer (as-contract tx-sender) tx-sender)))
        (ok true)
      )
    )
  )
)

;; ========================================
;; ORACLE MANAGEMENT
;; ========================================

(define-public (update-price (new-price uint))
  (begin
    (asserts! (is-authorized-oracle tx-sender) ERR_OWNER_ONLY)
    (asserts! (is-valid-price new-price) ERR_INVALID_PARAMETER)
    (var-set last-price new-price)
    (var-set price-valid true)
    (ok true)
  )
)

;; ========================================
;; GOVERNANCE & RISK
;; ========================================

(define-public (set-minimum-collateral-ratio (new-ratio uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (is-valid-ratio new-ratio) ERR_INVALID_PARAMETER)
    (asserts! (> new-ratio (var-get liquidation-ratio)) ERR_INVALID_PARAMETER)
    (var-set minimum-collateral-ratio new-ratio)
    (ok true)
  )
)

(define-public (set-liquidation-ratio (new-ratio uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (is-valid-ratio new-ratio) ERR_INVALID_PARAMETER)
    (asserts! (< new-ratio (var-get minimum-collateral-ratio)) ERR_INVALID_PARAMETER)
    (var-set liquidation-ratio new-ratio)
    (ok true)
  )
)

(define-public (set-stability-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (is-valid-fee new-fee) ERR_INVALID_PARAMETER)
    (var-set stability-fee new-fee)
    (ok true)
  )
)

;; ========================================
;; ACCESS CONTROL
;; ========================================

(define-public (add-liquidator (liquidator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (not (is-authorized-liquidator liquidator)) ERR_INVALID_PARAMETER)
    (map-set liquidators liquidator true)
    (ok true)
  )
)

(define-public (remove-liquidator (liquidator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (is-authorized-liquidator liquidator) ERR_INVALID_PARAMETER)
    (map-delete liquidators liquidator)
    (ok true)
  )
)

(define-public (add-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (not (is-authorized-oracle oracle)) ERR_INVALID_PARAMETER)
    (map-set price-oracles oracle true)
    (ok true)
  )
)

(define-public (remove-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (is-authorized-oracle oracle) ERR_INVALID_PARAMETER)
    (map-delete price-oracles oracle)
    (ok true)
  )
)

;; ========================================
;; EMERGENCY
;; ========================================

(define-public (trigger-emergency-shutdown)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (var-set emergency-shutdown true)
    (ok true)
  )
)

;; ========================================
;; READ-ONLY QUERIES
;; ========================================

(define-read-only (get-vault (owner principal))
  (map-get? vaults owner)
)

(define-read-only (get-collateral-ratio (owner principal))
  (let (
        (vault (unwrap! (map-get? vaults owner) ERR_LOW_BALANCE))
        (collateral (get collateral vault))
        (debt (get debt vault))
  )
    (if (is-eq debt u0)
      (ok u0)
      (ok (/ (* collateral (var-get last-price)) debt))
    )
  )
)

(define-read-only (is-authorized-liquidator (address principal))
  (default-to false (map-get? liquidators address))
)

(define-read-only (is-authorized-oracle (address principal))
  (default-to false (map-get? price-oracles address))
)

(define-read-only (get-stability-parameters)
  {
    minimum-collateral-ratio: (var-get minimum-collateral-ratio),
    liquidation-ratio: (var-get liquidation-ratio),
    stability-fee: (var-get stability-fee),
    price: (var-get last-price),
    price-valid: (var-get price-valid),
    emergency-shutdown: (var-get emergency-shutdown),
  }
)
