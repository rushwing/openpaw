# OpenPaw Architecture Diagrams — L0 Overall Architecture (ASCII)

> Scope: system-level view (overall platform). This is the top-level map for product/runtime architecture.
> Detail levels (L1/L2/L3) should be split into separate docs to keep token usage low for Agentic Coding.

---

## L0 Diagram (Overall / Runtime)

```text
                                   OpenPaw (L0 Overall)
                        Local-first + Cloud-scale Agentic AI Platform

Clients / Entry Channels
+--------------------------------------------------------------------------------------+
|  iOS App  |  Android App  |  Telegram Bot  |  Web API  |  Pi Local UI / LAN Web     |
+--------------------------------------------------------------------------------------+
                     |                      Commands / Uploads / Queries
                     v

Control Plane (Request entry, auth, policy, routing)
+--------------------------------------------------------------------------------------+
| apps/api_gateway                                                                     |
| - auth / tenant / rate limit / request validation                                    |
| - command dispatch (SubmitProblem, PostBounty, etc.)                                 |
+--------------------------------------------------------------------------------------+
                     | commands
                     v
+----------------------------------+         +-----------------------------------------+
| platform/policy_engine           |<------->| platform/auth / billing / feature_flags |
| - local vs cloud routing         |         | platform/observability / event_bus       |
| - model selection                |         | (outbox relay, inbox dedup, tracing)     |
| - privacy mode / cost caps       |         +-----------------------------------------+
| - embedding model consistency    |
+----------------------------------+
                     |
                     v

Workflow / Orchestration Plane (volatile AI chains; state machines)
+--------------------------------------------------------------------------------------+
| workflows/shared (BaseWorkflow, state machine, retry, event log, idempotency)        |
+--------------------------------------------------------------------------------------+
| retrieve_or_generate | solve_workflow | video_workflow | correction_validation        |
| reward_settlement    | bounty_fulfillment | reindex / sync workflows (future)         |
+--------------------------------------------------------------------------------------+
         | domain commands / domain events                  | adapter calls
         v                                                  v

Stable Business Domains (DDD-lite; invariants, rights, assets, rewards)
+--------------------------------------------------------------------------------------+
| domains/identity        | domains/asset_registry     | domains/rewards_ledger         |
| domains/reputation      | domains/marketplace        | (future) domains/entitlements  |
+--------------------------------------------------------------------------------------+
         | persisted facts + outbox                         | external I/O ports
         v                                                  v

Adapters / Infrastructure Integration
+--------------------------------------------------------------------------------------+
| adapters/openclaw | adapters/llm/* | adapters/ocr_vision | adapters/qdrant            |
| adapters/object_storage | adapters/elastic (planned) | adapters/redis | sync adapter |
+--------------------------------------------------------------------------------------+
         |                                       |                           |
         v                                       v                           v

Data / Infra (Cloud + Local variants)
+----------------------------------+   +-------------------+   +-------------------------+
| PostgreSQL (facts, workflow run, |   | Redis Streams/    |   | Object Storage          |
| outbox/inbox, ledger, assets)    |   | cache/locks       |   | MinIO (Pi) / OSS (ACK)  |
+----------------------------------+   +-------------------+   +-------------------------+
             |                                     |
             v                                     v
   +----------------------------+        +-------------------------------+
   | Qdrant (vector retrieval)  |        | Elastic/OpenSearch (planned)  |
   | Lite on Pi / Cluster cloud |        | keyword + filter + hybrid     |
   +----------------------------+        +-------------------------------+


Hybrid Topology / Deployment Modes
  [Raspberry Pi Local Deployment]
    - Single-tenant ("local"), Docker Compose
    - LOCAL_ONLY / privacy_mode enforcement
    - local cache + local Qdrant + local Postgres + MinIO
    - optional "Publish to Cloud" sync (consent-based)

  [Alibaba Cloud K8S Deployment]
    - Multi-tenant SaaS, ACK + autoscaling workers
    - managed Postgres / Redis / OSS / Qdrant cluster
    - app/API + worker_orchestrator pods + telegram bot integration


Key Architecture Rules (L0)
  1) Domains enforce invariants; workflows orchestrate volatile AI steps.
  2) Asset Registry is source of truth for problem/solution/video versions + provenance.
  3) Rewards Ledger is append-only; balances are derived.
  4) PolicyEngine decides routing/model/cost/privacy before external calls.
  5) Event delivery uses outbox/inbox for reliability (critical business paths).
```

---

## Reading Guide (How to use this L0 diagram)

- `Top -> bottom`: request flow from clients to control plane to workflows to domains/adapters/infra.
- `Left -> right`: mostly grouping by concern, not sequence.
- `Workflows` are the change-heavy layer (Agentic orchestration).
- `Domains` are the stable layer (DDD-lite invariants and facts).
- `PolicyEngine` is intentionally above workflows because routing/model/privacy is cross-cutting.

---

## Best Practice: Diagram Document Organization (recommended)

Use a dedicated folder and split by abstraction level + bounded context. Keep each file small enough
for AI agents to load selectively.

```text
docs/architecture-diagrams/
  README.md                              # index + conventions + legend
  L0-overall-architecture.md             # system-level map (this file)
  L1-runtime-topology.md                 # local vs cloud topology / sync boundaries
  L1-domain-landscape.md                 # domain map + event interactions
  workflows/
    L2-retrieve-or-generate.md           # state machine (ASCII)
    L2-correction-validation.md          # state machine (ASCII)
    L2-bounty-fulfillment.md             # state machine (ASCII)
  domains/
    L2-asset-registry.md                 # entity/component diagram
    L2-rewards-ledger.md                 # ledger flow / component diagram
    L2-marketplace.md                    # domain + escrow flow diagram
    L2-identity.md                       # entitlement/auth component diagram
    L2-reputation.md                     # event-consumer / scoring pipeline
  components/
    L2-policy-engine.md                  # policy resolution component diagram
    L2-event-bus-reliability.md          # outbox/inbox relay flow
```

### Conventions (important for consistency)

- One diagram focus per file: `overall`, `topology`, `domain`, `workflow`, or `component`.
- Include `Scope`, `Primary audience`, and `Related ADRs` at the top of every file.
- Prefer ASCII for reviewability in terminal + LLM contexts; optionally add Mermaid later.
- Put sequence/state behavior in `workflow/` docs, not in domain docs.
- Put invariants and entity relationships in `domains/` docs, not in workflow docs.
- Cross-link to `docs/adr/` and `docs/context-packs/` instead of duplicating long text.

---

## Related

- `docs/context-packs/L0-vision-glossary.md`
- `docs/context-packs/L1-domain-map.md`
- `docs/adr/ADR-001-ddd-lite-workflow-first.md`
- `docs/adr/ADR-002-asset-as-sot-ledger.md`
- `docs/adr/ADR-003-policy-routing.md`
- `docs/adr/ADR-004-outbox-inbox-idempotency.md`
- `docs/adr/ADR-005-privacy-boundary.md`
