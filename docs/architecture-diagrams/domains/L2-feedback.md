# OpenPaw Architecture Diagrams — L2 Feedback (Proposal / ValidationRun / Decision / Publication) (ASCII)

> Scope: domain-level design of `feedback` as a unified human-in-the-loop domain abstraction.
> Focus: proposal-centric modeling for corrections/ratings/expert answers, validation runs, decisions, and publication/reward triggers.

---

## Diagram A — Unified Feedback Domain Abstraction (Proposal-Centric Model)

```text
       OpenPaw L2 — Feedback (Proposal / ValidationRun / Decision / Publication Abstraction)

  Purpose:
    Model human-in-the-loop interactions as a consistent domain mechanism rather than scattered features.
    Unify corrections, replacements, and expert answer proposals under one lifecycle and validation model.


  Command / Input Surface (examples)
  ----------------------------------

   +------------------------------+      +------------------------------+
   | feedback.ProposeCorrection   |      | feedback.SubmitRating        |
   +------------------------------+      +------------------------------+
                    \                             /
                     \                           /
                      v                         v
              +------------------------------------------+
              | Feedback Domain / Application Facade      |
              |------------------------------------------|
              | - create_proposal()                      |
              | - submit_rating()                        |
              | - create_validation_run()                |
              | - record_decision()                      |
              | - create_publication_record()            |
              +------------------------------------------+
                                  |
                                  v

   +----------------------------------------------------------------------------------+
   | Proposal (core abstraction)                                                      |
   |----------------------------------------------------------------------------------|
   | proposal_id (UUID)                                                               |
   | proposal_type (html_patch | video_replacement | expert_answer | ...)             |
   | target_ref_type (asset_version | bounty | problem | ...)                         |
   | target_ref_id                                                                     |
   | submitter_user_id                                                                 |
   | content_ref (storage_key / patch / text answer)                                  |
   | explanation?                                                                      |
   | status (draft | submitted | validating | accepted | rejected | published)        |
   | dedup_hash? (optional duplicate detection)                                        |
   | created_at / submitted_at                                                         |
   +----------------------------------------------------------------------------------+
          | 1..* validation attempts
          v
   +----------------------------------------------------------------------------------+
   | ValidationRun                                                                     |
   |----------------------------------------------------------------------------------|
   | validation_run_id (UUID)                                                          |
   | proposal_id (FK -> Proposal)                                                      |
   | validator_type (ai_auto | ai_human_fallback | admin)                              |
   | status (queued | running | succeeded | failed)                                    |
   | confidence_score?                                                                  |
   | findings_json? (reasons, checks, diff/apply results, quality metrics)             |
   | model_id? / prompt_version?                                                        |
   | started_at / completed_at                                                          |
   +----------------------------------------------------------------------------------+
          | 0..1 final decision per proposal (or latest decision record)
          v
   +----------------------------------------------------------------------------------+
   | Decision                                                                          |
   |----------------------------------------------------------------------------------|
   | decision_id (UUID)                                                                |
   | proposal_id (FK -> Proposal)                                                      |
   | outcome (accepted | rejected)                                                     |
   | decided_by_type (ai_auto | ai_human_fallback | admin)                             |
   | reason? / rejection_reason?                                                       |
   | reward_points_hint? (policy input/output for reward workflow)                     |
   | decided_at                                                                         |
   +----------------------------------------------------------------------------------+
          | 0..1 publication record (accepted proposals only)
          v
   +----------------------------------------------------------------------------------+
   | Publication (result of accepted proposal)                                         |
   |----------------------------------------------------------------------------------|
   | publication_id (UUID)                                                             |
   | proposal_id (FK -> Proposal)                                                      |
   | publication_type (asset_version_publish | answer_publish | metadata_update)        |
   | published_target_type (asset_version | bounty_submission | ...)                   |
   | published_target_id                                                                |
   | published_by                                                                       |
   | published_at                                                                       |
   +----------------------------------------------------------------------------------+


  Adjacent but simpler feedback signal (not proposal-based)
  ---------------------------------------------------------

   +----------------------------------------------------------------------------------+
   | Rating                                                                           |
   |----------------------------------------------------------------------------------|
   | rating_id (UUID)                                                                 |
   | asset_version_id                                                                  |
   | rating_type (helpful | correct | video_quality)                                  |
   | score (1..5)                                                                      |
   | rater_user_id                                                                      |
   | created_at                                                                         |
   +----------------------------------------------------------------------------------+

   Note:
   - Ratings are feedback signals but usually do NOT require ValidationRun/Decision.
   - Rewarding top raters is handled later by RewardSettlementWorkflow (policy-driven).


  Why this abstraction matters
  ----------------------------

   Proposal -> ValidationRun -> Decision -> Publication
   can model:
   - HTML correction patch
   - Video replacement
   - Expert answer promotion (marketplace integration)
   - Future moderation / review workflows
```

---

## Diagram B — Feedback Lifecycle State Machine + Cross-Domain Triggers

```text
      OpenPaw L2 — Feedback (Lifecycle + Validation + Publication + Reward Trigger)

  Proposal Lifecycle (generic, proposal-centric)
  ----------------------------------------------

                                   +----------------------+
                                   |       DRAFT          |
                                   +----------------------+
                                             |
                                             | submit
                                             v
                                   +----------------------+
                                   |      SUBMITTED       |
                                   +----------------------+
                                             |
                                             | enqueue validation
                                             v
                                   +----------------------+
                                   |     VALIDATING       |
                                   | ValidationRun(s)     |
                                   +----------------------+
                                      |               |
                       decision=reject |               | decision=accept
                       (ai/human/admin)|               |
                                      v               v
                               +----------------+  +----------------------+
                               |   REJECTED     |  |      ACCEPTED        |
                               +----------------+  +----------------------+
                                                        |
                                                        | publication needed?
                                                        v
                                                +----------------------+
                                                |    PUBLISHING        |
                                                | create publication   |
                                                | target / records      |
                                                +----------------------+
                                                        |
                                                        | published
                                                        v
                                                +----------------------+
                                                |     PUBLISHED        |
                                                +----------------------+


  Validation Branching (AI-first, human fallback)
  -----------------------------------------------

   VALIDATING
      |
      +--> ValidationRun(ai_auto)
      |       - high confidence accept -> ACCEPTED
      |       - high confidence reject -> REJECTED
      |       - low confidence/conflict -> next ValidationRun(human/admin)
      |
      +--> ValidationRun(ai_human_fallback / admin)
              -> ACCEPTED or REJECTED


  Accepted Proposal -> Cross-Domain Effects (common pattern)
  ----------------------------------------------------------

   ACCEPTED
      |
      +--> emit feedback.CorrectionAccepted (or accepted proposal event variant)
      |
      +--> Publication:
      |      if target is solution/video asset:
      |        -> asset_registry.create_version / publish
      |        -> asset.AssetVersionCreated / AssetVersionPublished
      |
      +--> Reward trigger:
             -> RewardSettlementWorkflow consumes accepted event
             -> rewards_ledger.PointsEarned
             -> reputation.ReputationUpdated (indirect downstream)


  Rejected Proposal -> Cross-Domain Effects
  -----------------------------------------

   REJECTED
      |
      +--> emit feedback.CorrectionRejected (or rejected proposal event variant)
      +--> no publication
      +--> no reward settlement


  Duplicate / Idempotent Handling
  -------------------------------

   duplicate proposal payload for same target (same user, same content hash)
      -> return existing proposal OR reject as duplicate (policy)

   duplicate validation trigger for same proposal
      -> workflow idempotency gate returns existing validation outcome

   repeated publish trigger after ACCEPTED
      -> Publication record / target state guard prevents duplicate publish side effects


  Boundary Rules
  --------------

   - feedback owns proposal/validation/decision/publication records
   - asset_registry owns asset version creation/publish invariants
   - rewards_ledger owns points facts
   - reward_settlement orchestrates rewards; feedback only emits decision facts
```

---

## Key Entities (conceptual)

- `Proposal`
- `ValidationRun`
- `Decision`
- `Publication`
- `Rating`

---

## Service Operations (conceptual mapping)

- `create_proposal(...)`
- `submit_proposal(proposal_id)`
- `start_validation_run(proposal_id, validator_type)`
- `record_validation_result(validation_run_id, findings, confidence)`
- `record_decision(proposal_id, outcome, decided_by_type, reason)`
- `create_publication(proposal_id, target_ref, publication_type)` (accepted proposals only)
- `submit_rating(...)`

---

## Implementation Notes (important)

- Treat `Proposal` as the stable abstraction; proposal types extend behavior via validators/policies.
- Keep `ValidationRun` records append-only or immutable-after-completion for auditability.
- `Decision` should be explicit and queryable (do not infer only from workflow logs).
- Publication should be modeled explicitly so replays/retries can detect already-published outcomes.
- Ratings can remain simpler records, but still benefit from common moderation hooks later.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/architecture-diagrams/workflows/L2-correction-validation.md`
- `docs/architecture-diagrams/workflows/L2-reward-settlement.md`
- `docs/architecture-diagrams/domains/L2-asset-registry.md`
- `docs/architecture-diagrams/domains/L2-rewards-ledger.md`
- `contracts/commands/v0.json`
- `contracts/events/v0.json`
