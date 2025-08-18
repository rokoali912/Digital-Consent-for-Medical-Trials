(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-INPUT (err u103))
(define-constant ERR-TRIAL-INACTIVE (err u104))
(define-constant ERR-CONSENT-ALREADY-GIVEN (err u105))
(define-constant ERR-CONSENT-NOT-FOUND (err u106))
(define-constant ERR-WITHDRAWAL-NOT-ALLOWED (err u107))

(define-data-var contract-owner principal tx-sender)
(define-data-var trial-id-counter uint u0)
(define-data-var consent-id-counter uint u0)

(define-map authorized-researchers principal bool)
(define-map authorized-institutions principal bool)

(define-map trials
  uint
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    researcher: principal,
    institution: principal,
    start-block: uint,
    end-block: uint,
    max-participants: uint,
    current-participants: uint,
    active: bool,
    created-at: uint
  }
)

(define-map patient-profiles
  principal
  {
    name: (string-ascii 50),
    age: uint,
    medical-id: (string-ascii 20),
    verified: bool,
    registered-at: uint
  }
)

(define-map consent-records
  uint
  {
    trial-id: uint,
    patient: principal,
    consent-given: bool,
    consent-type: (string-ascii 50),
    timestamp: uint,
    block-height: uint,
    withdrawal-allowed: bool,
    data-usage-consent: bool,
    follow-up-consent: bool
  }
)

(define-map patient-consents
  { patient: principal, trial-id: uint }
  uint
)

(define-map trial-participants
  { trial-id: uint, participant: principal }
  bool
)

(define-map consent-withdrawals
  uint
  {
    consent-id: uint,
    withdrawal-reason: (string-ascii 200),
    withdrawn-at: uint,
    withdrawn-by: principal
  }
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (is-authorized-researcher (researcher principal))
  (default-to false (map-get? authorized-researchers researcher))
)

(define-read-only (is-authorized-institution (institution principal))
  (default-to false (map-get? authorized-institutions institution))
)

(define-read-only (get-trial-info (trial-id uint))
  (map-get? trials trial-id)
)

(define-read-only (get-patient-profile (patient principal))
  (map-get? patient-profiles patient)
)

(define-read-only (get-consent-record (consent-id uint))
  (map-get? consent-records consent-id)
)

(define-read-only (get-patient-consent (patient principal) (trial-id uint))
  (match (map-get? patient-consents { patient: patient, trial-id: trial-id })
    consent-id (map-get? consent-records consent-id)
    none
  )
)

(define-read-only (is-trial-participant (trial-id uint) (participant principal))
  (default-to false (map-get? trial-participants { trial-id: trial-id, participant: participant }))
)

(define-read-only (get-current-trial-id)
  (var-get trial-id-counter)
)

(define-read-only (get-current-consent-id)
  (var-get consent-id-counter)
)

(define-public (authorize-researcher (researcher principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-researchers researcher true))
  )
)

(define-public (authorize-institution (institution principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-institutions institution true))
  )
)

(define-public (revoke-researcher (researcher principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-researchers researcher false))
  )
)

(define-public (register-patient (name (string-ascii 50)) (age uint) (medical-id (string-ascii 20)))
  (begin
    (asserts! (> age u0) ERR-INVALID-INPUT)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len medical-id) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? patient-profiles tx-sender)) ERR-ALREADY-EXISTS)
    (ok (map-set patient-profiles tx-sender
      {
        name: name,
        age: age,
        medical-id: medical-id,
        verified: false,
        registered-at: stacks-block-height
      }
    ))
  )
)

(define-public (verify-patient (patient principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (match (map-get? patient-profiles patient)
      profile (ok (map-set patient-profiles patient (merge profile { verified: true })))
      ERR-NOT-FOUND
    )
  )
)

(define-public (create-trial 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (institution principal)
  (duration-blocks uint)
  (max-participants uint)
)
  (let
    (
      (new-trial-id (+ (var-get trial-id-counter) u1))
      (current-block stacks-block-height)
    )
    (asserts! (is-authorized-researcher tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-authorized-institution institution) ERR-NOT-AUTHORIZED)
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> duration-blocks u0) ERR-INVALID-INPUT)
    (asserts! (> max-participants u0) ERR-INVALID-INPUT)
    (map-set trials new-trial-id
      {
        title: title,
        description: description,
        researcher: tx-sender,
        institution: institution,
        start-block: current-block,
        end-block: (+ current-block duration-blocks),
        max-participants: max-participants,
        current-participants: u0,
        active: true,
        created-at: current-block
      }
    )
    (var-set trial-id-counter new-trial-id)
    (ok new-trial-id)
  )
)

(define-public (give-consent
  (trial-id uint)
  (consent-type (string-ascii 50))
  (data-usage-consent bool)
  (follow-up-consent bool)
)
  (let
    (
      (new-consent-id (+ (var-get consent-id-counter) u1))
      (current-block stacks-block-height)
    )
    (match (map-get? trials trial-id)
      trial-info
        (begin
          (asserts! (get active trial-info) ERR-TRIAL-INACTIVE)
          (asserts! (<= current-block (get end-block trial-info)) ERR-TRIAL-INACTIVE)
          (asserts! (< (get current-participants trial-info) (get max-participants trial-info)) ERR-TRIAL-INACTIVE)
          (match (map-get? patient-profiles tx-sender)
            patient-profile
              (begin
                (asserts! (get verified patient-profile) ERR-NOT-AUTHORIZED)
                (asserts! (is-none (map-get? patient-consents { patient: tx-sender, trial-id: trial-id })) ERR-CONSENT-ALREADY-GIVEN)
                (map-set consent-records new-consent-id
                  {
                    trial-id: trial-id,
                    patient: tx-sender,
                    consent-given: true,
                    consent-type: consent-type,
                    timestamp: current-block,
                    block-height: current-block,
                    withdrawal-allowed: true,
                    data-usage-consent: data-usage-consent,
                    follow-up-consent: follow-up-consent
                  }
                )
                (map-set patient-consents { patient: tx-sender, trial-id: trial-id } new-consent-id)
                (map-set trial-participants { trial-id: trial-id, participant: tx-sender } true)
                (map-set trials trial-id (merge trial-info { current-participants: (+ (get current-participants trial-info) u1) }))
                (var-set consent-id-counter new-consent-id)
                (ok new-consent-id)
              )
            ERR-NOT-FOUND
          )
        )
      ERR-NOT-FOUND
    )
  )
)

(define-public (withdraw-consent (trial-id uint) (reason (string-ascii 200)))
  (match (map-get? patient-consents { patient: tx-sender, trial-id: trial-id })
    consent-id
      (match (map-get? consent-records consent-id)
        consent-record
          (begin
            (asserts! (get withdrawal-allowed consent-record) ERR-WITHDRAWAL-NOT-ALLOWED)
            (asserts! (get consent-given consent-record) ERR-CONSENT-NOT-FOUND)
            (map-set consent-records consent-id (merge consent-record { consent-given: false }))
            (map-set consent-withdrawals consent-id
              {
                consent-id: consent-id,
                withdrawal-reason: reason,
                withdrawn-at: stacks-block-height,
                withdrawn-by: tx-sender
              }
            )
            (map-delete trial-participants { trial-id: trial-id, participant: tx-sender })
            (match (map-get? trials trial-id)
              trial-info (map-set trials trial-id (merge trial-info { current-participants: (- (get current-participants trial-info) u1) }))
              true
            )
            (ok true)
          )
        ERR-CONSENT-NOT-FOUND
      )
    ERR-CONSENT-NOT-FOUND
  )
)

(define-public (deactivate-trial (trial-id uint))
  (match (map-get? trials trial-id)
    trial-info
      (begin
        (asserts! (or (is-eq tx-sender (get researcher trial-info)) (is-eq tx-sender (var-get contract-owner))) ERR-NOT-AUTHORIZED)
        (ok (map-set trials trial-id (merge trial-info { active: false })))
      )
    ERR-NOT-FOUND
  )
)

(define-public (update-withdrawal-policy (consent-id uint) (withdrawal-allowed bool))
  (match (map-get? consent-records consent-id)
    consent-record
      (match (map-get? trials (get trial-id consent-record))
        trial-info
          (begin
            (asserts! (is-eq tx-sender (get researcher trial-info)) ERR-NOT-AUTHORIZED)
            (ok (map-set consent-records consent-id (merge consent-record { withdrawal-allowed: withdrawal-allowed })))
          )
        ERR-NOT-FOUND
      )
    ERR-NOT-FOUND
  )
)

(define-read-only (get-trial-consent-count (trial-id uint))
  (match (map-get? trials trial-id)
    trial-info (ok (get current-participants trial-info))
    ERR-NOT-FOUND
  )
)

(define-read-only (verify-consent-authenticity (consent-id uint))
  (match (map-get? consent-records consent-id)
    consent-record 
      (ok {
        consent-id: consent-id,
        trial-id: (get trial-id consent-record),
        patient: (get patient consent-record),
        timestamp: (get timestamp consent-record),
        block-height: (get block-height consent-record),
        consent-given: (get consent-given consent-record)
      })
    ERR-NOT-FOUND
  )
)
