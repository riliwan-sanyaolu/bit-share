;; Title: BitShare Protocol
;;
;; Description:
;; A decentralized protocol for tokenized real-world assets on Stacks Layer 2,
;; with full Bitcoin settlement compatibility. BitShare enables fractional ownership
;; of assets through semi-fungible tokens (SFTs), automated dividend distribution,
;; on-chain governance, and regulatory compliance integration.

;; Constants

;; Administrative
(define-constant contract-owner tx-sender)

;; Error codes
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-listed (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-not-authorized (err u104))
(define-constant err-kyc-required (err u105))
(define-constant err-vote-exists (err u106))
(define-constant err-vote-ended (err u107))
(define-constant err-price-expired (err u108))
(define-constant err-invalid-uri (err u110))
(define-constant err-invalid-value (err u111))
(define-constant err-invalid-duration (err u112))
(define-constant err-invalid-kyc-level (err u113))
(define-constant err-invalid-expiry (err u114))
(define-constant err-invalid-votes (err u115))
(define-constant err-invalid-address (err u116))
(define-constant err-invalid-title (err u117))
(define-constant err-insufficient-balance (err u118))
(define-constant err-kyc-expired (err u119))
(define-constant err-transfer-failed (err u120))

;; Configuration limits
(define-constant MAX-ASSET-VALUE u1000000000000) ;; 1 trillion
(define-constant MIN-ASSET-VALUE u1000) ;; 1 thousand
(define-constant MAX-DURATION u144) ;; ~1 day in blocks
(define-constant MIN-DURATION u12) ;; ~1 hour in blocks
(define-constant MAX-KYC-LEVEL u5)
(define-constant MAX-EXPIRY u52560) ;; ~1 year in blocks

;; SFTs per asset
(define-constant tokens-per-asset u100000)

;; Data Variables for ID tracking
(define-data-var last-asset-id uint u0)
(define-data-var last-proposal-id uint u0)

;; Data Maps

;; Asset registry
(define-map assets
  { asset-id: uint }
  {
    owner: principal,
    metadata-uri: (string-ascii 256),
    asset-value: uint,
    is-locked: bool,
    creation-height: uint,
    last-price-update: uint,
    total-dividends: uint,
  }
)

;; Token ownership records
(define-map token-balances
  {
    owner: principal,
    asset-id: uint,
  }
  { balance: uint }
)

;; KYC compliance registry
(define-map kyc-status
  { address: principal }
  {
    is-approved: bool,
    level: uint,
    expiry: uint,
  }
)

;; Governance proposals
(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 256),
    asset-id: uint,
    start-height: uint,
    end-height: uint,
    executed: bool,
    votes-for: uint,
    votes-against: uint,
    minimum-votes: uint,
  }
)

;; Voting registry
(define-map votes
  {
    proposal-id: uint,
    voter: principal,
  }
  { vote-amount: uint }
)

;; Dividend claim tracker
(define-map dividend-claims
  {
    asset-id: uint,
    claimer: principal,
  }
  { last-claimed-amount: uint }
)

;; Oracle price feeds
(define-map price-feeds
  { asset-id: uint }
  {
    price: uint,
    decimals: uint,
    last-updated: uint,
    oracle: principal,
  }
)

;; Input Validation Functions

;; Validates that an asset value is within acceptable bounds
(define-private (validate-asset-value (value uint))
  (and
    (>= value MIN-ASSET-VALUE)
    (<= value MAX-ASSET-VALUE)
  )
)

;; Validates that a governance proposal duration is within acceptable bounds
(define-private (validate-duration (duration uint))
  (and
    (>= duration MIN-DURATION)
    (<= duration MAX-DURATION)
  )
)

;; Validates that a KYC level is within acceptable bounds
(define-private (validate-kyc-level (level uint))
  (<= level MAX-KYC-LEVEL)
)

;; Validates that an expiry block height is within acceptable bounds
(define-private (validate-expiry (expiry uint))
  (and
    (> expiry stacks-block-height)
    (<= (- expiry stacks-block-height) MAX-EXPIRY)
  )
)

;; Validates that a minimum vote count is reasonable
(define-private (validate-minimum-votes (vote-count uint))
  (and
    (> vote-count u0)
    (<= vote-count tokens-per-asset)
  )
)

;; Validates that a metadata URI is valid
(define-private (validate-metadata-uri (uri (string-ascii 256)))
  (and
    (> (len uri) u0)
    (<= (len uri) u256)
  )
)

;; Validates that a principal address is valid (not zero address)
(define-private (validate-principal (addr principal))
  (not (is-eq addr 'SP000000000000000000002Q6VF78))
)

;; Validates that decimals value is reasonable for price feeds
(define-private (validate-decimals (decimals uint))
  (and
    (>= decimals u0)
    (<= decimals u18)
  )
)

;; Helper Functions

;; Gets the next asset ID to be assigned and increments the counter
(define-private (get-next-asset-id)
  (let ((next-id (+ (var-get last-asset-id) u1)))
    (var-set last-asset-id next-id)
    next-id
  )
)

;; Gets the next proposal ID to be assigned and increments the counter
(define-private (get-next-proposal-id)
  (let ((next-id (+ (var-get last-proposal-id) u1)))
    (var-set last-proposal-id next-id)
    next-id
  )
)

;; Gets the last asset ID that was assigned
(define-private (get-last-asset-id)
  (some (var-get last-asset-id))
)

;; Gets the last proposal ID that was assigned
(define-private (get-last-proposal-id)
  (some (var-get last-proposal-id))
)

;; Checks if a user has valid KYC status
(define-private (is-kyc-valid (user principal))
  (match (map-get? kyc-status { address: user })
    kyc-info (and
      (get is-approved kyc-info)
      (> (get expiry kyc-info) stacks-block-height)
    )
    false
  )
)

;; Asset Management Functions

;; Registers a new asset with the protocol
(define-public (register-asset
    (metadata-uri (string-ascii 256))
    (asset-value uint)
  )
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (validate-metadata-uri metadata-uri) err-invalid-uri)
    (asserts! (validate-asset-value asset-value) err-invalid-value)
    (let ((asset-id (get-next-asset-id)))
      (map-set assets { asset-id: asset-id } {
        owner: contract-owner,
        metadata-uri: metadata-uri,
        asset-value: asset-value,
        is-locked: false,
        creation-height: stacks-block-height,
        last-price-update: stacks-block-height,
        total-dividends: u0,
      })
      (map-set token-balances {
        owner: contract-owner,
        asset-id: asset-id,
      } { balance: tokens-per-asset }
      )
      (ok asset-id)
    )
  )
)

;; Transfers tokens from one user to another
(define-public (transfer-tokens
    (asset-id uint)
    (amount uint)
    (recipient principal)
  )
  (let (
      (sender-balance (get-balance tx-sender asset-id))
      (recipient-balance (get-balance recipient asset-id))
    )
    (begin
      (asserts! (is-some (get-asset-info asset-id)) err-not-found)
      (asserts! (>= sender-balance amount) err-insufficient-balance)
      (asserts! (> amount u0) err-invalid-amount)
      (asserts! (is-kyc-valid tx-sender) err-kyc-required)
      (asserts! (is-kyc-valid recipient) err-kyc-required)
      ;; Update sender balance
      (map-set token-balances {
        owner: tx-sender,
        asset-id: asset-id,
      } { balance: (- sender-balance amount) }
      )
      ;; Update recipient balance
      (map-set token-balances {
        owner: recipient,
        asset-id: asset-id,
      } { balance: (+ recipient-balance amount) }
      )
      (ok true)
    )
  )
)

;; KYC Management Functions

;; Approves KYC status for a user
(define-public (approve-kyc
    (user principal)
    (level uint)
    (expiry uint)
  )
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (validate-principal user) err-invalid-address)
    (asserts! (validate-kyc-level level) err-invalid-kyc-level)
    (asserts! (validate-expiry expiry) err-invalid-expiry)
    (ok (map-set kyc-status { address: user } {
      is-approved: true,
      level: level,
      expiry: expiry,
    }))
  )
)

;; Revokes KYC status for a user
(define-public (revoke-kyc (user principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (validate-principal user) err-invalid-address)
    (ok (map-set kyc-status { address: user } {
      is-approved: false,
      level: u0,
      expiry: u0,
    }))
  )
)

;; Oracle Functions

;; Updates price feed for an asset (only owner can call)
(define-public (update-price-feed
    (asset-id uint)
    (price uint)
    (decimals uint)
  )
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-some (get-asset-info asset-id)) err-not-found)
    (asserts! (> price u0) err-invalid-value)
    (asserts! (validate-decimals decimals) err-invalid-value)
    (ok (map-set price-feeds { asset-id: asset-id } {
      price: price,
      decimals: decimals,
      last-updated: stacks-block-height,
      oracle: tx-sender,
    }))
  )
)

;; Dividend Functions

;; Distributes dividends to an asset (only owner can call)
(define-public (distribute-dividends
    (asset-id uint)
    (dividend-amount uint)
  )
  (let ((asset (unwrap! (get-asset-info asset-id) err-not-found)))
    (begin
      (asserts! (is-eq tx-sender contract-owner) err-owner-only)
      (asserts! (> dividend-amount u0) err-invalid-amount)
      (asserts! (> asset-id u0) err-invalid-value)
      (ok (map-set assets { asset-id: asset-id }
        (merge asset { total-dividends: (+ (get total-dividends asset) dividend-amount) })
      ))
    )
  )
)

;; Claims available dividends for a given asset
(define-public (claim-dividends (asset-id uint))
  (let (
      (asset (unwrap! (get-asset-info asset-id) err-not-found))
      (balance (get-balance tx-sender asset-id))
      (last-claim (get-last-claim asset-id tx-sender))
      (total-dividends (get total-dividends asset))
      (claimable-amount (/ (* balance (- total-dividends last-claim)) tokens-per-asset))
    )
    (begin
      (asserts! (> claimable-amount u0) err-invalid-amount)
      (asserts! (> balance u0) err-insufficient-balance)
      (map-set dividend-claims {
        asset-id: asset-id,
        claimer: tx-sender,
      } { last-claimed-amount: total-dividends }
      )
      (ok claimable-amount)
    )
  )
)

;; Governance Functions

;; Creates a new governance proposal for an asset
(define-public (create-proposal
    (asset-id uint)
    (title (string-ascii 256))
    (duration uint)
    (minimum-votes uint)
  )
  (begin
    (asserts! (is-some (get-asset-info asset-id)) err-not-found)
    (asserts! (validate-duration duration) err-invalid-duration)
    (asserts! (validate-minimum-votes minimum-votes) err-invalid-votes)
    (asserts! (validate-metadata-uri title) err-invalid-title)
    (asserts! (>= (get-balance tx-sender asset-id) (/ tokens-per-asset u10))
      err-not-authorized
    )
    (asserts! (is-kyc-valid tx-sender) err-kyc-required)
    (let ((proposal-id (get-next-proposal-id)))
      (map-set proposals { proposal-id: proposal-id } {
        title: title,
        asset-id: asset-id,
        start-height: stacks-block-height,
        end-height: (+ stacks-block-height duration),
        executed: false,
        votes-for: u0,
        votes-against: u0,
        minimum-votes: minimum-votes,
      })
      (ok proposal-id)
    )
  )
)

;; Casts a vote on a governance proposal
(define-public (vote
    (proposal-id uint)
    (vote-for bool)
    (amount uint)
  )
  (let (
      (proposal (unwrap! (get-proposal proposal-id) err-not-found))
      (asset-id (get asset-id proposal))
      (balance (get-balance tx-sender asset-id))
    )
    (begin
      (asserts! (>= balance amount) err-insufficient-balance)
      (asserts! (> amount u0) err-invalid-amount)
      (asserts! (< stacks-block-height (get end-height proposal)) err-vote-ended)
      (asserts! (is-none (get-vote proposal-id tx-sender)) err-vote-exists)
      (asserts! (is-kyc-valid tx-sender) err-kyc-required)
      (map-set votes {
        proposal-id: proposal-id,
        voter: tx-sender,
      } { vote-amount: amount }
      )
      (map-set proposals { proposal-id: proposal-id }
        (merge proposal {
          votes-for: (if vote-for
            (+ (get votes-for proposal) amount)
            (get votes-for proposal)
          ),
          votes-against: (if vote-for
            (get votes-against proposal)
            (+ (get votes-against proposal) amount)
          ),
        })
      )
      (ok true)
    )
  )
)

;; Executes a governance proposal if it has passed
(define-public (execute-proposal (proposal-id uint))
  (let ((proposal (unwrap! (get-proposal proposal-id) err-not-found)))
    (begin
      (asserts! (>= stacks-block-height (get end-height proposal)) err-vote-ended)
      (asserts! (not (get executed proposal)) err-already-listed)
      (asserts!
        (>= (+ (get votes-for proposal) (get votes-against proposal))
          (get minimum-votes proposal)
        )
        err-invalid-votes
      )
      (asserts! (> (get votes-for proposal) (get votes-against proposal))
        err-not-authorized
      )
      (map-set proposals { proposal-id: proposal-id }
        (merge proposal { executed: true })
      )
      (ok true)
    )
  )
)

;; Read-Only Functions

;; Gets information about an asset
(define-read-only (get-asset-info (asset-id uint))
  (map-get? assets { asset-id: asset-id })
)

;; Gets the balance of tokens for an owner of a given asset
(define-read-only (get-balance
    (owner principal)
    (asset-id uint)
  )
  (default-to u0
    (get balance
      (map-get? token-balances {
        owner: owner,
        asset-id: asset-id,
      })
    ))
)

;; Gets information about a proposal
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

;; Gets information about a vote cast by a voter on a proposal
(define-read-only (get-vote
    (proposal-id uint)
    (voter principal)
  )
  (map-get? votes {
    proposal-id: proposal-id,
    voter: voter,
  })
)

;; Gets the price feed information for an asset
(define-read-only (get-price-feed (asset-id uint))
  (map-get? price-feeds { asset-id: asset-id })
)

;; Gets the last claimed dividend amount for a user on an asset
(define-read-only (get-last-claim
    (asset-id uint)
    (claimer principal)
  )
  (default-to u0
    (get last-claimed-amount
      (map-get? dividend-claims {
        asset-id: asset-id,
        claimer: claimer,
      })
    ))
)

;; Gets KYC status for a user
(define-read-only (get-kyc-status (user principal))
  (map-get? kyc-status { address: user })
)

;; Gets the current asset counter
(define-read-only (get-total-assets)
  (var-get last-asset-id)
)

;; Gets the current proposal counter
(define-read-only (get-total-proposals)
  (var-get last-proposal-id)
)

;; Checks if a proposal has passed
(define-read-only (has-proposal-passed (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal (and
      (>= stacks-block-height (get end-height proposal))
      (>= (+ (get votes-for proposal) (get votes-against proposal))
        (get minimum-votes proposal)
      )
      (> (get votes-for proposal) (get votes-against proposal))
    )
    false
  )
)
