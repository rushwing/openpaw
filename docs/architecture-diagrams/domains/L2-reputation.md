# OpenPaw Architecture Diagrams — L2 Reputation (Event-Driven Scoring + Level Updates) (ASCII)

> Scope: domain-level design of `domains/reputation/`.
> Focus: event-driven score updates, per-domain-tag reputation profiles, level transitions, and idempotent projection/rebuild paths.

---

## Diagram A — Event-Driven Reputation Update Pipeline

```text
           OpenPaw L2 — Reputation (Event-Driven Scoring + Level Updates)

  Purpose:
    Convert authoritative contribution events into per-domain reputation scores and expert levels.


  Event Inputs (from other domains / workflows)
  ---------------------------------------------

   +------------------------------+      +------------------------------+
   | rewards_ledger.PointsEarned  |      | feedback.RatingSubmitted     |
   | (authoritative credit facts) |      | (quality signal, optional)   |
   +------------------------------+      +------------------------------+
                 \                                  /
                  \                                /
                   \                              /
                    v                            v
                 +--------------------------------------+
                 | Reputation Consumer / Projector      |
                 |--------------------------------------|
                 | - inbox dedup (event_id, handler)    |
                 | - parse source event                 |
                 | - resolve domain_tag(s)              |
                 | - calculate score delta              |
                 | - update profile + emit event        |
                 +--------------------------------------+
                                   |
                                   | scoring policy / weights
                                   v
                 +--------------------------------------+
                 | Reputation Policy / Scoring Rules    |
                 |--------------------------------------|
                 | examples:                            |
                 | - correction_reward > rating_reward  |
                 | - bounty_reward boosts more          |
                 | - low-quality ratings dampened       |
                 | - anti-spam caps / decay hooks       |
                 +--------------------------------------+
                                   |
                                   | computed delta (+/-) per domain_tag
                                   v
                 +--------------------------------------+
                 | Reputation Domain Service            |
                 |--------------------------------------|
                 | apply_delta(user_id, domain_tag)     |
                 | - load ReputationProfile             |
                 | - update score                       |
                 | - check level thresholds             |
                 | - append ReputationEvent (optional)  |
                 +--------------------------------------+
                                   |
                                   | DB transaction
                                   v
   +----------------------------------------------------------------------------------+
   | Reputation Storage                                                                |
   |----------------------------------------------------------------------------------|
   | reputation_profiles (user_id, domain_tag, score, level, updated_at, ...)         |
   | reputation_events   (history / audit of score deltas, source_event_id, reason)    |
   +----------------------------------------------------------------------------------+
                                   |
                                   | if score and/or level changed materially
                                   v
                 +--------------------------------------+
                 | emit reputation.ReputationUpdated    |
                 +--------------------------------------+
                                   |
                                   v
                 +--------------------------------------+
                 | Consumers (UI / matching / ranking)  |
                 | - expert badges                      |
                 | - marketplace expert matching        |
                 | - leaderboards (optional)            |
                 +--------------------------------------+


  Core idea:
   rewards_ledger remains the source of points facts;
   reputation is a derived domain projection with its own policies and thresholds.
```

---

## Diagram B — Domain Tag Aggregation, Idempotency, and Rebuild / Backfill Paths

```text
      OpenPaw L2 — Reputation (Domain Tag Aggregation + Idempotent Projection + Rebuild)

  1) Domain Tag Resolution (where does domain_tag come from?)
  -----------------------------------------------------------

   Source event (PointsEarned / RatingSubmitted)
      |
      +--> source_event_id -> linked object lookup
             |
             +--> correction reward -> AssetVersion -> Problem -> topic_tags
             |
             +--> bounty reward -> Bounty / Submission -> domain_tags
             |
             +--> rating reward -> rating target asset -> Problem.topic_tags
             |
             +--> topup / subscription_grant -> no reputation impact (skip)
      |
      v
   resolved domain_tag(s): ["math.algebra", "algo.dp", ...]


  2) Idempotent Event Consumption (projection safety)
  ---------------------------------------------------

   Event Bus
      |
      v
   +------------------------------+
   | reputation consumer          |
   | handler=ReputationProjector  |
   +------------------------------+
      |
      | inbox check (event_id, handler_name)
      v
   +------------------------------+
   | inbox table                  |
   | UNIQUE(event_id, handler)    |
   +------------------------------+
      | miss                                 | hit
      v                                      v
   process + profile update +            skip duplicate
   inbox insert (same tx)                (idempotent replay)


  3) Level Threshold Evaluation (per domain_tag)
  ----------------------------------------------

   score_before + delta -> score_after
              |
              v
   +--------------------------------------------------+
   | threshold table / config                         |
   |--------------------------------------------------|
   | Contributor: >= 10                               |
   | Expert:      >= 100                              |
   | Master:      >= 500                              |
   | (example numbers; policy-configurable)           |
   +--------------------------------------------------+
              |
              | compare previous_level vs new_level
              v
   +------------------------------+
   | level_changed ?              |
   +------------------------------+
      | no                                  | yes
      v                                     v
   emit ReputationUpdated?*             emit ReputationUpdated(level_changed=true)

   *Product policy choice:
     - emit on every score change, or
     - emit only on threshold/level changes + periodic snapshots


  4) Rebuild / Backfill Path (for scoring-policy changes)
  -------------------------------------------------------

   Trigger:
    - scoring weights changed
    - bug fix in projector
    - historical import / migration

   +------------------------------+
   | Rebuild job / admin workflow |
   +------------------------------+
      |
      | scan authoritative events (primarily rewards_ledger.PointsEarned)
      v
   +------------------------------+
   | replay through scorer        |
   | (offline / batch mode)       |
   +------------------------------+
      |
      | recompute profiles
      v
   +------------------------------+
   | upsert reputation_profiles   |
   | append rebuild markers       |
   +------------------------------+
      |
      v
   emit reputation.ReputationUpdated snapshots (optional batched)


  Safety / Quality Rules
  ----------------------

   - Reputation updates are derived; never mutate rewards_ledger facts
   - Unknown source events => skip or quarantine (do not crash pipeline)
   - Anti-spam caps should be policy-configurable and observable
   - Keep score math deterministic for replay / rebuild consistency
```

---

## Key Entities (conceptual)

- `ReputationProfile` (per `user_id + domain_tag`)
- `ReputationEvent` (delta history / audit, optional but recommended)
- `ScoringPolicy` (config-driven weights/thresholds; may live in platform config with domain-owned interpretation)

---

## Service Operations (conceptual mapping)

- `apply_delta(user_id, domain_tag, delta, source_event_id, reason)`
- `get_profile(user_id, domain_tag)`
- `get_profiles(user_id)`
- `rebuild_profile(user_id, domain_tag)` / `rebuild_all(...)` (admin/batch)

---

## Implementation Notes (important)

- Reputation should consume events idempotently (inbox pattern) because event transport is at-least-once.
- `rewards_ledger.PointsEarned` is the primary trigger for contribution-based reputation.
- `feedback.RatingSubmitted` may be an auxiliary signal, but cap its influence to reduce gaming.
- Store both score and level in profile for fast reads; derive from deterministic thresholds.
- Keep scoring rules versioned so rebuilds and audits can explain historical changes.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/context-packs/L1-domain-map.md`
- `docs/architecture-diagrams/components/L2-event-bus-reliability.md`
- `docs/architecture-diagrams/domains/L2-rewards-ledger.md`
- `docs/architecture-diagrams/domains/L2-marketplace.md`
- `contracts/events/v0.json`
