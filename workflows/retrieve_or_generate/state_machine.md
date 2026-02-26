# RetrieveOrGenerateWorkflow — State Machine Specification

> This is the **most critical workflow** in OpenPaw. Every user-facing problem submission
> passes through it. Design it with maximum observability, idempotency, and retry safety.

---

## Purpose

Accept a user-submitted problem (image/text/URL), check if a high-quality solution already
exists (retrieve), and if not, generate a new HTML solution. Register the new asset, index it,
and enqueue video generation asynchronously (if policy allows). Return immediately after
the HTML solution is ready.

---

## States

```
INITIATED
  ↓
INGESTING           ← normalize media, compute hashes, OCR, topic tags
  ↓
RETRIEVING          ← hybrid search (pHash + vector + keyword)
  ↓ (hit)               ↓ (miss)
SUCCEEDED         GENERATING_SOLUTION   ← SolveWorkflow (blocking)
(outcome=hit)       ↓ (solve succeeded)
                  REGISTERING           ← save Problem + AssetVersion to DB
                    ↓ (asset saved)
                  INDEXING              ← embed + upsert to Qdrant
                    ↓ (indexed)
                  SUCCEEDED             ← video enqueued in background (if policy.video_generation != skip)
                  (outcome=new)
```

**Terminal states (maps to BaseWorkflow generics):**
- `SUCCEEDED` (outcome=`hit` or `new`) → `WorkflowResult.status = "succeeded"`
- `FAILED` → `WorkflowResult.status = "failed"`
- `CANCELLED` → `WorkflowResult.status = "cancelled"`

**Video generation is NOT a state in this workflow.**
After `SUCCEEDED (outcome=new)`, video is independently enqueued to `VideoWorkflow`
via the background queue if `policy.video_generation != "skip"`. This prevents a
slow video render from blocking the user response.

---

## State Transition Table

| From | To | Trigger | Guard |
|------|----|---------|-------|
| `INITIATED` | `INGESTING` | workflow started | idempotency check passed |
| `INGESTING` | `RETRIEVING` | `ingestion.MediaNormalized` | problem_signature computed |
| `INGESTING` | `FAILED` | `ingestion.MediaRejected` | — |
| `RETRIEVING` | `SUCCEEDED` | `retrieval.RetrievalHit` | confidence ≥ `policy.retrieval_threshold` |
| `RETRIEVING` | `GENERATING_SOLUTION` | `retrieval.RetrievalMiss` | confidence < threshold |
| `GENERATING_SOLUTION` | `REGISTERING` | SolveWorkflow returned success | HTML content available |
| `GENERATING_SOLUTION` | `FAILED` | SolveWorkflow failed + retries exhausted | OR cost cap exceeded |
| `REGISTERING` | `INDEXING` | `asset.ProblemRegistered` + `asset.AssetVersionCreated` | assets persisted |
| `INDEXING` | `SUCCEEDED` | `retrieval.DocumentIndexed` | — |
| `INDEXING` | `SUCCEEDED` | index timed out | asset still served; index retried in background |
| any non-terminal | `CANCELLED` | cancel command received | user owns this run |

---

## Retrieval Confidence Thresholds (from ExecutionPolicy)

| Method | Default threshold | Notes |
|--------|-------------------|-------|
| Exact pHash match | 1.0 | Same image (JPEG artifact tolerant) |
| Near-duplicate pHash | 0.95 | Hamming distance < 8 |
| Normalized text exact | 0.99 | OCR text after normalization |
| Vector similarity (Qdrant cosine) | `policy.retrieval_threshold` (default 0.85) | Semantic similarity |
| Hybrid re-ranked | `policy.retrieval_threshold - 0.02` | Use when vector alone is uncertain |

---

## Idempotency

- **Idempotency key:** `sha256(problem_signature + user_id + intent)`
- If a run with the same key is `SUCCEEDED`: return cached result immediately (no re-run)
- If a run with the same key is actively running (non-terminal state): return current state + ETA
- If a run with the same key is `FAILED`: increment `attempt_no`, reset to `INITIATED`, re-run same row

---

## Workflow Steps (Python pseudocode)

```python
class RetrieveOrGenerateWorkflow(BaseWorkflow):
    WORKFLOW_TYPE = "retrieve_or_generate"

    TRANSITIONS = {
        "INITIATED":             ["INGESTING", "CANCELLED"],
        "INGESTING":             ["RETRIEVING", "FAILED", "CANCELLED"],
        "RETRIEVING":            ["SUCCEEDED", "GENERATING_SOLUTION", "FAILED", "CANCELLED"],
        "GENERATING_SOLUTION":   ["REGISTERING", "FAILED", "CANCELLED"],
        "REGISTERING":           ["INDEXING", "FAILED"],
        "INDEXING":              ["SUCCEEDED", "FAILED"],
    }
    TERMINAL_STATES = {"SUCCEEDED", "FAILED", "CANCELLED"}

    async def run(self, cmd: SubmitProblem, context: WorkflowContext) -> WorkflowResult:

        # Step 0: Get policy (ALWAYS first — governs all subsequent decisions)
        policy = await self.policy_engine.get_policy(
            workflow_type=self.WORKFLOW_TYPE,
            user_id=context.user_id,
            subscription_tier=context.subscription_tier,
            content_sensitivity=context.sensitivity_tag,
        )
        await self.log_step("policy_applied", {"policy": policy.to_dict()})

        # Step 1: INGESTING
        await self.transition_to("INGESTING")
        media = await self.adapters.ocr_vision.normalize(
            content=cmd.upload_session_id or cmd.text or cmd.url,
            media_type=cmd.media_type,
        )
        if media.is_rejected:
            await self.emit(MediaRejected(...))
            await self.transition_to("FAILED")
            return WorkflowResult(status="failed", error_code=media.rejection_reason)

        problem_sig = ProblemSignature.compute(
            normalized_text=media.normalized_text,
            phash=media.phash,
            topic_tags=media.topic_tags,
        )
        await self.emit(MediaNormalized(...))

        # Step 2: RETRIEVING
        await self.transition_to("RETRIEVING")
        result = await self.adapters.qdrant.hybrid_search(
            problem_signature=problem_sig,
            threshold=policy.retrieval_threshold,   # from ExecutionPolicy
        )

        if result.is_hit:
            await self.emit(RetrievalHit(...))
            await self.transition_to("SUCCEEDED")
            return WorkflowResult(
                status="succeeded",
                outcome="hit",
                output={"asset_version_id": result.asset_version_id},
            )

        await self.emit(RetrievalMiss(...))

        # Step 3: GENERATING_SOLUTION (blocking — waits for HTML)
        await self.transition_to("GENERATING_SOLUTION")
        solve_result = await self.sub_workflow(
            SolveWorkflow,
            problem_signature=problem_sig,
            media=media,
            policy=policy,
        )
        if not solve_result.success:
            await self.transition_to("FAILED")
            return WorkflowResult(status="failed", error_code=solve_result.error_code)

        # Step 4: REGISTERING
        await self.transition_to("REGISTERING")
        problem = await self.domain_services.asset_registry.get_or_create_problem(problem_sig)
        asset_version = await self.domain_services.asset_registry.create_version(
            problem_id=problem.id,
            asset_type="solution_html",
            content_storage_key=solve_result.storage_key,
            provenance=solve_result.provenance,
        )
        await self.emit(AssetVersionCreated(...))

        # Step 5: INDEXING
        await self.transition_to("INDEXING")
        try:
            await self.adapters.qdrant.upsert(
                problem_signature=problem_sig,
                asset_version_id=asset_version.id,
                text=media.normalized_text,
            )
            await self.emit(DocumentIndexed(...))
        except TimeoutError:
            # Index failure is non-fatal: asset still served, index retried in background
            await self.enqueue_background("admin.ReindexAsset", asset_version_id=asset_version.id)
            await self.log_step("index_deferred", {"reason": "timeout"})

        # Step 6: Enqueue video (non-blocking — does NOT block state transition)
        if policy.video_generation != "skip":
            await self.enqueue_background(
                VideoWorkflow,
                problem_signature=problem_sig,
                solution_asset_version_id=asset_version.id,
                video_mode=policy.video_generation,  # "async" or "sync"
            )

        await self.transition_to("SUCCEEDED")
        return WorkflowResult(
            status="succeeded",
            outcome="new",
            output={
                "asset_version_id": asset_version.id,
                "video_pending": policy.video_generation == "async",
            },
        )
```

---

## Event Log (written to `workflow_step_logs`)

Every `transition_to()` and `log_step()` appends:

```sql
INSERT INTO workflow_step_logs
    (workflow_run_id, workflow_type, attempt_no, step_name, state_before, state_after, payload, occurred_at)
VALUES (...)
```

This enables: full replay, debugging, cost attribution, SLA tracking per step.

---

## Retry Strategy

| Step | Retry? | Max | Backoff |
|------|--------|-----|---------|
| INGESTING (OCR) | Yes | `policy.retry_max` | exponential 1s, 4s, 16s |
| RETRIEVING (Qdrant) | Yes | 3 | exponential |
| GENERATING_SOLUTION (LLM) | Yes | `policy.retry_max` | exponential + fallback model |
| REGISTERING (Postgres) | Yes | 5 | exponential |
| INDEXING (Qdrant) | Background retry | 5 | background queue (non-blocking) |

On `GENERATING_SOLUTION` failure after all retries AND cost cap not exceeded:
→ optionally serve a near-miss if top candidate has confidence > 0.70, with flag
`is_approximate: true` in WorkflowResult.

---

## Output

```python
WorkflowResult(
    status="succeeded",           # "succeeded" | "failed" | "cancelled"
    outcome="hit",                # "hit" | "new" (business outcome)
    output={
        "asset_version_id": "...",
        "video_pending": True,    # True if video enqueued in background
        "is_approximate": False,  # True only if serving a near-miss
    },
    workflow_run_id="...",
    attempt_no=1,
    cost_usd=0.12,
    duration_ms=1840,
)
```

---

## Related Files

- `workflows/shared/base_workflow.py` — BaseWorkflow class + transition engine
- `workflows/solve_workflow/` — HTML generation sub-workflow
- `workflows/video_workflow/` — video generation (enqueued by this workflow, runs independently)
- `adapters/qdrant/hybrid_search.py` — retrieval logic
- `platform/policy_engine/` — policy resolution, `retrieval_threshold`, `video_generation`
- `contracts/events/v0.json` → `retrieval.RetrievalHit`, `asset.AssetVersionCreated`, etc.
