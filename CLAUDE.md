# OpenPaw — AI Agent Project Guide

> This file is loaded into every AI agent context working on OpenPaw.
> Kept under 200 lines. Links out to detail files. Do NOT inline details here.

## What is OpenPaw?

Agentic AI platform: users photo-upload math/coding problems → system retrieves cached
solution (HTML + teaching video) or generates new ones via LLM + OpenClaw skills.
Community earns rewards for corrections/ratings. Expert bounty marketplace.

**Dual deployment:** Raspberry Pi (private local assistant) + Alibaba Cloud K8S (SaaS).

---

## Architecture Principles (Non-Negotiable — see ADRs)

| ADR | Decision |
|-----|----------|
| [ADR-001](docs/adr/ADR-001-ddd-lite-workflow-first.md) | DDD-lite for stable domains; Workflow-first for volatile AI chains |
| [ADR-002](docs/adr/ADR-002-asset-as-sot-ledger.md) | Asset is Source of Truth; Rewards Ledger is append-only forever |
| [ADR-003](docs/adr/ADR-003-policy-routing.md) | PolicyEngine controls model selection, cost caps, local/cloud routing |

**Stable → DDD-lite:** `identity` · `asset_registry` · `rewards_ledger` · `feedback` · `reputation` · `marketplace`

**Volatile → Workflow-first:** `retrieve_or_generate` · `solve_workflow` · `video_workflow` ·
`correction_validation` · `reward_settlement` · `bounty_fulfillment`

---

## Tech Stack (Locked — change only via ADR)

| Layer | Technology |
|-------|-----------|
| Language | Python 3.12+ |
| API | FastAPI + async/await |
| Queue | Redis Streams |
| Primary DB | PostgreSQL 16 |
| Vector DB | Qdrant (Lite on Pi, cluster on cloud) |
| Cache / Lock | Redis 7 |
| Object Storage | MinIO (Pi) / Aliyun OSS (cloud) |
| Package mgr | uv |
| Deploy | Docker Compose (Pi) / K8S ACK (cloud) |

---

## Repository Structure

```
apps/                    # Runnable services
  api_gateway/           #   FastAPI entrypoint, auth, rate-limit
  worker_orchestrator/   #   Workflow workers (asyncio + Redis Streams)
  telegram_bot/          #   Telegram interface

domains/                 # DDD-lite domain packages (stable business logic)
  identity/              #   User, Subscription, Entitlement, CreditWallet
  asset_registry/        #   Problem, SolutionAsset, VideoAsset, Version, Provenance
  rewards_ledger/        #   LedgerAccount, LedgerEntry (append-only)
  reputation/            #   ReputationProfile, ReputationEvent
  marketplace/           #   Bounty, ExpertProfile, Submission, Escrow

workflows/               # State-machine workflows (volatile AI chains)
  retrieve_or_generate/  #   CRITICAL: main user-facing workflow
  solve_workflow/        #   LLM-based HTML solution generation
  video_workflow/        #   Teaching video generation
  correction_validation/ #   AI validation of user corrections
  reward_settlement/     #   Calculate and settle rewards
  bounty_fulfillment/    #   End-to-end bounty lifecycle
  shared/                #   BaseWorkflow, state machine helpers, event log

adapters/                # External system integrations (thin wrappers only)
  llm/                   #   Claude / OpenAI / Gemini / Kimi clients
  openclaw/              #   OpenClaw skill runner
  qdrant/                #   Vector DB client
  object_storage/        #   OSS / MinIO
  ocr_vision/            #   OCR and image understanding

platform/                # Cross-cutting infrastructure
  auth/
  policy_engine/         #   CRITICAL: model/routing/cost decisions
  observability/
  event_bus/
  billing/

contracts/               # FROZEN event and command schemas
  events/v0.json
  commands/v0.json

deploy/
  local-pi/              #   Docker Compose + config for Raspberry Pi
  k8s-cloud/             #   Helm charts / K8S manifests

docs/
  adr/                   #   Architecture Decision Records
  context-packs/         #   Token-efficient context per component
  agent-teams/           #   LLM assignment and coordination guide
  domain-models/         #   Entity diagrams and invariants
  runbooks/              #   Ops procedures
```

---

## Context Pack Protocol (Token Efficiency — Critical)

Load context packs, not entire files. Layers:

| Level | File | When to load |
|-------|------|-------------|
| L0 | `docs/context-packs/L0-vision-glossary.md` | Always (every task) |
| L1 | `docs/context-packs/L1-domain-map.md` | Cross-domain work |
| L2 | `docs/context-packs/domains/<name>.md` | Single domain task |
| L3 | `docs/context-packs/workflows/<name>.md` | Workflow task |
| L4 | Task ticket (GitHub issue) | Specific implementation |

**Rule: Only load L0 + one L2/L3 + the task ticket. Never load the full codebase.**

---

## Contracts Are Frozen

`contracts/events/v0.json` and `contracts/commands/v0.json` define all inter-component
communication. **Do NOT modify** without a new ADR and version bump (v1, v2...).
All new code must validate against these schemas.

---

## Agent Team Assignments

See `docs/agent-teams/assignments.md`. Quick reference:

| Responsibility | Agent |
|---------------|-------|
| Architecture, ADRs, cross-domain design, code review | Claude Code |
| File implementation, tests, scaffolding | Codex (ChatGPT) |
| Long-context integration, ADR summaries, doc synthesis | Gemini 2.5 Pro |
| PRD refinement, Chinese docs, interface specs | Kimi |

**Rule: One agent per file per session. Freeze contracts before parallel coding.**

---

## Forbidden Patterns

- ❌ LLM/adapter imports in `domains/` code (domains must not know about AI)
- ❌ Mutable `balance` field in rewards_ledger tables (append-only only!)
- ❌ Hardcoded model names in workflow code (use `PolicyEngine.get_policy()`)
- ❌ Business rules in `apps/api_gateway/` handlers (gateway = routing + auth only)
- ❌ `SELECT *` without `tenant_id` filter in multi-tenant code paths
- ❌ Full DDD boilerplate (Repository/Factory/Aggregate) in `workflows/`

---

## Testing Rules

- **Domains:** pure unit tests, zero I/O, no mocks of domain objects
- **Workflows:** integration tests with real Postgres + Redis (testcontainers-python)
- **Contracts:** auto-generated schema validation tests from `contracts/*.json`
- **API:** OpenAPI contract tests

## Links

- [`features.md`](features.md) — full product requirements
- [`OpenPaw-Architecture.png`](OpenPaw-Architecture.png) — system diagram
- [`docs/adr/`](docs/adr/) — all architecture decisions
- [`docs/context-packs/`](docs/context-packs/) — context packs per component
- [`contracts/`](contracts/) — frozen event/command schemas
