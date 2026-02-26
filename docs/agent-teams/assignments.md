# OpenPaw — Agent Team Assignments

> How to coordinate multiple AI models for Agentic Coding on this project.
> Follow this to avoid conflicts, wasted tokens, and divergent implementations.

---

## Team Composition

| Agent | Model | Strengths | Primary Role |
|-------|-------|-----------|-------------|
| **Architect** | Claude Code (Sonnet/Opus) | Deep reasoning, cross-file edits, code review | Architecture, ADRs, complex workflow design, PR review |
| **Implementer** | Codex (ChatGPT o3/o4-mini) | Fast file-level coding, scaffolding, tests | Domain models, workflow steps, API endpoints |
| **Consistency Guardian** | Gemini 2.5 Pro | 1M-token context, cross-file analysis | Contract compliance checks, ADR drift detection, L2 context pack generation |
| **Spec Writer** | Kimi K2 | Chinese text, interface specs | PRD refinement, API interface specs, Chinese documentation |

---

## Module Ownership (Phase 0 → Phase 1)

### Architect (Claude Code) owns:
- `docs/adr/` — all ADRs
- `workflows/shared/` — BaseWorkflow, state machine, event log
- `workflows/retrieve_or_generate/` — critical main workflow
- `platform/policy_engine/` — ExecutionPolicy, routing logic
- `contracts/` — event/command schema decisions
- Code reviews across all modules

### Implementer (Codex) owns:
- `domains/identity/` — User, Subscription, CreditWallet models
- `domains/asset_registry/` — Problem, AssetVersion, Provenance models
- `domains/rewards_ledger/` — LedgerAccount, LedgerEntry, balance queries
- `domains/reputation/` — ReputationProfile, scoring
- `workflows/solve_workflow/` — HTML generation steps
- `workflows/video_workflow/` — Video generation steps
- `apps/api_gateway/` — FastAPI routes, auth middleware
- `apps/telegram_bot/` — Telegram handler
- Unit tests for all of the above

### Consistency Guardian (Gemini 2.5 Pro) owns:
- `docs/context-packs/` — generating and maintaining all L1/L2/L3 context packs
- `docs/domain-models/` — entity relationship summaries
- **Cross-file consistency checks after every PR** (see Consistency Check Protocol below)
- Long-context cross-file analysis (e.g., "does this PR break any contracts?")

### Spec Writer (Kimi) owns:
- `docs/runbooks/` — operational runbooks (Chinese + English)
- API interface specifications for mobile team
- Chinese product documentation
- PRD → technical requirements breakdown tasks

---

## Concurrent Development Rules

### Rule 1: Contracts First, Code Second

Before any agent writes implementation code for a module, the contract schemas must be frozen:
- `contracts/events/v0.json` — events for this module are defined
- `contracts/commands/v0.json` — commands for this module are defined

**Architect finalizes contracts → then Implementer codes against them.**

### Rule 2: One Agent, One File, One Session

Never let two agents edit the same file concurrently. If you need another agent's work,
wait for it to complete (or work on non-overlapping files).

**Safe to parallelize:**
- `domains/identity/` (Implementer) + `docs/context-packs/` (Doc Synthesizer)
- `workflows/solve_workflow/` (Implementer) + `docs/adr/` (Architect)

**Never parallelize:**
- Two agents editing `contracts/events/v0.json`
- Two agents editing the same domain's `model.py`

### Rule 3: Context Pack Before Coding

Every agent must load the relevant context packs before starting:
```
L0: docs/context-packs/L0-vision-glossary.md       (always)
L2: docs/context-packs/domains/<target-domain>.md  (for domain work)
L3: docs/context-packs/workflows/<name>.md         (for workflow work)
L4: The specific GitHub issue / task ticket        (for the task)
```

Do NOT load the entire codebase. Do NOT load context packs for unrelated modules.

### Rule 4: Output Format per Agent

| Agent | Typical outputs |
|-------|----------------|
| Architect | ADR `.md` files, `state_machine.md`, `base_workflow.py` patterns, review comments |
| Implementer | `model.py`, `service.py`, `repo.py`, `router.py`, `test_*.py` |
| Consistency Guardian | Updated context packs, consistency check reports, `overview.md`, cross-file analysis |
| Spec Writer | `api-spec.md`, `runbook-zh.md`, Chinese interface documentation |

---

## Consistency Check Protocol (Gemini 2.5 Pro)

Run after every meaningful PR (new domain, new workflow, new event):

**Prompt template to use with Gemini:**

```
Context files to load:
- contracts/events/v0.json
- contracts/commands/v0.json
- docs/adr/ADR-001-ddd-lite-workflow-first.md
- docs/adr/ADR-002-asset-as-sot-ledger.md
- docs/adr/ADR-003-policy-routing.md
- docs/adr/ADR-005-privacy-boundary.md
- [all modified files from the PR]

Check the modified files against these contracts and ADRs:
1. Does any domain code import from adapters/ or workflows/? (ADR-001 violation)
2. Does any code UPDATE or DELETE from ledger_entries or asset_versions? (ADR-002 violation)
3. Does any workflow hardcode a model name instead of using policy.llm_model? (ADR-003 violation)
4. Are all emitted events in contracts/events/v0.json? Are payloads consistent?
5. Does any local-mode code send data to cloud without checking privacy_mode? (ADR-005 violation)
6. Is embedding_model used consistently (same value everywhere)? (ADR-005 violation)
7. Are all ledger credits accompanied by a unique idempotency_key? (ADR-002 violation)

For each violation found: report file, line, ADR reference, and suggested fix.
```

**When to run:**
- After adding a new domain model
- After adding a new workflow step
- After changing contract schemas
- Before Phase milestone reviews

---

## Phase-by-Phase Task Assignment

### Phase 0: Architecture Freeze (current)

| Task | Owner | Deliverable |
|------|-------|------------|
| Write ADR-001, ADR-002, ADR-003 | Architect | `docs/adr/ADR-00*.md` |
| Freeze v0 contracts | Architect | `contracts/events/v0.json`, `contracts/commands/v0.json` |
| Write L0 context pack | Architect | `docs/context-packs/L0-vision-glossary.md` |
| Design RetrieveOrGenerate state machine | Architect | `workflows/retrieve_or_generate/state_machine.md` |
| Write BaseWorkflow skeleton | Architect | `workflows/shared/base_workflow.py` |
| Generate L2 context packs for all domains | Doc Synthesizer | `docs/context-packs/domains/*.md` |
| Spec out mobile API interface | Spec Writer | `docs/api-spec-mobile.md` |

### Phase 1: MVP Spine (RetrieveOrGenerate + SolveWorkflow)

| Task | Owner | Depends on |
|------|-------|-----------|
| `domains/asset_registry/model.py` | Implementer | contracts frozen |
| `domains/rewards_ledger/model.py` | Implementer | contracts frozen |
| `domains/identity/model.py` | Implementer | contracts frozen |
| `adapters/llm/` (Claude + OpenAI) | Implementer | policy engine interface |
| `adapters/qdrant/` | Implementer | retrieval workflow spec |
| `adapters/openclaw/` | Implementer | solve/video workflow spec |
| `workflows/retrieve_or_generate/` | Architect | all adapters interfaces |
| `workflows/solve_workflow/` | Implementer | openclaw adapter |
| `apps/api_gateway/routes/problems.py` | Implementer | commands v0 |
| Integration tests (Postgres + Redis) | Implementer | all of above |

### Phase 2: Video + Feedback (parallel tracks)

| Track A | Track B |
|---------|---------|
| `workflows/video_workflow/` (Implementer) | `workflows/correction_validation/` (Implementer) |
| `adapters/openclaw/video_skill.py` | `domains/reputation/` |
| Video asset versioning | `workflows/reward_settlement/` (Architect) |

### Phase 3: Marketplace + Platform

| Task | Owner |
|------|-------|
| `domains/marketplace/` | Implementer |
| `workflows/bounty_fulfillment/` | Architect |
| `platform/billing/` | Implementer |
| `deploy/local-pi/docker-compose.yml` | Implementer |
| `deploy/k8s-cloud/` Helm charts | Implementer |

---

## Handoff Protocol

When finishing a module, the completing agent must:

1. Update the corresponding context pack (`docs/context-packs/domains/<name>.md`)
2. Add contract validation tests if new events/commands were added
3. Annotate the GitHub issue with: "files modified", "contracts used", "known limitations"
4. Flag any decisions that need ADR documentation (Architect reviews)

---

## Token Budget Guidelines (approximate)

| Task type | Recommended context | Typical tokens |
|-----------|--------------------|-|
| New domain model | L0 + L2 (domain) + task | ~8K |
| New workflow step | L0 + L3 (workflow) + task | ~12K |
| ADR write | L0 + related ADRs + task | ~6K |
| Code review | L0 + changed files + contracts | ~20K |
| Context pack update | L0 + all changed files | ~30K (Gemini) |
