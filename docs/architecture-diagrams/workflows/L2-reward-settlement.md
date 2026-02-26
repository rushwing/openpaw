# OpenPaw Architecture Diagrams — L2 RewardSettlement Workflow (Unified Reward Orchestration + Idempotency) (ASCII)

> Scope: workflow-level design of `reward_settlement`.
> Focus: unified reward/refund settlement orchestration from multiple source events into `rewards_ledger`, with idempotency, policy evaluation, and downstream reputation triggers.

---

## Diagram A — Main State Machine (Source Event -> Reward Policy -> Ledger Posting)

```text
        OpenPaw L2 — RewardSettlement (Main State Machine)

  Purpose:
    Convert reward-triggering business events into authoritative ledger postings
    (PointsEarned / PointsDeducted) using a unified, idempotent settlement workflow.


                                   +----------------------+
                                   |      INITIATED       |
                                   +----------------------+
                                             |
                                             | event-triggered workflow start
                                             v
                                   +----------------------+
                                   |   LOADING_SOURCE     |
                                   | load source event +  |
                                   | settlement context   |
                                   +----------------------+
                                      |               |
                         source missing / malformed    | source loaded
                         unsupported schema/version    |
                                      v               v
                                 +-------------+  +----------------------+
                                 |   FAILED    |  |   CLASSIFYING_EVENT   |
                                 +-------------+  | map source -> settle   |
                                                  | action type            |
                                                  +----------------------+
                                                     |               |
                                  unsupported/no-op   |               | recognized reward/refund path
                                                     v               v
                                              +----------------+  +----------------------+
                                              |   SUCCEEDED    |  |  COMPUTING_POLICY     |
                                              | outcome=skipped|  | amount, entry_type,   |
                                              +----------------+  | recipient account(s)   |
                                                                  +----------------------+
                                                                         |            |
                                               policy denies / zero delta |            | policy result computed
                                                                         v            v
                                                                  +----------------+  +----------------------+
                                                                  |   SUCCEEDED    |  |  RESOLVING_ACCOUNT   |
                                                                  | outcome=no_op  |  | lookup ledger acct    |
                                                                  +----------------+  | + sanity checks       |
                                                                                      +----------------------+
                                                                                               |            |
                                                                       account missing / invalid |          | account ready
                                                                                               v            v
                                                                                         +-------------+  +----------------------+
                                                                                         |   FAILED    |  |   POSTING_LEDGER      |
                                                                                         +-------------+  | credit/deduct w/      |
                                                                                                          | idempotency key        |
                                                                                                          +----------------------+
                                                                                                                |              |
                                                                 duplicate (idempotent replay)                  |              | post success
                                                                 or already applied                              |              |
                                                                                                                v              v
                                                                                                      +----------------+  +----------------------+
                                                                                                      |   SUCCEEDED    |  |   EMIT_SUMMARY       |
                                                                                                      | outcome=already |  | workflow/log events   |
                                                                                                      +----------------+  +----------------------+
                                                                                                                                |
                                                                                                                                | done
                                                                                                                                v
                                                                                                                       +----------------------+
                                                                                                                       |      SUCCEEDED        |
                                                                                                                       | outcome=settled       |
                                                                                                                       +----------------------+


  Terminal states:
    - SUCCEEDED (outcome=settled | already_applied | no_op | skipped)
    - FAILED
    - CANCELLED (optional, before ledger posting)
```

---

## Diagram B — Source Event Branches, Idempotency, and Downstream Effects

```text
   OpenPaw L2 — RewardSettlement (Source Branches + Dedup + Downstream Effects)

  1) Supported Source Event Branches (examples)
  ---------------------------------------------

   Source events / triggers
   +--------------------------------------------------------------------+
   | identity.SubscriptionActivated                                      |
   | feedback.CorrectionAccepted                                         |
   | marketplace.BountySettled                                           |
   | marketplace.BountyExpired (refund path)                             |
   | (future) top-rated rater award, referral, admin grant, campaign     |
   +--------------------------------------------------------------------+
                             |
                             v
                    +----------------------+
                    | classify source type  |
                    +----------------------+
                             |
         +-------------------+-------------------+-------------------+-------------------+
         |                   |                   |                   |
         v                   v                   v                   v
   subscription_grant   correction_reward    bounty_reward       refund/reversal
   (earn)               (earn)               (earn)              (earn or deduct semantic)


  2) Policy Computation (reward rules)
  ------------------------------------

   Source event + context -> reward policy evaluator
      |
      +--> determine:
           - entry_type
           - amount
           - recipient account_id
           - source_event_id
           - whether reputation impact applies
           - no-op / deny conditions (e.g. zero points, spam, invalid state)
      |
      v
   settlement plan (deterministic)

   Examples:
   - SubscriptionActivated -> PointsEarned(entry_type=subscription_grant)
   - CorrectionAccepted -> PointsEarned(entry_type=correction_reward)
   - BountySettled -> PointsEarned(entry_type=bounty_reward)
   - BountyExpired -> refund semantic posting to poster


  3) Idempotency / Duplicate Processing Protection
  ------------------------------------------------

   Workflow-level protection:
   - idempotent trigger key per source_event_id (+ recipient/account if needed)
   - duplicate event replay -> existing workflow run / outcome

   Ledger-level protection (authoritative):
   - rewards_ledger UNIQUE(idempotency_key)
   - key examples:
     * earn:subscription_grant:{source_event_id}:{account_id}
     * earn:correction_reward:{source_event_id}:{account_id}
     * earn:bounty_reward:{source_event_id}:{account_id}
     * earn:refund:{source_event_id}:{account_id}

   Result:
   - even if workflow retries after partial failure, double-credit is prevented


  4) Downstream Effects (after ledger posting)
  --------------------------------------------

   POSTING_LEDGER success
      |
      +--> rewards_ledger.PointsEarned / PointsDeducted (authoritative fact)
      |
      +--> reputation consumer reacts (indirect)
      |      -> reputation.ReputationUpdated
      |
      +--> analytics / leaderboards / notifications (optional consumers)
      |
      +--> workflow.WorkflowSucceeded (observability)


  5) Failure / Retry Semantics
  ----------------------------

   Fail before ledger post:
    - safe retry, no financial side effect yet

   Fail after ledger post, before workflow finalization/logging:
    - retry workflow
    - ledger idempotency returns already_applied
    - workflow completes as SUCCEEDED(outcome=already_applied or settled)

   Unsupported source event:
    - mark skipped/no_op (do not fail workflow if intentionally unsupported)


  6) Boundary Rules
  -----------------

   - RewardSettlement computes and orchestrates rewards; rewards_ledger records the facts
   - identity.SubscriptionActivated is entitlement event, not points fact
   - Reputation is downstream projection; RewardSettlement should not mutate reputation directly
```

---

## Step-to-Domain Mapping (quick reference)

- `LOADING_SOURCE` / `CLASSIFYING_EVENT` / `COMPUTING_POLICY` -> workflow logic + policy rules
- `RESOLVING_ACCOUNT` -> `domains/rewards_ledger` account lookup (and possibly identity/account mapping)
- `POSTING_LEDGER` -> `domains/rewards_ledger` (`credit()` / `deduct()`)
- downstream reputation impact -> `domains/reputation` consumer (event-driven, separate)

---

## Key Events (inputs and outputs)

**Common inputs**
- `identity.SubscriptionActivated`
- `feedback.CorrectionAccepted`
- `marketplace.BountySettled`
- `marketplace.BountyExpired`

**Authoritative outputs**
- `rewards_ledger.PointsEarned`
- `rewards_ledger.PointsDeducted` (for deduction/reversal cases if used)

**Indirect downstream**
- `reputation.ReputationUpdated`

---

## Implementation Notes (important)

- Keep reward policy deterministic and versioned for auditability and replay.
- Use source-event-based idempotency keys to prevent duplicate ledger postings.
- Treat `already_applied` as a successful outcome, not a failure.
- Support `no_op` / `skipped` outcomes for source events that should not generate rewards.
- Log policy inputs/outputs (without sensitive payloads) to make disputes debuggable.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/architecture-diagrams/domains/L2-rewards-ledger.md`
- `docs/architecture-diagrams/domains/L2-reputation.md`
- `docs/architecture-diagrams/domains/L2-identity.md`
- `docs/architecture-diagrams/domains/L2-marketplace.md`
- `docs/architecture-diagrams/components/L2-event-bus-reliability.md`
- `contracts/events/v0.json`
