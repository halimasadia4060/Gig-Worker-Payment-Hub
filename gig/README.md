# Gig Worker Payment Hub Smart Contract

A decentralized platform for managing gig work with secure escrow payments, dispute resolution, and reputation management built on the Stacks blockchain.

## Overview

The Gig Worker Payment Hub enables clients to post gig opportunities and workers to apply and complete tasks with trustless payment guarantees. All payments are held in escrow and released upon completion approval, with built-in dispute resolution and rating systems.

## Key Features

### 💼 Gig Lifecycle Management
- **Create Gigs**: Clients post gigs with automatic escrow funding (payment + platform fee)
- **Apply for Work**: Workers submit proposals to open gigs
- **Assignment**: Clients review applications and assign workers
- **Completion**: Workers mark gigs complete, clients approve and release payment
- **Cancellation**: Clients can cancel unassigned gigs with full refund

### 💰 Secure Payment System
- **Escrow Protection**: Funds locked in contract until work completion
- **Platform Fee**: Configurable fee (default 2.5%) for platform sustainability
- **Automatic Transfers**: Payments released directly to workers upon approval
- **Fee Calculation**: Transparent fee computation on all transactions

### 👥 Profile & Reputation System
- **Worker Profiles**: Track total gigs, completions, earnings, and ratings
- **Client Profiles**: Monitor gigs posted, total spent, and ratings
- **Rating System**: 1-5 star ratings with comments (post-payment only)
- **Average Ratings**: Automatically calculated from all received ratings

### ⚖️ Dispute Resolution
- **Create Disputes**: Either party can raise disputes with detailed reasons
- **Owner Mediation**: Contract owner resolves disputes fairly
- **Flexible Resolution**: Payments directed based on dispute outcome
- **Status Tracking**: Complete dispute lifecycle management

## Contract Functions

### Core Gig Functions

**`create-gig`** `(title description payment deadline)`
- Creates new gig with escrow funding
- Returns: `gig-id`

**`apply-for-gig`** `(gig-id proposal)`
- Worker submits application with proposal
- Returns: `true` on success

**`assign-worker`** `(gig-id worker)`
- Client assigns worker to gig
- Returns: `true` on success

**`complete-gig`** `(gig-id)`
- Worker marks gig as completed
- Returns: `true` on success

**`approve-and-pay`** `(gig-id)`
- Client approves work and releases payment
- Returns: `true` on success

**`cancel-gig`** `(gig-id)`
- Client cancels unassigned gig (full refund)
- Returns: `refund-amount`

### Dispute Functions

**`create-dispute`** `(gig-id reason)`
- Initiate dispute (client or worker)
- Returns: `dispute-id`

**`resolve-dispute`** `(dispute-id resolution pay-worker)`
- Owner resolves dispute (admin only)
- `pay-worker`: `true` = pay worker, `false` = refund client

### Rating Functions

**`rate-participant`** `(gig-id rating comment)`
- Rate counterparty (1-5 stars)
- Only after payment completion
- Returns: `true` on success

### Read-Only Functions

**`get-gig`** `(gig-id)` - Get gig details
**`get-worker-profile`** `(worker)` - Get worker statistics
**`get-client-profile`** `(client)` - Get client statistics
**`get-dispute`** `(dispute-id)` - Get dispute information
**`get-application`** `(gig-id worker)` - Get application details
**`get-rating`** `(gig-id rater)` - Get rating details
**`get-platform-fee-percent`** - Current platform fee
**`calculate-fee`** `(amount)` - Calculate platform fee for amount

### Admin Functions

**`set-platform-fee`** `(new-fee)`
- Update platform fee percentage (max 10%)
- Owner only

## Gig Status Flow

```
open → assigned → completed → paid
  ↓         ↓          ↓
cancelled  disputed  resolved
```

## Error Codes

- `u100` - Owner only operation
- `u101` - Resource not found
- `u102` - Unauthorized access
- `u103` - Resource already exists
- `u104` - Invalid status for operation
- `u105` - Insufficient funds
- `u106` - Invalid amount
- `u107` - Already completed
- `u108` - Dispute active
- `u109` - Invalid rating (must be 1-5)

## Usage Example

### For Clients:
```clarity
;; 1. Create a gig (10 STX payment, deadline block 1000)
(contract-call? .gig-hub create-gig "Logo Design" "Need modern logo" u10000000 u1000)
;; Returns: (ok u1) - gig-id

;; 2. Assign worker after reviewing applications
(contract-call? .gig-hub assign-worker u1 'SP2ABC...)

;; 3. Approve completed work and release payment
(contract-call? .gig-hub approve-and-pay u1)

;; 4. Rate the worker
(contract-call? .gig-hub rate-participant u1 u5 "Excellent work!")
```

### For Workers:
```clarity
;; 1. Apply for a gig
(contract-call? .gig-hub apply-for-gig u1 "I have 5 years experience...")

;; 2. Complete the gig after assignment
(contract-call? .gig-hub complete-gig u1)

;; 3. Rate the client
(contract-call? .gig-hub rate-participant u1 u5 "Great client!")
```

## Security Features

- ✅ Escrow-based payment protection
- ✅ Authorization checks on all state changes
- ✅ Prevents duplicate applications and ratings
- ✅ Status validation prevents invalid transitions
- ✅ Protected admin functions
- ✅ No re-entrancy vulnerabilities
- ✅ Immutable dispute records

## Platform Fee Structure

Default platform fee: **2.5%** (250 basis points)
- Charged when gig is created
- Deducted from escrow before worker payment
- Configurable by contract owner (max 10%)

## Best Practices

1. **Clients**: Set realistic deadlines and clear descriptions
2. **Workers**: Submit detailed proposals highlighting relevant experience
3. **Both**: Communicate off-chain before work begins
4. **Disputes**: Provide detailed reasons with evidence references
5. **Ratings**: Be honest and constructive in feedback

