# OpenPaw Architecture Diagrams — L2 CorrectionValidation Workflow (Proposal -> Validate -> Accept/Reject -> Publish/Reward Trigger) (ASCII)

> Scope: workflow-level design of `correction_validation`.
> Focus: proposal intake, AI/human validation branches, accept/reject decisions, and downstream publish/reward trigger orchestration.

---

## Diagram A — Main State Machine (Proposal Validation and Decision)

```text
        OpenPaw L2 — CorrectionValidation (Main State Machine)

  Purpose:
    Validate user-submitted corrections (HTML patch or video replacement), accept or reject them,
    and trigger downstream asset publishing and reward settlement safely.


                                   +----------------------+
                                   |      INITIATED       |
                                   +----------------------+
                                             |
                                             | workflow start
                                             v
                                   +----------------------+
                                   |   LOADING_PROPOSAL   |
                                   | fetch proposal +     |
                                   | target asset version |
                                   +----------------------+
                                      |               |
                    proposal missing / invalid         | proposal loaded
                    (asset missing, malformed)         |
                                      v               v
                                 +-------------+  +----------------------+
                                 |   FAILED    |  |   PRECHECKING        |
                                 +-------------+  | schema / type / size  |
                                                  | duplicate / policy     |
                                                  +----------------------+
                                                     |             |
                            precheck reject (fatal)   |             | precheck passed
                                                     v             v
                                              +-------------+  +----------------------+
                                              |  REJECTED   |  |    VALIDATING_AI     |
                                              | final=no    |  | automated validation |
                                              +-------------+  +----------------------+
                                                                      |            |
                                                     ai says reject    |            | ai says accept
                                                     (confident)       |            | (confident)
                                                                      v            v
                                                               +-------------+  +----------------------+
                                                               |  REJECTED   |  |      ACCEPTED        |
                                                               | final=no    |  | decision=yes         |
                                                               +-------------+  +----------------------+
                                                                      ^
                                                                      |
                                            ai uncertain / conflict    |
                                            / low confidence           |
                                                                      |
                                                            +----------------------+
                                                            |  AWAITING_HUMAN      |
                                                            | fallback review       |
                                                            +----------------------+
                                                              |              |
                                            human rejects      |              | human accepts
                                                              v              v
                                                         +-------------+  +----------------------+
                                                         |  REJECTED   |  |      ACCEPTED        |
                                                         +-------------+  +----------------------+


  Terminal states:
    - ACCEPTED   (business decision = accepted)
    - REJECTED   (business decision = rejected)
    - FAILED     (workflow/system error)
    - CANCELLED  (optional, from non-terminal states)

  Note:
    ACCEPTED/REJECTED are business-final states for this workflow (both are "successful" validations
    from a business perspective). The generic WorkflowResult.status may still be "succeeded" with
    outcome="accepted" or outcome="rejected".
```

---

## Diagram B — Downstream Branches (Publish New Version / Reward Trigger / Reputation)

```text
     OpenPaw L2 — CorrectionValidation (Post-Decision Branches + Cross-Domain Triggers)

  1) Input / Proposal Types
  -------------------------

   feedback.ProposeCorrection command
      |
      v
   proposal_type:
   +----------------------+-------------------------+
   | html_patch           | video_replacement       |
   +----------------------+-------------------------+
   | patch target HTML    | replacement asset file  |
   | validate patch apply | validate media/quality  |
   +----------------------+-------------------------+


  2) Accepted Path (publish + reward trigger)
  -------------------------------------------

   [ACCEPTED decision]
      |
      | emit feedback.CorrectionAccepted
      v
   +-----------------------------------+
   | ACCEPTED event payload            |
   | - proposal_id                     |
   | - new_asset_version_id            |
   | - validation_method               |
   | - submitter_user_id               |
   | - reward_points (policy computed) |
   +-----------------------------------+
      |
      +------------------------------+
      |                              |
      v                              v
   +------------------------+    +------------------------------+
   | asset_registry domain  |    | RewardSettlementWorkflow     |
   | create new AssetVersion|    | (triggered by CorrectionAccepted)
   | + Provenance           |    +------------------------------+
   | publish new version    |              |
   | emit AssetVersion...   |              v
   +------------------------+    +------------------------------+
                                 | rewards_ledger.PointsEarned  |
                                 | (authoritative points fact)  |
                                 +------------------------------+
                                               |
                                               v
                                 +------------------------------+
                                 | reputation updater           |
                                 | -> ReputationUpdated         |
                                 +------------------------------+


  3) Rejected Path (no asset publish, no reward)
  ----------------------------------------------

   [REJECTED decision]
      |
      | emit feedback.CorrectionRejected
      v
   +------------------------------+
   | proposal remains rejected    |
   | no AssetVersion publish      |
   | no reward settlement         |
   +------------------------------+


  4) Validation Strategy Branching (AI-first with human fallback)
  ---------------------------------------------------------------

   VALIDATING_AI
      |
      +--> high confidence accept   -> ACCEPTED (validation_method=ai_auto)
      |
      +--> high confidence reject   -> REJECTED (validation_method=ai_auto)
      |
      +--> low confidence / conflict / unsafe diff
            -> AWAITING_HUMAN
            -> human decision
                 -> ACCEPTED (validation_method=ai_human_fallback or admin)
                 -> REJECTED (validation_method=ai_human_fallback or admin)


  5) Idempotency / Duplicate Submission Handling
  ----------------------------------------------

   duplicate proposal content for same asset_version_id (same submitter, same patch hash)
      -> precheck may short-circuit:
         - reject as duplicate proposal (business reject), OR
         - return existing proposal status (idempotent UX path)

   duplicate workflow start for same proposal_id
      -> workflow idempotency gate returns existing run / final result
```

---

## Step-to-Domain / Adapter Mapping (quick reference)

- `LOADING_PROPOSAL` -> feedback proposal store / repository
- `PRECHECKING` -> schema validators + policy checks + diff/media sanity checks
- `VALIDATING_AI` -> LLM / validation adapters (AI grader/checker)
- `AWAITING_HUMAN` -> moderator/admin interface queue (human review)
- `ACCEPTED path` -> `domains/asset_registry` + `RewardSettlementWorkflow`
- `REJECTED path` -> feedback status update only

---

## Key Events (correction workflow and downstream effects)

- `feedback.CorrectionProposed` (input fact, emitted earlier at proposal creation)
- `feedback.CorrectionAccepted` OR `feedback.CorrectionRejected`
- `asset.AssetVersionCreated` / `asset.AssetVersionPublished` (accepted path)
- `rewards_ledger.PointsEarned` (accepted path, via reward settlement workflow)
- `reputation.ReputationUpdated` (optional downstream projection)

---

## Implementation Notes (important)

- Separate "validation decision" from "reward settlement" to keep concerns clean.
- `CorrectionAccepted` should be emitted only after new asset version creation is committed (or include deterministic retry semantics).
- Treat `REJECTED` as a valid business outcome, not a system failure.
- Human fallback should preserve a full audit trail (who reviewed, why).
- Keep validator outputs structured (confidence score, reasons, diff checks) for observability and tuning.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/context-packs/L1-domain-map.md`
- `docs/architecture-diagrams/domains/L2-asset-registry.md`
- `docs/architecture-diagrams/domains/L2-rewards-ledger.md`
- `contracts/commands/v0.json`
- `contracts/events/v0.json`
