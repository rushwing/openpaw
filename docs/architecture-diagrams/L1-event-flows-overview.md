# OpenPaw Architecture Diagrams — L1 Event Flows Overview (Cross-Domain Choreography) (ASCII)

> Scope: L1 cross-domain event choreography map.
> Focus: which domains and workflows produce and consume which events, and how the five major
> business flows are wired together via events (not direct coupling).

---

## Diagram A — Event Producer / Consumer Matrix

```text
   OpenPaw L1 — Event Flows Overview (Producer / Consumer Matrix)

  Purpose:
    Show the full event mesh at L1 so implementers can understand cross-domain coupling,
    find the authoritative source for any event, and avoid creating hidden dependencies.


  +--------------------------+----------------------------------+------------------------------+
  | Producer                 | Events Published                 | Primary Consumers            |
  +--------------------------+----------------------------------+------------------------------+
  | domains/identity         | identity.UserRegistered          | analytics, sync              |
  |                          | identity.SubscriptionActivated   | reward_settlement (workflow) |
  |                          | identity.DeviceLinked            | sync agent                   |
  +--------------------------+----------------------------------+------------------------------+
  | ingestion pipeline       | ingestion.UploadSessionCreated   | client (upload URL)          |
  |                          | ingestion.MediaUploaded          | normalization worker         |
  |                          | ingestion.MediaNormalized        | retrieve_or_generate         |
  |                          | ingestion.MediaRejected          | client notification          |
  +--------------------------+----------------------------------+------------------------------+
  | domains/asset_registry   | asset.ProblemRegistered          | analytics, search index      |
  |                          | asset.AssetVersionCreated        | retrieval indexer, sync      |
  |                          | asset.AssetVersionPublished      | retrieval indexer, sync      |
  |                          | asset.AssetDeprecated            | retrieval index cleanup      |
  |                          | asset.AssetVideoReady            | client/bot (video player)    |
  +--------------------------+----------------------------------+------------------------------+
  | workflows/retrieve_or_   | retrieval.RetrievalHit           | analytics                    |
  | generate                 | retrieval.RetrievalMiss          | analytics                    |
  |                          | retrieval.DocumentIndexed        | observability                |
  |                          | generation.JobCreated            | observability                |
  |                          | generation.JobSucceeded          | video_workflow (trigger)     |
  |                          | generation.JobFailed             | alerting, retry handler      |
  +--------------------------+----------------------------------+------------------------------+
  | domains/rewards_ledger   | rewards_ledger.PointsEarned      | reputation (projector)       |
  |                          | rewards_ledger.PointsDeducted    | analytics, leaderboards      |
  +--------------------------+----------------------------------+------------------------------+
  | domains/feedback         | feedback.RatingSubmitted         | reputation (aux signal)      |
  |                          | feedback.CorrectionProposed      | correction_validation wf     |
  |                          | feedback.CorrectionAccepted      | asset_registry, reward_      |
  |                          |                                  | settlement (workflow)        |
  |                          | feedback.CorrectionRejected      | analytics, notification      |
  +--------------------------+----------------------------------+------------------------------+
  | domains/reputation       | reputation.ReputationUpdated     | UI badges, expert matching   |
  +--------------------------+----------------------------------+------------------------------+
  | domains/marketplace      | marketplace.BountyPosted         | analytics, expert discovery  |
  |                          | marketplace.SubmissionDelivered  | poster notification          |
  |                          | marketplace.BountySettled        | reward_settlement (wf)       |
  |                          | marketplace.BountyExpired        | reward_settlement (wf)       |
  +--------------------------+----------------------------------+------------------------------+
  | platform/sync_agent      | sync.AssetSyncRequested          | sync_publish_flow (wf)       |
  |                          | sync.AssetUplinked               | Pi local sync status         |
  |                          | sync.AssetDownlinked             | Pi asset importer            |
  |                          | sync.EmbeddingModelMismatch      | alerting, admin dashboard    |
  +--------------------------+----------------------------------+------------------------------+
  | workflow engine          | workflow.WorkflowStarted         | observability                |
  |                          | workflow.WorkflowSucceeded       | observability, analytics     |
  |                          | workflow.WorkflowFailed          | alerting, retry handler      |
  +--------------------------+----------------------------------+------------------------------+


  Key rules visible in this matrix:
   - rewards_ledger is the ONLY producer of points facts (PointsEarned / PointsDeducted)
   - identity does NOT produce point events; only entitlement/subscription events
   - reputation is a pure consumer (projection); it never mutates ledger or feedback data
   - marketplace produces business state facts; financial facts flow through rewards_ledger
   - sync.* events form an isolated namespace; no domain depends on them for business logic
```

---

## Diagram B — Major Event Choreography Chains

```text
   OpenPaw L1 — Five Major Event Flow Chains


  Chain 1 — Problem Solving (Happy Path: Hit vs Miss)
  ---------------------------------------------------

  User                  ingestion          retrieve_or_generate         asset_registry       video_workflow
  ----                  ---------          --------------------         --------------       -------------
  CreateUploadSession ->
                        UploadSessionCreated
  [upload to OSS] ->
                        MediaUploaded
                        MediaNormalized ->
                                           RETRIEVING
                                           ~~~~~~~~~~~~~~~~~~
                                           RetrievalHit? -> response to user (DONE)
                                           ~~~~~~~~~~~~~~~~~~
                                           RetrievalMiss ->
                                           GENERATING_SOLUTION
                                           JobCreated
                                           JobSucceeded ->
                                                                        AssetVersionCreated
                                                                        AssetVersionPublished
                                           SUCCEEDED(new) ----------->
                                           [enqueue video_workflow async]
                                                                                             REGISTERING_ASSET
                                                                                             AssetVersionCreated
                                                                                             (content_status=processing)
                                                                                             RENDERING_VIDEO
                                                                                             FINALIZING_READY
                                                                        AssetVersionCreated
                                                                        (content_status=ready)
                                                                        AssetVideoReady ----> client shows video


  Chain 2 — Community Correction
  -------------------------------

  User             feedback           correction_validation    asset_registry    reward_settlement     reputation
  ----             --------           ---------------------    --------------    -----------------     ----------
  ProposeCorrection ->
                   CorrectionProposed ->
                                      VALIDATING_AI
                                      [ai / human review]
                                      ~~~~~~~~~~~~~~~~~~
                                      CorrectionRejected  (no further effects)
                                      ~~~~~~~~~~~~~~~~~~
                                      CorrectionAccepted ->
                                                           AssetVersionCreated
                                                           AssetVersionPublished
                                                                             PointsEarned
                                                                             (correction_reward)
                                                                                               ReputationUpdated


  Chain 3 — Subscription → Points Grant
  ---------------------------------------

  Payment provider    identity           reward_settlement    rewards_ledger    reputation
  ----------------    --------           -----------------    --------------    ----------
  payment webhook ->
                      SubscriptionActivated ->
                                         COMPUTING_POLICY
                                         POSTING_LEDGER ->
                                                              PointsEarned
                                                              (subscription_grant)
                                                                                (no reputation
                                                                                 impact; skipped)


  Chain 4 — Expert Bounty Marketplace
  -------------------------------------

  Poster              marketplace        rewards_ledger    bounty_fulfillment    asset_registry    reputation
  ------              -----------        --------------    ------------------    --------------    ----------
  PostBounty ->
                      [escrow hold] ->
                      PointsDeducted ->
                      BountyPosted

  Expert submits ->
                      SubmissionDelivered

  Poster accepts ->
                      AcceptBountySubmission ->
                                               PAYOUT_PROCESSING ->
                                               PointsEarned (bounty_reward)
                                                                              [if reusable answer]
                                                                              AssetVersionCreated
                                                                              AssetVersionPublished
                      BountySettled

  [if no winner / expiry]
                      BountyExpired ->
                                               REFUND_PROCESSING ->
                                               PointsEarned (refund entry_type)
                                                                                                    ReputationUpdated
                                                                                                    (via PointsEarned
                                                                                                     consumer)


  Chain 5 — Edge-Cloud Sync
  --------------------------

  Pi user             sync_agent(Pi)    sync_publish_flow    sync_agent(Cloud)    cloud asset_registry
  -------             --------------    -----------------    -----------------    --------------------
  publish consent ->
                      AssetSyncRequested ->
                                         VALIDATING_CONSENT
                                         CHECKING_EMBEDDING
                                         TRANSFERRING  ------->
                                                               inbox receive
                                                               AssetImporter ->
                                                                                    AssetVersionCreated
                                                                                    (cloud, indexed)
                                                               AssetUplinked   (origin_node=cloud)
                      <- Pi receives AssetUplinked
                      cloud_sync_at recorded

  [cloud expert corrects Pi-origin asset]
                                                               AssetDownlinked (origin_node=cloud)
                      <- Pi receives AssetDownlinked
                      AssetImporter (local)
```

---

## Boundary Rules Visible in Event Flows

- **No domain calls another domain's service directly.** All cross-domain effects are event-driven.
- **reward_settlement is the single entry point for all point credits.** Subscription, correction,
  and bounty all funnel through it rather than posting to the ledger directly.
- **reputation never produces commands or writes to other domains.** It is a pure read projection.
- **sync.* events are infrastructure-layer events**, not business facts. Domains never depend on
  them for their own invariants.
- **marketplace manages business state; rewards_ledger manages financial facts.** A bounty being
  SETTLED in marketplace does not imply points were paid — `PointsEarned` is the only proof.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/architecture-diagrams/L1-domain-landscape.md`
- `docs/architecture-diagrams/L1-runtime-topology.md`
- `docs/context-packs/L1-domain-map.md`
- `contracts/events/v0.json`
- `contracts/commands/v0.json`
