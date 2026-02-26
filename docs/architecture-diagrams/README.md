# OpenPaw Architecture Diagrams (ASCII + Generated Images)

> Diagram index and conventions for architecture visualization.
> Goal: keep each diagram focused, small, and easy for humans + AI agents to load selectively.

---

## Levels

- `L0` Overall architecture (system/runtime map)
- `L1` Cross-cutting structure (topology, domain landscape, event relationships)
- `L2` Per workflow / per domain / per component deep dives
- `L3` Implementation-detail diagrams (optional; only when needed)

---

## File Organization (Best Practice)

```text
docs/architecture-diagrams/
  README.md
  L0-overall-architecture.md
  L0-overall-architecture.png
  L1-runtime-topology.md                 # next
  L1-domain-landscape.md                 # this stage
  workflows/
    L2-retrieve-or-generate.md
    L2-correction-validation.md
    L2-bounty-fulfillment.md
  domains/
    L2-identity.md
    L2-asset-registry.md
    L2-rewards-ledger.md
    L2-reputation.md
    L2-marketplace.md
  components/
    L2-policy-engine.md
    L2-event-bus-reliability.md
```

---

## Diagram Rules

- One primary concern per file (`overall`, `topology`, `domain landscape`, `workflow`, `component`)
- ASCII first (terminal/LLM-friendly); image export optional (`.png`)
- Put behavior/state transitions in workflow diagrams, not domain diagrams
- Put invariants/entity ownership in domain diagrams, not workflow diagrams
- Cross-link to ADRs and context packs; do not duplicate long prose
- If a generated image exists, use the same basename as the `.md` source

---

## Current Diagrams

- `L0-overall-architecture.md` / `L0-overall-architecture.png`
- `L1-domain-landscape.md` (ASCII)

