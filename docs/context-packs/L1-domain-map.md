# OpenPaw — L1 Context Pack: Domain Map

> Load this when working across multiple domains or designing cross-domain interactions.
> For single-domain work, skip to the L2 pack for that domain.

---

## Domain Overview (5 DDD-lite domains)

| Domain | Package | Primary Responsibility |
|--------|---------|----------------------|
| `identity` | `domains/identity/` | Auth, subscriptions, quota entitlements |
| `asset_registry` | `domains/asset_registry/` | Problem dedup, solution versioning, provenance |
| `rewards_ledger` | `domains/rewards_ledger/` | Append-only points ledger |
| `reputation` | `domains/reputation/` | Expert scores and levels per domain tag |
| `marketplace` | `domains/marketplace/` | Bounties, submissions, escrow |

---

## Domain Dependency Map

```
identity ──────────────────────────────────────────────→ (provides user context to all)
asset_registry ────────────────────────────────────────→ (provides asset_version_id to all)
rewards_ledger ← feedback (triggers PointsEarned)
rewards_ledger ← marketplace (triggers PointsDeducted for escrow)
reputation ← rewards_ledger (score recalculated on earn events)
marketplace → asset_registry (bounty answer becomes an AssetVersion)
```

**Cross-domain communication rule: events only.** No direct function calls between domains.

---

## Domain → Events Published

### identity
- `identity.UserRegistered`
- `identity.SubscriptionActivated` — *does NOT credit ledger; triggers RewardSettlementWorkflow*
- `identity.DeviceLinked`

### asset_registry
- `asset.ProblemRegistered` — first time a ProblemSignature is seen
- `asset.AssetVersionCreated` — any new version (generation, correction, expert answer)
- `asset.AssetVersionPublished` — one version promoted to active
- `asset.AssetDeprecated`

### rewards_ledger
- `rewards_ledger.PointsEarned` — AUTHORITATIVE grant event (all credit facts)
- `rewards_ledger.PointsDeducted` — AUTHORITATIVE deduct event (all debit facts)

### reputation
- `reputation.ReputationUpdated`

### marketplace
- `marketplace.BountyPosted`
- `marketplace.SubmissionDelivered`
- `marketplace.BountySettled`
- `marketplace.BountyExpired`

---

## Domain → Commands Consumed

| Domain | Commands consumed |
|--------|------------------|
| identity | (passive — reacts to SubscriptionActivated) |
| asset_registry | `admin.ReindexAsset`, `admin.DeprecateAsset` |
| rewards_ledger | (no direct commands — driven by workflows) |
| reputation | (no direct commands — driven by rewards_ledger events) |
| marketplace | `marketplace.PostBounty`, `marketplace.SubmitBountyAnswer`, `marketplace.AcceptBountySubmission` |

---

## Key Cross-Domain Flow: Correction → Reward → Reputation

```
User submits feedback.ProposeCorrection
  → CorrectionValidationWorkflow validates
  → feedback.CorrectionAccepted emitted
  → RewardSettlementWorkflow triggered
      → rewards_ledger.PointsEarned for submitter
      → asset_registry: new AssetVersion published
  → Reputation service reacts to PointsEarned
      → reputation.ReputationUpdated
```

---

## Key Cross-Domain Flow: Subscription → Points Grant

```
Payment system (external) → identity.SubscriptionActivated
  → RewardSettlementWorkflow triggered
      → rewards_ledger.PointsEarned (entry_type: subscription_grant)
```

**Why not direct?** Keeps ledger as the single source for all points facts. Subscription
activation is an entitlement event, not a financial event. The workflow mediates.

---

## Bounded Context Invariants Summary

| Invariant | Enforced by |
|-----------|------------|
| ProblemSignature uniqueness | `asset_registry.service.get_or_create_problem()` |
| One published version per (problem, asset_type) | `asset_registry` domain |
| Ledger entries INSERT-only | `rewards_ledger` domain (no UPDATE/DELETE in repo) |
| Idempotency key uniqueness in ledger | `UNIQUE(idempotency_key)` in `ledger_entries` |
| Balance never goes negative | Pre-check in `rewards_ledger.service.deduct()` |
| Bounty escrow must be held before BountyPosted | `marketplace` domain |

---

## L2 Packs (load for deeper work)

- `docs/context-packs/domains/identity.md` (to be created)
- `docs/context-packs/domains/asset_registry.md` (to be created)
- `docs/context-packs/domains/rewards_ledger.md` (to be created)
- `docs/context-packs/domains/reputation.md` (to be created)
- `docs/context-packs/domains/marketplace.md` (to be created)

*Assign Gemini 2.5 Pro to generate L2 packs from domain README + model files once implemented.*
