# Rewards Ledger Domain

> Append-only credit ledger for all user rewards and deductions.
> See [ADR-002](../../docs/adr/ADR-002-asset-as-sot-ledger.md) for rationale.

## Key Entities

- **LedgerAccount** — one per user; holds account metadata only (no mutable balance)
- **LedgerEntry** — immutable record of one credit/debit event

## Invariants (enforced by this domain)

1. LedgerEntry is INSERT-only (no UPDATE, no DELETE — ever)
2. Every entry has a unique `idempotency_key`
3. Balance = `SUM(amount)` computed from entries (cached in Redis, TTL 60s)
4. Amount can be negative (debit) but total balance must never go below 0 (pre-check)

## Idempotency Key Pattern

```python
key = f"reward:{event_type}:{source_event_id}:{account_id}"
# e.g. "reward:correction_accepted:abc123:user456"
```

## Files (to implement)

```
domains/rewards_ledger/
  __init__.py
  model.py       # LedgerAccount, LedgerEntry value objects
  service.py     # credit(), debit(), get_balance(), get_history()
  repo.py        # Async Postgres: INSERT ledger_entries, SUM queries
  events.py      # CreditsGranted, CreditsSpent domain events
```
