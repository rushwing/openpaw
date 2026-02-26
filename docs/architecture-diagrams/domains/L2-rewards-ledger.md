# OpenPaw Architecture Diagrams — L2 Rewards Ledger (Ledger + Idempotency) (ASCII)

> Scope: domain-level design of `domains/rewards_ledger/`.
> Focus: append-only ledger model, idempotent credit/debit writes, escrow patterns, and balance read model.

---

## Diagram A — Ledger Entity Model + Posting Flow (Append-only)

```text
                OpenPaw L2 — Rewards Ledger (Append-only Ledger + Posting Flow)

  Purpose:
    Authoritative source of all points facts (earn / deduct / escrow), auditable and concurrency-safe.


  Entity Model
  ------------

   +----------------------------------------------------------------------------------+
   | LedgerAccount                                                                    |
   |----------------------------------------------------------------------------------|
   | account_id (UUID)                                                                |
   | owner_user_id (UUID)                                                             |
   | account_type (user_wallet | escrow | system_pool)                                |
   | status (active | frozen | closed)                                                |
   | tenant_id                                                                        |
   | created_at                                                                       |
   |----------------------------------------------------------------------------------|
   | NOTE: no mutable balance column                                                  |
   +----------------------------------------------------------------------------------+
                          | 1
                          | has many
                          | 1..*
                          v
   +----------------------------------------------------------------------------------+
   | LedgerEntry (append-only)                                                        |
   |----------------------------------------------------------------------------------|
   | entry_id (UUID)                                                                  |
   | account_id (FK -> LedgerAccount)                                                 |
   | amount (int; +credit, -debit)                                                    |
   | entry_type (subscription_grant | correction_reward | rating_reward |             |
   |            bounty_escrow_hold | bounty_payout | refund | admin_adjustment | ...) |
   | reference_id (source event / proposal / bounty / settlement id)                  |
   | idempotency_key (UNIQUE)                                                         |
   | metadata_json? (reason/context snapshot)                                         |
   | created_at                                                                       |
   +----------------------------------------------------------------------------------+


  Posting Flow (credit / debit)
  -----------------------------

   [Workflow or domain-triggered settlement]
        |
        | e.g. RewardSettlementWorkflow / BountyFulfillmentWorkflow
        v
   +-----------------------------+
   | rewards_ledger.service      |
   | - credit() / deduct()       |
   | - validate amount           |
   | - build idempotency_key     |
   +-----------------------------+
        |
        | (debit only) pre-check available balance
        v
   +-----------------------------+
   | repo.get_balance(account_id)|
   | SUM(ledger_entries.amount)  |
   +-----------------------------+
        |
        | if insufficient -> reject
        v
   +-------------------------------------------------------------------+
   | DB transaction                                                    |
   |-------------------------------------------------------------------|
   | INSERT ledger_entries (...)                                       |
   | INSERT outbox (rewards_ledger.PointsEarned / PointsDeducted)      |
   +-------------------------------------------------------------------+
        |
        | COMMIT
        v
   +-----------------------------+
   | Points fact recorded        |
   | (authoritative)             |
   +-----------------------------+


  Escrow Pattern (Marketplace bounties)
  -------------------------------------

   Poster user wallet account              Escrow account                    Expert wallet account
   +-------------------------+             +-------------------------+      +-------------------------+
   | user_wallet             |             | escrow_account          |      | expert_wallet           |
   +-------------------------+             +-------------------------+      +-------------------------+
             |                                         |                                 ^
             | PointsDeducted (bounty_escrow_hold)     |                                 |
             +-------------------------------> [held funds] ------------------------------+
                                                       | payout on settle
                                                       +--> PointsEarned (bounty_payout)

   Notes:
   - Hold and payout are separate ledger facts (auditable)
   - Refund on expiry/cancel is another ledger entry (never mutate old rows)
```

---

## Diagram B — Idempotency / Dedup + Balance Read Model

```text
             OpenPaw L2 — Rewards Ledger Idempotency + Balance Read Path

  A) Idempotent Write (duplicate reward/deduct protection)
  -------------------------------------------------------

   Trigger event / settlement input
   (e.g. feedback.CorrectionAccepted, marketplace.BountySettled)
              |
              v
   +------------------------------+
   | rewards_ledger.service       |
   | build idempotency_key        |
   | examples:                    |
   | - earn:{entry_type}:{src}:{acct}
   | - deduct:{entry_type}:{src}:{acct}
   +------------------------------+
              |
              | INSERT ledger_entry with UNIQUE(idempotency_key)
              v
   +------------------------------+
   | PostgreSQL ledger_entries    |
   | UNIQUE(idempotency_key)      |
   +------------------------------+
        | success                           | duplicate key violation
        |                                   |
        v                                   v
   +------------------------------+   +------------------------------+
   | first write wins             |   | treat as idempotent replay   |
   | emit PointsEarned/Deducted   |   | return existing logical result|
   +------------------------------+   +------------------------------+


  B) Balance Read Path (derived, optionally cached)
  -------------------------------------------------

   [Caller]
   (API / workflow pre-check / marketplace escrow check)
              |
              v
   +------------------------------+
   | rewards_ledger.service       |
   | get_balance(account_id)      |
   +------------------------------+
              |
              | cache lookup (TTL, e.g. 60s)
              v
   +------------------------------+
   | Redis cache (optional)       |
   | key: balance:{account_id}    |
   +------------------------------+
        | hit                               | miss / stale
        |                                   |
        v                                   v
   +------------------------------+   +------------------------------------------+
   | return cached balance        |   | Postgres aggregate query                 |
   | (fast path)                  |   | SELECT COALESCE(SUM(amount),0) ...       |
   +------------------------------+   +------------------------------------------+
                                               |
                                               | cache set (TTL)
                                               v
                                   +------------------------------+
                                   | return computed balance      |
                                   +------------------------------+


  C) Safety Rules (write-time + read-time)
  ----------------------------------------

   Write-time:
   - INSERT only (no UPDATE/DELETE on ledger_entries)
   - unique idempotency key per logical posting
   - debit must not make computed balance < 0 (pre-check)

   Read-time:
   - balance is derived from entries (cache is optimization only)
   - cache invalidation on new ledger write (or short TTL fallback)
```

---

## Key Domain Events (authoritative points facts)

- `rewards_ledger.PointsEarned`
- `rewards_ledger.PointsDeducted`

These are the canonical points events. Other domains/workflows may trigger rewards, but the
ledger domain is the source of truth for recorded points facts.

---

## Service Operations (conceptual mapping)

- `credit(account_id, amount, entry_type, reference_id, idempotency_key, metadata)`
- `deduct(account_id, amount, entry_type, reference_id, idempotency_key, metadata)`
- `get_balance(account_id)`
- `get_history(account_id, page, page_size)`
- `transfer_to_escrow(...)` / `payout_from_escrow(...)` (optional wrappers over credit/deduct)

---

## Implementation Notes (important)

- Prefer DB constraints for idempotency (`UNIQUE(idempotency_key)`) over app-only checks.
- Handle duplicate-key errors as success-equivalent idempotent replays when logically identical.
- Keep ledger writes and outbox event insert in one transaction.
- For high throughput, add materialized/read model later; keep append-only source intact.
- Never store mutable `balance` in `ledger_accounts`.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/adr/ADR-002-asset-as-sot-ledger.md`
- `docs/adr/ADR-004-outbox-inbox-idempotency.md`
- `domains/rewards_ledger/README.md`
- `docs/context-packs/L1-domain-map.md`
