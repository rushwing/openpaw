# Contract Tests

> These tests verify that all code honours the frozen event and command contracts.
> Run with: `make test-contracts`

## Purpose

1. Every event in `contracts/events/v0.json` has a corresponding Pydantic model in `platform/contracts/validators.py`
2. Every emitted event (in `domains/*/events.py` and `workflows/*/`) serializes to the spec
3. Every command handler (in `apps/api_gateway/`) deserializes from the spec

## Files (to implement)

```
tests/contracts/
  conftest.py                    # Load v0.json specs as fixtures
  test_event_specs.py            # Verify each event can be serialised/deserialised
  test_command_specs.py          # Verify each command can be deserialised
  test_envelope_required.py      # Verify envelope fields are always present
```

## Validation Strategy

```python
# tests/contracts/test_event_specs.py
import json
from pathlib import Path
from platform.contracts.validators import EVENT_VALIDATORS

SPEC = json.loads(Path("contracts/events/v0.json").read_text())

@pytest.mark.parametrize("event_type", SPEC["events"].keys())
def test_event_has_validator(event_type: str) -> None:
    assert event_type in EVENT_VALIDATORS, (
        f"Event '{event_type}' in v0.json has no corresponding Pydantic model. "
        f"Add it to platform/contracts/validators.py"
    )
```

## Status

Stub — implement in Phase 1 when `platform/contracts/validators.py` exists.
