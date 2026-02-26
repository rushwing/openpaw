# OpenPaw Contracts

> **These files define the public interface between all components.**
> Modifying them requires team discussion (phase0_locked) or a new ADR and version bump (frozen).

## What Are Contracts?

Contracts define the **shared vocabulary** for:
- Domain events (what domain services publish)
- Commands (what clients send to trigger workflows)

By agreeing on contracts **before** parallel development begins, multiple agents can
code against each other's interfaces without runtime surprises.

## Files

| File | Description |
|------|-------------|
| `events/v0.json` | All domain and workflow events |
| `commands/v0.json` | All commands from clients and internal callers |

## Status: `phase0_locked`

`phase0_locked` = changes are allowed during Phase 0, but require discussion.
After Phase 1 kick-off, this becomes `frozen` — breaking changes require a version bump (v1) and ADR.

**Breaking changes** (require version bump):
- Removing a field from payload
- Changing a field type
- Removing an event or command
- Renaming an event or command

**Non-breaking changes** (allowed without version bump):
- Adding a new optional field to payload
- Adding a new event or command
- Improving a description

## Format Note

These files are **human-readable event/command specifications**, NOT strict JSON Schemas.
- Use these files for documentation and as source-of-truth for Pydantic models
- Programmatic validation: `platform/contracts/validators.py` (Pydantic models)
- Contract tests: `tests/contracts/`

## Event Envelope (applies to all events)

```json
{
  "event_id":       "<uuid>",
  "event_type":     "<domain>.<EventName>",
  "causation_id":   "<uuid> | null",
  "correlation_id": "<uuid>",
  "tenant_id":      "<string>",
  "user_id":        "<uuid> | null",
  "occurred_at":    "<ISO8601>",
  "schema_version": "v0",
  "payload":        { }
}
```

## Credit/Points Boundary (important)

**`identity.*` events** = entitlement and subscription management (quota, plan tier)
**`rewards_ledger.*` events** = all point grant/deduct facts (the ledger source of truth)

Never use `identity.*` events to update the ledger. The `reward_settlement` workflow
mediates between `identity.SubscriptionActivated` and `rewards_ledger.PointsEarned`.

## Namespace Map

| Namespace | Domain |
|-----------|--------|
| `identity` | User registration, subscriptions, entitlements |
| `ingestion` | Media upload, OCR, normalization |
| `retrieval` | Vector search, cache hits/misses |
| `generation` | Async solve/video job lifecycle |
| `asset` | Problem and solution versioning |
| `rewards_ledger` | Append-only points ledger facts |
| `feedback` | Ratings, corrections, reward triggers |
| `reputation` | Expert score changes |
| `marketplace` | Bounty lifecycle |
| `workflow` | Cross-cutting workflow observability |

## Adding a New Event or Command

1. Open a GitHub issue: "Contract proposal: `domain.EventName`"
2. Add the spec to the appropriate v0.json with full payload description
3. Create a Pydantic model in `platform/contracts/validators.py`
4. Add a contract test in `tests/contracts/`
5. Update the relevant L2 context pack
6. Get approval from Architect (Claude Code) before merging
