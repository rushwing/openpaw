# OpenPaw Architecture Diagrams — L2 Sync Agent (Edge/Cloud Relay + Anti-Echo Loop) (ASCII)

> Scope: component-level design of the sync agent running on both Pi (edge) and Cloud nodes.
> Focus: bidirectional asset relay, origin_node anti-echo enforcement, consent gating,
> and embedding model mismatch detection.

---

## Diagram A — Sync Agent Component Model (Internals + Node Roles)

```text
        OpenPaw L2 — Sync Agent (Component Model: Edge/Cloud Relay)

  Purpose:
    Relay asset events and content bidirectionally between Pi (edge) and Cloud nodes,
    enforcing origin_node dedup (anti-echo), consent gating, and embedding model consistency.

  Running on BOTH nodes (one instance per deployment)
  ---------------------------------------------------

  +--------------------------------------------------------------------------+
  | SyncAgent                                                                |
  |--------------------------------------------------------------------------|
  |                                                                          |
  |  +---------------------------+    +--------------------------------+     |
  |  | Outbox Listener           |    | Inbound Relay Receiver         |     |
  |  | - polls local outbox      |    | - HTTP/gRPC endpoint           |     |
  |  | - filters events to relay |    | - authenticates remote node    |     |
  |  | - builds relay payload    |    | - writes to local inbox        |     |
  |  +---------------------------+    +--------------------------------+     |
  |             |                                    |                       |
  |             v                                    v                       |
  |  +---------------------------+    +--------------------------------+     |
  |  | Origin Node Filter        |    | Inbox Consumer                 |     |
  |  | SKIP if                   |    | - dedup UNIQUE(event_id,       |     |
  |  |   event.origin_node ==    |    |   handler_name)                |     |
  |  |   local_node_id           |    | - dispatch to local handlers   |     |
  |  +---------------------------+    +--------------------------------+     |
  |             |                                    |                       |
  |             v                                    v                       |
  |  +---------------------------+    +--------------------------------+     |
  |  | Consent Gate (uplink)     |    | Asset Importer (downlink)      |     |
  |  | - check publish_consents  |    | - write AssetVersion to local  |     |
  |  | - block if privacy_mode   |    |   asset_registry               |     |
  |  |   = true                  |    | - preserve ProvenanceRecord    |     |
  |  +---------------------------+    | - emit local AssetVersion...   |     |
  |             |                     +--------------------------------+     |
  |             v                                                            |
  |  +---------------------------+                                          |
  |  | Embedding Model Check     |                                          |
  |  | compare local             |                                          |
  |  | embedding_model_global    |                                          |
  |  | vs remote reported value  |                                          |
  |  +---------------------------+                                          |
  |       |               |                                                 |
  |  mismatch           match                                               |
  |       v               v                                                 |
  |  emit sync.Embedding  proceed to Transfer Client                        |
  |  ModelMismatch                                                          |
  |  (halt uplink)                                                          |
  |       |               |                                                 |
  |       v               v                                                 |
  |  +-----------------------------------------------------------+          |
  |  | Transfer Client                                           |          |
  |  | - POST asset metadata + pre-signed content_ref to remote |          |
  |  | - retry transient failures                                |          |
  |  | - receive acknowledgement (sync run_id)                   |          |
  |  +-----------------------------------------------------------+          |
  +--------------------------------------------------------------------------+


  Node-Specific Roles (same component, different active paths)
  ------------------------------------------------------------

   Pi (edge node)                        Cloud (ACK node)
   +---------------------------------+   +----------------------------------+
   | Uplink role (primary)           |   | Receive + Index role (primary)   |
   | - initiates sync on user        |   | - indexes asset into Qdrant      |
   |   consent                       |   | - adds to cloud asset_registry   |
   | - consent + embedding pre-check |   | - emits sync.AssetUplinked       |
   |   before transfer               |   |   as confirmation                |
   |                                 |   |                                  |
   | Downlink role (secondary)       |   | Downlink role (secondary)        |
   | - receives improved versions    |   | - detects Pi-origin assets with  |
   |   from cloud experts            |   |   new published version on cloud |
   | - imports into local registry   |   | - emits sync.AssetDownlinked     |
   |   via asset importer            |   |   to originating Pi node         |
   +---------------------------------+   +----------------------------------+
```

---

## Diagram B — Uplink, Downlink, Anti-Echo, and Mismatch Flows

```text
   OpenPaw L2 — Sync Agent (Bidirectional Event Flows + Anti-Echo + Mismatch)


  1) Anti-Echo Loop Protection (origin_node filter)
  -------------------------------------------------

   Every event envelope carries:
     origin_node: "cloud" | "pi-node-abc123" | ...

   SyncAgent rule on BOTH nodes:
   +-------------------------------------------------------------+
   | For every received sync event:                              |
   |   if event.origin_node == local_node_id  ->  SKIP (no-op)  |
   |   if event.origin_node != local_node_id  ->  process       |
   +-------------------------------------------------------------+

   Example: Pi emits sync.AssetSyncRequested (origin_node=pi-abc)
     -> Cloud receives, origin_node != cloud  -> process ✓
     -> Cloud emits sync.AssetUplinked        (origin_node=cloud)
     -> Pi receives,   origin_node != pi-abc  -> process ✓
     -> Pi does NOT re-relay back to Cloud    (no echo)


  2) Uplink Flow (Pi → Cloud)
  ---------------------------

   User grants publish consent on Pi
         |
         v
   +------------------------------+
   | publish_consents INSERT      |
   | (user_id, asset_version_id,  |
   |  consent_ref, consented_at)  |
   +------------------------------+
         |
         | triggers sync.AssetSyncRequested
         | (origin_node=pi-abc123)
         v
   +------------------------------+
   | Pi SyncAgent                 |
   | 1. origin filter: skip self? |  <- no (local emit, process it)
   | 2. consent gate: verified    |
   | 3. embedding model: match?   |
   +------------------------------+
         |
         | POST asset metadata + content_ref to Cloud relay endpoint
         v
   +------------------------------+
   | Cloud SyncAgent              |
   | 4. inbox dedup               |
   | 5. asset importer            |
   |    -> cloud asset_registry   |
   |    -> Qdrant index           |
   +------------------------------+
         |
         | emit sync.AssetUplinked (origin_node=cloud)
         v
   Pi SyncAgent receives (origin_node=cloud != pi-abc -> process)
   Pi marks asset as cloud-synced


  3) Downlink Flow (Cloud → Pi, expert correction push)
  -----------------------------------------------------

   Expert on Cloud submits + accepts correction for a Pi-origin asset
         |
         v
   feedback.CorrectionAccepted
   asset.AssetVersionPublished (cloud, asset.origin_node=pi-abc123)
         |
         | Cloud SyncAgent detects: origin_node of asset == a known Pi node
         v
   emit sync.AssetDownlinked
   (origin_node=cloud,
    target_node=pi-abc123,
    asset_version_id=...,
    content_ref=...)
         |
         | Pi SyncAgent receives (origin_node=cloud != pi-abc -> process)
         v
   +------------------------------+
   | Pi SyncAgent                 |
   | - inbox dedup                |
   | - asset importer             |
   |   create local AssetVersion  |
   |   provenance=cloud_sync      |
   +------------------------------+
         |
         v
   Pi asset_registry updated with expert-improved version


  4) Embedding Model Mismatch Detection
  --------------------------------------

   During uplink pre-flight (Pi SyncAgent):
         |
         | compare local embedding_model_global
         |         vs Cloud-reported embedding_model_global
         v
   +------------------------------+
   | match?                       |
   +------------------------------+
      | yes                   | no
      v                       v
   continue uplink        emit sync.EmbeddingModelMismatch
                          (origin_node=pi-abc,
                           local_model=text-embedding-v2,
                           remote_model=text-embedding-3-small)
                          HALT uplink
                          await admin reindex resolution

   During downlink receipt (Cloud SyncAgent):
         |
         | Pi asset arrives with embedding_model=X
         | Cloud uses embedding_model=Y
         v
   emit sync.EmbeddingModelMismatch
   quarantine (do not index into Qdrant)
   alert + await admin resolution
```

---

## Step-to-Domain / Adapter Mapping

- Origin node filter → event envelope field (`platform/event_bus`)
- Consent gate → `publish_consents` table (`domains/identity` or `domains/asset_registry`)
- Embedding model check → `platform/policy_engine` (`embedding_model_global` constant)
- Asset importer → `domains/asset_registry`
- Transfer client → `adapters/sync_relay` (HTTP/gRPC)
- Outbox/inbox dedup → `docs/adr/ADR-004-outbox-inbox-idempotency.md`

---

## Key Events

- `sync.AssetSyncRequested` — uplink request triggered by user consent action on Pi
- `sync.AssetUplinked` — Cloud confirmation that asset was received and indexed
- `sync.AssetDownlinked` — Cloud pushing an expert-improved version to the Pi origin node
- `sync.EmbeddingModelMismatch` — embedding model drift detected; indexing halted until resolved

---

## Implementation Notes (important)

- `origin_node` in every event envelope is the sole anti-echo mechanism; never relay an event
  whose `origin_node` matches the local node ID.
- Consent is per-asset and must be re-verified at relay time, not only at trigger time
  (user may revoke consent before the relay completes).
- `sync.EmbeddingModelMismatch` is a blocking condition — do not silently re-embed with a
  different model; requires explicit admin intervention and a reindex workflow run.
- Content transfer must use pre-signed object storage URLs, not inline payloads in the event.
- SyncAgent is idempotent on both sides: duplicate transfer → inbox dedup prevents double-import.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/adr/ADR-005-privacy-boundary.md`
- `docs/adr/ADR-004-outbox-inbox-idempotency.md`
- `docs/architecture-diagrams/L1-runtime-topology.md`
- `docs/architecture-diagrams/components/L2-event-bus-reliability.md`
- `docs/architecture-diagrams/workflows/L2-sync-publish-flow.md`
- `contracts/events/v0.json`
