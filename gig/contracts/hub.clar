;; Gig Worker Payment Hub Smart Contract
;; A decentralized platform for managing gig work, escrow payments, disputes, and reputation

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-invalid-amount (err u106))
(define-constant err-already-completed (err u107))
(define-constant err-dispute-active (err u108))
(define-constant err-invalid-rating (err u109))
(define-constant err-invalid-deadline (err u110))
(define-constant err-empty-string (err u111))

(define-constant max-payment u1000000000000) ;; 1 million STX max
(define-constant min-payment u100000) ;; 0.1 STX min

;; Data Variables
(define-data-var platform-fee-percent uint u250) ;; 2.5% (basis points)
(define-data-var min-dispute-deposit uint u1000000) ;; 1 STX in microSTX
(define-data-var gig-nonce uint u0)
(define-data-var dispute-nonce uint u0)

;; Data Maps
(define-map gigs
  uint
  {
    client: principal,
    worker: (optional principal),
    title: (string-ascii 100),
    description: (string-ascii 500),
    payment: uint,
    escrow-amount: uint,
    deadline: uint,
    status: (string-ascii 20),
    created-at: uint,
    completed-at: (optional uint)
  }
)

(define-map worker-profiles
  principal
  {
    total-gigs: uint,
    completed-gigs: uint,
    total-earned: uint,
    rating-sum: uint,
    rating-count: uint,
    active: bool
  }
)

(define-map client-profiles
  principal
  {
    total-gigs-posted: uint,
    total-spent: uint,
    rating-sum: uint,
    rating-count: uint
  }
)

(define-map disputes
  uint
  {
    gig-id: uint,
    initiator: principal,
    reason: (string-ascii 300),
    status: (string-ascii 20),
    resolution: (optional (string-ascii 20)),
    created-at: uint,
    resolved-at: (optional uint)
  }
)

(define-map gig-applications
  {gig-id: uint, worker: principal}
  {
    applied-at: uint,
    proposal: (string-ascii 300),
    status: (string-ascii 20)
  }
)

(define-map ratings
  {gig-id: uint, rater: principal}
  {
    rating: uint,
    comment: (string-ascii 200),
    created-at: uint
  }
)

;; Private Functions
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-percent)) u10000)
)

(define-private (get-worker-avg-rating (worker principal))
  (let ((profile (unwrap! (map-get? worker-profiles worker) u0)))
    (if (> (get rating-count profile) u0)
      (/ (get rating-sum profile) (get rating-count profile))
      u0
    )
  )
)

(define-private (is-valid-string (str (string-ascii 500)))
  (> (len str) u0)
)

(define-private (is-valid-short-string (str (string-ascii 300)))
  (> (len str) u0)
)

(define-private (is-valid-comment (str (string-ascii 200)))
  (> (len str) u0)
)

(define-private (is-valid-title (str (string-ascii 100)))
  (and (> (len str) u0) (<= (len str) u100))
)

;; Read-Only Functions
(define-read-only (get-gig (gig-id uint))
  (map-get? gigs gig-id)
)

(define-read-only (get-worker-profile (worker principal))
  (map-get? worker-profiles worker)
)

(define-read-only (get-client-profile (client principal))
  (map-get? client-profiles client)
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes dispute-id)
)

(define-read-only (get-application (gig-id uint) (worker principal))
  (map-get? gig-applications {gig-id: gig-id, worker: worker})
)

(define-read-only (get-rating (gig-id uint) (rater principal))
  (map-get? ratings {gig-id: gig-id, rater: rater})
)

(define-read-only (get-platform-fee-percent)
  (ok (var-get platform-fee-percent))
)

(define-read-only (calculate-fee (amount uint))
  (ok (calculate-platform-fee amount))
)

;; Public Functions

;; Create a new gig posting
(define-public (create-gig (title (string-ascii 100)) (description (string-ascii 500)) (payment uint) (deadline uint))
  (let
    (
      (gig-id (+ (var-get gig-nonce) u1))
      (validated-payment (begin
        (asserts! (>= payment min-payment) err-invalid-amount)
        (asserts! (<= payment max-payment) err-invalid-amount)
        payment
      ))
      (validated-deadline (begin
        (asserts! (> deadline block-height) err-invalid-deadline)
        deadline
      ))
      (validated-title (begin
        (asserts! (is-valid-title title) err-empty-string)
        title
      ))
      (validated-description (begin
        (asserts! (is-valid-string description) err-empty-string)
        description
      ))
      (fee (calculate-platform-fee validated-payment))
      (total-amount (+ validated-payment fee))
    )
    (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
    (map-set gigs gig-id {
      client: tx-sender,
      worker: none,
      title: validated-title,
      description: validated-description,
      payment: validated-payment,
      escrow-amount: total-amount,
      deadline: validated-deadline,
      status: "open",
      created-at: block-height,
      completed-at: none
    })
    (map-set client-profiles tx-sender
      (merge (default-to {total-gigs-posted: u0, total-spent: u0, rating-sum: u0, rating-count: u0}
        (map-get? client-profiles tx-sender))
        {total-gigs-posted: (+ (default-to u0 (get total-gigs-posted (map-get? client-profiles tx-sender))) u1)}
      )
    )
    (var-set gig-nonce gig-id)
    (ok gig-id)
  )
)

;; Apply for a gig
(define-public (apply-for-gig (gig-id uint) (proposal (string-ascii 300)))
  (let 
    (
      (gig (unwrap! (map-get? gigs gig-id) err-not-found))
      (validated-proposal (begin
        (asserts! (is-valid-short-string proposal) err-empty-string)
        proposal
      ))
    )
    (asserts! (is-eq (get status gig) "open") err-invalid-status)
    (asserts! (is-none (map-get? gig-applications {gig-id: gig-id, worker: tx-sender})) err-already-exists)
    (map-set gig-applications {gig-id: gig-id, worker: tx-sender} {
      applied-at: block-height,
      proposal: validated-proposal,
      status: "pending"
    })
    (ok true)
  )
)

;; Assign worker to gig
(define-public (assign-worker (gig-id uint) (worker principal))
  (let 
    (
      (gig (unwrap! (map-get? gigs gig-id) err-not-found))
      (validated-worker (begin
        (asserts! (not (is-eq worker tx-sender)) err-unauthorized)
        (asserts! (is-standard worker) err-unauthorized)
        worker
      ))
    )
    (asserts! (is-eq tx-sender (get client gig)) err-unauthorized)
    (asserts! (is-eq (get status gig) "open") err-invalid-status)
    (map-set gigs gig-id (merge gig {worker: (some validated-worker), status: "assigned"}))
    (map-set worker-profiles validated-worker
      (merge (default-to {total-gigs: u0, completed-gigs: u0, total-earned: u0, rating-sum: u0, rating-count: u0, active: true}
        (map-get? worker-profiles validated-worker))
        {total-gigs: (+ (default-to u0 (get total-gigs (map-get? worker-profiles validated-worker))) u1)}
      )
    )
    (ok true)
  )
)

;; Mark gig as completed by worker
(define-public (complete-gig (gig-id uint))
  (let ((gig (unwrap! (map-get? gigs gig-id) err-not-found)))
    (asserts! (is-eq (some tx-sender) (get worker gig)) err-unauthorized)
    (asserts! (is-eq (get status gig) "assigned") err-invalid-status)
    (map-set gigs gig-id (merge gig {status: "completed", completed-at: (some block-height)}))
    (ok true)
  )
)

;; Approve completion and release payment
(define-public (approve-and-pay (gig-id uint))
  (let
    (
      (gig (unwrap! (map-get? gigs gig-id) err-not-found))
      (worker (unwrap! (get worker gig) err-not-found))
      (payment (get payment gig))
    )
    (asserts! (is-eq tx-sender (get client gig)) err-unauthorized)
    (asserts! (is-eq (get status gig) "completed") err-invalid-status)
    (try! (as-contract (stx-transfer? payment tx-sender worker)))
    (map-set gigs gig-id (merge gig {status: "paid"}))
    (map-set worker-profiles worker
      (merge (unwrap! (map-get? worker-profiles worker) err-not-found)
        {
          completed-gigs: (+ (get completed-gigs (unwrap! (map-get? worker-profiles worker) err-not-found)) u1),
          total-earned: (+ (get total-earned (unwrap! (map-get? worker-profiles worker) err-not-found)) payment)
        }
      )
    )
    (map-set client-profiles tx-sender
      (merge (unwrap! (map-get? client-profiles tx-sender) err-not-found)
        {total-spent: (+ (get total-spent (unwrap! (map-get? client-profiles tx-sender) err-not-found)) payment)}
      )
    )
    (ok true)
  )
)

;; Create dispute
(define-public (create-dispute (gig-id uint) (reason (string-ascii 300)))
  (let
    (
      (gig (unwrap! (map-get? gigs gig-id) err-not-found))
      (dispute-id (+ (var-get dispute-nonce) u1))
      (is-participant (or (is-eq tx-sender (get client gig)) 
                         (is-eq (some tx-sender) (get worker gig))))
      (validated-reason (begin
        (asserts! (is-valid-short-string reason) err-empty-string)
        reason
      ))
    )
    (asserts! is-participant err-unauthorized)
    (asserts! (not (is-eq (get status gig) "paid")) err-already-completed)
    (map-set disputes dispute-id {
      gig-id: gig-id,
      initiator: tx-sender,
      reason: validated-reason,
      status: "open",
      resolution: none,
      created-at: block-height,
      resolved-at: none
    })
    (map-set gigs gig-id (merge gig {status: "disputed"}))
    (var-set dispute-nonce dispute-id)
    (ok dispute-id)
  )
)

;; Resolve dispute (owner only)
(define-public (resolve-dispute (dispute-id uint) (resolution (string-ascii 20)) (pay-worker bool))
  (let
    (
      (dispute (unwrap! (map-get? disputes dispute-id) err-not-found))
      (gig (unwrap! (map-get? gigs (get gig-id dispute)) err-not-found))
      (worker (unwrap! (get worker gig) err-not-found))
      (payment (get payment gig))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-eq (get status dispute) "open") err-invalid-status)
    (if pay-worker
      (try! (as-contract (stx-transfer? payment tx-sender worker)))
      (try! (as-contract (stx-transfer? payment tx-sender (get client gig))))
    )
    (map-set disputes dispute-id (merge dispute {
      status: "resolved",
      resolution: (some resolution),
      resolved-at: (some block-height)
    }))
    (map-set gigs (get gig-id dispute) (merge gig {status: "resolved"}))
    (ok true)
  )
)

;; Rate worker or client
(define-public (rate-participant (gig-id uint) (rating uint) (comment (string-ascii 200)))
  (let
    (
      (gig (unwrap! (map-get? gigs gig-id) err-not-found))
      (worker (unwrap! (get worker gig) err-not-found))
      (is-client (is-eq tx-sender (get client gig)))
      (is-worker (is-eq tx-sender worker))
      (target (if is-client worker (get client gig)))
      (validated-rating (begin
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
        rating
      ))
      (validated-comment (begin
        (asserts! (is-valid-comment comment) err-empty-string)
        comment
      ))
    )
    (asserts! (or is-client is-worker) err-unauthorized)
    (asserts! (is-eq (get status gig) "paid") err-invalid-status)
    (asserts! (is-none (map-get? ratings {gig-id: gig-id, rater: tx-sender})) err-already-exists)
    (map-set ratings {gig-id: gig-id, rater: tx-sender} {
      rating: validated-rating,
      comment: validated-comment,
      created-at: block-height
    })
    (if is-client
      (map-set worker-profiles target
        (merge (unwrap! (map-get? worker-profiles target) err-not-found)
          {
            rating-sum: (+ (get rating-sum (unwrap! (map-get? worker-profiles target) err-not-found)) validated-rating),
            rating-count: (+ (get rating-count (unwrap! (map-get? worker-profiles target) err-not-found)) u1)
          }
        )
      )
      (map-set client-profiles target
        (merge (unwrap! (map-get? client-profiles target) err-not-found)
          {
            rating-sum: (+ (get rating-sum (unwrap! (map-get? client-profiles target) err-not-found)) validated-rating),
            rating-count: (+ (get rating-count (unwrap! (map-get? client-profiles target) err-not-found)) u1)
          }
        )
      )
    )
    (ok true)
  )
)

;; Cancel gig (only if not assigned)
(define-public (cancel-gig (gig-id uint))
  (let
    (
      (gig (unwrap! (map-get? gigs gig-id) err-not-found))
      (refund-amount (get escrow-amount gig))
    )
    (asserts! (is-eq tx-sender (get client gig)) err-unauthorized)
    (asserts! (is-eq (get status gig) "open") err-invalid-status)
    (try! (as-contract (stx-transfer? refund-amount tx-sender (get client gig))))
    (map-set gigs gig-id (merge gig {status: "cancelled"}))
    (ok refund-amount)
  )
)

;; Update platform fee (owner only)
(define-public (set-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee u1000) err-invalid-amount)
    (var-set platform-fee-percent new-fee)
    (ok true)
  )
)