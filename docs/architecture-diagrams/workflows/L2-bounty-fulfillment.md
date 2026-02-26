# OpenPaw Architecture Diagrams — L2 BountyFulfillment Workflow (Settlement Orchestration + Branches) (ASCII)

> Scope: workflow-level design of `bounty_fulfillment`.
> Focus: accepted-submission settlement orchestration across marketplace, rewards_ledger, and optional asset_registry publication.

---

## Diagram A — Main State Machine (Accept Winner -> Settle Escrow -> Finalize)

```text
         OpenPaw L2 — BountyFulfillment (Main State Machine)

  Purpose:
    Orchestrate the multi-domain settlement after a bounty winner is accepted:
    validate bounty/submission, settle payout/refund semantics, optionally register reusable asset,
    then finalize marketplace state and emit settlement events.


                                   +----------------------+
                                   |      INITIATED       |
                                   +----------------------+
                                             |
                                             | workflow start
                                             v
                                   +----------------------+
                                   |    LOADING_BOUNTY     |
                                   | bounty + submission   |
                                   | + winner selection    |
                                   +----------------------+
                                      |               |
                   missing/invalid bounty/submission   | loaded + consistent
                   or ownership violation              |
                                      v               v
                                 +-------------+  +----------------------+
                                 |   FAILED    |  |      VALIDATING      |
                                 +-------------+  | state/expiry/escrow   |
                                                  | idempotency checks     |
                                                  +----------------------+
                                                     |              |
                              invalid terminal state  |              | valid to settle
                              / duplicate mismatch    |              |
                                                     v              v
                                              +-------------+  +----------------------+
                                              |   FAILED    |  |  RESERVING_SETTLEMENT |
                                              +-------------+  | settlement lock /     |
                                                               | idempotency gate      |
                                                               +----------------------+
                                                                          |
                                                                          | acquired / safe replay path
                                                                          v
                                                               +----------------------+
                                                               |   PAYOUT_PROCESSING   |
                                                               | rewards_ledger credit |
                                                               | (winner payout)       |
                                                               +----------------------+
                                                                  |                |
                                            payout failed / retry exhausted         | payout success
                                                                  v                v
                                                             +-------------+  +----------------------+
                                                             |   FAILED    |  |   ASSET_OPTIONAL     |
                                                             +-------------+  | register winner as    |
                                                                              | reusable asset?       |
                                                                              +----------------------+
                                                                                    |           |
                                                                  no reusable asset |           | yes, create/publish asset version
                                                                                    |           |
                                                                                    v           v
                                                                              +----------------------+
                                                                              | MARKETPLACE_FINALIZE  |
                                                                              | mark SETTLED + emit   |
                                                                              | BountySettled         |
                                                                              +----------------------+
                                                                                       |
                                                                                       | finalized
                                                                                       v
                                                                              +----------------------+
                                                                              |      SUCCEEDED        |
                                                                              | outcome=settled       |
                                                                              +----------------------+


  Alternate business outcome path (expiry / no winner)
  ----------------------------------------------------

   scheduler/manual trigger
      -> VALIDATING (bounty expired, no accepted winner)
      -> REFUND_PROCESSING (via reward/refund settlement path)
      -> MARKETPLACE_FINALIZE_REFUND (BountyExpired + refund recorded)
      -> SUCCEEDED(outcome=expired_refunded)


  Terminal states:
    - SUCCEEDED (outcome=settled | expired_refunded | already_settled)
    - FAILED
    - CANCELLED (optional, only before irreversible settlement step)
```

---

## Diagram B — Branches, Side Effects, Idempotency, and Compensation Strategy

```text
   OpenPaw L2 — BountyFulfillment (Execution Branches + Cross-Domain Side Effects)

  1) Entry Triggers (two common modes)
  ------------------------------------

   A) Poster accepts submission
      marketplace.AcceptBountySubmission
         -> BountyFulfillmentWorkflow (winner payout path)

   B) Expiry scheduler detects no winner
      scheduler / expiry job
         -> BountyFulfillmentWorkflow (refund path)


  2) Winner Payout Path (accepted submission)
  -------------------------------------------

   [VALIDATING passed]
      |
      v
   +------------------------------+
   | rewards_ledger.credit()      |
   | entry_type=bounty_reward     |
   | source_event_id=bounty/settle|
   +------------------------------+
      |
      | emits rewards_ledger.PointsEarned
      v
   +------------------------------+
   | optional asset_registry step |
   | if answer_type is reusable   |
   | (solution_html / video)      |
   +------------------------------+
      | no                                    | yes
      |                                       |
      v                                       v
   skip asset registration             create AssetVersion + Provenance
                                       publish version (optional policy)
                                       emit AssetVersionCreated/Published
      \                                       /
       \                                     /
        v                                   v
   +----------------------------------------------+
   | marketplace finalize                         |
   | - mark bounty SETTLED                        |
   | - record winner_submission_id                |
   | - emit marketplace.BountySettled             |
   +----------------------------------------------+


  3) Expiry Refund Path (no winner)
  ---------------------------------

   [VALIDATING detects expired, no accepted winner]
      |
      v
   +------------------------------+
   | rewards_ledger.credit()      |
   | entry_type=refund / reversal |
   | recipient=poster             |
   +------------------------------+
      |
      | emits rewards_ledger.PointsEarned (refund semantic entry_type)
      v
   +----------------------------------------------+
   | marketplace finalize refund                  |
   | - mark bounty EXPIRED / CLOSED_REFUNDED      |
   | - emit marketplace.BountyExpired             |
   +----------------------------------------------+


  4) Idempotency and Duplicate Trigger Handling
  ---------------------------------------------

   duplicate AcceptBountySubmission command
      -> workflow idempotency gate (same bounty_id + submission_id)
      -> return existing run / outcome

   duplicate payout attempt
      -> rewards_ledger UNIQUE(idempotency_key)
      -> no double credit

   duplicate finalize attempt
      -> marketplace state guard (already SETTLED / CLOSED_REFUNDED)
      -> return outcome=already_settled (or already_refunded)


  5) Failure / Retry / Compensation Notes
  ---------------------------------------

   Fail before payout write:
     - safe retry, no financial side effect yet

   Fail after payout write, before marketplace finalize:
     - retry workflow
     - ledger idempotency prevents duplicate payout
     - finalize step completes on retry

   Asset registration failure after payout:
     - product policy decision:
       a) non-fatal: settle bounty, queue asset registration retry
       b) fatal to workflow: retry asset step, keep payout idempotent

   Preferred default:
     - payout + marketplace finalization are critical
     - asset registration is optional / best-effort (retriable branch)


  6) Cross-Domain Events Produced / Consumed
  ------------------------------------------

   Consumes:
   - marketplace.AcceptBountySubmission (command trigger path)
   - marketplace.BountyExpired conditions (scheduler-triggered path)

   Produces / triggers:
   - rewards_ledger.PointsEarned (payout or refund)
   - marketplace.BountySettled OR marketplace.BountyExpired
   - asset.AssetVersionCreated / Published (optional reusable answer path)
   - reputation.ReputationUpdated (indirect downstream via rewards_ledger consumer)
```

---

## Step-to-Domain Mapping (quick reference)

- `LOADING_BOUNTY` / `VALIDATING` -> `domains/marketplace`
- `RESERVING_SETTLEMENT` -> workflow idempotency + marketplace state guard
- `PAYOUT_PROCESSING` / `REFUND_PROCESSING` -> `domains/rewards_ledger`
- `ASSET_OPTIONAL` -> `domains/asset_registry` (if reusable answer)
- `MARKETPLACE_FINALIZE*` -> `domains/marketplace`

---

## Implementation Notes (important)

- Treat payout/refund posting as the financial source of truth; marketplace state alone is insufficient.
- Use ledger idempotency keys keyed by bounty settlement/refund source event to prevent double credits.
- Marketplace finalization should be retry-safe and state-guarded (`already settled`/`already refunded`).
- Keep asset registration decoupled enough to avoid blocking settlement on non-critical content processing failures.
- Emit clear workflow outcomes (`settled`, `expired_refunded`, `already_settled`) for UI and auditability.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/architecture-diagrams/domains/L2-marketplace.md`
- `docs/architecture-diagrams/domains/L2-rewards-ledger.md`
- `docs/architecture-diagrams/domains/L2-asset-registry.md`
- `docs/architecture-diagrams/components/L2-event-bus-reliability.md`
- `contracts/commands/v0.json`
- `contracts/events/v0.json`
