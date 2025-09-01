;; Automated Compliance Monitoring System
;; Continuous regulatory oversight and protocol deviation tracking for clinical trials

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-RULE-NOT-FOUND (err u301))
(define-constant ERR-INVALID-SEVERITY (err u302))
(define-constant ERR-VIOLATION-EXISTS (err u303))
(define-constant ERR-REPORT-NOT-FOUND (err u304))
(define-constant ERR-INVALID-PARAMETERS (err u305))
(define-constant ERR-NOT-FOUND (err u306))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var compliance-rule-counter uint u0)
(define-data-var violation-counter uint u0)
(define-data-var report-counter uint u0)

;; Authorized entities
(define-map authorized-compliance-officers principal bool)
(define-map authorized-regulators principal bool)

;; Compliance rule definitions
(define-map compliance-rules
  { rule-id: uint }
  {
    rule-name: (string-ascii 100),
    rule-description: (string-ascii 300),
    rule-category: (string-ascii 50), ;; "consent", "data", "safety", "protocol"
    severity-level: uint, ;; 1=low, 2=medium, 3=high, 4=critical
    monitoring-frequency: uint, ;; blocks between checks
    auto-reporting: bool,
    regulatory-standard: (string-ascii 50), ;; "ICH-GCP", "FDA-CFR", "EMA-GCP"
    created-at: uint,
    active: bool
  }
)

;; Protocol deviation tracking
(define-map protocol-violations
  { violation-id: uint }
  {
    trial-id: uint,
    rule-id: uint,
    violating-entity: principal,
    violation-type: (string-ascii 50),
    severity-level: uint,
    detected-at: uint,
    description: (string-ascii 500),
    auto-detected: bool,
    resolved: bool,
    resolution-notes: (string-ascii 300)
  }
)

;; Trial compliance status tracking
(define-map trial-compliance-status
  { trial-id: uint }
  {
    overall-score: uint, ;; 0-100 percentage
    total-violations: uint,
    critical-violations: uint,
    last-audit-block: uint,
    compliance-level: (string-ascii 20), ;; "excellent", "good", "needs-attention", "critical"
    next-audit-due: uint,
    regulatory-alerts-sent: uint
  }
)

;; Automated compliance reports
(define-map compliance-reports
  { report-id: uint }
  {
    trial-id: uint,
    report-type: (string-ascii 30), ;; "weekly", "monthly", "deviation", "final"
    generated-by: principal,
    report-period-start: uint,
    report-period-end: uint,
    violations-count: uint,
    compliance-score: uint,
    recommendations: (string-ascii 500),
    regulatory-recipient: (optional principal),
    report-timestamp: uint
  }
)

;; Real-time monitoring alerts
(define-map compliance-alerts
  { alert-id: uint }
  {
    trial-id: uint,
    alert-type: (string-ascii 30),
    severity: uint,
    message: (string-ascii 200),
    triggered-by-violation: uint,
    alert-timestamp: uint,
    acknowledged: bool,
    acknowledged-by: (optional principal)
  }
)

;; Create compliance rule
(define-public (create-compliance-rule
  (rule-name (string-ascii 100))
  (rule-description (string-ascii 300))
  (rule-category (string-ascii 50))
  (severity-level uint)
  (monitoring-frequency uint)
  (regulatory-standard (string-ascii 50)))
  (let
    (
      (rule-id (var-get compliance-rule-counter))
    )
    
    ;; Validate inputs
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= severity-level u1) (<= severity-level u4)) ERR-INVALID-SEVERITY)
    (asserts! (> monitoring-frequency u0) ERR-INVALID-PARAMETERS)
    
    ;; Create compliance rule
    (map-set compliance-rules
      { rule-id: rule-id }
      {
        rule-name: rule-name,
        rule-description: rule-description,
        rule-category: rule-category,
        severity-level: severity-level,
        monitoring-frequency: monitoring-frequency,
        auto-reporting: true,
        regulatory-standard: regulatory-standard,
        created-at: stacks-block-height,
        active: true
      })
    
    (var-set compliance-rule-counter (+ rule-id u1))
    (ok rule-id)
  )
)

;; Report protocol violation
(define-public (report-violation
  (trial-id uint)
  (rule-id uint)
  (violating-entity principal)
  (violation-type (string-ascii 50))
  (description (string-ascii 500)))
  (let
    (
      (violation-id (var-get violation-counter))
      (rule-data (unwrap! (map-get? compliance-rules { rule-id: rule-id }) ERR-RULE-NOT-FOUND))
    )
    
    ;; Validate reporter authorization
    (asserts! (or (is-authorized-compliance-officer tx-sender) 
                  (is-eq tx-sender (var-get contract-owner))) ERR-NOT-AUTHORIZED)
    
    ;; Record violation
    (map-set protocol-violations
      { violation-id: violation-id }
      {
        trial-id: trial-id,
        rule-id: rule-id,
        violating-entity: violating-entity,
        violation-type: violation-type,
        severity-level: (get severity-level rule-data),
        detected-at: stacks-block-height,
        description: description,
        auto-detected: false,
        resolved: false,
        resolution-notes: ""
      })
    
    ;; Update trial compliance status
    (unwrap-panic (update-trial-compliance-status trial-id violation-id (get severity-level rule-data)))
    
    ;; Generate alert if critical
    (if (>= (get severity-level rule-data) u3)
        (begin
          (unwrap-panic (generate-compliance-alert trial-id violation-id))
          true)
        true)
    
    (var-set violation-counter (+ violation-id u1))
    (ok violation-id)
  )
)

;; Generate automated compliance report
(define-public (generate-compliance-report
  (trial-id uint)
  (report-type (string-ascii 30))
  (period-start uint)
  (period-end uint))
  (let
    (
      (report-id (var-get report-counter))
      (trial-status (unwrap! (map-get? trial-compliance-status { trial-id: trial-id }) ERR-NOT-FOUND))
    )
    
    ;; Validate reporter
    (asserts! (or (is-authorized-compliance-officer tx-sender) 
                  (is-authorized-regulator tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Generate report
    (map-set compliance-reports
      { report-id: report-id }
      {
        trial-id: trial-id,
        report-type: report-type,
        generated-by: tx-sender,
        report-period-start: period-start,
        report-period-end: period-end,
        violations-count: (get total-violations trial-status),
        compliance-score: (get overall-score trial-status),
        recommendations: (generate-recommendations (get overall-score trial-status)),
        regulatory-recipient: none,
        report-timestamp: stacks-block-height
      })
    
    (var-set report-counter (+ report-id u1))
    (ok report-id)
  )
)

;; Resolve protocol violation
(define-public (resolve-violation
  (violation-id uint)
  (resolution-notes (string-ascii 300)))
  (let
    (
      (violation-data (unwrap! (map-get? protocol-violations { violation-id: violation-id }) ERR-NOT-FOUND))
    )
    
    ;; Validate resolver
    (asserts! (is-authorized-compliance-officer tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Update violation status
    (map-set protocol-violations
      { violation-id: violation-id }
      (merge violation-data {
        resolved: true,
        resolution-notes: resolution-notes
      }))
    
    ;; Recalculate trial compliance score
    (unwrap-panic (recalculate-trial-score (get trial-id violation-data)))
    
    (ok true)
  )
)

;; Helper functions
(define-private (update-trial-compliance-status (trial-id uint) (violation-id uint) (severity uint))
  (let
    (
      (current-status (default-to
        { overall-score: u100, total-violations: u0, critical-violations: u0,
          last-audit-block: stacks-block-height, compliance-level: "excellent",
          next-audit-due: (+ stacks-block-height u1008), regulatory-alerts-sent: u0 }
        (map-get? trial-compliance-status { trial-id: trial-id })))
      (new-violations (+ (get total-violations current-status) u1))
      (new-critical (if (>= severity u4) (+ (get critical-violations current-status) u1) 
                                         (get critical-violations current-status)))
      (score-penalty (* severity u5))
      (new-score (if (>= (get overall-score current-status) score-penalty) 
                     (- (get overall-score current-status) score-penalty) 
                     u0))
      (new-level (calculate-compliance-level new-score))
    )
    
    (map-set trial-compliance-status
      { trial-id: trial-id }
      (merge current-status {
        overall-score: new-score,
        total-violations: new-violations,
        critical-violations: new-critical,
        last-audit-block: stacks-block-height,
        compliance-level: new-level
      }))
    
    (ok true)
  )
)

(define-private (generate-compliance-alert (trial-id uint) (violation-id uint))
  (let
    (
      (alert-id (+ (var-get violation-counter) u1000)) ;; Use different range for alerts
      (violation-data (unwrap-panic (map-get? protocol-violations { violation-id: violation-id })))
    )
    
    (map-set compliance-alerts
      { alert-id: alert-id }
      {
        trial-id: trial-id,
        alert-type: "critical-violation",
        severity: (get severity-level violation-data),
        message: (get violation-type violation-data),
        triggered-by-violation: violation-id,
        alert-timestamp: stacks-block-height,
        acknowledged: false,
        acknowledged-by: none
      })
    
    (ok alert-id)
  )
)

(define-private (calculate-compliance-level (score uint))
  (if (>= score u90) "excellent"
    (if (>= score u70) "good"
      (if (>= score u50) "needs-attention"
        "critical")))
)

(define-private (generate-recommendations (score uint))
  (if (>= score u90) "Maintain current compliance standards"
    (if (>= score u70) "Review recent protocol changes and staff training"
      (if (>= score u50) "Immediate protocol review and corrective actions required"
        "Critical intervention needed - consider trial suspension")))
)

(define-private (recalculate-trial-score (trial-id uint))
  (let
    (
      (current-status (unwrap-panic (map-get? trial-compliance-status { trial-id: trial-id })))
      ;; Simplified recalculation - in reality would analyze all violations
      (improvement (+ (get overall-score current-status) u5))
      (new-score (if (> improvement u100) u100 improvement)) ;; Cap at 100
    )
    
    (map-set trial-compliance-status
      { trial-id: trial-id }
      (merge current-status {
        overall-score: new-score,
        compliance-level: (calculate-compliance-level new-score)
      }))
    
    (ok true)
  )
)

;; Authorization functions
(define-public (authorize-compliance-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-compliance-officers officer true))
  )
)

(define-public (authorize-regulator (regulator principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-regulators regulator true))
  )
)

;; Helper authorization checks
(define-read-only (is-authorized-compliance-officer (officer principal))
  (default-to false (map-get? authorized-compliance-officers officer))
)

(define-read-only (is-authorized-regulator (regulator principal))
  (default-to false (map-get? authorized-regulators regulator))
)

;; Read-only functions
(define-read-only (get-compliance-rule (rule-id uint))
  (map-get? compliance-rules { rule-id: rule-id })
)

(define-read-only (get-violation-details (violation-id uint))
  (map-get? protocol-violations { violation-id: violation-id })
)

(define-read-only (get-trial-compliance-status (trial-id uint))
  (map-get? trial-compliance-status { trial-id: trial-id })
)

(define-read-only (get-compliance-report (report-id uint))
  (map-get? compliance-reports { report-id: report-id })
)

(define-read-only (get-compliance-alert (alert-id uint))
  (map-get? compliance-alerts { alert-id: alert-id })
)

(define-read-only (get-system-overview)
  (ok {
    total-rules: (var-get compliance-rule-counter),
    total-violations: (var-get violation-counter),
    total-reports: (var-get report-counter),
    system-status: "operational"
  })
)
