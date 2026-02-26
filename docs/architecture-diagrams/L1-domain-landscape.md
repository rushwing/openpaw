# OpenPaw Architecture Diagrams — L1 Domain Landscape (ASCII)

> Scope: cross-domain landscape and event relationships among DDD-lite domains.
> Focus: who owns what facts, how workflows trigger domain changes, and how events propagate.

---

## L1 Diagram (Domain Landscape / Event Relationships)

```text
                              OpenPaw L1 — Domain Landscape (Event-Driven)

          External Inputs / Triggers
   +------------------------------------------------------------------+
   | API / Telegram / Mobile / Admin / Payment Provider / Sync Agent   |
   +------------------------------------------------------------------+
                 | commands / webhooks / user actions
                 v

          Workflow / Application Layer (orchestrates, no stable invariants)
   +------------------------------------------------------------------+
   | RetrieveOrGenerate | CorrectionValidation | RewardSettlement      |
   | BountyFulfillment  | Reindex | Sync (future)                      |
   +------------------------------------------------------------------+
        | domain commands / service calls            | publish / consume events
        | (within workflow transaction boundaries)    v
        |                                 +-----------------------------+
        +-------------------------------->| platform/event_bus          |
                                          | - outbox relay              |
                                          | - inbox dedup               |
                                          | - Redis Streams topics      |
                                          +-----------------------------+
                                                    ^
                                                    | domain events
                                                    |

   DDD-lite Domains (stable facts + invariants; cross-domain communication = events only)

   +--------------------+        +--------------------------+        +----------------------+
   | identity           |        | asset_registry           |        | rewards_ledger       |
   |--------------------|        |--------------------------|        |----------------------|
   | Owns:              |        | Owns:                    |        | Owns:                |
   | - users            |        | - Problem (dedup)        |        | - ledger_accounts    |
   | - subscription     |        | - AssetVersion           |        | - ledger_entries     |
   | - entitlements     |        | - Provenance             |        | (append-only)        |
   |                    |        | - publish/deprecate      |        | - balance derivation |
   | Publishes:         |        | Publishes:               |        | Publishes:           |
   | - UserRegistered   |        | - ProblemRegistered      |        | - PointsEarned       |
   | - Subscription...  |        | - AssetVersionCreated    |        | - PointsDeducted     |
   | - DeviceLinked     |        | - AssetVersionPublished  |        |                      |
   +--------------------+        | - AssetDeprecated        |        +----------------------+
          |                      +--------------------------+                  |
          |                                 ^                                  |
          |                                 |                                  |
          |                      bounty answer becomes asset                    |
          |                                 |                                  |
          v                                 |                                  v
   +--------------------+        +--------------------------+        +----------------------+
   | marketplace        |------->| (event-driven link only) |------->| reputation           |
   |--------------------|        +--------------------------+        |----------------------|
   | Owns:              |                                           | Owns:                |
   | - bounties         |<--------------- reacts to ----------------| - scores by tag      |
   | - submissions      |         rewards_ledger.Points*            | - expert levels      |
   | - escrow intent    |                                           | Publishes:           |
   | Publishes:         |---------------> events ------------------>| - ReputationUpdated  |
   | - BountyPosted     |                                           +----------------------+
   | - Submission...    |
   | - BountySettled    |
   | - BountyExpired    |
   +--------------------+


   Canonical Cross-Domain Event Flows (L1 view)
   --------------------------------------------

   A) Subscription -> Points grant (via workflow)
      Payment Provider -> identity.SubscriptionActivated
                       -> RewardSettlementWorkflow
                       -> rewards_ledger.PointsEarned
                       -> reputation (optional score update)

   B) Correction -> New asset version + reward + reputation
      User feedback -> CorrectionValidationWorkflow
                    -> feedback.CorrectionAccepted (workflow/domain boundary event)
                    -> RewardSettlementWorkflow
                    -> rewards_ledger.PointsEarned
                    -> asset_registry.AssetVersionCreated / Published
                    -> reputation.ReputationUpdated

   C) Bounty -> Submission -> Settlement
      marketplace.BountyPosted
          -> BountyFulfillmentWorkflow
          -> marketplace.SubmissionDelivered
          -> rewards_ledger.PointsDeducted (escrow hold) / PointsEarned (payout)
          -> asset_registry.AssetVersionCreated (if accepted answer becomes reusable asset)
          -> marketplace.BountySettled


   Boundary Rules (must stay true)
   -------------------------------
   1) No direct domain-to-domain function calls (events only).
   2) rewards_ledger is the authoritative source for points facts.
   3) asset_registry is the authoritative source for reusable solution/video assets.
   4) Workflows coordinate multi-domain changes but must not bypass domain invariants.
```

---

## Why this diagram type (Landscape / Event Graph)

- L1 is best shown as a `domain landscape + event graph`, not a sequence diagram.
- The goal is to clarify ownership and boundaries before diving into per-domain L2 diagrams.
- Detailed state transitions belong in workflow L2 docs (e.g. `retrieve_or_generate`).

---

## Suggested L2 Diagram Types (per domain)

- `identity`: component diagram (auth / subscription / entitlement / quota)
- `asset_registry`: entity + lifecycle diagram (Problem / AssetVersion / Provenance / publish)
- `rewards_ledger`: ledger flow / component diagram (append-only entries, idempotency, balance read model)
- `reputation`: event-consumer pipeline diagram (inputs -> scoring -> level updates)
- `marketplace`: workflow or state diagram (bounty lifecycle + escrow interactions)

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/context-packs/L1-domain-map.md`
- `docs/adr/ADR-001-ddd-lite-workflow-first.md`
- `docs/adr/ADR-002-asset-as-sot-ledger.md`
- `docs/adr/ADR-004-outbox-inbox-idempotency.md`
- `docs/adr/ADR-005-privacy-boundary.md`
