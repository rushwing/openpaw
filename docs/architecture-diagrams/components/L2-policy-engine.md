# OpenPaw Architecture Diagrams — L2 Policy Engine (ASCII)

> Scope: component-level design of `platform/policy_engine/`.
> Focus: policy resolution inputs, decision order, constraints, and `ExecutionPolicy` output used by workflows.

---

## L2 Diagram (Policy Engine Components + Resolution Flow)

```text
                     OpenPaw L2 — Policy Engine (Routing / Cost / Privacy / Model Selection)

  Purpose:
    Produce an ExecutionPolicy BEFORE any workflow makes external calls.
    Centralizes local-vs-cloud routing, model choice, privacy rules, and cost/timeout limits.


  1) Callers (who asks for policy)
  --------------------------------

   +------------------------------+     +------------------------------+
   | Workflow: retrieve_or_generate|    | Workflow: solve / video / ...|
   +------------------------------+     +------------------------------+
                \                               /
                 \ get_policy(...)             /  (workflow_type, user_id, tier, sensitivity, ...)
                  \                           /
                   v                         v
                 +------------------------------------------------------+
                 |                 PolicyEngine                         |
                 |------------------------------------------------------|
                 | get_policy(context)                                  |
                 | - resolve defaults                                   |
                 | - apply overrides                                    |
                 | - enforce privacy/routing constraints                |
                 | - apply circuit breaker / availability fallback      |
                 | - return ExecutionPolicy                             |
                 +------------------------------------------------------+


  2) Inputs / Data Sources (queried by PolicyEngine)
  --------------------------------------------------

    Static Config / Local Files                 Runtime / Dynamic Sources
   +--------------------------------+         +----------------------------------+
   | default_policies.yaml          |         | policy_overrides (Postgres)      |
   | - per workflow_type            |         | - tenant/user overrides          |
   | - per subscription tier        |         | - A/B rollout flags              |
   | - local overrides              |         +----------------------------------+
   | - embedding_model_global       |                          |
   +--------------------------------+                          v
                   \                                +----------------------------------+
                    \------------------------------->| Redis circuit breaker state      |
                                                     | - spend counters                 |
                                                     | - provider health / availability |
                                                     +----------------------------------+
                                                                       |
                                                                       v
                                                     +----------------------------------+
                                                     | Environment / Deployment Flags   |
                                                     | - LOCAL_ONLY                     |
                                                     | - MAX_DAILY_SPEND_USD            |
                                                     | - DEPLOYMENT_MODE=pi|cloud       |
                                                     +----------------------------------+


  3) Resolution Pipeline (ordered rules)
  --------------------------------------

   [Request Context]
     - workflow_type
     - user_id / tenant_id
     - subscription_tier
     - content_sensitivity
     - user privacy preference
     - optional task hints (latency/quality priority)
             |
             v
   +-------------------------------+
   | Step 1: Load tier default     |
   | from default_policies.yaml    |
   +-------------------------------+
             |
             v
   +-------------------------------+
   | Step 2: Apply deployment mode |
   | (Pi local mode / cloud mode)  |
   | e.g. LOCAL_ONLY => local exec |
   +-------------------------------+
             |
             v
   +-------------------------------+
   | Step 3: Privacy enforcement   |
   | private => local-only route   |
   | block cloud sync paths        |
   +-------------------------------+
             |
             v
   +-------------------------------+
   | Step 4: Apply tenant/user     |
   | overrides (Postgres)          |
   +-------------------------------+
             |
             v
   +-------------------------------+
   | Step 5: Circuit breaker       |
   | spend caps / degradation      |
   +-------------------------------+
             |
             v
   +-------------------------------+
   | Step 6: Provider availability |
   | fallback if primary unhealthy |
   +-------------------------------+
             |
             v
   +-------------------------------+
   | Step 7: Validate constraints  |
   | - executor allowed?           |
   | - model allowed?              |
   | - embedding_model matches?    |
   +-------------------------------+
             |
             v
   +-------------------------------+
   | ExecutionPolicy (output)      |
   +-------------------------------+


  4) ExecutionPolicy Output (consumed by workflows)
  -------------------------------------------------

   +-----------------------------------------------------------------------+
   | ExecutionPolicy                                                        |
   |-----------------------------------------------------------------------|
   | executor: local | cloud                                                |
   | llm_provider / llm_model                                               |
   | fallback provider/model                                                |
   | max_cost_usd                                                           |
   | timeout_sec                                                            |
   | retry_max                                                              |
   | priority                                                               |
   | privacy_mode                                                           |
   | embedding_model (global constant for index compatibility)              |
   | workflow-specific knobs (e.g. retrieval_threshold, video_generation)  |
   +-----------------------------------------------------------------------+
             |
             | log policy snapshot
             v
   +-------------------------------+
   | workflow_runs.policy_snapshot |
   +-------------------------------+


  5) Local vs Cloud Policy Behavior (same component, different outcomes)
  ----------------------------------------------------------------------

   [Pi / Local deployment]
     - often executor=local
     - privacy_mode frequently true
     - cloud sync blocked unless explicit consent
     - still may call external LLM APIs (if user enabled)

   [Cloud / ACK deployment]
     - executor=cloud by default
     - tenant-aware overrides and A/B routing
     - cost caps + provider fallback + autoscaling friendly defaults


  6) Failure / Fallback Semantics
  -------------------------------

   If PolicyEngine cannot produce a safe policy:
     -> return PolicyViolation / fail-fast (workflow does not start external calls)

   If primary provider unavailable:
     -> emit policy decision log + use fallback provider/model (if configured)

   If embedding_model mismatch detected:
     -> halt indexing-related policy grants / raise alert
```

---

## Key Interfaces (conceptual)

- `PolicyEngine.get_policy(...) -> ExecutionPolicy`
- `overrides_repo.get_override(tenant_id, user_id, workflow_type)`
- `circuit_breaker.get_state()`
- `provider_health.is_available(provider, model)`

---

## Design Notes

- PolicyEngine is a `platform` component, not a domain service.
- Workflows must call PolicyEngine first and log the returned policy snapshot.
- Keep resolution order deterministic and documented (critical for debugging).
- Separate `base policy fields` from `workflow-specific knobs` to avoid schema drift.
- `embedding_model` must remain globally consistent across local/cloud indexes (ADR-005).

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/adr/ADR-003-policy-routing.md`
- `docs/adr/ADR-005-privacy-boundary.md`
- `platform/policy_engine/README.md`
- `workflows/shared/README.md`
