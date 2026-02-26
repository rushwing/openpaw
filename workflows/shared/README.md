# Workflows Shared — BaseWorkflow & State Machine

> All OpenPaw workflows inherit from `BaseWorkflow` and use the shared state machine.
> This package provides: state transitions, event logging, retry, cancellation, and policy integration.

---

## BaseWorkflow Contract

Every workflow in `workflows/` must:

1. Inherit from `BaseWorkflow`
2. Declare `WORKFLOW_TYPE: str` class variable
3. Implement `async def run(self, command, context) -> WorkflowResult`
4. Call `await self.policy_engine.get_policy(...)` as the first step
5. Call `await self.transition_to(state)` before each major step
6. Call `await self.log_step(name, payload)` for observable sub-steps
7. Call `await self.emit(event)` for domain events

---

## Terminal States (shared layer — business-neutral)

The shared `BaseWorkflow` only recognises these generic terminal states:

| State | Meaning |
|-------|---------|
| `SUCCEEDED` | Workflow completed successfully |
| `FAILED` | Workflow failed after all retries (or unrecoverable error) |
| `CANCELLED` | Workflow was explicitly cancelled by user or system |

**Each workflow maps its own business states to these generics:**

```python
# RetrieveOrGenerateWorkflow maps COMPLETED_HIT / COMPLETED_NEW → SUCCEEDED
# The business state is stored in WorkflowResult.outcome, not in current_state

class RetrieveOrGenerateWorkflow(BaseWorkflow):
    # Internal business states (workflow-private):
    #   INITIATED → INGESTING → RETRIEVING → GENERATING_SOLUTION
    #   → REGISTERING → INDEXING → SUCCEEDED
    # WorkflowResult.outcome = "hit" | "new"
```

**Do NOT hard-code business terminal states into `workflows/shared/`.**

---

## Workflow Lifecycle

```
create(command, context, idempotency_key)
  → check idempotency (return cached result if already SUCCEEDED)
  → if existing run is RUNNING / INITIATED: return current state + ETA
  → if existing run is FAILED: increment attempt_no, reset to INITIATED (same run_id)
  → persist WorkflowRun row (state=INITIATED, attempt_no=1)
  → run()
      → get_policy()
      → transition_to states...
      → emit domain events
  → persist final state (SUCCEEDED / FAILED / CANCELLED) + result
```

---

## Idempotency + Retry Model

**Unique constraint:** `(workflow_type, idempotency_key)` — one active run per key.

**Retry semantics:**
- When a run reaches `FAILED`, the same run row is reused on retry
- `attempt_no` increments; `current_state` resets to `INITIATED`
- This avoids creating a new row and keeps the same `run_id` stable

```sql
-- Idempotency check on incoming command:
SELECT id, current_state, attempt_no, result
FROM workflow_runs
WHERE workflow_type = $1 AND idempotency_key = $2;

-- Branch:
-- current_state = SUCCEEDED → return cached result (no re-run)
-- current_state IN (INITIATED, INGESTING, ...) → return run_id + current_state (no duplicate)
-- current_state = FAILED → UPDATE attempt_no = attempt_no + 1, current_state = INITIATED
-- no row found → INSERT new run
```

---

## State Machine Rules

- States are stored in `workflow_runs.current_state` (Postgres)
- Transitions are appended to `workflow_step_logs` (append-only, never updated)
- Invalid transitions (not in the workflow's transition table) raise `InvalidTransitionError`
- Each workflow defines its own transition table as a class-level dict

---

## Files in this package (to implement)

```
workflows/shared/
  __init__.py
  base_workflow.py       # BaseWorkflow ABC
  state_machine.py       # Transition engine + validation
  event_log.py           # Append-only step logger (Postgres)
  retry.py               # Exponential backoff + max retries
  context.py             # WorkflowContext dataclass
  result.py              # WorkflowResult dataclass
  exceptions.py          # WorkflowError, InvalidTransitionError, PolicyViolationError
```

---

## WorkflowContext (passed to every workflow)

```python
@dataclass
class WorkflowContext:
    user_id: str
    tenant_id: str
    subscription_tier: str          # "free" | "pro" | "enterprise"
    correlation_id: str             # traces request end-to-end
    idempotency_key: str
    sensitivity_tag: str = "standard"   # "private" | "standard" | "public"
    source: str = "api"             # "api" | "telegram" | "scheduler"
```

## WorkflowResult (returned by every workflow)

```python
@dataclass
class WorkflowResult:
    status: Literal["succeeded", "failed", "cancelled"]
    outcome: str | None = None      # business outcome, e.g. "hit" | "new" | "accepted"
    output: dict | None = None      # workflow-specific output data
    workflow_run_id: str = ""
    attempt_no: int = 1
    cost_usd: float = 0.0
    duration_ms: int = 0
    error_code: str | None = None
    error_detail: str | None = None
```

---

## Postgres Schema

```sql
CREATE TABLE workflow_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_type   TEXT NOT NULL,
    current_state   TEXT NOT NULL DEFAULT 'INITIATED',
    tenant_id       TEXT NOT NULL,
    user_id         UUID,
    correlation_id  UUID NOT NULL,
    idempotency_key TEXT NOT NULL,
    attempt_no      INTEGER NOT NULL DEFAULT 1,
    policy_snapshot JSONB,          -- ExecutionPolicy used (logged for debugging)
    result          JSONB,          -- final WorkflowResult (null until terminal state)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (workflow_type, idempotency_key)      -- one active run per key+type
);

CREATE TABLE workflow_step_logs (
    id              BIGSERIAL PRIMARY KEY,
    workflow_run_id UUID NOT NULL REFERENCES workflow_runs(id),
    workflow_type   TEXT NOT NULL,
    attempt_no      INTEGER NOT NULL,
    step_name       TEXT NOT NULL,
    state_before    TEXT,
    state_after     TEXT,
    payload         JSONB,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON workflow_step_logs (workflow_run_id, attempt_no);
```

---

## Implementation Priority

1. `base_workflow.py` + `state_machine.py` — needed before any workflow can be coded
2. `event_log.py` — needed for observability
3. `retry.py` — needed for production reliability
4. `context.py` + `result.py` + `exceptions.py` — needed for type safety
