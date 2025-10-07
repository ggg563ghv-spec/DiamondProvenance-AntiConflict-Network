;; Mine and Trader Registry Contract
;; Manages registration and certification of mines, traders, and relevant authorities
;; Handles KP (Kimberley Process) and RJC (Responsible Jewellery Council) certifications

;; Constants for error handling
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ALREADY_REGISTERED (err u101))
(define-constant ERR_NOT_REGISTERED (err u102))
(define-constant ERR_INVALID_CERTIFICATION (err u103))
(define-constant ERR_EXPIRED_CERTIFICATION (err u104))
(define-constant ERR_AUDIT_FAILED (err u105))
(define-constant ERR_INSUFFICIENT_BALANCE (err u106))

;; Contract owner and administrator roles
(define-data-var contract-owner principal tx-sender)
(define-data-var registration-fee uint u1000000) ;; 1 STX in microSTX

;; Entity types enumeration
(define-constant ENTITY_TYPE_MINE u1)
(define-constant ENTITY_TYPE_TRADER u2)
(define-constant ENTITY_TYPE_AUTHORITY u3)
(define-constant ENTITY_TYPE_RETAILER u4)

;; Certification types
(define-constant CERT_TYPE_KP u1) ;; Kimberley Process
(define-constant CERT_TYPE_RJC u2) ;; Responsible Jewellery Council
(define-constant CERT_TYPE_ISO u3) ;; ISO Standards
(define-constant CERT_TYPE_LOCAL u4) ;; Local Government License

;; Data structures for entity registration
(define-map registered-entities
  { entity-id: principal }
  {
    entity-type: uint,
    entity-name: (string-ascii 100),
    registration-date: uint,
    location: (string-ascii 200),
    contact-info: (string-ascii 200),
    is-active: bool,
    compliance-score: uint,
    last-audit-date: uint,
    next-audit-due: uint
  }
)

;; Certification management
(define-map entity-certifications
  { entity-id: principal, cert-type: uint }
  {
    cert-number: (string-ascii 50),
    issued-date: uint,
    expiry-date: uint,
    issuing-authority: (string-ascii 100),
    is-valid: bool,
    last-verified: uint
  }
)

;; Authority permissions
(define-map authorized-auditors
  { auditor-id: principal }
  {
    authority-name: (string-ascii 100),
    authorized-date: uint,
    cert-types-authorized: (list 10 uint),
    is-active: bool
  }
)

;; Audit records
(define-map audit-records
  { entity-id: principal, audit-date: uint }
  {
    auditor-id: principal,
    audit-type: uint,
    compliance-score: uint,
    findings: (string-ascii 500),
    recommendations: (string-ascii 500),
    status: uint, ;; 1=passed, 2=conditional, 3=failed
    next-audit-due: uint
  }
)

;; Violation tracking
(define-map violations
  { entity-id: principal, violation-id: uint }
  {
    violation-type: uint,
    description: (string-ascii 300),
    severity: uint, ;; 1=low, 2=medium, 3=high, 4=critical
    reported-date: uint,
    reported-by: principal,
    status: uint, ;; 1=open, 2=investigating, 3=resolved, 4=closed
    resolution-date: (optional uint)
  }
)

;; Registration fee collection
(define-map collected-fees
  { entity-id: principal }
  { amount-paid: uint, payment-date: uint }
)

;; Entity registration counter for violation IDs
(define-data-var violation-counter uint u0)

;; Public functions

;; Register a new entity (mine, trader, authority, retailer)
(define-public (register-entity
  (entity-type uint)
  (entity-name (string-ascii 100))
  (location (string-ascii 200))
  (contact-info (string-ascii 200))
)
  (let (
    (entity-id tx-sender)
    (current-block-height burn-block-height)
  )
    ;; Check if entity already registered
    (asserts! (is-none (map-get? registered-entities { entity-id: entity-id })) ERR_ALREADY_REGISTERED)
    
    ;; Check registration fee payment
    (asserts! (>= (stx-get-balance tx-sender) (var-get registration-fee)) ERR_INSUFFICIENT_BALANCE)
    
    ;; Transfer registration fee
    (try! (stx-transfer? (var-get registration-fee) tx-sender (var-get contract-owner)))
    
    ;; Register entity
    (map-set registered-entities
      { entity-id: entity-id }
      {
        entity-type: entity-type,
        entity-name: entity-name,
        registration-date: current-block-height,
        location: location,
        contact-info: contact-info,
        is-active: true,
        compliance-score: u70, ;; Starting score
        last-audit-date: u0,
        next-audit-due: (+ current-block-height u52560) ;; ~1 year in blocks
      }
    )
    
    ;; Record fee payment
    (map-set collected-fees
      { entity-id: entity-id }
      { amount-paid: (var-get registration-fee), payment-date: current-block-height }
    )
    
    (ok true)
  )
)

;; Add certification to an entity
(define-public (add-certification
  (entity-id principal)
  (cert-type uint)
  (cert-number (string-ascii 50))
  (expiry-date uint)
  (issuing-authority (string-ascii 100))
)
  (let (
    (current-block-height burn-block-height)
    (entity-data (unwrap! (map-get? registered-entities { entity-id: entity-id }) ERR_NOT_REGISTERED))
  )
    ;; Only authorized auditors or contract owner can add certifications
    (asserts! (or
      (is-eq tx-sender (var-get contract-owner))
      (is-some (map-get? authorized-auditors { auditor-id: tx-sender }))
    ) ERR_NOT_AUTHORIZED)
    
    ;; Validate certification type
    (asserts! (and (>= cert-type u1) (<= cert-type u4)) ERR_INVALID_CERTIFICATION)
    
    ;; Validate expiry date
    (asserts! (> expiry-date current-block-height) ERR_EXPIRED_CERTIFICATION)
    
    ;; Add certification
    (map-set entity-certifications
      { entity-id: entity-id, cert-type: cert-type }
      {
        cert-number: cert-number,
        issued-date: current-block-height,
        expiry-date: expiry-date,
        issuing-authority: issuing-authority,
        is-valid: true,
        last-verified: current-block-height
      }
    )
    
    ;; Update compliance score
    (map-set registered-entities
      { entity-id: entity-id }
      (merge entity-data { compliance-score: (+ (get compliance-score entity-data) u10) })
    )
    
    (ok true)
  )
)

;; Conduct audit for an entity
(define-public (conduct-audit
  (entity-id principal)
  (audit-type uint)
  (compliance-score uint)
  (findings (string-ascii 500))
  (recommendations (string-ascii 500))
  (status uint)
)
  (let (
    (current-block-height burn-block-height)
    (entity-data (unwrap! (map-get? registered-entities { entity-id: entity-id }) ERR_NOT_REGISTERED))
    (auditor-data (unwrap! (map-get? authorized-auditors { auditor-id: tx-sender }) ERR_NOT_AUTHORIZED))
  )
    ;; Verify auditor is active
    (asserts! (get is-active auditor-data) ERR_NOT_AUTHORIZED)
    
    ;; Validate compliance score (0-100)
    (asserts! (and (>= compliance-score u0) (<= compliance-score u100)) ERR_AUDIT_FAILED)
    
    ;; Validate status (1=passed, 2=conditional, 3=failed)
    (asserts! (and (>= status u1) (<= status u3)) ERR_AUDIT_FAILED)
    
    ;; Record audit
    (map-set audit-records
      { entity-id: entity-id, audit-date: current-block-height }
      {
        auditor-id: tx-sender,
        audit-type: audit-type,
        compliance-score: compliance-score,
        findings: findings,
        recommendations: recommendations,
        status: status,
        next-audit-due: (+ current-block-height u52560) ;; Next audit in ~1 year
      }
    )
    
    ;; Update entity record
    (map-set registered-entities
      { entity-id: entity-id }
      (merge entity-data {
        compliance-score: compliance-score,
        last-audit-date: current-block-height,
        next-audit-due: (+ current-block-height u52560),
        is-active: (if (is-eq status u3) false true) ;; Deactivate if audit failed
      })
    )
    
    (ok true)
  )
)

;; Report a violation
(define-public (report-violation
  (entity-id principal)
  (violation-type uint)
  (description (string-ascii 300))
  (severity uint)
)
  (let (
    (current-block-height burn-block-height)
    (violation-id (+ (var-get violation-counter) u1))
    (entity-data (unwrap! (map-get? registered-entities { entity-id: entity-id }) ERR_NOT_REGISTERED))
  )
    ;; Validate severity (1=low, 2=medium, 3=high, 4=critical)
    (asserts! (and (>= severity u1) (<= severity u4)) ERR_INVALID_CERTIFICATION)
    
    ;; Record violation
    (map-set violations
      { entity-id: entity-id, violation-id: violation-id }
      {
        violation-type: violation-type,
        description: description,
        severity: severity,
        reported-date: current-block-height,
        reported-by: tx-sender,
        status: u1, ;; Open status
        resolution-date: none
      }
    )
    
    ;; Update violation counter
    (var-set violation-counter violation-id)
    
    ;; Reduce compliance score based on severity
    (let (
      (score-reduction (if (is-eq severity u4) u30
                        (if (is-eq severity u3) u20
                         (if (is-eq severity u2) u10 u5))))
      (new-score (if (> (get compliance-score entity-data) score-reduction)
                    (- (get compliance-score entity-data) score-reduction)
                    u0))
    )
      (map-set registered-entities
        { entity-id: entity-id }
        (merge entity-data { compliance-score: new-score })
      )
    )
    
    (ok violation-id)
  )
)

;; Admin functions

;; Authorize an auditor
(define-public (authorize-auditor
  (auditor-id principal)
  (authority-name (string-ascii 100))
  (cert-types (list 10 uint))
)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    
    (map-set authorized-auditors
      { auditor-id: auditor-id }
      {
        authority-name: authority-name,
        authorized-date: burn-block-height,
        cert-types-authorized: cert-types,
        is-active: true
      }
    )
    
    (ok true)
  )
)

;; Update registration fee
(define-public (update-registration-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (var-set registration-fee new-fee)
    (ok true)
  )
)

;; Read-only functions

;; Get entity information
(define-read-only (get-entity-info (entity-id principal))
  (map-get? registered-entities { entity-id: entity-id })
)

;; Get certification information
(define-read-only (get-certification (entity-id principal) (cert-type uint))
  (map-get? entity-certifications { entity-id: entity-id, cert-type: cert-type })
)

;; Check if entity is in good standing
(define-read-only (is-entity-compliant (entity-id principal))
  (match (map-get? registered-entities { entity-id: entity-id })
    entity-data
      (and
        (get is-active entity-data)
        (>= (get compliance-score entity-data) u60) ;; Minimum compliance score
        (< burn-block-height (get next-audit-due entity-data)) ;; Audit not overdue
      )
    false
  )
)

;; Get current registration fee
(define-read-only (get-registration-fee)
  (var-get registration-fee)
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; title: mine-and-trader-registry
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

