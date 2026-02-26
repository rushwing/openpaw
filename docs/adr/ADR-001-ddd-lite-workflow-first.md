# ADR-001: DDD-lite for Stable Domains, Workflow-first for Volatile AI Chains

## Status

Accepted — Phase 0

## Context

OpenPaw combines two fundamentally different types of logic:

1. **Stable business logic** with strict invariants (credit balances, asset ownership, identity,
   escrow). These rules change rarely and must be enforced consistently.

2. **Volatile AI orchestration chains** — which model to call, in what order, with what prompt,
   at what cost — that change frequently as models/prompts/pipelines evolve.

Traditional heavy DDD (Aggregate/Repository/Factory everywhere) works well for (1) but creates
crippling complexity for (2) because AI workflow steps are not domain objects — they are
sequenced external calls with retry, cancellation, and observability requirements.

Pure "everything is a workflow" ignores the invariant enforcement needed for (1) and leads to
business rules leaking into orchestration code, making them impossible to test or audit.

## Decision

### Stable Domains → DDD-lite

Apply DDD patterns **only** to these bounded contexts:

| Domain | Key Aggregates |
|--------|---------------|
| `identity` | User, Subscription, Entitlement, CreditWallet |
| `asset_registry` | Problem, SolutionAsset, VideoAsset, AssetVersion, ProvenanceRecord |
| `rewards_ledger` | LedgerAccount, LedgerEntry |
| `feedback` | Proposal, ValidationRun, Decision, Publication, Rating |
| `reputation` | ReputationProfile, ReputationEvent |
| `marketplace` | Bounty, ExpertProfile, Submission, EscrowAccount |

**DDD-lite rules (what we DO):**

- Aggregate only where you need multi-entity invariant enforcement (e.g., credit deduction
  must not go below zero and must be idempotent)
- Value Objects for rich domain concepts: `ProblemSignature`, `CreditAmount`, `AssetVersionRef`
- Domain Events as the only interface between bounded contexts (no direct cross-domain calls)
- Domain Services for operations that span multiple aggregates within one context

**DDD-lite rules (what we DON'T do):**

- No Repository interface per aggregate (use direct async DB calls in infra layer)
- No Factory classes (use domain constructors or classmethods)
- No Application Services that just delegate to Repositories (collapse the layers)
- No separate Domain/Application/Infrastructure package per domain (one package, three modules: `model.py`, `service.py`, `repo.py`)

### Volatile Chains → Workflow-first

Apply Workflow/State-machine patterns to:

| Workflow | Description |
|----------|-------------|
| `retrieve_or_generate` | Main user-facing pipeline: ingest → retrieve → generate → index |
| `solve_workflow` | LLM-based HTML solution generation |
| `video_workflow` | Teaching video generation via OpenClaw skills |
| `correction_validation` | AI validation + human fallback for user corrections |
| `reward_settlement` | Calculate and settle rewards after accepted contributions |
| `bounty_fulfillment` | Post → match → submit → validate → settle |

**Workflow-first rules:**

- Every workflow is a **state machine** with explicit states and transitions (see `workflows/shared/`)
- Every workflow step appends to an **event log** in Postgres (observable, replayable)
- Steps are **idempotent** — safe to retry with the same input
- Workflows support: `start`, `retry`, `cancel`, `get_state`, `get_history`
- Workflows call **domain services** for business decisions (never bypass domain invariants)
- Workflows call **adapters** for all external calls (LLM, storage, OCR, OpenClaw)
- Workflows never import from other workflow packages (no cross-workflow coupling)

## Consequences

**Positive:**
- Domains stay small, focused, testable with pure unit tests (no I/O)
- Workflows can be iterated fast without domain model churn
- Clear architecture boundary: AI models only appear in `workflows/` and `adapters/`, never in `domains/`
- Observable by design: every workflow step is logged and replayable
- Multiple LLMs can work on non-overlapping modules without conflicts

**Negative:**
- Developers must decide: "is this domain logic or workflow logic?"
- Slight duplication: domain events AND workflow step events (different purposes, different stores)
- Requires discipline not to drift domain rules into workflow code

## Decision Rule for Code Review

> **Domain code:** "This rule would be true regardless of which AI model or workflow engine we use."
>
> **Workflow code:** "This depends on the specific sequence of AI/external calls."

When in doubt → implement as workflow code, call a domain service for the invariant check.

## Related

- [ADR-002](ADR-002-asset-as-sot-ledger.md) — Asset versioning and ledger immutability
- [ADR-003](ADR-003-policy-routing.md) — Policy Engine for model/routing decisions
- `workflows/shared/README.md` — BaseWorkflow implementation guide
