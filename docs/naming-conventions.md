# OpenPaw — Naming Conventions & Error Codes

> Shared vocabulary for events, commands, error codes, and identifiers.
> Enforced in: code reviews, contract validation tests.

---

## Event Naming

Format: `<domain>.<PascalCaseEventName>`

### Rules
1. Use past tense (something happened): `UserRegistered`, `AssetVersionCreated`
2. Domain prefix must match the `namespace_map` in `contracts/events/v0.json`
3. Avoid vague names: `Updated` → use `Published`, `Activated`, `Deprecated`
4. Aggregate + action: `Asset` + `VersionCreated` → `AssetVersionCreated`

### Examples

| ❌ Bad | ✅ Good | Reason |
|--------|--------|--------|
| `asset.Updated` | `asset.AssetVersionPublished` | Specific action |
| `user.Changed` | `identity.UserRegistered` | Domain prefix + past tense |
| `points.Added` | `rewards_ledger.PointsEarned` | Full domain namespace |
| `job.Done` | `generation.JobSucceeded` | Explicit terminal state |

---

## Command Naming

Format: `<domain>.<ImperativePascalCase>`

### Rules
1. Use imperative (do something now): `SubmitProblem`, `PostBounty`, `ProposeCorrection`
2. Avoid CRUD names: `Create/Update/Delete` → prefer `Register`, `Publish`, `Deprecate`

---

## Field Naming

| Concept | Naming |
|---------|--------|
| All IDs | `{entity}_id` (e.g. `problem_id`, `user_id`) |
| Timestamps | `{event}_at` (e.g. `created_at`, `expires_at`, `occurred_at`) |
| Booleans | `is_{condition}` or plain adjective (e.g. `is_approximate`, `privacy_mode`) |
| Counts | `{noun}_count` (e.g. `retry_count`) |
| Durations | `{noun}_ms` or `{noun}_sec` (e.g. `duration_ms`, `timeout_sec`) |
| Amounts | `{noun}_usd` or `{noun}_points` (e.g. `cost_usd`, `escrow_amount`) |

---

## Error Codes

Format: `OPENPAW_{DOMAIN}_{CODE}` — uppercase with underscores.

### Ingestion Errors

| Code | Description |
|------|-------------|
| `OPENPAW_INGESTION_UNSAFE_CONTENT` | Media failed safety check |
| `OPENPAW_INGESTION_UNSUPPORTED_FORMAT` | File type not supported |
| `OPENPAW_INGESTION_TOO_LARGE` | File exceeds size limit |
| `OPENPAW_INGESTION_OCR_FAILED` | OCR could not extract text |
| `OPENPAW_INGESTION_LOW_QUALITY` | Image resolution too low |
| `OPENPAW_INGESTION_SESSION_EXPIRED` | Upload session expired |

### Generation Errors

| Code | Description |
|------|-------------|
| `OPENPAW_GENERATION_COST_CAP_EXCEEDED` | Job cost would exceed policy.max_cost_usd |
| `OPENPAW_GENERATION_MODEL_UNAVAILABLE` | All LLM providers failed |
| `OPENPAW_GENERATION_TIMEOUT` | Job exceeded policy.timeout_sec |
| `OPENPAW_GENERATION_CONTENT_FILTERED` | LLM refused to answer (safety) |
| `OPENPAW_GENERATION_INVALID_OUTPUT` | LLM output failed format validation |

### Retrieval Errors

| Code | Description |
|------|-------------|
| `OPENPAW_RETRIEVAL_INDEX_UNAVAILABLE` | Qdrant not reachable |
| `OPENPAW_RETRIEVAL_INDEX_TIMEOUT` | Search exceeded timeout |

### Asset Errors

| Code | Description |
|------|-------------|
| `OPENPAW_ASSET_NOT_FOUND` | Problem or AssetVersion does not exist |
| `OPENPAW_ASSET_ALREADY_DEPRECATED` | Cannot publish a deprecated version |

### Identity / Auth Errors

| Code | Description |
|------|-------------|
| `OPENPAW_AUTH_UNAUTHORIZED` | Missing or invalid token |
| `OPENPAW_AUTH_FORBIDDEN` | User lacks required role/permission |
| `OPENPAW_IDENTITY_QUOTA_EXCEEDED` | User's generation quota exhausted |
| `OPENPAW_IDENTITY_INSUFFICIENT_POINTS` | Not enough points for operation |

### Marketplace Errors

| Code | Description |
|------|-------------|
| `OPENPAW_MARKETPLACE_BOUNTY_EXPIRED` | Bounty deadline passed |
| `OPENPAW_MARKETPLACE_ESCROW_FAILED` | Could not lock escrow (insufficient balance) |

### Generic Errors

| Code | Description |
|------|-------------|
| `OPENPAW_INTERNAL_ERROR` | Unexpected server error (catch-all) |
| `OPENPAW_VALIDATION_ERROR` | Request payload failed schema validation |
| `OPENPAW_IDEMPOTENCY_CONFLICT` | Conflicting idempotency key |

---

## Idempotency Key Patterns

| Use case | Pattern |
|----------|---------|
| Workflow run | `sha256({workflow_type}:{problem_signature}:{user_id}:{intent})` |
| Points earn | `earn:{entry_type}:{source_event_id}:{account_id}` |
| Points deduct | `deduct:{entry_type}:{source_event_id}:{account_id}` |
| Job creation | `job:{job_type}:{problem_signature}:{user_id}:{attempt_no}` |

---

## ProblemSignature Computation

```python
def compute_problem_signature(
    normalized_text: str | None,
    phash: str | None,
    topic_tags: list[str],
) -> str:
    parts = [
        normalized_text or "",
        phash or "",
        ":".join(sorted(topic_tags)),
    ]
    return hashlib.sha256("|".join(parts).encode()).hexdigest()

def normalize_text(raw_ocr: str) -> str:
    # 1. Lowercase
    # 2. Strip punctuation (keep math symbols: +, -, *, /, =, ^, (, ), [, ])
    # 3. Normalize whitespace (collapse runs, strip leading/trailing)
    # 4. Normalize CJK full-width characters to ASCII
    ...
```

---

## File Naming

| Type | Convention | Example |
|------|-----------|---------|
| Python modules | `snake_case.py` | `base_workflow.py` |
| Test files | `test_{module}.py` | `test_base_workflow.py` |
| Config files | `snake_case.{yaml,json,toml}` | `default_policies.yaml` |
| ADRs | `ADR-{NNN}-{slug}.md` | `ADR-001-ddd-lite-workflow-first.md` |
| Context packs | `{L}{N}-{slug}.md` or `{domain}.md` | `L0-vision-glossary.md` |
