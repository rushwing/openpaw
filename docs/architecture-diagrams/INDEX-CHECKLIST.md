# OpenPaw Architecture Diagrams — Index Checklist

> Tracking checklist for ASCII architecture docs and Nano Banana image generation.
> Use this file to manage coverage, consistency, and next priorities across L0/L1/L2.

---

## Usage

- `ASCII Doc`: the `.md` source under `docs/architecture-diagrams/`
- `PNG`: generated image (typically from Nano Banana)
- `Status` values:
  - `done` = completed and reviewed
  - `ascii-done` = ASCII doc completed, image not yet generated
  - `in-progress`
  - `todo`
- `Priority`:
  - `P0` core architecture communication / implementation-blocking
  - `P1` important for domain/workflow implementation
  - `P2` polish / secondary diagrams

---

## Coverage Summary

- Levels covered: `L0`, `L1`, `L2`
- Main categories: `overall`, `topology`, `domains`, `workflows`, `components`
- Style baseline: hand-drawn Nano Banana images with title prefix `OpenPaw - ...` and no footer text

---

## L0 / L1 Index

| Level | Diagram | Type | ASCII Doc | PNG | Status | Priority |
|------|---------|------|-----------|-----|--------|----------|
| L0 | Overall Architecture | overall system map | `docs/architecture-diagrams/L0-overall-architecture.md` | `docs/architecture-diagrams/L0-overall-architecture.png` | done | P0 |
| L1 | Domain Landscape | domain/event landscape | `docs/architecture-diagrams/L1-domain-landscape.md` | `docs/architecture-diagrams/L1-domain-landscape.png` | done | P0 |
| L1 | Runtime Topology | deployment + trust/sync boundaries | `docs/architecture-diagrams/L1-runtime-topology.md` | `docs/architecture-diagrams/L1-runtime-topology.png` | done | P0 |
| L1 | Event Flows Overview | cross-domain event choreography | `docs/architecture-diagrams/L1-event-flows-overview.md` | `docs/architecture-diagrams/L1-event-flows-overview.png` | ascii-done | P1 |

---

## L2 Components Index

| Level | Diagram | Type | ASCII Doc | PNG | Status | Priority |
|------|---------|------|-----------|-----|--------|----------|
| L2 | Event Bus Reliability | component flow (outbox/inbox) | `docs/architecture-diagrams/components/L2-event-bus-reliability.md` | `docs/architecture-diagrams/components/L2-event-bus-reliability.png` | done | P0 |
| L2 | Policy Engine | component + decision pipeline | `docs/architecture-diagrams/components/L2-policy-engine.md` | `docs/architecture-diagrams/components/L2-policy-engine.png` | done | P0 |
| L2 | Sync Agent | edge/cloud relay + anti-echo loop | `docs/architecture-diagrams/components/L2-sync-agent.md` | `docs/architecture-diagrams/components/L2-sync-agent.png` | ascii-done | P1 |

---

## L2 Domain Index

| Level | Diagram | Type | ASCII Doc | PNG | Status | Priority |
|------|---------|------|-----------|-----|--------|----------|
| L2 | Asset Registry | entity + lifecycle | `docs/architecture-diagrams/domains/L2-asset-registry.md` | `docs/architecture-diagrams/domains/L2-asset-registry.png` | done | P0 |
| L2 | Rewards Ledger | ledger + idempotency/read model | `docs/architecture-diagrams/domains/L2-rewards-ledger.md` | `docs/architecture-diagrams/domains/L2-rewards-ledger.png` | done | P0 |
| L2 | Marketplace | lifecycle + escrow interactions | `docs/architecture-diagrams/domains/L2-marketplace.md` | `docs/architecture-diagrams/domains/L2-marketplace.png` | done | P1 |
| L2 | Reputation | event-driven scoring pipeline | `docs/architecture-diagrams/domains/L2-reputation.md` | `docs/architecture-diagrams/domains/L2-reputation.png` | done | P1 |
| L2 | Identity | auth/subscription/entitlement/quota | `docs/architecture-diagrams/domains/L2-identity.md` | `docs/architecture-diagrams/domains/L2-identity.png` | done | P1 |
| L2 | Feedback | proposal/validation/decision/publication abstraction | `docs/architecture-diagrams/domains/L2-feedback.md` | `docs/architecture-diagrams/domains/L2-feedback.png` | done | P0 |

---

## L2 Workflow Index

| Level | Diagram | Type | ASCII Doc | PNG | Status | Priority |
|------|---------|------|-----------|-----|--------|----------|
| L2 | RetrieveOrGenerate | state machine + branches | `docs/architecture-diagrams/workflows/L2-retrieve-or-generate.md` | `docs/architecture-diagrams/workflows/L2-retrieve-or-generate.png` | done | P0 |
| L2 | Video Workflow | async orchestration + retries | `docs/architecture-diagrams/workflows/L2-video-workflow.md` | `docs/architecture-diagrams/workflows/L2-video-workflow.png` | done | P1 |
| L2 | Correction Validation | proposal validate/accept/reject flow | `docs/architecture-diagrams/workflows/L2-correction-validation.md` | `docs/architecture-diagrams/workflows/L2-correction-validation.png` | done | P0 |
| L2 | Reward Settlement | unified reward/refund orchestration | `docs/architecture-diagrams/workflows/L2-reward-settlement.md` | `docs/architecture-diagrams/workflows/L2-reward-settlement.png` | done | P0 |
| L2 | Bounty Fulfillment | settlement orchestration + compensation | `docs/architecture-diagrams/workflows/L2-bounty-fulfillment.md` | `docs/architecture-diagrams/workflows/L2-bounty-fulfillment.png` | done | P1 |
| L2 | Sync Publish Flow | Pi→Cloud consent + asset sync lifecycle | `docs/architecture-diagrams/workflows/L2-sync-publish-flow.md` | `docs/architecture-diagrams/workflows/L2-sync-publish-flow.png` | ascii-done | P1 |

---

## Suggested Next Diagrams (Backlog)

### L1

- [x] `L1-event-flows-overview.md` — cross-workflow event choreography map (P1) — ascii-done

### L2 Components

- [x] `components/L2-sync-agent.md` — edge/cloud sync agent and anti-echo loop (P1) — ascii-done
- [ ] `components/L2-observability.md` — tracing/logging/metrics across workflows and domains (P2)
- [ ] `components/L2-contract-validation.md` — command/event validation generation and runtime checks (P2)

### L2 Domains

- [ ] `domains/L2-entitlements.md` — if split out from identity later (P2)
- [ ] `domains/L2-billing.md` — if billing becomes a domain/platform hybrid with its own rules (P2)

### L2 Workflows

- [x] `workflows/L2-sync-publish-flow.md` — edge publish-to-cloud consent and sync lifecycle (P1) — ascii-done
- [ ] `workflows/L2-reindex-workflow.md` — embedding migration/reindex orchestration (P2)
- [ ] `workflows/L2-rating-reward-cycle.md` — top-rater reward periodic job (P2)

---

## Nano Banana Batch Checklist

Use this section to track image generation progress without editing each table row repeatedly.

### Ready to Generate (ASCII done)

- [ ] `docs/architecture-diagrams/L1-event-flows-overview.png`
- [ ] `docs/architecture-diagrams/components/L2-sync-agent.png`
- [ ] `docs/architecture-diagrams/workflows/L2-sync-publish-flow.png`

### Style Consistency Checklist (for each generated image)

- [ ] Title prefix is `OpenPaw - ...` (not `OpenClaw`)
- [ ] Hand-drawn sketch style matches prior images
- [ ] White background + soft blue/gray/orange accents
- [ ] No footer text block
- [ ] Text readable at presentation scale
- [ ] Main diagram focus is visually dominant
- [ ] Section headers present when image contains 2 sub-diagrams

---

## Review Checklist (Architecture Consistency)

Before marking a diagram `done`, verify:

- [ ] Terminology matches `docs/naming-conventions.md`
- [ ] Event names match `contracts/events/v0.json`
- [ ] Command names match `contracts/commands/v0.json`
- [ ] Domain boundaries align with `docs/adr/ADR-001-ddd-lite-workflow-first.md`
- [ ] Asset/ledger invariants align with `docs/adr/ADR-002-asset-as-sot-ledger.md`
- [ ] Policy/privacy references align with `docs/adr/ADR-003-policy-routing.md` and `docs/adr/ADR-005-privacy-boundary.md`
- [ ] Outbox/inbox reliability claims align with `docs/adr/ADR-004-outbox-inbox-idempotency.md`

---

## Notes

- Keep diagrams focused: if a file grows too dense, split into `-part1` / `-part2` or separate by concern.
- ASCII docs remain the source of truth for iterative changes; PNGs are presentation artifacts.
- Update this checklist as new diagrams are added so parallel work stays coordinated.
