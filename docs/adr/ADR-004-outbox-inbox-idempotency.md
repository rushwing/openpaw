# ADR-004: Outbox/Inbox Pattern for Reliable Event Delivery

## Status

Accepted — Phase 0 (design decision); Phase 1 (implementation required before first deployment)

## Context

OpenPaw is event-driven: domain services emit events, workflows react to events.
Without care, events can be lost or processed twice:

1. **Lost events:** domain writes to DB + emits event in-process → if the process crashes
   between the DB write and the event emit, the event is never delivered.
2. **Duplicate processing:** a consumer processes an event, crashes before acknowledging,
   and processes it again on restart.

Both scenarios corrupt business state (missing rewards, double-crediting ledger entries).

## Decision

### A: Transactional Outbox (for domain services)

Domain services write to DB **and** an `outbox` table in the **same transaction**.
A separate relay process polls `outbox` and delivers to the event bus (Redis Streams).

```sql
CREATE TABLE outbox (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type      TEXT NOT NULL,
    event_id        UUID NOT NULL,
    payload         JSONB NOT NULL,
    correlation_id  UUID NOT NULL,
    tenant_id       TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    delivered_at    TIMESTAMPTZ                     -- set when relay delivers
);
CREATE INDEX ON outbox (delivered_at) WHERE delivered_at IS NULL;  -- pending events
```

```python
# In domain service (same transaction as business write):
async with db.transaction():
    await db.execute("INSERT INTO problems ...")
    await db.execute("INSERT INTO asset_versions ...")
    await db.execute("INSERT INTO outbox (event_type, payload, ...) VALUES (...)")
    # Transaction commits → both rows or neither

# Relay process (separate, polling):
pending = await db.fetch("SELECT * FROM outbox WHERE delivered_at IS NULL LIMIT 100")
for event in pending:
    await redis_streams.publish(event)
    await db.execute("UPDATE outbox SET delivered_at = now() WHERE id = $1", event.id)
```

### B: Inbox Deduplication (for event consumers and command handlers)

Consumers record every processed `event_id` (or `command_id`) in an `inbox` table.
Before processing, check if already seen. Skip if duplicate.

```sql
CREATE TABLE inbox (
    id              UUID PRIMARY KEY,       -- event_id or command_id
    handler_name    TEXT NOT NULL,          -- which consumer processed it
    processed_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, handler_name)              -- same event can be handled by multiple consumers
);
```

```python
# In any event consumer:
async def handle_event(event: Event) -> None:
    already_processed = await db.fetchval(
        "SELECT 1 FROM inbox WHERE id = $1 AND handler_name = $2",
        event.event_id, self.HANDLER_NAME
    )
    if already_processed:
        return  # idempotent skip

    async with db.transaction():
        await self._process(event)
        await db.execute(
            "INSERT INTO inbox (id, handler_name) VALUES ($1, $2)",
            event.event_id, self.HANDLER_NAME
        )
```

### C: Workflow Command Inbox

Commands dispatched to `worker_orchestrator` use the same inbox pattern with `command_id`.
This prevents duplicate workflow starts if the API retries the dispatch.

## When NOT Required

- Read-only queries: no outbox/inbox needed
- In-process function calls within a single domain: no outbox needed
- Observability/logging events: at-most-once is acceptable

## Consequences

**Positive:**
- Zero event loss under crash/restart
- Zero duplicate processing for critical business logic (ledger, asset registry)
- Auditable: outbox and inbox provide delivery receipts

**Negative:**
- Extra tables + relay process
- Slightly higher write latency (extra INSERT per business transaction)
- Relay process must be monitored (add to platform/observability)

## Implementation Priority

Implement **before Phase 1 goes to production.** The relay process and inbox check
can be added to `platform/event_bus/`. Start with the rewards_ledger and asset_registry
domains (highest risk of data inconsistency).

## Related

- [ADR-002](ADR-002-asset-as-sot-ledger.md) — ledger append-only invariant
- `platform/event_bus/` — relay implementation
- `workflows/shared/event_log.py` — workflow step log (different from outbox, but same principle)
