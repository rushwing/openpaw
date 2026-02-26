# OpenPaw Architecture Diagrams — L2 SyncPublishFlow Workflow (Pi→Cloud Consent + Asset Sync) (ASCII)

> Scope: workflow-level design of `sync_publish_flow`.
> Focus: explicit user-consent publish from Pi to Cloud, embedding model compatibility check,
> content transfer + remote indexing, and the complementary downlink receipt path.

---

## Diagram A — Main State Machine (Consent → Check → Transfer → Index → Confirm)

```text
        OpenPaw L2 — SyncPublishFlow (Main State Machine)

  Purpose:
    Orchestrate the explicit "Publish to Cloud" action initiated by a Pi user:
    validate consent, verify embedding model compatibility, transfer asset content,
    trigger remote indexing, and confirm sync completion.


                                   +----------------------+
                                   |      INITIATED       |
                                   +----------------------+
                                             |
                                             | workflow start (user publish action)
                                             v
                                   +----------------------+
                                   | VALIDATING_CONSENT   |
                                   | check publish_consents|
                                   | + privacy_mode flag  |
                                   +----------------------+
                                      |               |
                        no consent /  |               | consent valid
                        privacy_mode  |               |
                        = true        v               v
                                 +-------------+  +----------------------+
                                 |  SUCCEEDED  |  | CHECKING_EMBEDDING   |
                                 | outcome=    |  | compare local vs     |
                                 | skipped     |  | cloud embedding_model|
                                 +-------------+  +----------------------+
                                                      |           |
                                      mismatch        |           | match
                                      (models differ) |           |
                                                      v           v
                                               +-------------+  +----------------------+
                                               |   FAILED    |  |    TRANSFERRING      |
                                               | emit Embed- |  | POST asset metadata  |
                                               | dingModel   |  | + content_ref to     |
                                               | Mismatch    |  | cloud relay endpoint |
                                               +-------------+  +----------------------+
                                                                    |           |
                                                transfer failed /   |           | transfer success
                                                retries exhausted   |           |
                                                                    v           v
                                                              +-------------+  +----------------------+
                                                              |   FAILED    |  |  INDEXING_REMOTE     |
                                                              +-------------+  | cloud indexes into   |
                                                                               | Qdrant + asset_reg   |
                                                                               +----------------------+
                                                                                    |           |
                                                                 indexing failed /  |           | indexed
                                                                 retries exhausted  |           |
                                                                                    v           v
                                                                              +-------------+  +----------------------+
                                                                              |   FAILED    |  |    CONFIRMING        |
                                                                              +-------------+  | record local sync    |
                                                                                               | metadata +           |
                                                                                               | emit AssetUplinked   |
                                                                                               +----------------------+
                                                                                                        |
                                                                                                        | confirmed
                                                                                                        v
                                                                                               +----------------------+
                                                                                               |      SUCCEEDED       |
                                                                                               | outcome=published    |
                                                                                               +----------------------+


  Alternate: already published
  ----------------------------

   VALIDATING_CONSENT or early check:
      -> asset already has cloud_sync_at record for this version
      -> short-circuit: SUCCEEDED(outcome=already_published)


  Terminal states:
    - SUCCEEDED (outcome=published | already_published | skipped)
    - FAILED (embedding_mismatch | transfer_failed | indexing_failed)
    - CANCELLED (optional, before TRANSFERRING)
```

---

## Diagram B — Consent Model, Embedding Check, and Downlink Receipt Path

```text
   OpenPaw L2 — SyncPublishFlow (Consent + Embedding + Downlink)


  1) Consent Model (publish_consents)
  ------------------------------------

   Explicit publish action by Pi user
         |
         v
   +----------------------------------------------+
   | publish_consents                             |
   |----------------------------------------------|
   | consent_id (UUID)                            |
   | user_id                                      |
   | asset_version_id                             |
   | consent_ref (user-readable description)      |
   | consented_at                                 |
   | revoked_at? (nullable)                       |
   +----------------------------------------------+

   Rules:
   - Consent is per asset version (not blanket)
   - privacy_mode=true always blocks, regardless of consent record
   - Revoked consent at workflow start -> outcome=skipped
   - SyncAgent re-verifies consent at relay time (race-condition safety)


  2) Embedding Model Compatibility Check
  ---------------------------------------

   [CHECKING_EMBEDDING step]
         |
         | Pi local embedding_model_global = "text-embedding-3-small"
         | Cloud reports  embedding_model_global = ?
         v
   +----------------------------------------------+
   | match?                                       |
   +----------------------------------------------+
      | yes                            | no
      v                                v
   proceed to TRANSFERRING         emit sync.EmbeddingModelMismatch
                                   (local_model=..., remote_model=...)
                                   workflow -> FAILED
                                   (asset is not transferred)

   Why this matters:
   - Assets are indexed by embedding model at creation time
   - Mixing embeddings in the same Qdrant collection silently corrupts retrieval
   - Resolution: run L2-reindex-workflow on one side before retrying sync


  3) Transfer Payload (what is sent)
  -----------------------------------

   +----------------------------------------------+
   | Sync Transfer Payload                        |
   |----------------------------------------------|
   | asset_version_id                             |
   | problem_signature                            |
   | asset_type                                   |
   | content_ref (pre-signed object storage URL)  |
   | provenance snapshot                          |
   | embedding_model                              |
   | origin_node = local_node_id                  |
   | consent_ref                                  |
   +----------------------------------------------+

   Content is transferred via pre-signed URL (not inline payload):
     Pi SyncAgent  ->  obtains pre-signed read URL from local MinIO/OSS
     Cloud SyncAgent  ->  downloads directly from Pi-local storage
                          (or Pi uploads to shared OSS bucket)


  4) Remote Indexing (INDEXING_REMOTE step on Cloud)
  ---------------------------------------------------

   Cloud receives transfer payload
         |
         v
   +----------------------------------------------+
   | Cloud SyncAgent / Indexing Worker            |
   |----------------------------------------------|
   | - create or update Problem in cloud registry |
   |   (match by problem_signature)               |
   | - create AssetVersion                        |
   |   content_status=processing -> ready         |
   | - create ProvenanceRecord                    |
   |   created_by_type=sync_from_edge             |
   |   embedding_model=<from payload>             |
   | - index into Qdrant                          |
   +----------------------------------------------+
         |
         | emit asset.AssetVersionCreated (cloud)
         | emit sync.AssetUplinked (origin_node=cloud)
         v
   Pi receives AssetUplinked, records cloud_sync_at on local AssetVersion


  5) Downlink Receipt Path (complementary — Pi receives expert improvements)
  --------------------------------------------------------------------------

   [This path is initiated by the Cloud, not the user]

   Cloud expert corrects a Pi-origin asset
      -> asset.AssetVersionPublished (cloud, origin_node=pi-abc)
      -> Cloud SyncAgent emits sync.AssetDownlinked
         (target_node=pi-abc, asset_version_id=new_v)
      -> Pi SyncAgent receives (inbox dedup)
      -> Pi imports AssetVersion into local asset_registry
         created_by_type=cloud_sync
      -> Pi emits local asset.AssetVersionCreated

   Pi user then sees improved version in local app.
   No consent required for downlink (cloud-initiated improvement, user-beneficial).
   User can still deprecate the downlinked version locally if preferred.


  6) Idempotency
  --------------

   Workflow key:     sha256(asset_version_id + target_node_id)
   Duplicate run:    -> VALIDATING_CONSENT finds cloud_sync_at already set
                     -> SUCCEEDED(outcome=already_published)

   Retry after transfer fail:
     - cloud relay is idempotent (inbox dedup on cloud SyncAgent)
     - re-transfer returns same cloud asset_version_id
```

---

## Step-to-Domain / Adapter Mapping

- `VALIDATING_CONSENT` → `publish_consents` table (identity or asset_registry boundary)
- `CHECKING_EMBEDDING` → `platform/policy_engine` embedding_model_global constant
- `TRANSFERRING` → `adapters/sync_relay` + `adapters/object_storage` (pre-signed URL)
- `INDEXING_REMOTE` → `domains/asset_registry` (cloud-side) + `adapters/qdrant`
- `CONFIRMING` → local `domains/asset_registry` (record cloud_sync_at)

---

## Key Events

**Inputs**
- User publish consent action (command or UI trigger)
- `sync.AssetDownlinked` (for complementary downlink receipt path)

**Outputs**
- `sync.AssetSyncRequested` (triggered at workflow start, before TRANSFERRING)
- `sync.AssetUplinked` (emitted by Cloud on successful indexing)
- `sync.EmbeddingModelMismatch` (emitted on model drift detection, workflow fails)
- `asset.AssetVersionCreated` (emitted on Cloud when asset is registered remotely)

---

## Implementation Notes (important)

- Never transfer content inline; always use pre-signed object storage URLs to keep event
  payloads small and avoid memory pressure in the relay.
- Consent revocation between workflow start and TRANSFERRING must result in FAILED (not skipped)
  to make revocations auditable and surfaced to the user.
- Treat embedding model mismatch as a hard blocker: the reindex workflow must run on one side
  before sync can succeed. Do not silently re-embed or ignore the mismatch.
- The downlink path requires no user consent but should be surfaced in the local UI so users
  are aware of cloud-pushed improvements to their local library.
- Record `cloud_sync_at` and `cloud_asset_version_id` on the local AssetVersion for
  auditability and idempotency checks on retry.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/adr/ADR-005-privacy-boundary.md`
- `docs/architecture-diagrams/components/L2-sync-agent.md`
- `docs/architecture-diagrams/L1-runtime-topology.md`
- `docs/architecture-diagrams/domains/L2-asset-registry.md`
- `docs/architecture-diagrams/components/L2-event-bus-reliability.md`
- `contracts/events/v0.json`
