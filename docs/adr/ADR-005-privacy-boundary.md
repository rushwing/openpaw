# ADR-005: Privacy Boundary, Edge-Cloud Sync, and Embedding Model Consistency

## Status

Accepted — Phase 0

## Context

OpenPaw runs on two topologies:
1. **Raspberry Pi (local):** User's private device, no cloud billing, privacy-first
2. **Alibaba Cloud K8S:** Multi-tenant SaaS, full feature set

This creates three critical design problems that must be resolved before Phase 1:

### Problem A: What data MUST NOT leave the local device?

Without a clear privacy boundary, developers will make ad-hoc decisions about what to
send to the cloud, creating both privacy violations and legal risk.

### Problem B: How does local → cloud asset sync work?

The architecture diagram shows "Secure Sync & Fallback" but there's no spec for when
and how a Pi-generated asset enters the global cloud index.

### Problem C: Embedding model drift between edge and cloud

If the Pi indexes using `text-embedding-3-small` and the cloud uses `bge-m3`, their Qdrant
vector spaces are incompatible. Retrieval results from cross-node searches will be garbage.
This is the most dangerous silent failure mode in the hybrid architecture.

## Decision

### A: Privacy Boundary Rules

#### Data that NEVER leaves a local device (when `privacy_mode=True`):

| Data | Reason |
|------|--------|
| Raw uploaded images | User's personal problem images may contain personal info |
| OCR-extracted text | Derived from private image |
| Media object IDs | Can be used to reconstruct content |
| Normalized text | Derived from private image |

#### Data that CAN leave (opt-in, user consent required):

| Data | Condition |
|------|-----------|
| `ProblemSignature` | Hash only — reveals nothing about content |
| `AssetVersion` (HTML/video) | User explicitly publishes to cloud (see Publish to Cloud action) |
| `topic_tags` | Aggregated, non-identifying |
| Embedding vectors | Only after user consent to publish |

#### Automatic sync (no consent required):

- `workflow.WorkflowStarted/Succeeded/Failed` — anonymized observability (no payload content)
- `identity.*` events — user's own subscription/reputation events
- `rewards_ledger.*` events — user's own ledger events

#### Privacy mode enforcement:

```python
# platform/policy_engine/engine.py
if policy.privacy_mode:
    # Block all outbound calls except:
    # 1. LLM API (text goes to Claude/OpenAI — user is already aware of this)
    # 2. identity/rewards sync (user account events, no problem content)
    assert policy.executor == "local"
    # Raise if any adapter tries to push to cloud object storage
```

### B: Edge-to-Cloud Sync Protocol

#### User-initiated "Publish to Cloud" action

A Pi user can explicitly choose to contribute a locally-generated asset to the global cloud
database. This is an **opt-in action**, not automatic.

```
User clicks "Share to Community" in local app
  → System shows: "This will upload your solution to OpenPaw cloud database"
  → User confirms (consent recorded with user_id + timestamp)
  → sync.AssetSyncRequested event emitted (with user_consent_ref)
  → Cloud sync agent pulls asset from Pi local storage
  → Cloud: creates new cloud AssetVersion, indexes in Qdrant
  → sync.AssetUplinked event emitted back to Pi
  → Pi: shows "Contributed! +10 points"
```

**Consent reference**: `user_consent_ref` in `sync.AssetSyncRequested` must point to a
persisted consent record (`Postgres.publish_consents` table) for audit purposes.

#### Cloud-to-Edge sync (expert corrections)

When a cloud expert corrects a solution that a Pi user solved:
- Cloud emits `asset.AssetVersionPublished` (new corrected version)
- Sync service checks if the Pi has that `problem_signature` in its local index
- If yes: pushes new asset version to Pi via `sync.AssetDownlinked`
- Pi user gets notification: "Your solution was improved by an expert"

#### Anti-echo loop rule

Every event envelope includes `origin_node`. The sync service must:
- NOT re-sync events back to their origin node
- NOT index events in the source's Qdrant if they originated there

### C: Embedding Model Consistency (CRITICAL)

**Rule: The `embedding_model` is a system-wide constant, not a per-tier or per-workflow setting.**

```yaml
# platform/policy_engine/default_policies.yaml
embedding_model_global: text-embedding-3-small   # IMMUTABLE without full re-index
```

**Enforcement:**
1. PolicyEngine always returns the SAME `embedding_model` value for ALL tiers, ALL nodes
2. At startup, every worker checks: `assert local_qdrant_metadata.embedding_model == config.embedding_model_global`
3. If mismatch detected → emit `sync.EmbeddingModelMismatch` alert → halt indexing operations

**Changing the embedding model:**
- Only allowed as a planned migration event with:
  1. New ADR documenting the change and re-index plan
  2. Full re-index of all `asset_versions` (use `admin.ReindexAsset` for each)
  3. Qdrant collection recreation (not in-place update)
  4. Staged rollout: cloud first, then Pi nodes

**Recommended models:**

| Model | Notes |
|-------|-------|
| `text-embedding-3-small` | **Default.** OpenAI, cheap, available everywhere via API, stable |
| `bge-m3` | Open-source, multilingual (good for Chinese math), can run on Pi without API call |

**Phase 0 default:** `text-embedding-3-small`. Switch to `bge-m3` only if privacy-first
Pi deployment becomes primary use case (requires full re-index).

### D: Content Status for Video Assets

When VideoWorkflow is enqueued in the background (after RetrieveOrGenerateWorkflow succeeds),
the `AssetVersion` for video does not yet exist. The system must communicate video availability
clearly to the frontend.

**Protocol:**
1. `RetrieveOrGenerateWorkflow` returns: `{outcome: "new", video_pending: true, ...}`
2. Frontend polls `GET /problems/{signature}/status` (or subscribes via WebSocket)
3. When `VideoWorkflow` completes: emits `asset.AssetVersionCreated` (video, content_status=ready) + `asset.AssetVideoReady`
4. Frontend receives signal and shows video player

The `AssetVersion` domain entity MUST include `content_status: ready | processing | failed`.
"Processing" video versions should not appear in public search results.

## Consequences

**Positive:**
- Privacy boundary is explicit and enforceable (PolicyEngine, not ad-hoc)
- Sync is user-controlled (consent-based, auditable)
- Embedding consistency prevents silent retrieval failures
- `sync.EmbeddingModelMismatch` event provides early detection of drift

**Negative:**
- Pi users must take an explicit action to contribute to global pool (reduces auto-contribution)
- Changing embedding model requires expensive full re-index operation
- Sync agent adds operational complexity (must monitor for sync.EmbeddingModelMismatch)

## Implementation Checklist (Phase 1)

- [ ] `platform/policy_engine/engine.py`: enforce `privacy_mode` → block cloud calls
- [ ] `Postgres.publish_consents` table for consent records
- [ ] Sync agent service in `apps/` (or as a workflow)
- [ ] `platform/policy_engine/default_policies.yaml`: set `embedding_model_global`
- [ ] Worker startup check: `assert embedding_model == config.embedding_model_global`
- [ ] Monitor for `sync.EmbeddingModelMismatch` in observability dashboard

## Related

- [ADR-003](ADR-003-policy-routing.md) — `privacy_mode`, `embedding_model` in ExecutionPolicy
- [ADR-004](ADR-004-outbox-inbox-idempotency.md) — event delivery for sync events
- `contracts/events/v0.json` → `sync.*` events, `asset.AssetVideoReady`
- `platform/policy_engine/` — embedding_model_global config
- `deploy/local-pi/README.md` — Pi deployment constraints
