# ADR-002: Asset Registry as Source of Truth; Rewards Ledger is Append-only

## Status

Accepted — Phase 0

## Context

Two design decisions with large, irreversible downstream consequences:

### Problem A: Generated Solutions Need a Canonical Registry

The platform generates AI solutions (HTML, video) and reuses them across users. Without a
clear ownership model, these assets will become orphaned, de-duplicated incorrectly, and
lose provenance. Users can propose corrections, which creates new versions. The system must
support rollback if a correction turns out to be wrong.

### Problem B: Credits/Points Must Be Auditable

The platform grants points for corrections, ratings, and bounties. Points drive expert
reputation and are used as escrow for bounties. A mutable `balance` column leads to:
race conditions under concurrent reward settlement, no audit trail, and irreversible bugs
when a reward workflow fails halfway.

## Decision

### A: Asset Registry as Source of Truth

```
Problem (canonical dedup identity)
  └── AssetVersions (1..*)
        ├── SolutionHTMLVersion (v1, v2, v3...)
        │     └── ProvenanceRecord (who/what/when)
        └── VideoVersion (v1, v2...)
              └── ProvenanceRecord
```

**Rules (enforced by `asset_registry` domain):**

1. Assets are **never deleted** — only set to `status: deprecated`
2. New AI generation → new `AssetVersion` (never overwrite existing)
3. Accepted user correction → new `AssetVersion` linked to `CorrectionProposal.id`
4. Only one version is `status: published` at any time per asset type
5. `ProblemSignature` is the dedup key:
   ```
   ProblemSignature = hash(
     normalize(ocr_text),    # lowercase, strip punctuation, normalize whitespace
     image_phash,            # perceptual hash (tolerates JPEG artifacts)
     topic_tags              # sorted list of ML-assigned topic tags
   )
   ```
6. Retrieving "the solution" means: find Problem by ProblemSignature → get published AssetVersion

**ProvenanceRecord captures:**
- `created_by_type`: `ai_generation | user_correction | expert_answer | system_migration`
- `model_id`: e.g., `claude-sonnet-4-6`
- `skill_name`: e.g., `openclaw:photo-solve`
- `prompt_version`: hash of prompt template used
- `user_id`: if human-contributed
- `correction_proposal_id`: if based on a user correction

### B: Rewards Ledger is Append-only Forever

```sql
-- CORRECT: append-only ledger
CREATE TABLE ledger_entries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id      UUID NOT NULL REFERENCES ledger_accounts(id),
    amount          INTEGER NOT NULL,          -- positive = credit, negative = debit
    entry_type      TEXT NOT NULL,             -- 'correction_reward' | 'rating_reward' | 'bounty_escrow' | ...
    reference_id    UUID NOT NULL,             -- links to source event (CorrectionAccepted.id, etc.)
    idempotency_key TEXT NOT NULL UNIQUE,      -- prevents double-crediting
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Balance is COMPUTED, never stored:
-- SELECT SUM(amount) FROM ledger_entries WHERE account_id = $1

-- FORBIDDEN: mutable balance field
-- ALTER TABLE accounts ADD COLUMN balance INTEGER;  -- never do this
```

**Rules (enforced by `rewards_ledger` domain):**

1. `INSERT` only — no `UPDATE` or `DELETE` on `ledger_entries`
2. Every entry requires a unique `idempotency_key` (prevents duplicate rewards)
3. `reference_id` must link to a real domain event (enforceable via FK or soft validation)
4. Balance is a computed aggregate, optionally cached in Redis with TTL
5. For escrow (bounties): use a separate `escrow_account_id` that acts as a holding account

**Idempotency key pattern:**
```python
key = f"reward:{event_type}:{source_event_id}:{account_id}"
# e.g., "reward:correction_accepted:abc123:user456"
```

## Consequences

**Positive:**
- Full audit trail: every credit/debit traces to a source event
- No race conditions: concurrent reward settlements are safe (each inserts independently)
- Asset rollback is trivial: re-publish a previous version
- De-duplication is deterministic: same ProblemSignature → same asset
- Compliance: can reconstruct any account's full history at any point in time

**Negative:**
- Balance queries require aggregation (mitigate with: Redis cache + Postgres materialized view)
- Asset storage grows indefinitely (mitigate with: cold storage tiering in OSS)
- ProblemSignature computation is non-trivial (see `adapters/ocr_vision/` for OCR normalization)

**Migration note:** If importing existing data, assign `created_by_type: system_migration`
and set `model_id: null` in ProvenanceRecord.

## Related

- [ADR-001](ADR-001-ddd-lite-workflow-first.md) — why asset_registry is a DDD domain
- `domains/asset_registry/model.py` — Problem, AssetVersion, ProvenanceRecord entities
- `domains/rewards_ledger/model.py` — LedgerAccount, LedgerEntry entities
- `workflows/retrieve_or_generate/` — uses asset registry as SoT
