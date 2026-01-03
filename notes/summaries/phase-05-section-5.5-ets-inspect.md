# Phase 5 Section 5.5: ETS Inspect Tool Implementation

**Date:** 2026-01-02
**Branch:** `feature/phase5-section-5.5-ets-inspect`
**Status:** Complete

## Summary

Implemented the `ets_inspect` tool for inspecting ETS tables with security controls. This tool allows inspection of ETS table contents through four operations: list, info, lookup, and sample, while blocking access to system tables.

## Changes Made

### Tool Definition (`lib/jido_code/tools/definitions/elixir.ex`)

- Added `ets_inspect/0` function returning Tool struct
- Updated `all/0` to include `ets_inspect()` (now returns 5 tools)
- Parameters:
  - `operation` (required, string, enum) - "list", "info", "lookup", "sample"
  - `table` (optional, string) - Table name for info/lookup/sample operations
  - `key` (optional, string) - Key for lookup operation (parsed from string)
  - `limit` (optional, integer) - Max entries for sample (default: 10, max: 100)

### Handler Implementation (`lib/jido_code/tools/handlers/elixir.ex`)

Created `EtsInspect` module with full implementation (~350 lines):

#### Operations

1. **list** - Get all project-owned ETS tables
   - Filters `:ets.all()` to project tables
   - Returns table name, type, size, memory, protection
   - Excludes reference-based (unnamed) tables

2. **info** - Get detailed table information
   - Returns full `:ets.info(table)` data
   - Validates table is not blocked

3. **lookup** - Find entries by key
   - Parses key from string (atoms, integers, floats, booleans, strings)
   - Validates table is accessible and readable
   - Returns matching entries

4. **sample** - Get first N entries
   - Uses `:ets.first/1` and `:ets.next/2` for safe traversal
   - Respects limit (default: 10, max: 100)
   - Indicates truncation status

#### Security Features

- **Blocked tables list** - 22 system ETS tables blocked (code, ac_tab, etc.)
- **Owner blocking** - Tables owned by system/internal processes blocked
- **Access level enforcement** - Private tables block lookup/sample
- **Named tables only** - Reference-based tables not exposed in list

#### Result Structures

```elixir
# list operation
%{
  "operation" => "list",
  "tables" => [
    %{"name" => "my_table", "type" => "set", "size" => 10,
      "memory" => 1234, "protection" => "public"}
  ],
  "count" => 1
}

# info operation
%{
  "operation" => "info",
  "table" => "my_table",
  "info" => %{
    "type" => "set",
    "protection" => "public",
    "size" => 10,
    "owner" => "#PID<0.123.0>",
    ...
  }
}

# lookup operation
%{
  "operation" => "lookup",
  "table" => "my_table",
  "key" => ":my_key",
  "entries" => ["{:my_key, \"value\"}"],
  "count" => 1
}

# sample operation
%{
  "operation" => "sample",
  "table" => "my_table",
  "entries" => [...],
  "count" => 10,
  "total_size" => 100,
  "truncated" => true
}
```

#### Key Parsing

Supports multiple key formats:
- Atoms: `:my_key` or `:my_atom`
- Integers: `123` or `-456`
- Floats: `3.14` or `-2.5`
- Booleans: `true` or `false`
- Quoted strings: `"my string"` or `'single quoted'`
- Plain strings: treated as-is

### Test Coverage

Added 40+ new tests across handler and definition test files:

| Category | Tests |
|----------|-------|
| list operation | 3 (lists tables, excludes system, returns summary) |
| info operation | 4 (returns info, non-existent, blocks system, requires param) |
| lookup operation | 6 (atom/int/string keys, empty results, requires key, blocks private) |
| sample operation | 5 (returns entries, default limit, caps at 100, empty, truncation) |
| Security | 4 (blocks system tables, private tables, protected tables info) |
| Error handling | 4 (missing operation, invalid operation, invalid type, references) |
| Telemetry | 3 (success, error, list operation) |
| Key parsing | 4 (booleans, floats, single-quoted, unquoted) |
| Definition tests | 3 (name/description, parameters, handler) |
| Integration tests | 4 (registration, execution list/info, validation, blocking) |

## Test Results

```
200 tests, 0 failures
```

All Elixir handler and definition tests pass.

## Files Modified

| File | Change |
|------|--------|
| `lib/jido_code/tools/definitions/elixir.ex` | Added ets_inspect tool definition |
| `lib/jido_code/tools/handlers/elixir.ex` | Added EtsInspect handler module (~350 lines) |
| `test/jido_code/tools/handlers/elixir_test.exs` | Added 33 EtsInspect tests |
| `test/jido_code/tools/definitions/elixir_test.exs` | Updated tool count, added 7 tests |
| `notes/planning/tooling/phase-05-tools.md` | Marked 5.5 complete |

## Security Model

1. **Blocked tables** - 22 system ETS tables explicitly blocked
2. **Owner validation** - Tables owned by system processes blocked
3. **Access level enforcement** - Private tables cannot be read (lookup/sample)
4. **Named tables only** - Reference-based tables filtered from list
5. **Limit enforcement** - Sample capped at 100 entries maximum
6. **Telemetry** - All operations emit telemetry for monitoring

## Implementation Notes

- EtsInspect handler follows same patterns as ProcessState and SupervisorTree
- Uses `:ets.all()` and `:ets.info/1` for safe table inspection
- Key parsing handles common Elixir types via string format
- Telemetry events emitted at `[:jido_code, :elixir, :ets_inspect]`
- Test cleanup uses try/catch to handle table deletion race conditions
