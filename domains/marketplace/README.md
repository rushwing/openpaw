# Domain: marketplace

## Scope

**This domain covers the expert bounty Q&A marketplace only.**

Responsibilities:
- Bounty lifecycle (DRAFT → OPEN → SUBMISSIONS_PRESENT → AWAITING_SETTLEMENT → SETTLED / EXPIRED / CANCELLED)
- Expert submission and winner acceptance
- Escrow hold and settlement coordination with `rewards_ledger`
- Expert profile metadata for matching

This domain does **not** cover skill trading, skill licensing, or developer revenue sharing.
Those concerns belong to a future `skills_marketplace` domain (separate bounded context).

> **Future note:** When a skills marketplace is added, create a new `domains/skills_marketplace/`
> rather than extending this domain. The bounty Q&A and skill trading models have different
> lifecycle states, pricing models, and escrow semantics — merging them would bloat this domain.

## Key Aggregates

- `Bounty`
- `Submission`
- `EscrowAccount` (or escrow metadata linked to `rewards_ledger` account)
- `ExpertProfile`

## Key Events Published

- `marketplace.BountyPosted`
- `marketplace.SubmissionDelivered`
- `marketplace.BountySettled`
- `marketplace.BountyExpired`

## Related

- `docs/architecture-diagrams/domains/L2-marketplace.md`
- `docs/architecture-diagrams/workflows/L2-bounty-fulfillment.md`
- `docs/adr/ADR-001-ddd-lite-workflow-first.md`
- `contracts/events/v0.json`
- `contracts/commands/v0.json`
