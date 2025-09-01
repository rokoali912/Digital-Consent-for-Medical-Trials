# Trialok - Digital Consent for Medical Trials

Immutable proof of patient agreement for medical research trials on the Stacks blockchain.

## Overview

Trialok is a smart contract that provides a secure, transparent, and immutable system for managing patient consent in medical trials. It ensures that patient agreements are permanently recorded on the blockchain while maintaining regulatory compliance and patient rights.

## Core Features

- **Patient Registration**: Secure patient identity verification and profile management
- **Trial Management**: Research institutions can create and manage clinical trials
- **Digital Consent**: Immutable consent recording with comprehensive consent types
- **Consent Withdrawal**: Patients can withdraw consent with proper audit trails
- **Authorization System**: Role-based access control for researchers and institutions
- **Audit Trail**: Complete transparency of all consent activities

## Smart Contract Functions

### Administrative Functions

#### `authorize-researcher (researcher principal)`
Authorizes a researcher to create and manage trials.
- **Caller**: Contract owner only
- **Returns**: Success confirmation

#### `authorize-institution (institution principal)`
Authorizes an institution to participate in trials.
- **Caller**: Contract owner only
- **Returns**: Success confirmation

### Patient Functions

#### `register-patient (name age medical-id)`
Registers a new patient profile.
- **Parameters**:
  - `name`: Patient name (max 50 characters)
  - `age`: Patient age
  - `medical-id`: Unique medical identifier (max 20 characters)
- **Returns**: Success confirmation

#### `give-consent (trial-id consent-type data-usage-consent follow-up-consent)`
Records patient consent for a specific trial.
- **Parameters**:
  - `trial-id`: Unique trial identifier
  - `consent-type`: Type of consent (max 50 characters)
  - `data-usage-consent`: Boolean for data usage agreement
  - `follow-up-consent`: Boolean for follow-up study agreement
- **Returns**: Consent ID

#### `withdraw-consent (trial-id reason)`
Withdraws consent from a trial.
- **Parameters**:
  - `trial-id`: Trial to withdraw from
  - `reason`: Withdrawal reason (max 200 characters)
- **Returns**: Success confirmation

### Researcher Functions

#### `create-trial (title description institution duration-blocks max-participants)`
Creates a new medical trial.
- **Parameters**:
  - `title`: Trial title (max 100 characters)
  - `description`: Trial description (max 500 characters)
  - `institution`: Authorized institution principal
  - `duration-blocks`: Trial duration in blockchain blocks
  - `max-participants`: Maximum number of participants
- **Returns**: Trial ID

#### `deactivate-trial (trial-id)`
Deactivates an active trial.
- **Caller**: Trial researcher or contract owner
- **Returns**: Success confirmation

### Read-Only Functions

#### `get-trial-info (trial-id)`
Retrieves complete trial information.

#### `get-patient-profile (patient)`
Gets patient profile information.

#### `get-consent-record (consent-id)`
Retrieves detailed consent record.

#### `verify-consent-authenticity (consent-id)`
Verifies and returns consent authenticity data.

## Usage Examples

### 1. Setting Up the System

```clarity
;; Authorize a research institution
(contract-call? .trialok authorize-institution 'SP1234567890ABCDEF)

;; Authorize a researcher
(contract-call? .trialok authorize-researcher 'SP0987654321FEDCBA)
```

### 2. Patient Registration

```clarity
;; Register as a patient
(contract-call? .trialok register-patient "John Doe" u35 "MED123456")
```

### 3. Creating a Clinical Trial

```clarity
;; Create a new trial
(contract-call? .trialok create-trial 
  "COVID-19 Vaccine Efficacy Study"
  "Phase 3 randomized controlled trial evaluating vaccine efficacy"
  'SP1234567890ABCDEF  ;; institution
  u144000              ;; ~100 days in blocks
  u1000)               ;; max participants
```

### 4. Giving Consent

```clarity
;; Patient gives consent to participate
(contract-call? .trialok give-consent 
  u1                    ;; trial-id
  "Informed Consent"    ;; consent-type
  true                  ;; data-usage-consent
  true)                 ;; follow-up-consent
```

### 5. Withdrawing Consent

```clarity
;; Patient withdraws consent
(contract-call? .trialok withdraw-consent 
  u1 
  "Personal circumstances changed")
```

## Data Structures

### Trial Record
- Title and description
- Researcher and institution
- Start/end blocks
- Participant limits and counts
- Active status

### Consent Record
- Trial association
- Patient identity
- Consent details and timestamps
- Withdrawal permissions
- Data usage agreements

### Patient Profile
- Basic information
- Verification status
- Registration timestamp

## Security Features

- **Immutable Records**: All consent data is permanently stored on blockchain
- **Access Control**: Role-based permissions for different user types
- **Patient Privacy**: Medical IDs are used instead of personal information
- **Audit Trail**: Complete history of all consent activities
- **Withdrawal Rights**: Patients can withdraw consent while maintaining audit trail

## Error Codes

- `u100`: Not authorized
- `u101`: Record already exists
- `u102`: Record not found
- `u103`: Invalid input parameters
- `u104`: Trial inactive or expired
- `u105`: Consent already given
- `u106`: Consent not found
- `u107`: Withdrawal not allowed

## Deployment

1. Deploy the contract using Clarinet
2. Authorize initial researchers and institutions
3. Begin patient registration and trial creation

## Testing

Run the test suite:
```bash
clarinet test
```

## Compliance

This contract is designed to support compliance with:
- Good Clinical Practice (GCP) guidelines
- International Council for Harmonisation (ICH) standards
- Local regulatory requirements for clinical trials

## License

This project is open source and available under the MIT License.
