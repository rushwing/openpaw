# OpenPaw Architecture Diagrams — L2 Event Bus Reliability (Outbox / Inbox) (ASCII)

> Scope: component-level reliability pattern for domain events and workflow commands.
> Focus: transactional outbox, relay, event bus delivery, inbox dedup, and idempotent handlers.

---

## L2 Diagram (Outbox / Inbox Reliability Flow)

```text
                OpenPaw L2 — Event Bus Reliability (Transactional Outbox + Inbox Dedup)

  Goal:
    Prevent lost events and duplicate side effects across domains/workflows in an event-driven system.


  A) Domain/Event Publish Path (reliable emit via transactional outbox)
  ---------------------------------------------------------------------

   [Workflow Step / API Handler]
             |
             | calls domain service (e.g. asset_registry.create_asset_version)
             v
   +-----------------------------+
   | Domain Service              |
   | - enforces invariants       |
   | - prepares domain event     |
   +-----------------------------+
             |
             | single DB transaction
             v
   +-------------------------------------------------------------------+
   | PostgreSQL Transaction (atomic)                                   |
   |-------------------------------------------------------------------|
   | 1) INSERT / UPDATE business tables                                |
   |    - asset_versions / ledger_entries / bounties / ...             |
   | 2) INSERT outbox row                                               |
   |    - event_id, event_type, payload, correlation_id, tenant_id     |
   +-------------------------------------------------------------------+
             |
             | COMMIT (both persist or neither persists)
             v
   +-----------------------------+
   | outbox table (pending rows) |
   | delivered_at IS NULL        |
   +-----------------------------+
             |
             | poll / batch fetch pending rows
             v
   +-----------------------------+
   | Outbox Relay Worker         |
   | (platform/event_bus)        |
   | - publish to Redis Streams  |
   | - mark delivered_at         |
   +-----------------------------+
             |
             | at-least-once delivery
             v
   +-----------------------------+
   | Event Bus (Redis Streams)   |
   | topic by event_type         |
   +-----------------------------+


  B) Event Consume Path (idempotent processing via inbox dedup)
  -------------------------------------------------------------

   +-----------------------------+
   | Event Bus (Redis Streams)   |
   +-----------------------------+
             |
             | delivers event (may redeliver after crash/retry)
             v
   +-----------------------------+
   | Consumer / Handler          |
   | examples:                   |
   | - RewardSettlementWorkflow  |
   | - Reputation projector      |
   | - Sync worker               |
   +-----------------------------+
             |
             | check (event_id, handler_name)
             v
   +-----------------------------+
   | inbox table                 |
   | UNIQUE(event_id, handler)   |
   +-----------------------------+
        | miss (not processed)             | hit (duplicate)
        |                                  |
        v                                  v
   +-----------------------------+      +-----------------------------+
   | Begin DB transaction        |      | Skip side effects           |
   | - process event             |      | Ack / return idempotently   |
   | - write business changes    |      +-----------------------------+
   | - INSERT inbox marker       |
   +-----------------------------+
             |
             | COMMIT
             v
   +-----------------------------+
   | Side effects applied once   |
   | (logical exactly-once)      |
   +-----------------------------+


  C) Workflow Command Start Path (same inbox pattern for command dedup)
  ---------------------------------------------------------------------

   [API Gateway]
       |
       | dispatch command (command_id, idempotency_key, correlation_id)
       v
   [worker_orchestrator command consumer]
       |
       | inbox check on command_id + handler_name
       v
   [inbox table]
       | miss -> create workflow run
       | hit  -> return existing / skip duplicate start
       v
   [workflow_runs + workflow_step_logs]


  Failure Cases Covered
  ---------------------
   1) Crash after business write, before publish:
      - event still in outbox -> relay publishes later (not lost)

   2) Crash after consume side effect, before ack:
      - event redelivered -> inbox detects duplicate -> side effect not re-applied

   3) API retry sends same command twice:
      - command inbox blocks duplicate workflow start


  Guarantees / Non-Guarantees
  ---------------------------
   - Guarantees:
     * no lost critical domain events (with outbox relay running)
     * no duplicate business side effects per handler (via inbox + idempotent tx)
     * auditability of delivery attempts and processing markers

   - Non-Guarantees:
     * exactly-once transport delivery on Redis Streams (not required)
     * global ordering across all event types (only per-stream semantics)
```

---

## Component Responsibilities

- `domains/*/service.py`: write business facts + outbox row in one transaction
- `platform/event_bus/outbox_relay.py`: poll outbox, publish, mark delivered
- `platform/event_bus/consumer.py`: consume event, inbox dedup, invoke handler
- `platform/event_bus/inbox_repo.py`: processed marker persistence
- `workflows/shared/`: command consumer side uses same inbox pattern for `command_id`

---

## Design Notes (important for implementation)

- `outbox.delivered_at` tracks relay delivery, not consumer processing success.
- Inbox uniqueness should be `(event_id, handler_name)` or `(command_id, handler_name)`.
- Consumer processing + inbox insert must be in the same transaction.
- Business handlers should still be internally idempotent when possible (defense in depth).
- Use batch relay with small limits first; optimize later.

---

## Related

- `docs/architecture-diagrams/README.md`
- `docs/adr/ADR-004-outbox-inbox-idempotency.md`
- `platform/event_bus/` (planned)
- `workflows/shared/README.md`
