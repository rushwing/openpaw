# Asset Registry Domain

> Source of Truth for all problems, solutions, and videos.
> See [ADR-002](../../docs/adr/ADR-002-asset-as-sot-ledger.md) for rationale.

## Key Entities

- **Problem** — normalized question (ProblemSignature as dedup key)
- **SolutionAsset** — versioned HTML solution linked to a Problem
- **VideoAsset** — versioned teaching video linked to a Problem
- **AssetVersion** — one immutable snapshot of an asset (v1, v2, ...)
- **ProvenanceRecord** — who/what created each version

## Invariants (enforced by this domain)

1. Assets are never deleted (only `status=deprecated`)
2. Exactly one `status=published` version per (problem_id, asset_type)
3. New generation → new version (never overwrite)
4. All versions have a ProvenanceRecord

## Files (to implement)

```
domains/asset_registry/
  __init__.py
  model.py       # Problem, AssetVersion, ProvenanceRecord entities + value objects
  service.py     # create_asset(), publish_version(), deprecate_version(), get_published()
  repo.py        # Async Postgres queries (no Repository pattern, just async functions)
  events.py      # Domain events: AssetCreated, AssetVersionPublished, AssetDeprecated
```

## Context Pack

See `docs/context-packs/domains/asset_registry.md` (to be created by Gemini).
