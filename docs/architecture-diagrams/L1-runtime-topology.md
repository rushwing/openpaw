# OpenPaw Architecture Diagrams — L1 Runtime Topology (ASCII)

> Scope: deployment topology and trust/sync boundaries between Raspberry Pi local deployment and Alibaba Cloud K8S cloud deployment.
> Focus: privacy boundary, routing boundary, sync boundary, and shared consistency constraints.

---

## L1 Diagram (Runtime Topology / Local-Cloud-Sync Boundaries)

```text
                        OpenPaw L1 — Runtime Topology (Local / Cloud / Sync Boundaries)

                                         Internet / WAN
=================================================================================================

 [User Devices / Entry Points]
 +---------------------------------------------------------------------------------------------+
 |  iOS App  |  Android App  |  Telegram Bot  |  Browser/Web API  |  Pi LAN UI / Local Browser |
 +---------------------------------------------------------------------------------------------+
          |                      |                                 |
          |                      |                                 |
          |                      +------------ cloud path ---------+---------------------------+
          |                                                                                (LAN)
          +-------------------------------------------- local path (Pi) ----------------------+


 +=======================================================================================================+
 | TRUST ZONE A: USER HOME / RASPBERRY PI (single-tenant, privacy-first)                                |
 |-------------------------------------------------------------------------------------------------------|
 | [Pi Local UI / API]                                                                                   |
 |   - local app / local API gateway                                                                     |
 |   - auth (single-user or household)                                                                   |
 |   - local command dispatch                                                                            |
 |                                                                                                       |
 | [Policy Engine - Local Mode]                                                                          |
 |   - LOCAL_ONLY optional                                                                               |
 |   - privacy_mode enforcement                                                                          |
 |   - local/cloud routing decision                                                                      |
 |   - embedding_model_global check                                                                      |
 |                                                                                                       |
 | [Workflow Workers - Local]                                                                            |
 |   - retrieve_or_generate                                                                              |
 |   - solve_workflow / video_workflow                                                                   |
 |   - optional local sync worker                                                                        |
 |                                                                                                       |
 | [Local Domains + Data]                                                                                |
 |   - asset_registry / rewards_ledger / identity / reputation / marketplace (subset as enabled)       |
 |   - Postgres (local facts + workflow_runs + outbox/inbox)                                            |
 |   - Redis (streams/cache/locks)                                                                       |
 |   - Qdrant Lite (local vector index)                                                                  |
 |   - MinIO / local storage (images/html/video)                                                         |
 |                                                                                                       |
 | [Outbound APIs]                                                                                       |
 |   - LLM providers (Claude/OpenAI/etc.)                                                                |
 |   - optional cloud sync endpoint (only allowed by policy + consent)                                   |
 +=======================================================================================================+
                |                 ^
                | consent-based    | expert updates / sync ack / metadata sync
                | publish-to-cloud |
                v                 |

                           ======== SECURE SYNC BOUNDARY ========
                           Rules:
                           - opt-in "Publish to Cloud" for assets
                           - no raw image/OCR text leaves Pi when privacy_mode=true
                           - include origin_node to prevent echo loops
                           - embedding_model_global must match on both sides
                           ======================================

                ^                 |
                | cloud-to-edge    | edge-to-cloud
                | downlink         | uplink
                |                  v
 +=======================================================================================================+
 | TRUST ZONE B: ALIBABA CLOUD ACK / K8S (multi-tenant SaaS)                                             |
 |-------------------------------------------------------------------------------------------------------|
 | [Ingress / API Gateway]                                                                               |
 |   - public API, mobile app backend, Telegram webhook handlers                                         |
 |   - auth, tenant isolation, rate limit                                                                |
 |                                                                                                       |
 | [Policy Engine - Cloud Mode]                                                                          |
 |   - tier-based model routing / cost caps                                                              |
 |   - provider fallback / availability / circuit breaker                                                |
 |   - privacy-aware routing (respect local-only requests)                                               |
 |   - embedding_model_global source of truth                                                            |
 |                                                                                                       |
 | [Worker Orchestrator Pods (autoscaling)]                                                              |
 |   - retrieve_or_generate / correction_validation / reward_settlement                                  |
 |   - bounty_fulfillment / reindex / sync workers                                                       |
 |                                                                                                       |
 | [Cloud Domains + Platform]                                                                            |
 |   - identity / asset_registry / rewards_ledger / reputation / marketplace                             |
 |   - platform/event_bus (outbox relay + inbox dedup)                                                   |
 |   - observability / billing / feature flags                                                           |
 |                                                                                                       |
 | [Managed Data Services]                                                                               |
 |   - ApsaraDB PostgreSQL                                                                               |
 |   - Redis (ApsaraCache)                                                                               |
 |   - Qdrant Cluster                                                                                    |
 |   - OSS (object storage)                                                                              |
 |   - Elastic/OpenSearch (planned)                                                                      |
 +=======================================================================================================+


 Routing / Privacy / Sync Semantics (L1)
 ---------------------------------------
 1) Local-first path is possible: Pi handles request end-to-end in home trust zone.
 2) Cloud path serves SaaS clients and can also accelerate Pi users when allowed.
 3) privacy_mode=true blocks cloud content sync for raw media and derived text.
 4) Publish-to-cloud is explicit user action (consent recorded).
 5) Cloud-to-edge sync can deliver improved published asset versions back to Pi.
 6) embedding_model_global must remain consistent across Pi + cloud indexes.
```

---

## Why this diagram type (Topology / Boundary Map)

- L1 runtime topology is best represented as a `trust-boundary + deployment-topology` diagram.
- It complements `L1-domain-landscape.md` (ownership/events) by showing `where` components run.
- It clarifies privacy and sync constraints before implementing sync workers and deployment manifests.

---

## What belongs in L2 after this

- `components/L2-policy-engine.md`: policy resolution inside one deployment mode
- `components/L2-event-bus-reliability.md`: outbox/inbox relay mechanics
- `workflows/L2-retrieve-or-generate.md`: state machine and local-vs-cloud execution branching
- `workflows/L2-sync-publish-flow.md` (future): consent, uplink, downlink, anti-echo loop

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/architecture-diagrams/L0-overall-architecture.md`
- `docs/architecture-diagrams/L1-domain-landscape.md`
- `docs/adr/ADR-003-policy-routing.md`
- `docs/adr/ADR-004-outbox-inbox-idempotency.md`
- `docs/adr/ADR-005-privacy-boundary.md`
- `deploy/local-pi/README.md`
- `deploy/k8s-cloud/README.md`
