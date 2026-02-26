# OpenPaw Architecture Diagrams — L2 Marketplace (Bounty Lifecycle + Escrow) (ASCII)

> Scope: domain-level design of `domains/marketplace/`.
> Focus: bounty lifecycle states, submission/acceptance flows, and escrow settlement interactions with `rewards_ledger`.

---

## Diagram A — Bounty Lifecycle (State Machine + Domain Events)

```text
                OpenPaw L2 — Marketplace (Bounty Lifecycle State Machine)

  Purpose:
    Let users post bounties, collect expert submissions, accept a winner, and settle escrow safely.


  Commands (entry points)
  -----------------------
   - marketplace.PostBounty
   - marketplace.SubmitBountyAnswer
   - marketplace.AcceptBountySubmission


                                            +----------------------+
                                            |       DRAFT          |
                                            | (optional staging)   |
                                            +----------------------+
                                                     |
                                                     | PostBounty validated
                                                     | escrow hold succeeds
                                                     v
                                            +----------------------+
                                            |        OPEN          |
                                            | visible to experts   |
                                            +----------------------+
                                              |       |        |
                                              |       |        | expiry reached (no winner)
                                              |       |        v
                                              |       |   +----------------------+
                                              |       |   |      EXPIRED         |
                                              |       |   | refund required       |
                                              |       |   +----------------------+
                                              |       |             |
                                              |       |             | refund settled
                                              |       |             v
                                              |       |   +----------------------+
                                              |       |   |   CLOSED_REFUNDED     |
                                              |       |   +----------------------+
                                              |       |
                                              |       | SubmitBountyAnswer
                                              |       | (one or many)
                                              |       v
                                              |   +----------------------+
                                              |   | SUBMISSIONS_PRESENT  |
                                              |   | open + answers exist |
                                              |   +----------------------+
                                              |      |            |
                                              |      |            | more submissions
                                              |      |            +----(stay)----+
                                              |      |
                                              |      | AcceptBountySubmission
                                              |      | winner selected
                                              |      v
                                              |   +----------------------+
                                              |   |  AWAITING_SETTLEMENT |
                                              |   | payout workflow runs |
                                              |   +----------------------+
                                              |             |
                                              |             | payout + asset registration (if applicable)
                                              |             v
                                              |   +----------------------+
                                              |   |       SETTLED        |
                                              |   | winner paid          |
                                              |   +----------------------+
                                              |
                                              | cancel by poster/admin (optional policy)
                                              v
                                     +----------------------+
                                     |      CANCELLED       |
                                     | refund may apply     |
                                     +----------------------+


  Domain Events Along Lifecycle
  -----------------------------

   OPEN:
     -> marketplace.BountyPosted

   New submission:
     -> marketplace.SubmissionDelivered

   Expiry (no accepted winner):
     -> marketplace.BountyExpired

   Settlement complete:
     -> marketplace.BountySettled


  Invariants (marketplace domain)
  -------------------------------

   1) Bounty cannot become OPEN unless escrow hold succeeds first
   2) Exactly one winning submission per bounty
   3) Cannot accept submission after bounty is EXPIRED / CANCELLED / SETTLED
   4) Settlement is idempotent (same bounty + winner -> no duplicate payout)
```

---

## Diagram B — Escrow / Settlement Flow (Marketplace <-> Rewards Ledger <-> Asset Registry)

```text
         OpenPaw L2 — Marketplace Escrow + Settlement (Events + Ledger Facts)

  A) Post Bounty (escrow hold before BountyPosted)
  -----------------------------------------------

   User command: marketplace.PostBounty
         |
         v
   +------------------------------+
   | marketplace service          |
   | validate payload / expiry    |
   | create bounty draft          |
   +------------------------------+
         |
         | trigger escrow hold (via workflow / rewards_ledger)
         v
   +------------------------------+
   | rewards_ledger.deduct()      |
   | entry_type=bounty_escrow     |
   | pre-check balance >= amount  |
   +------------------------------+
         |
         | success -> PointsDeducted (authoritative)
         v
   +------------------------------+
   | marketplace marks OPEN       |
   | emit marketplace.BountyPosted|
   +------------------------------+

   Failure branch:
   - insufficient points / deduct failed -> bounty remains draft/rejected (not OPEN)


  B) Submit Answer (expert delivery)
  ----------------------------------

   Expert command: marketplace.SubmitBountyAnswer
         |
         v
   +------------------------------+
   | marketplace service          |
   | create Submission            |
   | status=delivered             |
   +------------------------------+
         |
         v
   emit marketplace.SubmissionDelivered


  C) Accept Winner + Settle Escrow (payout + optional asset creation)
  -------------------------------------------------------------------

   Poster command: marketplace.AcceptBountySubmission
         |
         v
   +-----------------------------------+
   | BountyFulfillmentWorkflow         |
   | (multi-domain orchestration)      |
   +-----------------------------------+
      |             |                    |
      |             |                    |
      |             |                    +--> (optional) asset_registry.create_version(...)
      |             |                          if winning answer becomes reusable asset
      |             |                          -> asset.AssetVersionCreated / Published
      |             |
      |             +--> rewards_ledger.credit()
      |                  entry_type=bounty_reward
      |                  -> rewards_ledger.PointsEarned (winner)
      |
      +--> marketplace mark SETTLED
           -> emit marketplace.BountySettled


  D) Expiry / Refund Path
  -----------------------

   scheduler / expiry check
        |
        v
   marketplace marks EXPIRED
        |
        +--> emit marketplace.BountyExpired
        |
        +--> RewardSettlementWorkflow (or expiry settlement worker)
              -> rewards_ledger.credit() refund to poster
              -> rewards_ledger.PointsEarned (refund / reversal semantics by entry_type)


  Escrow Accounts / Ledger Facts (conceptual)
  -------------------------------------------

   Poster wallet         Escrow holding account         Expert wallet
   +-------------+       +---------------------+        +-------------+
   | user points  |----->| held bounty points  |------->| reward paid |
   +-------------+       +---------------------+        +-------------+
        deduct:                hold state / audit             credit:
        PointsDeducted         (ledger entries, append-only)  PointsEarned

   Notes:
   - "Escrow" is represented by ledger facts and/or dedicated escrow account(s)
   - No mutable escrow balance overrides; all changes are posted as entries
   - Refunds and payouts are separate entries, never edits to previous rows
```

---

## Key Aggregates / Entities (conceptual)

- `Bounty`
- `Submission`
- `EscrowAccount` (or escrow metadata linked to `rewards_ledger` account)
- `ExpertProfile` (matching metadata; may live in `reputation` integration path)

---

## Service Operations (conceptual mapping)

- `post_bounty(...)`
- `submit_answer(...)`
- `accept_submission(...)`
- `expire_bounty(...)`
- `cancel_bounty(...)` (if product policy allows)

---

## Implementation Notes (important)

- Marketplace must not bypass `rewards_ledger` for points/escrow facts.
- `BountyPosted` should be emitted only after escrow hold succeeds.
- Settlement should be idempotent (guard by bounty state + idempotency key).
- Acceptance and settlement are separate concerns: domain decision vs multi-domain workflow.
- If accepted answer is reusable, asset registration belongs to workflow + `asset_registry`, not marketplace entity internals.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/context-packs/L1-domain-map.md`
- `docs/architecture-diagrams/domains/L2-rewards-ledger.md`
- `docs/architecture-diagrams/domains/L2-asset-registry.md`
- `contracts/commands/v0.json`
- `contracts/events/v0.json`
