# OpenPaw Architecture Diagrams — L2 Video Workflow (Async Video Generation Orchestration) (ASCII)

> Scope: workflow-level design of `video_workflow`.
> Focus: asynchronous video generation orchestration, asset content status transitions, retries, and non-blocking integration with `retrieve_or_generate`.

---

## Diagram A — Main State Machine (Async Video Generation Workflow)

```text
           OpenPaw L2 — VideoWorkflow (Async Video Generation State Machine)

  Purpose:
    Generate a teaching video asynchronously after an HTML solution is ready, without blocking the
    user-facing RetrieveOrGenerate workflow.


                                   +----------------------+
                                   |      INITIATED       |
                                   +----------------------+
                                             |
                                             | background job dequeued
                                             v
                                   +----------------------+
                                   |   LOADING_CONTEXT     |
                                   | load problem +        |
                                   | solution asset + policy|
                                   +----------------------+
                                      |               |
                     missing input / invalid refs      | context loaded
                     (solution not found, forbidden)   |
                                      v               v
                                 +-------------+  +----------------------+
                                 |   FAILED    |  |   PREPARING_VIDEO    |
                                 +-------------+  | script/storyboard/    |
                                                  | render plan            |
                                                  +----------------------+
                                                     |              |
                              prep failed / invalid output            | prep success
                                                     v              v
                                              +-------------+  +----------------------+
                                              |   FAILED    |  |   REGISTERING_ASSET   |
                                              +-------------+  | create video asset     |
                                                               | content_status=processing
                                                               +----------------------+
                                                                          |
                                                                          | asset version created
                                                                          | emit asset.AssetVersionCreated
                                                                          v
                                                               +----------------------+
                                                               |    RENDERING_VIDEO    |
                                                               | OpenClaw skill /      |
                                                               | model / media render  |
                                                               +----------------------+
                                                                  |                |
                                       retries exhausted / fatal    |                | render success
                                       (generation.JobFailed)       |                |
                                                                  v                v
                                                           +----------------+   +----------------------+
                                                           | FAILURE_MARKING |   |   PERSIST_OUTPUT      |
                                                           | mark content    |   | upload mp4/captions   |
                                                           | status=failed   |   | thumbnails metadata    |
                                                           +----------------+   +----------------------+
                                                                  |                        |
                                                                  | emit AssetVersion...   | persist success
                                                                  | (failed optional)      |
                                                                  v                        v
                                                           +-------------+         +----------------------+
                                                           |   FAILED    |         |   FINALIZING_READY    |
                                                           +-------------+         | content_status=ready  |
                                                                                   | emit AssetVideoReady  |
                                                                                   +----------------------+
                                                                                              |
                                                                                              | finalize success
                                                                                              v
                                                                                   +----------------------+
                                                                                   |      SUCCEEDED        |
                                                                                   | outcome=video_ready   |
                                                                                   +----------------------+


  Terminal states:
    - SUCCEEDED (outcome=video_ready | already_ready | skipped)
    - FAILED
    - CANCELLED (optional, before irreversible render/persist steps)
```

---

## Diagram B — Async Branches, Asset Status Updates, Idempotency, and Retry Paths

```text
     OpenPaw L2 — VideoWorkflow (Async Integration + Side Paths)

  1) Entry Triggers (how VideoWorkflow starts)
  -------------------------------------------

   A) RetrieveOrGenerateWorkflow success (outcome=new)
      -> enqueue VideoWorkflow (policy.video_generation = async)

   B) Manual/admin re-run (future)
      -> generation.RetryJob / admin trigger

   C) Correction accepted / new published HTML (future policy)
      -> enqueue VideoWorkflow to regenerate improved teaching video


  2) Asset Registry Integration (content_status lifecycle)
  --------------------------------------------------------

   REGISTERING_ASSET step:
      |
      +--> asset_registry.create_version(
              asset_type="video",
              content_status="processing",
              provenance=ai_generation
          )
      |
      +--> emit asset.AssetVersionCreated(content_status=processing)

   RENDERING succeeds:
      |
      +--> persist media output
      +--> asset_registry.update_content_status(..., "ready")
      +--> emit asset.AssetVideoReady
      +--> (optional) asset.AssetVersionPublished if policy auto-publishes video

   RENDERING fails (after retries exhausted):
      |
      +--> asset_registry.update_content_status(..., "failed")
      +--> keep version row for audit / retry


  3) Idempotency / Duplicate Enqueue Handling
  -------------------------------------------

   idempotency dimensions (recommended):
   - problem_signature
   - solution_asset_version_id
   - video_style / language
   - prompt_version / render_profile (if relevant)

   duplicate enqueue scenarios:
   - same video already ready -> short-circuit outcome=already_ready
   - same video processing run active -> return existing run_id / state
   - previous failed run -> retry same workflow row (attempt_no++)


  4) Retry / Fallback Strategy (async-friendly)
  ---------------------------------------------

   PREPARING_VIDEO (LLM/script generation):
    - retry with fallback model/provider via PolicyEngine

   RENDERING_VIDEO (OpenClaw skill/media pipeline):
    - retry transient failures
    - fail fast on invalid inputs / unsupported media format

   PERSIST_OUTPUT (object storage):
    - retry upload timeouts
    - if persist uncertain, verify by storage key existence before re-upload

   Final failure behavior:
    - mark content_status=failed
    - emit workflow.WorkflowFailed / generation.JobFailed
    - allow later RetryJob


  5) UX / Consumer Effects (non-blocking user experience)
  -------------------------------------------------------

   RetrieveOrGenerate returns immediately:
     output.video_pending = true

   Frontend / bot polls status (or subscribes):
     - sees video AssetVersion content_status=processing
     - later receives asset.AssetVideoReady
     - updates UI to show video player


  6) Optional Branch: Skip Video Generation
  -----------------------------------------

   policy.video_generation = "skip"
      -> workflow may short-circuit:
         outcome=skipped (SUCCEEDED)
         no video asset version created
```

---

## Step-to-Domain / Adapter Mapping (quick reference)

- `LOADING_CONTEXT` -> `domains/asset_registry` + policy context
- `PREPARING_VIDEO` -> LLM/OpenClaw planning adapters
- `REGISTERING_ASSET` -> `domains/asset_registry` (create video version in processing state)
- `RENDERING_VIDEO` -> `adapters/openclaw` / media render adapters
- `PERSIST_OUTPUT` -> `adapters/object_storage`
- `FINALIZING_READY` -> `domains/asset_registry` (content status + readiness events)

---

## Key Events (video workflow and downstream signals)

- `generation.JobCreated` / `generation.JobSucceeded` / `generation.JobFailed` (if modeled as jobs)
- `asset.AssetVersionCreated` (`asset_type=video`, `content_status=processing`)
- `asset.AssetVideoReady` (video content became available)
- `asset.AssetVersionPublished` (optional auto-publish policy)
- workflow step logs for retries, deferred failures, and final outcome

---

## Implementation Notes (important)

- Video generation should stay decoupled from the main retrieve/generate response path for latency.
- Create the video `AssetVersion` early with `content_status=processing` for observability and UX polling.
- Persist output before marking `ready`; avoid `ready` status if object storage write is uncertain.
- Keep retries idempotent with stable output keys or existence checks to prevent duplicate blobs.
- Treat `already_ready` as a valid success outcome for duplicate/replayed requests.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/architecture-diagrams/workflows/L2-retrieve-or-generate.md`
- `docs/architecture-diagrams/domains/L2-asset-registry.md`
- `docs/architecture-diagrams/components/L2-policy-engine.md`
- `workflows/retrieve_or_generate/state_machine.md`
- `contracts/events/v0.json`
