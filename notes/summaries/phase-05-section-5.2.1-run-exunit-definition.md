# Phase 5 Section 5.2.1: Run ExUnit Tool Definition

**Date:** 2026-01-02
**Branch:** `feature/phase5-section-5.2.1-run-exunit-definition`
**Status:** Complete

## Summary

Implemented the `run_exunit` tool definition for running ExUnit tests with comprehensive filtering options. This provides granular control over test execution beyond what the generic `mix_task` tool offers.

## Changes Made

### Tool Definition (`lib/jido_code/tools/definitions/elixir.ex`)

Added `run_exunit/0` function with 7 parameters:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | no | Test file or directory path |
| `line` | integer | no | Run test at specific line number |
| `tag` | string | no | Run only tests with specific tag |
| `exclude_tag` | string | no | Exclude tests with specific tag |
| `max_failures` | integer | no | Stop after N test failures |
| `seed` | integer | no | Random seed for test ordering |
| `timeout` | integer | no | Timeout in milliseconds (default 120000) |

Updated `all/0` to return both `mix_task()` and `run_exunit()`.

### Handler Implementation (`lib/jido_code/tools/handlers/elixir.ex`)

Added `RunExunit` module with:

- `execute/2` - Main entry point with validation pipeline
- Path traversal validation (blocks `../` patterns)
- Command argument builder for ExUnit options
- Test output summary parser
- Timeout enforcement (default 120s, max 5min)
- Output truncation (max 1MB)
- Telemetry emission (`[:jido_code, :elixir, :run_exunit]`)

### Test Coverage (`test/jido_code/tools/definitions/elixir_test.exs`)

Added 7 new tests:

1. `all/0` returns 2 tools (updated from 1)
2. `run_exunit/0` has correct name and description
3. `run_exunit/0` has correct parameters (all 7 validated)
4. `run_exunit/0` has correct handler
5. Executor integration: run_exunit tool is registered and executable
6. Executor integration: run_exunit blocks path traversal
7. Executor integration: run_exunit accepts filtering parameters
8. Executor integration: run_exunit with max_failures

## Test Results

```
27 tests, 0 failures
```

## Files Modified

| File | Change |
|------|--------|
| `lib/jido_code/tools/definitions/elixir.ex` | Added `run_exunit/0`, updated `all/0` |
| `lib/jido_code/tools/handlers/elixir.ex` | Added `RunExunit` module |
| `test/jido_code/tools/definitions/elixir_test.exs` | Added 7 new tests |
| `notes/planning/tooling/phase-05-tools.md` | Marked 5.2.1 items complete |

## Security Features

- Path traversal detection (blocks `../`, URL-encoded variants)
- Environment fixed to `test` (no prod execution)
- Timeout enforcement with graceful shutdown
- Output truncation at 1MB

## Next Steps

Section 5.2.2 will complete the handler implementation with:
- Path validation within `test/` directory
- Enhanced output parsing for failure details
- Structured test summary results
