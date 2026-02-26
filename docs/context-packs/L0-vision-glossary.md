# OpenPaw — L0 Context Pack: Vision & Glossary

> **Load this pack for every task.** It is the shared vocabulary and context foundation.
> Under 120 lines. Does not contain implementation details.

---

## Product Vision (1 paragraph)

OpenPaw is an Agentic AI platform for educational problem-solving. Users photograph or describe
a math or coding problem; the system either retrieves an existing cached solution (HTML page +
teaching video) or generates a new one using LLMs and OpenClaw skills. The community continuously
improves the asset library through ratings and corrections, earning rewards. An expert marketplace
allows users to post bounties for human expert answers. The platform runs locally on Raspberry Pi
(private assistant) and in Alibaba Cloud K8S (scalable SaaS).

---

## Core User Flows

1. **Solve:** Upload image → retrieve hit → return solution HTML + video *(< 1s on hit)*
2. **Generate:** Upload image → retrieve miss → generate HTML → generate video → index → return
3. **Correct:** Submit HTML patch or replacement video → AI validates → reward if accepted
4. **Rate:** Rate a solution → top rater earns bonus points
5. **Bounty:** Post question with credit escrow → expert answers → accept → credits released

---

## Glossary

| Term | Definition |
|------|-----------|
| **Problem** | A normalized representation of a question (OCR text + image + topic tags) |
| **ProblemSignature** | Deterministic dedup key = hash(normalized_text + phash + sorted_topic_tags) |
| **Asset** | A generated or contributed solution (HTML or video) linked to a Problem |
| **AssetVersion** | One immutable snapshot of an Asset; versioned as v1, v2, v3... |
| **ProvenanceRecord** | Metadata about who/what created an AssetVersion (model, skill, user) |
| **Published version** | The one AssetVersion currently shown to users; exactly one per asset type per Problem |
| **RetrievalHit** | ProblemSignature found in vector/hash index with confidence ≥ threshold |
| **RetrievalMiss** | No match found; generation workflow is triggered |
| **LedgerEntry** | Immutable record of a credit grant or deduction; balance = SUM(entries) |
| **CorrectionProposal** | A user-submitted HTML patch or video replacement awaiting validation |
| **ValidationRun** | AI + optional human review of a CorrectionProposal |
| **Bounty** | A question posted with credit escrow, seeking expert answers |
| **ExecutionPolicy** | Runtime config returned by PolicyEngine: which model, where to run, cost cap |
| **OpenClaw skill** | A Claude Code skill that generates HTML solutions or teaching videos |
| **Tenant** | An isolated deployment (cloud: each org; Pi: always single-tenant `"local"`) |
| **CorrelationId** | UUID that traces a user request end-to-end across all services |
| **WorkflowRun** | One execution instance of a workflow (has state, event log, policy snapshot) |
| **Context Pack** | Minimal documentation loaded by an AI agent for a specific task (saves tokens) |

---

## Architecture Layers (top → bottom)

```
[iOS / Android / Telegram / Web API]
         ↓ Commands
[apps/api_gateway]  ← auth + rate-limit + routing only
         ↓
[platform/policy_engine]  ← decides model/executor/cost
         ↓
[workflows/]  ← state machines for volatile AI chains
     ↕ events ↕
[domains/]   ← DDD-lite for stable business invariants
         ↓
[adapters/]  ← thin wrappers: LLM / Qdrant / OSS / OCR
         ↓
[PostgreSQL] [Qdrant] [Redis] [MinIO/OSS]
```

---

## Critical Invariants (always true, never bypass)

1. `ProblemSignature` is the only dedup key — same problem → same asset, always
2. `ledger_entries` table is INSERT-only (no UPDATE, no DELETE)
3. Every `ledger_entries` row has a unique `idempotency_key` (prevents double-reward)
4. An `AssetVersion` is never deleted, only deprecated
5. Exactly one `AssetVersion` per asset type per Problem has `status = published`
6. Domain code never imports from `adapters/` or `workflows/` (one-way dependency)
7. `ExecutionPolicy` is logged at the start of every workflow run
8. All API endpoints filter by `tenant_id` (multi-tenant isolation)

---

## Key Technology Choices

| Decision | Choice | Why |
|----------|--------|-----|
| Language | Python 3.12+ | AI ecosystem, Raspberry Pi support |
| API | FastAPI async | Performance, OpenAPI auto-generation |
| Queue | Redis Streams | Simple, Pi-compatible, no broker install |
| Vector DB | Qdrant | Excellent Python SDK, Pi Lite version exists |
| Workflow engine | Postgres state machine (custom) | No Temporal dependency; Pi-compatible |
| Package manager | uv | Fast, reproducible |

---

## Next Packs to Load

For deeper work, load one of:
- `docs/context-packs/L1-domain-map.md` — all 5 domain overviews
- `docs/context-packs/domains/asset_registry.md` — Asset/Version/Provenance deep dive
- `docs/context-packs/workflows/retrieve_or_generate.md` — main workflow deep dive
- `docs/agent-teams/assignments.md` — which LLM handles which component
