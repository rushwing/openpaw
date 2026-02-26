# ADR-003: PolicyEngine Controls Model Selection, Cost Caps, and Local/Cloud Routing

## Status

Accepted — Phase 0

## Context

OpenPaw runs in two radically different environments:

1. **Raspberry Pi (local):** ARM CPU, 4-8 GB RAM, no GPU, no per-token cost, privacy-first
2. **Alibaba Cloud K8S:** auto-scaling, multiple LLM providers, billed per token/compute job

Each workflow must answer at runtime:
- Where to run? (local worker vs cloud worker)
- Which LLM? (Claude / GPT-4 / Gemini / Kimi — based on capability, cost, availability)
- What's the cost cap? (free users: $0.10/job; pro: $0.50/job; enterprise: unlimited)
- Privacy mode? (local-only for sensitive content; user-opted-in for cloud)
- Timeout and retry limits?

Hardcoding these decisions in workflow code leads to:
- Routing logic scattered across 6+ workflow files
- Impossible to A/B test models without changing workflow code
- Cannot give different users different policies without `if subscription_tier == "pro":` everywhere
- Cannot add a new LLM provider without editing every workflow

## Decision

A `PolicyEngine` service (in `platform/policy_engine/`) is consulted **at the start of
every workflow** before any external call is made. It returns an `ExecutionPolicy` that
the workflow must obey.

### ExecutionPolicy Schema

```python
@dataclass(frozen=True)
class ExecutionPolicy:
    executor: Literal["local", "cloud"]
    llm_provider: str                         # "claude" | "openai" | "gemini" | "kimi"
    llm_model: str                            # e.g., "claude-sonnet-4-6"
    max_cost_usd: float                       # per workflow run budget cap
    timeout_sec: int
    privacy_mode: bool                        # if True: no data leaves local device
    retry_max: int
    priority: Literal["low", "normal", "high"]
    fallback_llm_provider: str | None         # used if primary is unavailable
    # --- workflow-specific fields ---
    retrieval_threshold: float = 0.85         # min cosine similarity to count as cache hit
    video_generation: Literal["sync", "async", "skip"] = "async"
    # "sync"  = wait for video before returning (premium UX)
    # "async" = enqueue video in background, return HTML immediately (default)
    # "skip"  = do not generate video (free tier, cost saving)
    embedding_model: str = "text-embedding-3-small"
    # CRITICAL: this field MUST be identical on Local Pi and Cloud for vector space alignment.
    # Changing it requires a full re-index of all Qdrant data (expensive). See ADR-005.
    # Allowed values: "text-embedding-3-small" (default), "bge-m3" (open-source, runs locally)
    # DO NOT route this through subscription tier — it is a SYSTEM-WIDE constant.
```

### Usage Pattern (all workflows follow this)

```python
async def run(self, context: WorkflowContext) -> WorkflowResult:
    # 1. Always first: get policy
    policy = await self.policy_engine.get_policy(
        workflow_type=self.WORKFLOW_TYPE,
        user_id=context.user_id,
        subscription_tier=context.subscription_tier,
        content_sensitivity=context.sensitivity_tag,
    )

    # 2. Log policy used (for observability + debugging)
    await self.event_log.append(PolicyApplied(policy=policy, workflow_run_id=self.run_id))

    # 3. Use policy throughout workflow
    llm_client = self.adapter_registry.get_llm(policy.llm_provider, policy.llm_model)
    ...
```

### Policy Resolution Order (highest priority first)

1. Content sensitivity tag (`private` → always local, never cloud)
2. Deployment environment (`LOCAL_ONLY=true` env var on Pi → always local)
3. User subscription tier (free → small model; pro → full model; enterprise → custom)
4. System circuit breaker (if daily cloud spend > threshold → downgrade to smaller model)
5. Model availability (if primary provider returns 5xx → use `fallback_llm_provider`)
6. Default policy in `platform/policy_engine/default_policies.yaml`

### Configuration Storage

| Location | Purpose |
|----------|---------|
| `platform/policy_engine/default_policies.yaml` | Default policies per workflow type |
| `Postgres.policy_overrides` table | Per-tenant/per-user overrides (cloud only) |
| Environment variables | Deployment-specific: `LOCAL_ONLY`, `MAX_DAILY_SPEND_USD` |
| Redis | Circuit breaker state (spend counters, model availability flags) |

### LLM Provider → Model Mapping (v0 defaults)

| Provider | Free tier | Pro tier | Notes |
|----------|-----------|---------|-------|
| claude | haiku-4-5 | sonnet-4-6 | Best for complex reasoning |
| openai | gpt-4o-mini | gpt-4o | Good for code generation |
| gemini | gemini-2.0-flash | gemini-2.5-pro | Best for long context |
| kimi | moonshot-v1-8k | moonshot-v1-128k | Best for Chinese content |

## Consequences

**Positive:**
- Zero model/routing logic in workflow code
- Single place to change behavior for all users (update policy config, not code)
- A/B testing: route X% to new model by updating `policy_overrides` table
- New LLM provider: add adapter + add to default_policies.yaml, no workflow changes
- Cost control: policy caps prevent runaway spend; circuit breaker handles spikes
- Privacy compliance: `privacy_mode=True` is enforced at policy level, not in each workflow

**Negative:**
- Extra indirection: debugging requires inspecting the applied policy log
- PolicyEngine must be healthy before any workflow can start (add health check)
- Policy configuration needs its own test suite (changes to policies affect all workflows)

**Mitigation:** Every workflow logs the full `ExecutionPolicy` it used in the workflow event log.
`GET /workflows/{run_id}/policy` endpoint for debugging.

## Related

- [ADR-001](ADR-001-ddd-lite-workflow-first.md) — why policy is in platform/, not domains/
- `platform/policy_engine/` — implementation
- `platform/policy_engine/default_policies.yaml` — policy configuration
- `workflows/shared/base_workflow.py` — shows `get_policy()` call pattern
