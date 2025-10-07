;; Certification Verification Contract
;; Validates lab certificates and maintains chain-of-custody documentation
;; Integrates with external certification authorities for authenticity verification

;; Constants for error handling
(define-constant ERR_NOT_AUTHORIZED (err u300))
(define-constant ERR_CERTIFICATE_NOT_FOUND (err u301))
(define-constant ERR_CERTIFICATE_EXPIRED (err u302))
(define-constant ERR_CERTIFICATE_REVOKED (err u303))
(define-constant ERR_INVALID_CERTIFICATE (err u304))
(define-constant ERR_AUTHORITY_NOT_RECOGNIZED (err u305))
(define-constant ERR_VERIFICATION_FAILED (err u306))
(define-constant ERR_DUPLICATE_CERTIFICATE (err u307))
(define-constant ERR_INVALID_HASH (err u308))

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Certificate types
(define-constant CERT_TYPE_GIA u1)      ;; Gemological Institute of America
(define-constant CERT_TYPE_SSEF u2)     ;; Swiss Gemmological Institute
(define-constant CERT_TYPE_GÜBELIN u3)  ;; Gübelin Gem Lab
(define-constant CERT_TYPE_AGL u4)      ;; American Gemological Laboratories
(define-constant CERT_TYPE_GCAL u5)     ;; Gem Certification and Assurance Lab
(define-constant CERT_TYPE_KP u6)       ;; Kimberley Process Certificate

;; Certificate status enumeration
(define-constant STATUS_PENDING u1)     ;; Awaiting verification
(define-constant STATUS_VERIFIED u2)    ;; Verified and valid
(define-constant STATUS_EXPIRED u3)     ;; Past expiry date
(define-constant STATUS_REVOKED u4)     ;; Revoked by issuing authority
(define-constant STATUS_DISPUTED u5)    ;; Under dispute/investigation

;; Recognized certification authorities
(define-map recognized-authorities
  { authority-id: principal }
  {
    authority-name: (string-ascii 100),
    authority-type: uint,
    registration-date: uint,
    is-active: bool,
    reputation-score: uint,
    certificates-issued: uint,
    certificates-revoked: uint,
    verification-endpoint: (optional (string-ascii 200)),
    public-key: (optional (string-ascii 200))
  }
)

;; Certificate registry
(define-map certificate-registry
  { certificate-number: (string-ascii 50), issuing-authority: principal }
  {
    stone-id: (optional uint),
    certificate-type: uint,
    issue-date: uint,
    expiry-date: uint,
    holder: principal,
    verification-status: uint,
    stone-characteristics: {
      carat-weight: uint,
      color-grade: (string-ascii 10),
      clarity-grade: uint,
      cut-grade: (string-ascii 20),
      fluorescence: (optional (string-ascii 20)),
      measurements: (optional (string-ascii 50))
    },
    certificate-hash: (string-ascii 64),
    verification-hash: (optional (string-ascii 64)),
    creation-block: uint,
    last-verified: uint,
    verification-count: uint
  }
)

;; Certificate verification history
(define-map verification-history
  { certificate-number: (string-ascii 50), verification-id: uint }
  {
    verifier: principal,
    verification-date: uint,
    verification-method: uint, ;; 1=manual, 2=api, 3=blockchain
    verification-result: bool,
    verification-notes: (string-ascii 200),
    external-reference: (optional (string-ascii 100))
  }
)

;; Chain of custody records
(define-map custody-chain
  { stone-id: uint, custody-id: uint }
  {
    certificate-number: (string-ascii 50),
    custodian: principal,
    custody-date: uint,
    custody-type: uint, ;; 1=mining, 2=cutting, 3=polishing, 4=certification, 5=trading, 6=retail
    location: (string-ascii 100),
    handling-notes: (string-ascii 200),
    documentation-hash: (string-ascii 64),
    verified-by: (optional principal)
  }
)

;; Certificate verification counters
(define-map verification-counters
  { certificate-number: (string-ascii 50) }
  { verification-count: uint, custody-count: uint }
)

;; Global counters
(define-data-var total-certificates uint u0)
(define-data-var total-authorities uint u0)

;; Public functions

;; Register a new certification authority
(define-public (register-authority
  (authority-name (string-ascii 100))
  (authority-type uint)
  (verification-endpoint (optional (string-ascii 200)))
  (public-key (optional (string-ascii 200)))
)
  (let (
    (current-block-height block-height)
  )
    ;; Only contract owner can register authorities
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    
    ;; Validate authority type
    (asserts! (and (>= authority-type u1) (<= authority-type u6)) ERR_INVALID_CERTIFICATE)
    
    ;; Register authority
    (map-set recognized-authorities
      { authority-id: tx-sender }
      {
        authority-name: authority-name,
        authority-type: authority-type,
        registration-date: current-block-height,
        is-active: true,
        reputation-score: u100, ;; Starting score
        certificates-issued: u0,
        certificates-revoked: u0,
        verification-endpoint: verification-endpoint,
        public-key: public-key
      }
    )
    
    ;; Update counter
    (var-set total-authorities (+ (var-get total-authorities) u1))
    
    (ok true)
  )
)

;; Issue a new certificate
(define-public (issue-certificate
  (certificate-number (string-ascii 50))
  (stone-id (optional uint))
  (certificate-type uint)
  (expiry-date uint)
  (holder principal)
  (carat-weight uint)
  (color-grade (string-ascii 10))
  (clarity-grade uint)
  (cut-grade (string-ascii 20))
  (certificate-hash (string-ascii 64))
)
  (let (
    (current-block-height block-height)
    (authority-data (unwrap! (map-get? recognized-authorities { authority-id: tx-sender }) ERR_AUTHORITY_NOT_RECOGNIZED))
  )
    ;; Verify authority is active
    (asserts! (get is-active authority-data) ERR_AUTHORITY_NOT_RECOGNIZED)
    
    ;; Check if certificate already exists
    (asserts! (is-none (map-get? certificate-registry { certificate-number: certificate-number, issuing-authority: tx-sender })) ERR_DUPLICATE_CERTIFICATE)
    
    ;; Validate certificate type matches authority type
    (asserts! (is-eq certificate-type (get authority-type authority-data)) ERR_INVALID_CERTIFICATE)
    
    ;; Validate expiry date is in the future
    (asserts! (> expiry-date current-block-height) ERR_CERTIFICATE_EXPIRED)
    
    ;; Validate clarity grade
    (asserts! (and (>= clarity-grade u1) (<= clarity-grade u11)) ERR_INVALID_CERTIFICATE)
    
    ;; Issue certificate
    (map-set certificate-registry
      { certificate-number: certificate-number, issuing-authority: tx-sender }
      {
        stone-id: stone-id,
        certificate-type: certificate-type,
        issue-date: current-block-height,
        expiry-date: expiry-date,
        holder: holder,
        verification-status: STATUS_VERIFIED,
        stone-characteristics: {
          carat-weight: carat-weight,
          color-grade: color-grade,
          clarity-grade: clarity-grade,
          cut-grade: cut-grade,
          fluorescence: none,
          measurements: none
        },
        certificate-hash: certificate-hash,
        verification-hash: none,
        creation-block: current-block-height,
        last-verified: current-block-height,
        verification-count: u1
      }
    )
    
    ;; Initialize verification counters
    (map-set verification-counters
      { certificate-number: certificate-number }
      { verification-count: u1, custody-count: u0 }
    )
    
    ;; Update authority statistics
    (map-set recognized-authorities
      { authority-id: tx-sender }
      (merge authority-data { certificates-issued: (+ (get certificates-issued authority-data) u1) })
    )
    
    ;; Update global counter
    (var-set total-certificates (+ (var-get total-certificates) u1))
    
    (ok true)
  )
)

;; Verify a certificate
(define-public (verify-certificate
  (certificate-number (string-ascii 50))
  (issuing-authority principal)
  (verification-method uint)
  (verification-notes (string-ascii 200))
  (external-reference (optional (string-ascii 100)))
)
  (let (
    (certificate-data (unwrap! (map-get? certificate-registry { certificate-number: certificate-number, issuing-authority: issuing-authority }) ERR_CERTIFICATE_NOT_FOUND))
    (counters (unwrap! (map-get? verification-counters { certificate-number: certificate-number }) ERR_CERTIFICATE_NOT_FOUND))
    (verification-id (+ (get verification-count counters) u1))
    (current-block-height block-height)
  )
    ;; Check if certificate is not expired
    (asserts! (< current-block-height (get expiry-date certificate-data)) ERR_CERTIFICATE_EXPIRED)
    
    ;; Check if certificate is not revoked
    (asserts! (not (is-eq (get verification-status certificate-data) STATUS_REVOKED)) ERR_CERTIFICATE_REVOKED)
    
    ;; Validate verification method
    (asserts! (and (>= verification-method u1) (<= verification-method u3)) ERR_VERIFICATION_FAILED)
    
    ;; Record verification attempt
    (map-set verification-history
      { certificate-number: certificate-number, verification-id: verification-id }
      {
        verifier: tx-sender,
        verification-date: current-block-height,
        verification-method: verification-method,
        verification-result: true,
        verification-notes: verification-notes,
        external-reference: external-reference
      }
    )
    
    ;; Update certificate verification data
    (map-set certificate-registry
      { certificate-number: certificate-number, issuing-authority: issuing-authority }
      (merge certificate-data {
        last-verified: current-block-height,
        verification-count: (+ (get verification-count certificate-data) u1)
      })
    )
    
    ;; Update counters
    (map-set verification-counters
      { certificate-number: certificate-number }
      (merge counters { verification-count: verification-id })
    )
    
    (ok verification-id)
  )
)

;; Add custody record
(define-public (add-custody-record
  (stone-id uint)
  (certificate-number (string-ascii 50))
  (custody-type uint)
  (location (string-ascii 100))
  (handling-notes (string-ascii 200))
  (documentation-hash (string-ascii 64))
)
  (let (
    (counters (unwrap! (map-get? verification-counters { certificate-number: certificate-number }) ERR_CERTIFICATE_NOT_FOUND))
    (custody-id (+ (get custody-count counters) u1))
    (current-block-height block-height)
  )
    ;; Verify entity is compliant
    (asserts! (is-eq (contract-call? .mine-and-trader-registry is-entity-compliant tx-sender) true) ERR_NOT_AUTHORIZED)
    
    ;; Validate custody type
    (asserts! (and (>= custody-type u1) (<= custody-type u6)) ERR_INVALID_CERTIFICATE)
    
    ;; Add custody record
    (map-set custody-chain
      { stone-id: stone-id, custody-id: custody-id }
      {
        certificate-number: certificate-number,
        custodian: tx-sender,
        custody-date: current-block-height,
        custody-type: custody-type,
        location: location,
        handling-notes: handling-notes,
        documentation-hash: documentation-hash,
        verified-by: none
      }
    )
    
    ;; Update counters
    (map-set verification-counters
      { certificate-number: certificate-number }
      (merge counters { custody-count: custody-id })
    )
    
    (ok custody-id)
  )
)

;; Revoke a certificate
(define-public (revoke-certificate
  (certificate-number (string-ascii 50))
  (revocation-reason (string-ascii 200))
)
  (let (
    (certificate-data (unwrap! (map-get? certificate-registry { certificate-number: certificate-number, issuing-authority: tx-sender }) ERR_CERTIFICATE_NOT_FOUND))
    (authority-data (unwrap! (map-get? recognized-authorities { authority-id: tx-sender }) ERR_AUTHORITY_NOT_RECOGNIZED))
    (current-block-height block-height)
  )
    ;; Only issuing authority can revoke
    (asserts! (get is-active authority-data) ERR_NOT_AUTHORIZED)
    
    ;; Update certificate status
    (map-set certificate-registry
      { certificate-number: certificate-number, issuing-authority: tx-sender }
      (merge certificate-data { verification-status: STATUS_REVOKED })
    )
    
    ;; Update authority statistics
    (map-set recognized-authorities
      { authority-id: tx-sender }
      (merge authority-data { certificates-revoked: (+ (get certificates-revoked authority-data) u1) })
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get certificate information
(define-read-only (get-certificate-info (certificate-number (string-ascii 50)) (issuing-authority principal))
  (map-get? certificate-registry { certificate-number: certificate-number, issuing-authority: issuing-authority })
)

;; Get authority information
(define-read-only (get-authority-info (authority-id principal))
  (map-get? recognized-authorities { authority-id: authority-id })
)

;; Check if certificate is valid
(define-read-only (is-certificate-valid (certificate-number (string-ascii 50)) (issuing-authority principal))
  (match (map-get? certificate-registry { certificate-number: certificate-number, issuing-authority: issuing-authority })
    certificate-data
      (and
        (is-eq (get verification-status certificate-data) STATUS_VERIFIED)
        (> (get expiry-date certificate-data) block-height)
        (match (map-get? recognized-authorities { authority-id: issuing-authority })
          authority-data (get is-active authority-data)
          false
        )
      )
    false
  )
)

;; Get verification history
(define-read-only (get-verification-history (certificate-number (string-ascii 50)) (verification-id uint))
  (map-get? verification-history { certificate-number: certificate-number, verification-id: verification-id })
)

;; Get custody chain
(define-read-only (get-custody-record (stone-id uint) (custody-id uint))
  (map-get? custody-chain { stone-id: stone-id, custody-id: custody-id })
)

;; Get verification counters
(define-read-only (get-verification-counters (certificate-number (string-ascii 50)))
  (map-get? verification-counters { certificate-number: certificate-number })
)

;; Get total statistics
(define-read-only (get-total-certificates)
  (var-get total-certificates)
)

(define-read-only (get-total-authorities)
  (var-get total-authorities)
)

;; Comprehensive certificate verification
(define-read-only (comprehensive-certificate-check 
  (certificate-number (string-ascii 50)) 
  (issuing-authority principal)
  (stone-id uint)
)
  (match (map-get? certificate-registry { certificate-number: certificate-number, issuing-authority: issuing-authority })
    certificate-data
      (and
        ;; Certificate exists and is verified
        (is-eq (get verification-status certificate-data) STATUS_VERIFIED)
        ;; Certificate is not expired
        (> (get expiry-date certificate-data) block-height)
        ;; Issuing authority is recognized and active
        (match (map-get? recognized-authorities { authority-id: issuing-authority })
          authority-data (get is-active authority-data)
          false
        )
        ;; Stone ID matches (if specified)
        (match (get stone-id certificate-data)
          cert-stone-id (is-eq cert-stone-id stone-id)
          true ;; No stone ID restriction
        )
        ;; Stone is conflict-free
        (is-eq (contract-call? .stone-provenance-ledger is-stone-conflict-free stone-id) true)
      )
    false
  )
)