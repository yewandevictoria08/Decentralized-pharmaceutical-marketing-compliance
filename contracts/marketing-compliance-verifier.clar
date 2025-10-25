;; Marketing Compliance Verifier Smart Contract
;; Ensures pharmaceutical marketing materials comply with regulations and ethical guidelines

;; Constants for contract administration
(define-constant contract-owner tx-sender)
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-already-reviewed (err u104))
(define-constant err-invalid-severity (err u105))
(define-constant err-invalid-jurisdiction (err u106))
(define-constant err-claim-limit-exceeded (err u107))
(define-constant err-material-not-approved (err u108))

;; Material status constants
(define-constant status-pending u1)
(define-constant status-under-review u2)
(define-constant status-approved u3)
(define-constant status-rejected u4)
(define-constant status-revision-required u5)

;; Claim verification status
(define-constant claim-unverified u1)
(define-constant claim-verified u2)
(define-constant claim-rejected u3)

;; Violation severity levels
(define-constant severity-low u1)
(define-constant severity-medium u2)
(define-constant severity-high u3)
(define-constant severity-critical u4)

;; Jurisdiction codes
(define-constant jurisdiction-fda u1)
(define-constant jurisdiction-ema u2)
(define-constant jurisdiction-pmda u3)
(define-constant jurisdiction-tga u4)
(define-constant jurisdiction-global u5)

;; Maximum claims per material
(define-constant max-claims-per-material u50)

;; Data variables for tracking IDs and statistics
(define-data-var material-id-nonce uint u0)
(define-data-var claim-id-nonce uint u0)
(define-data-var review-id-nonce uint u0)
(define-data-var violation-id-nonce uint u0)
(define-data-var total-materials uint u0)
(define-data-var total-approved uint u0)
(define-data-var total-rejected uint u0)
(define-data-var total-violations uint u0)
(define-data-var total-claims uint u0)

;; Marketing materials registry
(define-map marketing-materials
  { material-id: uint }
  {
    company: principal,
    title: (string-ascii 100),
    content-hash: (string-ascii 64),
    material-type: (string-ascii 50),
    jurisdiction: uint,
    status: uint,
    submitted-at: uint,
    reviewed-at: uint,
    claim-count: uint
  }
)

;; Claims database
(define-map claims
  { claim-id: uint }
  {
    material-id: uint,
    claim-text: (string-ascii 200),
    evidence-hash: (string-ascii 64),
    status: uint,
    verified: bool,
    verifier: (optional principal),
    verified-at: uint
  }
)

;; Compliance reviews
(define-map compliance-reviews
  { review-id: uint }
  {
    material-id: uint,
    reviewer: principal,
    compliant: bool,
    notes: (string-ascii 200),
    reviewed-at: uint
  }
)

;; Violations registry
(define-map violations
  { violation-id: uint }
  {
    material-id: uint,
    violation-type: (string-ascii 100),
    severity: uint,
    reporter: principal,
    reported-at: uint,
    resolved: bool
  }
)

;; Company materials tracking
(define-map company-materials
  { company: principal, index: uint }
  { material-id: uint }
)

(define-map company-material-count
  { company: principal }
  { count: uint }
)

;; Reviewer tracking
(define-map reviewer-stats
  { reviewer: principal }
  { total-reviews: uint, approved-count: uint, rejected-count: uint }
)

;; Material-specific claim tracking
(define-map material-claims
  { material-id: uint, claim-index: uint }
  { claim-id: uint }
)

;; Private helper functions
(define-private (get-next-material-id)
  (let ((current-id (var-get material-id-nonce)))
    (var-set material-id-nonce (+ current-id u1))
    current-id
  )
)

(define-private (get-next-claim-id)
  (let ((current-id (var-get claim-id-nonce)))
    (var-set claim-id-nonce (+ current-id u1))
    current-id
  )
)

(define-private (get-next-review-id)
  (let ((current-id (var-get review-id-nonce)))
    (var-set review-id-nonce (+ current-id u1))
    current-id
  )
)

(define-private (get-next-violation-id)
  (let ((current-id (var-get violation-id-nonce)))
    (var-set violation-id-nonce (+ current-id u1))
    current-id
  )
)

(define-private (is-valid-jurisdiction (jurisdiction uint))
  (or
    (is-eq jurisdiction jurisdiction-fda)
    (is-eq jurisdiction jurisdiction-ema)
    (is-eq jurisdiction jurisdiction-pmda)
    (is-eq jurisdiction jurisdiction-tga)
    (is-eq jurisdiction jurisdiction-global)
  )
)

(define-private (is-valid-severity (severity uint))
  (or
    (is-eq severity severity-low)
    (is-eq severity severity-medium)
    (is-eq severity severity-high)
    (is-eq severity severity-critical)
  )
)

;; Public functions

;; Submit marketing material for compliance review
(define-public (submit-material
  (title (string-ascii 100))
  (content-hash (string-ascii 64))
  (material-type (string-ascii 50))
  (jurisdiction uint))
  (let
    (
      (material-id (get-next-material-id))
      (company-count (default-to { count: u0 } (map-get? company-material-count { company: tx-sender })))
    )
    (asserts! (is-valid-jurisdiction jurisdiction) err-invalid-jurisdiction)
    (map-set marketing-materials
      { material-id: material-id }
      {
        company: tx-sender,
        title: title,
        content-hash: content-hash,
        material-type: material-type,
        jurisdiction: jurisdiction,
        status: status-pending,
        submitted-at: stacks-block-height,
        reviewed-at: u0,
        claim-count: u0
      }
    )
    (map-set company-materials
      { company: tx-sender, index: (get count company-count) }
      { material-id: material-id }
    )
    (map-set company-material-count
      { company: tx-sender }
      { count: (+ (get count company-count) u1) }
    )
    (var-set total-materials (+ (var-get total-materials) u1))
    (ok material-id)
  )
)

;; Add a medical claim to a material
(define-public (add-claim
  (material-id uint)
  (claim-text (string-ascii 200))
  (evidence-hash (string-ascii 64)))
  (let
    (
      (claim-id (get-next-claim-id))
      (material (unwrap! (map-get? marketing-materials { material-id: material-id }) err-not-found))
      (current-claim-count (get claim-count material))
    )
    (asserts! (is-eq tx-sender (get company material)) err-unauthorized)
    (asserts! (< current-claim-count max-claims-per-material) err-claim-limit-exceeded)
    (map-set claims
      { claim-id: claim-id }
      {
        material-id: material-id,
        claim-text: claim-text,
        evidence-hash: evidence-hash,
        status: claim-unverified,
        verified: false,
        verifier: none,
        verified-at: u0
      }
    )
    (map-set material-claims
      { material-id: material-id, claim-index: current-claim-count }
      { claim-id: claim-id }
    )
    (map-set marketing-materials
      { material-id: material-id }
      (merge material { claim-count: (+ current-claim-count u1) })
    )
    (var-set total-claims (+ (var-get total-claims) u1))
    (ok claim-id)
  )
)

;; Review a marketing material for compliance
(define-public (review-material
  (material-id uint)
  (compliant bool)
  (notes (string-ascii 200)))
  (let
    (
      (material (unwrap! (map-get? marketing-materials { material-id: material-id }) err-not-found))
      (review-id (get-next-review-id))
      (reviewer-data (default-to
        { total-reviews: u0, approved-count: u0, rejected-count: u0 }
        (map-get? reviewer-stats { reviewer: tx-sender })
      ))
    )
    (asserts! (is-eq (get reviewed-at material) u0) err-already-reviewed)
    (map-set compliance-reviews
      { review-id: review-id }
      {
        material-id: material-id,
        reviewer: tx-sender,
        compliant: compliant,
        notes: notes,
        reviewed-at: stacks-block-height
      }
    )
    (map-set marketing-materials
      { material-id: material-id }
      (merge material
        {
          status: (if compliant status-approved status-rejected),
          reviewed-at: stacks-block-height
        }
      )
    )
    (map-set reviewer-stats
      { reviewer: tx-sender }
      {
        total-reviews: (+ (get total-reviews reviewer-data) u1),
        approved-count: (if compliant (+ (get approved-count reviewer-data) u1) (get approved-count reviewer-data)),
        rejected-count: (if compliant (get rejected-count reviewer-data) (+ (get rejected-count reviewer-data) u1))
      }
    )
    (if compliant
      (var-set total-approved (+ (var-get total-approved) u1))
      (var-set total-rejected (+ (var-get total-rejected) u1))
    )
    (ok review-id)
  )
)

;; Report a compliance violation
(define-public (report-violation
  (material-id uint)
  (violation-type (string-ascii 100))
  (severity uint))
  (let
    (
      (material (unwrap! (map-get? marketing-materials { material-id: material-id }) err-not-found))
      (violation-id (get-next-violation-id))
    )
    (asserts! (is-valid-severity severity) err-invalid-severity)
    (map-set violations
      { violation-id: violation-id }
      {
        material-id: material-id,
        violation-type: violation-type,
        severity: severity,
        reporter: tx-sender,
        reported-at: stacks-block-height,
        resolved: false
      }
    )
    (var-set total-violations (+ (var-get total-violations) u1))
    (ok violation-id)
  )
)

;; Verify a medical claim
(define-public (verify-claim (claim-id uint))
  (let
    (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-not-found))
    )
    (map-set claims
      { claim-id: claim-id }
      (merge claim
        {
          status: claim-verified,
          verified: true,
          verifier: (some tx-sender),
          verified-at: stacks-block-height
        }
      )
    )
    (ok true)
  )
)

;; Reject a medical claim
(define-public (reject-claim (claim-id uint))
  (let
    (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-not-found))
    )
    (map-set claims
      { claim-id: claim-id }
      (merge claim
        {
          status: claim-rejected,
          verified: false,
          verifier: (some tx-sender),
          verified-at: stacks-block-height
        }
      )
    )
    (ok true)
  )
)

;; Mark violation as resolved
(define-public (resolve-violation (violation-id uint))
  (let
    (
      (violation (unwrap! (map-get? violations { violation-id: violation-id }) err-not-found))
    )
    (map-set violations
      { violation-id: violation-id }
      (merge violation { resolved: true })
    )
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-material (material-id uint))
  (map-get? marketing-materials { material-id: material-id })
)

(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)

(define-read-only (get-review (review-id uint))
  (map-get? compliance-reviews { review-id: review-id })
)

(define-read-only (get-violation (violation-id uint))
  (map-get? violations { violation-id: violation-id })
)

(define-read-only (get-company-material (company principal) (index uint))
  (map-get? company-materials { company: company, index: index })
)

(define-read-only (get-material-claim (material-id uint) (claim-index uint))
  (map-get? material-claims { material-id: material-id, claim-index: claim-index })
)

(define-read-only (get-reviewer-stats (reviewer principal))
  (map-get? reviewer-stats { reviewer: reviewer })
)

(define-read-only (get-company-material-count (company principal))
  (default-to { count: u0 } (map-get? company-material-count { company: company }))
)

(define-read-only (get-platform-stats)
  {
    total-materials: (var-get total-materials),
    total-approved: (var-get total-approved),
    total-rejected: (var-get total-rejected),
    total-violations: (var-get total-violations),
    total-claims: (var-get total-claims)
  }
)
