# PolicyEngine

> Controls model selection, cost caps, and local/cloud routing for every workflow.
> See [ADR-003](../../docs/adr/ADR-003-policy-routing.md) for rationale.

## Interface

```python
# platform/policy_engine/engine.py

class PolicyEngine:
    async def get_policy(
        self,
        workflow_type: str,
        user_id: str,
        subscription_tier: str,
        content_sensitivity: str = "standard",
    ) -> ExecutionPolicy:
        ...
```

## Resolution Order (highest priority first)

1. `content_sensitivity == "private"` → `executor=local, privacy_mode=True`
2. `LOCAL_ONLY=true` env var → `executor=local` always
3. Per-user override in `policy_overrides` table (cloud only)
4. Per-tier defaults from `default_policies.yaml`
5. System circuit breaker (daily spend > limit → downgrade model)
6. Model availability check (fallback on 5xx)

## Files (to implement)

```
platform/policy_engine/
  __init__.py
  engine.py              # PolicyEngine class
  models.py              # ExecutionPolicy dataclass
  default_policies.yaml  # Default policies per workflow type and tier
  overrides_repo.py      # Load per-user/tenant overrides from Postgres
  circuit_breaker.py     # Redis-backed spend counter + availability flags
```

## default_policies.yaml structure

```yaml
defaults:
  solve_workflow:
    free:
      executor: cloud
      llm_provider: claude
      llm_model: claude-haiku-4-5-20251001
      max_cost_usd: 0.10
      timeout_sec: 60
      retry_max: 2
      retrieval_threshold: 0.85
      video_generation: skip          # free tier: no video
    pro:
      executor: cloud
      llm_provider: claude
      llm_model: claude-sonnet-4-6
      max_cost_usd: 0.50
      timeout_sec: 120
      retry_max: 3
      retrieval_threshold: 0.85
      video_generation: async         # pro: video in background
    enterprise:
      executor: cloud
      llm_provider: claude
      llm_model: claude-opus-4-6
      max_cost_usd: 5.00
      timeout_sec: 300
      retry_max: 5
      retrieval_threshold: 0.80       # lower threshold = more cache hits served
      video_generation: sync          # enterprise: wait for video

  video_workflow:
    free:
      executor: cloud
      llm_provider: openai
      llm_model: gpt-4o-mini
      max_cost_usd: 0.20
      timeout_sec: 300
      retry_max: 2
      retrieval_threshold: 0.85
      video_generation: skip
    pro:
      executor: cloud
      llm_provider: openai
      llm_model: gpt-4o
      max_cost_usd: 1.00
      timeout_sec: 600
      retry_max: 3
      retrieval_threshold: 0.85
      video_generation: async

local_overrides:
  # Applied when LOCAL_ONLY=true (Raspberry Pi deployment)
  all:
    executor: local
    llm_provider: claude
    llm_model: claude-haiku-4-5-20251001
    max_cost_usd: 0.0
    privacy_mode: true
    retry_max: 2
    retrieval_threshold: 0.85
    video_generation: async           # Pi can generate video async (no billing pressure)
    embedding_model: text-embedding-3-small   # MUST match cloud value — see ADR-005

# SYSTEM-WIDE CONSTANT (not per-tier):
# embedding_model must be identical across ALL tiers and ALL nodes.
# If you change it, you MUST trigger admin.ReindexAsset for every AssetVersion.
# Monitor for sync.EmbeddingModelMismatch events from edge nodes.
embedding_model_global: text-embedding-3-small
```
