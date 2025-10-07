;; Stone Provenance Ledger Contract
;; Tracks individual stones through their lifecycle from rough extraction to final sale
;; Maintains immutable records of transformations, ownership transfers, and quality assessments

;; Import the mine-and-trader-registry contract for entity validation
(use-trait entity-registry-trait .mine-and-trader-registry)

;; Constants for error handling
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_STONE_NOT_FOUND (err u201))
(define-constant ERR_STONE_ALREADY_REGISTERED (err u202))
(define-constant ERR_INVALID_ENTITY (err u203))
(define-constant ERR_INVALID_TRANSFORMATION (err u204))
(define-constant ERR_STONE_ALREADY_SOLD (err u205))
(define-constant ERR_INSUFFICIENT_COMPLIANCE (err u206))
(define-constant ERR_INVALID_QUALITY_GRADE (err u207))
(define-constant ERR_OWNERSHIP_TRANSFER_FAILED (err u208))
(define-constant ERR_INVALID_STONE_STATUS (err u209))

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Stone status enumeration
(define-constant STATUS_ROUGH u1)      ;; Just extracted from mine
(define-constant STATUS_CUT u2)        ;; Cut but not polished
(define-constant STATUS_POLISHED u3)   ;; Cut and polished
(define-constant STATUS_CERTIFIED u4)  ;; Lab certified
(define-constant STATUS_RETAIL u5)     ;; Ready for retail sale
(define-constant STATUS_SOLD u6)       ;; Sold to end consumer

;; Transformation types
(define-constant TRANSFORM_CUTTING u1)
(define-constant TRANSFORM_POLISHING u2)
(define-constant TRANSFORM_CERTIFICATION u3)
(define-constant TRANSFORM_SETTING u4) ;; Into jewelry

;; Quality grades (following GIA standards)
(define-constant GRADE_FL u1)  ;; Flawless
(define-constant GRADE_IF u2)  ;; Internally Flawless
(define-constant GRADE_VVS1 u3) ;; Very Very Slightly Included 1
(define-constant GRADE_VVS2 u4) ;; Very Very Slightly Included 2
(define-constant GRADE_VS1 u5)  ;; Very Slightly Included 1
(define-constant GRADE_VS2 u6)  ;; Very Slightly Included 2
(define-constant GRADE_SI1 u7)  ;; Slightly Included 1
(define-constant GRADE_SI2 u8)  ;; Slightly Included 2
(define-constant GRADE_I1 u9)   ;; Included 1
(define-constant GRADE_I2 u10)  ;; Included 2
(define-constant GRADE_I3 u11)  ;; Included 3

;; Stone counter for unique IDs
(define-data-var stone-counter uint u0)

;; Core stone registry
(define-map stone-registry
  { stone-id: uint }
  {
    origin-mine: principal,
    registration-date: uint,
    current-owner: principal,
    current-status: uint,
    rough-weight: uint,      ;; in milligrams
    current-weight: uint,    ;; in milligrams (changes with cutting)
    color-grade: (string-ascii 10),
    clarity-grade: uint,     ;; Using our grade constants
    cut-grade: (optional (string-ascii 20)),
    carat-weight: (optional uint), ;; in hundredths of carats
    dimensions: (optional (string-ascii 50)), ;; length x width x depth in mm
    is-conflict-free: bool,
    kp-certificate: (optional (string-ascii 100)),
    creation-block: uint,
    last-updated: uint
  }
)

;; Transformation history for each stone
(define-map transformation-history
  { stone-id: uint, transformation-id: uint }
  {
    transformation-type: uint,
    performed-by: principal,
    performed-date: uint,
    previous-weight: uint,
    new-weight: uint,
    previous-status: uint,
    new-status: uint,
    transformation-details: (string-ascii 300),
    quality-assessment: (optional (string-ascii 200)),
    verification-hash: (string-ascii 64) ;; For external verification
  }
)

;; Ownership transfer history
(define-map ownership-transfers
  { stone-id: uint, transfer-id: uint }
  {
    previous-owner: principal,
    new-owner: principal,
    transfer-date: uint,
    transfer-price: (optional uint), ;; in microSTX
    transfer-reason: (string-ascii 100),
    documentation-hash: (string-ascii 64),
    verified-by: (optional principal) ;; Authority that verified the transfer
  }
)

;; Laboratory certifications
(define-map lab-certifications
  { stone-id: uint, lab-id: principal }
  {
    certificate-number: (string-ascii 50),
    certification-date: uint,
    expiry-date: uint,
    carat-weight: uint,
    color-grade: (string-ascii 10),
    clarity-grade: uint,
    cut-grade: (string-ascii 20),
    lab-name: (string-ascii 100),
    certificate-hash: (string-ascii 64),
    is-valid: bool
  }
)

;; Quality assessments during transformations
(define-map quality-assessments
  { stone-id: uint, assessment-date: uint }
  {
    assessor: principal,
    assessment-type: uint, ;; 1=rough, 2=cut, 3=polished, 4=final
    weight: uint,
    measurements: (string-ascii 50),
    color-assessment: (string-ascii 20),
    clarity-assessment: uint,
    inclusions-map: (optional (string-ascii 200)),
    estimated-value: (optional uint),
    notes: (string-ascii 300)
  }
)

;; Transformation and transfer counters for each stone
(define-map stone-counters
  { stone-id: uint }
  {
    transformation-count: uint,
    transfer-count: uint,
    assessment-count: uint
  }
)

;; Public Functions

;; Register a new rough stone from a mine
(define-public (register-rough-stone
  (origin-mine principal)
  (rough-weight uint)
  (color-grade (string-ascii 10))
  (kp-certificate (optional (string-ascii 100)))
)
  (let (
    (stone-id (+ (var-get stone-counter) u1))
    (current-block-height block-height)
  )
    ;; Verify the mine is registered and compliant
    (asserts! (is-eq (contract-call? .mine-and-trader-registry is-entity-compliant origin-mine) true) ERR_INVALID_ENTITY)
    
    ;; Verify caller is the mine or authorized
    (asserts! (or 
      (is-eq tx-sender origin-mine)
      (is-eq tx-sender (var-get contract-owner))
    ) ERR_NOT_AUTHORIZED)
    
    ;; Register the stone
    (map-set stone-registry
      { stone-id: stone-id }
      {
        origin-mine: origin-mine,
        registration-date: current-block-height,
        current-owner: origin-mine,
        current-status: STATUS_ROUGH,
        rough-weight: rough-weight,
        current-weight: rough-weight,
        color-grade: color-grade,
        clarity-grade: u0, ;; To be assessed later
        cut-grade: none,
        carat-weight: none,
        dimensions: none,
        is-conflict-free: true, ;; Assumed true if from registered mine
        kp-certificate: kp-certificate,
        creation-block: current-block-height,
        last-updated: current-block-height
      }
    )
    
    ;; Initialize counters
    (map-set stone-counters
      { stone-id: stone-id }
      {
        transformation-count: u0,
        transfer-count: u0,
        assessment-count: u0
      }
    )
    
    ;; Update stone counter
    (var-set stone-counter stone-id)
    
    (ok stone-id)
  )
)

;; Perform transformation on a stone (cutting, polishing, etc.)
(define-public (perform-transformation
  (stone-id uint)
  (transformation-type uint)
  (new-weight uint)
  (new-status uint)
  (transformation-details (string-ascii 300))
  (verification-hash (string-ascii 64))
)
  (let (
    (stone-data (unwrap! (map-get? stone-registry { stone-id: stone-id }) ERR_STONE_NOT_FOUND))
    (counters (unwrap! (map-get? stone-counters { stone-id: stone-id }) ERR_STONE_NOT_FOUND))
    (transformation-id (+ (get transformation-count counters) u1))
    (current-block-height block-height)
  )
    ;; Verify entity is authorized for this transformation
    (asserts! (is-eq (contract-call? .mine-and-trader-registry is-entity-compliant tx-sender) true) ERR_INVALID_ENTITY)
    
    ;; Verify current owner or authorized processor
    (asserts! (is-eq tx-sender (get current-owner stone-data)) ERR_NOT_AUTHORIZED)
    
    ;; Validate transformation type and status progression
    (asserts! (and (>= transformation-type u1) (<= transformation-type u4)) ERR_INVALID_TRANSFORMATION)
    (asserts! (and (>= new-status u1) (<= new-status u6)) ERR_INVALID_STONE_STATUS)
    
    ;; Stone cannot be transformed if already sold
    (asserts! (not (is-eq (get current-status stone-data) STATUS_SOLD)) ERR_STONE_ALREADY_SOLD)
    
    ;; Weight should not increase (only decrease through cutting)
    (asserts! (<= new-weight (get current-weight stone-data)) ERR_INVALID_TRANSFORMATION)
    
    ;; Record transformation
    (map-set transformation-history
      { stone-id: stone-id, transformation-id: transformation-id }
      {
        transformation-type: transformation-type,
        performed-by: tx-sender,
        performed-date: current-block-height,
        previous-weight: (get current-weight stone-data),
        new-weight: new-weight,
        previous-status: (get current-status stone-data),
        new-status: new-status,
        transformation-details: transformation-details,
        quality-assessment: none,
        verification-hash: verification-hash
      }
    )
    
    ;; Update stone registry
    (map-set stone-registry
      { stone-id: stone-id }
      (merge stone-data {
        current-weight: new-weight,
        current-status: new-status,
        last-updated: current-block-height
      })
    )
    
    ;; Update counters
    (map-set stone-counters
      { stone-id: stone-id }
      (merge counters { transformation-count: transformation-id })
    )
    
    (ok transformation-id)
  )
)

;; Transfer ownership of a stone
(define-public (transfer-ownership
  (stone-id uint)
  (new-owner principal)
  (transfer-price (optional uint))
  (transfer-reason (string-ascii 100))
  (documentation-hash (string-ascii 64))
)
  (let (
    (stone-data (unwrap! (map-get? stone-registry { stone-id: stone-id }) ERR_STONE_NOT_FOUND))
    (counters (unwrap! (map-get? stone-counters { stone-id: stone-id }) ERR_STONE_NOT_FOUND))
    (transfer-id (+ (get transfer-count counters) u1))
    (current-block-height block-height)
  )
    ;; Verify current owner
    (asserts! (is-eq tx-sender (get current-owner stone-data)) ERR_NOT_AUTHORIZED)
    
    ;; Verify new owner is registered and compliant
    (asserts! (is-eq (contract-call? .mine-and-trader-registry is-entity-compliant new-owner) true) ERR_INVALID_ENTITY)
    
    ;; Stone cannot be transferred if already sold to end consumer
    (asserts! (not (is-eq (get current-status stone-data) STATUS_SOLD)) ERR_STONE_ALREADY_SOLD)
    
    ;; Record transfer
    (map-set ownership-transfers
      { stone-id: stone-id, transfer-id: transfer-id }
      {
        previous-owner: (get current-owner stone-data),
        new-owner: new-owner,
        transfer-date: current-block-height,
        transfer-price: transfer-price,
        transfer-reason: transfer-reason,
        documentation-hash: documentation-hash,
        verified-by: none
      }
    )
    
    ;; Update stone ownership
    (map-set stone-registry
      { stone-id: stone-id }
      (merge stone-data {
        current-owner: new-owner,
        last-updated: current-block-height
      })
    )
    
    ;; Update counters
    (map-set stone-counters
      { stone-id: stone-id }
      (merge counters { transfer-count: transfer-id })
    )
    
    (ok transfer-id)
  )
)

;; Add laboratory certification
(define-public (add-lab-certification
  (stone-id uint)
  (certificate-number (string-ascii 50))
  (expiry-date uint)
  (carat-weight uint)
  (color-grade (string-ascii 10))
  (clarity-grade uint)
  (cut-grade (string-ascii 20))
  (lab-name (string-ascii 100))
  (certificate-hash (string-ascii 64))
)
  (let (
    (stone-data (unwrap! (map-get? stone-registry { stone-id: stone-id }) ERR_STONE_NOT_FOUND))
    (current-block-height block-height)
  )
    ;; Verify lab is registered and authorized
    (asserts! (is-eq (contract-call? .mine-and-trader-registry is-entity-compliant tx-sender) true) ERR_INVALID_ENTITY)
    
    ;; Validate clarity grade
    (asserts! (and (>= clarity-grade u1) (<= clarity-grade u11)) ERR_INVALID_QUALITY_GRADE)
    
    ;; Add certification
    (map-set lab-certifications
      { stone-id: stone-id, lab-id: tx-sender }
      {
        certificate-number: certificate-number,
        certification-date: current-block-height,
        expiry-date: expiry-date,
        carat-weight: carat-weight,
        color-grade: color-grade,
        clarity-grade: clarity-grade,
        cut-grade: cut-grade,
        lab-name: lab-name,
        certificate-hash: certificate-hash,
        is-valid: true
      }
    )
    
    ;; Update stone status to certified
    (map-set stone-registry
      { stone-id: stone-id }
      (merge stone-data {
        current-status: STATUS_CERTIFIED,
        clarity-grade: clarity-grade,
        cut-grade: (some cut-grade),
        carat-weight: (some carat-weight),
        last-updated: current-block-height
      })
    )
    
    (ok true)
  )
)

;; Mark stone as sold to end consumer
(define-public (mark-stone-sold
  (stone-id uint)
  (final-buyer (optional principal))
  (sale-price (optional uint))
  (documentation-hash (string-ascii 64))
)
  (let (
    (stone-data (unwrap! (map-get? stone-registry { stone-id: stone-id }) ERR_STONE_NOT_FOUND))
    (counters (unwrap! (map-get? stone-counters { stone-id: stone-id }) ERR_STONE_NOT_FOUND))
    (transfer-id (+ (get transfer-count counters) u1))
    (current-block-height block-height)
  )
    ;; Verify current owner (retailer)
    (asserts! (is-eq tx-sender (get current-owner stone-data)) ERR_NOT_AUTHORIZED)
    
    ;; Stone must be ready for retail
    (asserts! (>= (get current-status stone-data) STATUS_RETAIL) ERR_INVALID_STONE_STATUS)
    
    ;; Record final sale
    (match final-buyer
      buyer
        (map-set ownership-transfers
          { stone-id: stone-id, transfer-id: transfer-id }
          {
            previous-owner: (get current-owner stone-data),
            new-owner: buyer,
            transfer-date: current-block-height,
            transfer-price: sale-price,
            transfer-reason: "Final consumer sale",
            documentation-hash: documentation-hash,
            verified-by: (some tx-sender)
          }
        )
      true ;; No buyer specified, just mark as sold
    )
    
    ;; Update stone status to sold
    (map-set stone-registry
      { stone-id: stone-id }
      (merge stone-data {
        current-status: STATUS_SOLD,
        last-updated: current-block-height
      })
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get stone information
(define-read-only (get-stone-info (stone-id uint))
  (map-get? stone-registry { stone-id: stone-id })
)

;; Get transformation history
(define-read-only (get-transformation-history (stone-id uint) (transformation-id uint))
  (map-get? transformation-history { stone-id: stone-id, transformation-id: transformation-id })
)

;; Get ownership transfer history
(define-read-only (get-ownership-transfer (stone-id uint) (transfer-id uint))
  (map-get? ownership-transfers { stone-id: stone-id, transfer-id: transfer-id })
)

;; Get laboratory certification
(define-read-only (get-lab-certification (stone-id uint) (lab-id principal))
  (map-get? lab-certifications { stone-id: stone-id, lab-id: lab-id })
)

;; Check if stone is conflict-free
(define-read-only (is-stone-conflict-free (stone-id uint))
  (match (map-get? stone-registry { stone-id: stone-id })
    stone-data
      (and
        (get is-conflict-free stone-data)
        (is-eq (contract-call? .mine-and-trader-registry is-entity-compliant (get origin-mine stone-data)) true)
      )
    false
  )
)

;; Get stone counters
(define-read-only (get-stone-counters (stone-id uint))
  (map-get? stone-counters { stone-id: stone-id })
)

;; Get total stones registered
(define-read-only (get-total-stones)
  (var-get stone-counter)
)

;; Verify stone authenticity (comprehensive check)
(define-read-only (verify-stone-authenticity (stone-id uint))
  (match (map-get? stone-registry { stone-id: stone-id })
    stone-data
      (and
        ;; Stone exists
        true
        ;; Origin mine is compliant
        (is-eq (contract-call? .mine-and-trader-registry is-entity-compliant (get origin-mine stone-data)) true)
        ;; Current owner is compliant
        (is-eq (contract-call? .mine-and-trader-registry is-entity-compliant (get current-owner stone-data)) true)
        ;; Stone is marked as conflict-free
        (get is-conflict-free stone-data)
      )
    false
  )
)

