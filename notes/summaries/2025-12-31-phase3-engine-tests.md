# Task 3.2.2 Promotion Engine Unit Tests

**Status**: Complete
**Branch**: `feature/3.4-promotion-engine-tests`
**Planning Reference**: `notes/planning/two-tier-memory/phase-03-promotion-engine.md` Section 3.2.2

## Summary

This task verifies and documents the existing unit tests for the Promotion.Engine module. The tests were already implemented and passing; this task marks them complete in the planning document.

## Test File

`test/jido_code/memory/promotion/engine_test.exs` - 28 tests, all passing

## Test Coverage

### evaluate/1 Tests (8 tests)

| Test | Description |
|------|-------------|
| returns empty list for empty state | Empty working_context and pending_memories returns [] |
| scores context items correctly | Context items with promotable types get scored |
| includes items above threshold | Items with importance_score >= 0.6 included |
| excludes items below threshold | Items with importance_score < 0.6 excluded |
| always includes agent_decisions | Agent decisions (score 1.0) always included |
| excludes items with nil suggested_type | Items without memory type classification excluded |
| sorts by importance descending | Results sorted highest score first |
| limits to max_promotions_per_run | Maximum 20 candidates returned |

### promote/3 Tests (5 tests)

| Test | Description |
|------|-------------|
| persists candidates to long-term store | Candidates persisted via Memory.persist |
| returns count of successfully persisted items | Returns {:ok, count} |
| includes agent_id in memory input | agent_id option passed to memory input |
| includes project_id in memory input | project_id option passed to memory input |
| handles partial failures gracefully | Invalid candidates don't break batch |

### run/2 and run_with_state/3 Tests (5 tests)

| Test | Description |
|------|-------------|
| returns {:ok, 0} when no candidates | Empty state returns zero promoted |
| evaluates, promotes, and returns count | Full flow works end-to-end |
| returns promoted ids for cleanup | Returns list of promoted IDs |
| returns error when state not provided | Missing :state option returns error |
| emits telemetry on promotion | Telemetry event emitted with metrics |

### Helper Function Tests (8 tests)

| Test | Description |
|------|-------------|
| generate_id generates unique ids | 32-char hex IDs, unique each call |
| format_content handles string values | Strings passed through |
| format_content handles non-string values | Numbers inspected |
| format_content handles map with value key | Extracts value from map |
| format_content handles map with value and key | Formats as "key: value" |
| format_content handles map with content key | Extracts content from map |
| format_content handles complex terms | Falls back to inspect |

### Configuration Tests (2 tests)

| Test | Description |
|------|-------------|
| promotion_threshold returns 0.6 | Default threshold |
| max_promotions_per_run returns 20 | Default limit |

### Integration Test (1 test)

| Test | Description |
|------|-------------|
| full flow with context and pending items | Complete promotion flow with multiple sources |

## Running Tests

```bash
mix test test/jido_code/memory/promotion/engine_test.exs --trace
```

## Test Helpers

The test file includes several helper functions:

- `create_empty_state/0` - Creates state with empty short-term memory components
- `create_state_with_context/1` - Creates state with working context items
- `create_pending_item/1` - Creates pending memory item with defaults

## Notes

The tests verify all public functions of the Promotion.Engine:
- `evaluate/1` - Find promotion candidates from session state
- `promote/3` - Persist candidates to long-term storage
- `run/2` - Convenience function combining evaluate + promote + cleanup
- `run_with_state/3` - Run with explicit state (no session lookup)
- `promotion_threshold/0` - Get threshold configuration
- `max_promotions_per_run/0` - Get limit configuration
- `generate_id/0` - Generate unique memory IDs
- `format_content/1` - Convert terms to string content
