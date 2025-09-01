;; Patient Data Integrity & Verification System
;; Provides cryptographic proof-of-authenticity for patient medical data submissions

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-INVALID-INPUT (err u202))
(define-constant ERR-DATA-ALREADY-EXISTS (err u203))
(define-constant ERR-VERIFICATION-FAILED (err u204))
(define-constant ERR-DISPUTE-ALREADY-EXISTS (err u205))
(define-constant ERR-INVALID-SIGNATURE (err u206))
(define-constant ERR-DATA-EXPIRED (err u207))
(define-constant ERR-INSUFFICIENT-VERIFIERS (err u208))

;; Contract variables
(define-data-var contract-owner principal tx-sender)
(define-data-var data-submission-counter uint u0)
(define-data-var verification-counter uint u0)
(define-data-var dispute-counter uint u0)
(define-data-var minimum-verifiers uint u2)

;; Maps for authorized entities
(define-map authorized-verifiers principal bool)
(define-map authorized-auditors principal bool)

;; Core data structures
(define-map data-submissions
  uint
  {
    submitter: principal,
    trial-id: uint,
    data-hash: (buff 32),
    metadata-hash: (buff 32),
    submission-timestamp: uint,
    expiry-block: uint,
    verification-count: uint,
    verification-threshold: uint,
    data-type: (string-ascii 50),
    encrypted-data-uri: (string-ascii 200),
    verified: bool,
    challenged: bool
  }
)

(define-map data-verifications
  uint
  {
    submission-id: uint,
    verifier: principal,
    verification-hash: (buff 32),
    verification-result: bool,
    verification-timestamp: uint,
    verifier-signature: (buff 65),
    verification-notes: (string-ascii 300)
  }
)

(define-map patient-data-submissions
  { patient: principal, trial-id: uint }
  (list 50 uint)
)

(define-map data-integrity-challenges
  uint
  {
    submission-id: uint,
    challenger: principal,
    challenge-reason: (string-ascii 300),
    challenge-timestamp: uint,
    challenge-hash: (buff 32),
    resolved: bool,
    resolution-timestamp: (optional uint),
    resolution-result: (optional bool)
  }
)

(define-map verifier-performance
  principal
  {
    total-verifications: uint,
    successful-verifications: uint,
    failed-verifications: uint,
    reputation-score: uint,
    last-activity: uint
  }
)

;; Data sharing permissions
(define-map data-sharing-permissions
  { submission-id: uint, authorized-party: principal }
  {
    permission-granted: bool,
    granted-by: principal,
    granted-at: uint,
    access-level: (string-ascii 20),
    expiry-block: uint
  }
)

;; Batch verification tracking
(define-map batch-verifications
  uint
  {
    verifier: principal,
    submission-ids: (list 20 uint),
    batch-hash: (buff 32),
    batch-timestamp: uint,
    batch-size: uint,
    all-verified: bool
  }
)

;; Read-only functions
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (is-authorized-verifier (verifier principal))
  (default-to false (map-get? authorized-verifiers verifier))
)

(define-read-only (is-authorized-auditor (auditor principal))
  (default-to false (map-get? authorized-auditors auditor))
)

(define-read-only (get-data-submission (submission-id uint))
  (map-get? data-submissions submission-id)
)

(define-read-only (get-verification-record (verification-id uint))
  (map-get? data-verifications verification-id)
)

(define-read-only (get-patient-submissions (patient principal) (trial-id uint))
  (default-to (list) (map-get? patient-data-submissions { patient: patient, trial-id: trial-id }))
)

(define-read-only (get-challenge-details (challenge-id uint))
  (map-get? data-integrity-challenges challenge-id)
)

(define-read-only (get-verifier-performance (verifier principal))
  (map-get? verifier-performance verifier)
)

(define-read-only (get-sharing-permission (submission-id uint) (party principal))
  (map-get? data-sharing-permissions { submission-id: submission-id, authorized-party: party })
)

(define-read-only (calculate-data-integrity-score (submission-id uint))
  (match (map-get? data-submissions submission-id)
    submission
      (let
        (
          (verification-ratio (if (> (get verification-threshold submission) u0)
                               (/ (* (get verification-count submission) u100) (get verification-threshold submission))
                               u0))
          (challenge-penalty (if (get challenged submission) u20 u0))
          (verification-bonus (if (get verified submission) u10 u0))
        )
        (ok (- (+ verification-ratio verification-bonus) challenge-penalty))
      )
    ERR-NOT-FOUND
  )
)

;; Administrative functions
(define-public (authorize-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-verifiers verifier true))
  )
)

(define-public (authorize-auditor (auditor principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-auditors auditor true))
  )
)

(define-public (revoke-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-verifiers verifier false))
  )
)

(define-public (set-minimum-verifiers (min-verifiers uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (> min-verifiers u0) ERR-INVALID-INPUT)
    (ok (var-set minimum-verifiers min-verifiers))
  )
)

;; Core functionality
(define-public (submit-patient-data
  (trial-id uint)
  (data-hash (buff 32))
  (metadata-hash (buff 32))
  (data-type (string-ascii 50))
  (encrypted-data-uri (string-ascii 200))
  (verification-threshold uint)
  (expiry-blocks uint)
)
  (let
    (
      (new-submission-id (+ (var-get data-submission-counter) u1))
      (current-block stacks-block-height)
      (expiry-block (+ current-block expiry-blocks))
    )
    (asserts! (> (len data-hash) u0) ERR-INVALID-INPUT)
    (asserts! (> (len metadata-hash) u0) ERR-INVALID-INPUT)
    (asserts! (> (len data-type) u0) ERR-INVALID-INPUT)
    (asserts! (> verification-threshold u0) ERR-INVALID-INPUT)
    (asserts! (>= verification-threshold (var-get minimum-verifiers)) ERR-INSUFFICIENT-VERIFIERS)
    (asserts! (> expiry-blocks u0) ERR-INVALID-INPUT)
    
    (map-set data-submissions new-submission-id
      {
        submitter: tx-sender,
        trial-id: trial-id,
        data-hash: data-hash,
        metadata-hash: metadata-hash,
        submission-timestamp: current-block,
        expiry-block: expiry-block,
        verification-count: u0,
        verification-threshold: verification-threshold,
        data-type: data-type,
        encrypted-data-uri: encrypted-data-uri,
        verified: false,
        challenged: false
      }
    )
    
    ;; Update patient submission list
    (let
      (
        (current-submissions (get-patient-submissions tx-sender trial-id))
        (updated-submissions (unwrap! (as-max-len? (append current-submissions new-submission-id) u50) ERR-INVALID-INPUT))
      )
      (map-set patient-data-submissions { patient: tx-sender, trial-id: trial-id } updated-submissions)
    )
    
    (var-set data-submission-counter new-submission-id)
    (ok new-submission-id)
  )
)

(define-public (verify-data-submission
  (submission-id uint)
  (verification-hash (buff 32))
  (verification-result bool)
  (verifier-signature (buff 65))
  (verification-notes (string-ascii 300))
)
  (let
    (
      (new-verification-id (+ (var-get verification-counter) u1))
      (current-block stacks-block-height)
    )
    (asserts! (is-authorized-verifier tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len verification-hash) u0) ERR-INVALID-INPUT)
    (asserts! (> (len verifier-signature) u0) ERR-INVALID-SIGNATURE)
    
    (match (map-get? data-submissions submission-id)
      submission
        (begin
          (asserts! (<= current-block (get expiry-block submission)) ERR-DATA-EXPIRED)
          (asserts! (not (get challenged submission)) ERR-VERIFICATION-FAILED)
          
          ;; Record verification
          (map-set data-verifications new-verification-id
            {
              submission-id: submission-id,
              verifier: tx-sender,
              verification-hash: verification-hash,
              verification-result: verification-result,
              verification-timestamp: current-block,
              verifier-signature: verifier-signature,
              verification-notes: verification-notes
            }
          )
          
          ;; Update submission verification count
          (let
            (
              (new-verification-count (+ (get verification-count submission) u1))
              (updated-submission (merge submission { verification-count: new-verification-count }))
              (final-submission (if (>= new-verification-count (get verification-threshold submission))
                                 (merge updated-submission { verified: true })
                                 updated-submission))
            )
            (map-set data-submissions submission-id final-submission)
          )
          
          ;; Update verifier performance
          (update-verifier-performance tx-sender verification-result)
          
          (var-set verification-counter new-verification-id)
          (ok new-verification-id)
        )
      ERR-NOT-FOUND
    )
  )
)

(define-public (challenge-data-integrity
  (submission-id uint)
  (challenge-reason (string-ascii 300))
  (challenge-hash (buff 32))
)
  (let
    (
      (new-challenge-id (+ (var-get dispute-counter) u1))
      (current-block stacks-block-height)
    )
    (asserts! (is-authorized-auditor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len challenge-reason) u0) ERR-INVALID-INPUT)
    (asserts! (> (len challenge-hash) u0) ERR-INVALID-INPUT)
    
    (match (map-get? data-submissions submission-id)
      submission
        (begin
          (asserts! (not (get challenged submission)) ERR-DISPUTE-ALREADY-EXISTS)
          
          ;; Mark submission as challenged
          (map-set data-submissions submission-id (merge submission { challenged: true }))
          
          ;; Create challenge record
          (map-set data-integrity-challenges new-challenge-id
            {
              submission-id: submission-id,
              challenger: tx-sender,
              challenge-reason: challenge-reason,
              challenge-timestamp: current-block,
              challenge-hash: challenge-hash,
              resolved: false,
              resolution-timestamp: none,
              resolution-result: none
            }
          )
          
          (var-set dispute-counter new-challenge-id)
          (ok new-challenge-id)
        )
      ERR-NOT-FOUND
    )
  )
)

(define-public (resolve-integrity-challenge
  (challenge-id uint)
  (resolution-result bool)
)
  (let
    (
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    
    (match (map-get? data-integrity-challenges challenge-id)
      challenge
        (begin
          (asserts! (not (get resolved challenge)) ERR-NOT-FOUND)
          
          ;; Update challenge resolution
          (map-set data-integrity-challenges challenge-id
            (merge challenge 
              {
                resolved: true,
                resolution-timestamp: (some current-block),
                resolution-result: (some resolution-result)
              }
            )
          )
          
          ;; Update submission status based on resolution
          (match (map-get? data-submissions (get submission-id challenge))
            submission
              (if resolution-result
                ;; Challenge rejected - remove challenge flag
                (map-set data-submissions (get submission-id challenge)
                  (merge submission { challenged: false }))
                ;; Challenge upheld - invalidate verification
                (map-set data-submissions (get submission-id challenge)
                  (merge submission { verified: false, challenged: true })))
            true
          )
          
          (ok resolution-result)
        )
      ERR-NOT-FOUND
    )
  )
)

(define-public (grant-data-access
  (submission-id uint)
  (authorized-party principal)
  (access-level (string-ascii 20))
  (expiry-blocks uint)
)
  (let
    (
      (current-block stacks-block-height)
      (expiry-block (+ current-block expiry-blocks))
    )
    (match (map-get? data-submissions submission-id)
      submission
        (begin
          (asserts! (is-eq tx-sender (get submitter submission)) ERR-NOT-AUTHORIZED)
          (asserts! (get verified submission) ERR-VERIFICATION-FAILED)
          (asserts! (> (len access-level) u0) ERR-INVALID-INPUT)
          (asserts! (> expiry-blocks u0) ERR-INVALID-INPUT)
          
          (ok (map-set data-sharing-permissions
            { submission-id: submission-id, authorized-party: authorized-party }
            {
              permission-granted: true,
              granted-by: tx-sender,
              granted-at: current-block,
              access-level: access-level,
              expiry-block: expiry-block
            }
          ))
        )
      ERR-NOT-FOUND
    )
  )
)

(define-public (revoke-data-access
  (submission-id uint)
  (authorized-party principal)
)
  (match (map-get? data-submissions submission-id)
    submission
      (begin
        (asserts! (is-eq tx-sender (get submitter submission)) ERR-NOT-AUTHORIZED)
        (ok (map-delete data-sharing-permissions { submission-id: submission-id, authorized-party: authorized-party }))
      )
    ERR-NOT-FOUND
  )
)

(define-public (batch-verify-submissions
  (submission-ids (list 20 uint))
  (batch-hash (buff 32))
  (overall-verification-result bool)
)
  (let
    (
      (new-batch-id (+ (var-get verification-counter) u1))
      (current-block stacks-block-height)
      (batch-size (len submission-ids))
    )
    (asserts! (is-authorized-verifier tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> batch-size u0) ERR-INVALID-INPUT)
    (asserts! (> (len batch-hash) u0) ERR-INVALID-INPUT)
    
    ;; Record batch verification
    (map-set batch-verifications new-batch-id
      {
        verifier: tx-sender,
        submission-ids: submission-ids,
        batch-hash: batch-hash,
        batch-timestamp: current-block,
        batch-size: batch-size,
        all-verified: overall-verification-result
      }
    )
    
    ;; Update verifier performance for batch operation
    (update-verifier-performance tx-sender overall-verification-result)
    
    (var-set verification-counter new-batch-id)
    (ok new-batch-id)
  )
)

(define-public (update-data-expiry
  (submission-id uint)
  (additional-blocks uint)
)
  (match (map-get? data-submissions submission-id)
    submission
      (begin
        (asserts! (is-eq tx-sender (get submitter submission)) ERR-NOT-AUTHORIZED)
        (asserts! (> additional-blocks u0) ERR-INVALID-INPUT)
        
        (let
          (
            (new-expiry-block (+ (get expiry-block submission) additional-blocks))
          )
          (ok (map-set data-submissions submission-id
            (merge submission { expiry-block: new-expiry-block })
          ))
        )
      )
    ERR-NOT-FOUND
  )
)

(define-public (validate-data-chain
  (submission-ids (list 10 uint))
  (chain-hash (buff 32))
)
  (begin
    (asserts! (is-authorized-verifier tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len submission-ids) u0) ERR-INVALID-INPUT)
    (asserts! (> (len chain-hash) u0) ERR-INVALID-INPUT)
    
    ;; Validate that all submissions in chain are verified
    (asserts! (fold check-submission-verified submission-ids true) ERR-VERIFICATION-FAILED)
    
    (ok { chain-valid: true, validated-by: tx-sender, validated-at: stacks-block-height })
  )
)

(define-public (create-integrity-snapshot
  (trial-id uint)
  (snapshot-hash (buff 32))
)
  (begin
    (asserts! (is-authorized-auditor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len snapshot-hash) u0) ERR-INVALID-INPUT)
    
    (ok {
      snapshot-id: (+ (var-get dispute-counter) u1),
      trial-id: trial-id,
      snapshot-hash: snapshot-hash,
      created-by: tx-sender,
      created-at: stacks-block-height,
      snapshot-type: "integrity-audit"
    })
  )
)

;; Helper functions
(define-private (update-verifier-performance (verifier principal) (success bool))
  (let
    (
      (current-performance (default-to 
        { total-verifications: u0, successful-verifications: u0, failed-verifications: u0, reputation-score: u100, last-activity: u0 }
        (map-get? verifier-performance verifier)))
      (new-total (+ (get total-verifications current-performance) u1))
      (new-successful (if success (+ (get successful-verifications current-performance) u1) (get successful-verifications current-performance)))
      (new-failed (if success (get failed-verifications current-performance) (+ (get failed-verifications current-performance) u1)))
      (new-reputation (if (> new-total u0) (/ (* new-successful u100) new-total) u0))
    )
    (map-set verifier-performance verifier
      {
        total-verifications: new-total,
        successful-verifications: new-successful,
        failed-verifications: new-failed,
        reputation-score: new-reputation,
        last-activity: stacks-block-height
      }
    )
  )
)

(define-private (check-submission-verified (submission-id uint) (acc bool))
  (and acc 
    (match (map-get? data-submissions submission-id)
      submission (and (get verified submission) (not (get challenged submission)))
      false
    )
  )
)

(define-read-only (get-verified-submissions-count (trial-id uint))
  (fold count-verified-submissions-for-trial (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) u0)
)

(define-private (count-verified-submissions-for-trial (submission-id uint) (acc uint))
  (match (map-get? data-submissions submission-id)
    submission 
      (if (and (get verified submission) (not (get challenged submission)))
        (+ acc u1)
        acc)
    acc
  )
)

(define-private (collect-trial-submissions (submission-id uint) (acc (list 1000 uint)))
  (unwrap! (as-max-len? (append acc submission-id) u1000) acc)
)

(define-private (is-trial-submission (submission-id uint) (target-trial-id uint))
  (match (map-get? data-submissions submission-id)
    submission (is-eq (get trial-id submission) target-trial-id)
    false
  )
)

(define-private (is-submission-verified (submission-id uint))
  (match (map-get? data-submissions submission-id)
    submission (and (get verified submission) (not (get challenged submission)))
    false
  )
)

(define-read-only (get-data-integrity-summary (trial-id uint))
  (let
    (
      (total-submissions (fold count-trial-submissions (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0))
      (verified-count (get-verified-submissions-count trial-id))
      (challenge-count (fold count-trial-challenges (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0))
    )
    (ok {
      trial-id: trial-id,
      total-submissions: total-submissions,
      verified-submissions: verified-count,
      pending-verifications: (- total-submissions verified-count),
      total-challenges: challenge-count,
      integrity-percentage: (if (> total-submissions u0) (/ (* verified-count u100) total-submissions) u0)
    })
  )
)

(define-private (count-trial-submissions (submission-id uint) (acc uint))
  (match (map-get? data-submissions submission-id)
    submission (+ acc u1)
    acc
  )
)

(define-private (count-trial-challenges (challenge-id uint) (acc uint))
  (match (map-get? data-integrity-challenges challenge-id)
    challenge (+ acc u1)
    acc
  )
)

(define-public (bulk-authorize-verifiers (verifiers (list 20 principal)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map authorize-single-verifier verifiers))
  )
)

(define-private (authorize-single-verifier (verifier principal))
  (map-set authorized-verifiers verifier true)
)

(define-read-only (get-submission-verification-status (submission-id uint))
  (match (map-get? data-submissions submission-id)
    submission
      (ok {
        submission-id: submission-id,
        verified: (get verified submission),
        verification-count: (get verification-count submission),
        verification-threshold: (get verification-threshold submission),
        verification-progress: (/ (* (get verification-count submission) u100) (get verification-threshold submission)),
        challenged: (get challenged submission),
        expired: (> stacks-block-height (get expiry-block submission))
      })
    ERR-NOT-FOUND
  )
)
