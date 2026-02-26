# OpenPaw Architecture Diagrams — L2 RetrieveOrGenerate Workflow (State Machine + Branches) (ASCII)

> Scope: workflow-level design of `retrieve_or_generate`.
> Focus: main state machine, hit/miss branches, async video enqueue branch, idempotency/retry entry behavior.

---

## Diagram A — Main State Machine (Workflow Runtime States)

```text
          OpenPaw L2 — RetrieveOrGenerate (Main State Machine)

  Purpose:
    User submits a problem -> retrieve existing asset if possible -> otherwise generate HTML,
    register asset, index it, and enqueue video generation asynchronously.


                                    +----------------------+
                                    |      INITIATED       |
                                    +----------------------+
                                              |
                                              | workflow start
                                              v
                                    +----------------------+
                                    |      INGESTING       |
                                    | OCR / normalize /    |
                                    | phash / topic tags   |
                                    +----------------------+
                                      |                 |
                 MediaRejected         |                 | MediaNormalized + problem_signature
                   (fatal)             |                 |
                                      v                 v
                               +-------------+   +----------------------+
                               |   FAILED    |   |     RETRIEVING       |
                               +-------------+   | hybrid search        |
                                                 | pHash + vector + kw  |
                                                 +----------------------+
                                                     |             |
                                   RetrievalHit       |             | RetrievalMiss
                                   (>= threshold)     |             | (< threshold)
                                                     v             v
                                            +----------------+  +----------------------+
                                            |   SUCCEEDED    |  | GENERATING_SOLUTION  |
                                            |  outcome=hit   |  | SolveWorkflow (HTML) |
                                            +----------------+  +----------------------+
                                                                      |             |
                                          solve failed / retries exhausted            | solve success
                                          or cost cap exceeded                        |
                                                                      v             v
                                                               +-------------+  +----------------------+
                                                               |   FAILED    |  |     REGISTERING      |
                                                               +-------------+  | create Problem +     |
                                                                                 | AssetVersion + prov  |
                                                                                 +----------------------+
                                                                                          |
                                                                                          | persisted
                                                                                          v
                                                                                 +----------------------+
                                                                                 |       INDEXING        |
                                                                                 | embed + Qdrant upsert |
                                                                                 +----------------------+
                                                                                    |               |
                                                                  indexed success    |               | index timeout
                                                                  or non-fatal        |               | (defer reindex)
                                                                  defer               v               v
                                                                                 +----------------------+
                                                                                 |      SUCCEEDED        |
                                                                                 |      outcome=new      |
                                                                                 +----------------------+


  Terminal states:
    - SUCCEEDED (business outcome = hit | new)
    - FAILED
    - CANCELLED (can be reached from any non-terminal state)
```

---

## Diagram B — Execution Branches (Idempotency / Async Video / Failure Paths)

```text
      OpenPaw L2 — RetrieveOrGenerate (Execution Branches + Side Paths)

  1) Idempotency Entry Gate
  -------------------------

   Incoming command: ingestion.SubmitProblem
      |
      | idempotency_key = sha256(problem_signature + user_id + intent)
      v
   +------------------------------------+
   | workflow_runs lookup               |
   | (workflow_type, idempotency_key)   |
   +------------------------------------+
      | no row            | existing running            | existing SUCCEEDED         | existing FAILED
      |                   | (INITIATED/INGESTING/...)   |                           |
      v                   v                             v                           v
   start new run      return run_id + state + ETA   return cached result       retry same row:
                                                                         attempt_no += 1, reset INITIATED


  2) Core Business Branching (Retrieve hit vs Generate new)
  ---------------------------------------------------------

   INGESTING -> RETRIEVING
                  |
                  +--> [Hit path]
                  |      - emit retrieval.RetrievalHit
                  |      - SUCCEEDED(outcome=hit)
                  |      - return published asset_version_id
                  |
                  +--> [Miss path]
                         - emit retrieval.RetrievalMiss
                         - GENERATING_SOLUTION (blocking SolveWorkflow)
                         - REGISTERING (asset_registry domain)
                         - INDEXING (Qdrant; timeout is non-fatal)
                         - SUCCEEDED(outcome=new)


  3) Video Branch (decoupled, non-blocking)
  -----------------------------------------

   After SUCCEEDED(outcome=new) decision is ready:
      |
      | policy.video_generation
      v
   +----------------------+--------------------------+----------------------+
   | skip                 | async                     | sync (optional mode) |
   | no video job         | enqueue VideoWorkflow     | enqueue/wait policy  |
   | video_pending=false  | return immediately        | (rare; usually avoid)|
   +----------------------+--------------------------+----------------------+
                               |
                               v
                      +--------------------------+
                      | background queue         |
                      | VideoWorkflow runs later |
                      +--------------------------+
                               |
                               v
                      video AssetVersionCreated / AssetVideoReady (separate flow)


  4) Failure / Degradation Paths
  ------------------------------

   A) Ingestion failure
      MediaRejected -> FAILED

   B) Solve failure
      SolveWorkflow retries exhausted / cost cap exceeded -> FAILED
      Optional degradation:
        serve near-miss candidate if confidence > 0.70
        -> SUCCEEDED(outcome=hit-like, output.is_approximate=true)

   C) Indexing timeout (non-fatal)
      INDEXING timeout -> enqueue admin.ReindexAsset -> SUCCEEDED(outcome=new)


  5) Cancellation Path (generic)
  ------------------------------

   Cancel command received (user owns run)
      -> transition to CANCELLED from any non-terminal state
      -> stop further external calls / enqueue no new work
```

---

## Step-to-Domain / Adapter Mapping (quick reference)

- `INGESTING` -> `adapters/ocr_vision`
- `RETRIEVING` -> `adapters/qdrant` (+ keyword/hybrid adapters as added)
- `GENERATING_SOLUTION` -> `SolveWorkflow` (+ LLM / OpenClaw adapters)
- `REGISTERING` -> `domains/asset_registry`
- `INDEXING` -> `adapters/qdrant`
- `video enqueue` -> background queue + `VideoWorkflow`

---

## Key Events Along the Happy Path

- `ingestion.MediaNormalized`
- `retrieval.RetrievalHit` or `retrieval.RetrievalMiss`
- `asset.ProblemRegistered` (first-seen only)
- `asset.AssetVersionCreated`
- `retrieval.DocumentIndexed` (or deferred reindex log)
- workflow step logs for every transition and major action

---

## Implementation Notes (important)

- PolicyEngine must be called before any external adapter calls.
- `SUCCEEDED` is a generic terminal state; business result lives in `WorkflowResult.outcome`.
- Video generation is intentionally decoupled to keep user response latency low.
- Indexing timeout is non-fatal; asset availability takes priority over immediate searchability.
- Retry uses same `workflow_runs` row (`attempt_no` increments) to keep `run_id` stable.

---

## Related

- `docs/architecture-diagrams/README.md`
- `workflows/retrieve_or_generate/state_machine.md`
- `workflows/shared/README.md`
- `docs/architecture-diagrams/components/L2-policy-engine.md`
- `docs/architecture-diagrams/domains/L2-asset-registry.md`
