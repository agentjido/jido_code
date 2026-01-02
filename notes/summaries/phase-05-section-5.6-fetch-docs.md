# Phase 5 Section 5.6 - Fetch Elixir Docs Tool

**Date:** 2026-01-02
**Branch:** `feature/phase5-section-5.6-fetch-docs`
**Status:** Complete

---

## Overview

Implemented the `fetch_elixir_docs` tool for retrieving documentation for Elixir modules and functions. This tool uses `Code.fetch_docs/1` to access embedded documentation and `Code.Typespec.fetch_specs/1` to retrieve type specifications.

## Implementation Details

### Tool Definition

**File:** `lib/jido_code/tools/definitions/elixir.ex`

Added `fetch_elixir_docs/0` function with:
- **Name:** `fetch_elixir_docs`
- **Handler:** `JidoCode.Tools.Handlers.Elixir.FetchDocs`
- **Parameters:**
  - `module` (required, string) - Module name (e.g., "Enum", "String")
  - `function` (optional, string) - Function name to filter docs
  - `arity` (optional, integer) - Function arity to filter docs

Updated `Elixir.all/0` to include the new tool (now returns 6 tools).

### Handler Implementation

**File:** `lib/jido_code/tools/handlers/elixir.ex`

Created `FetchDocs` module (~140 lines) with:

#### Core Functions

```elixir
def execute(args, context)
```

Main entry point that:
1. Parses module name safely using `String.to_existing_atom/1`
2. Fetches documentation via `Code.fetch_docs/1`
3. Extracts and filters function docs
4. Fetches type specs via `Code.Typespec.fetch_specs/1`
5. Returns JSON with structured documentation

#### Security Features

- **Atom Table Protection:** Uses `String.to_existing_atom/1` exclusively
  - Non-existent modules return error without creating atoms
  - Test verifies atoms are not created for random module names
- **Module Loading Check:** Verifies module is loaded via `Code.ensure_loaded?/1`
- **Handles Missing Docs:** Returns meaningful errors for undocumented modules

#### Output Format

```json
{
  "module": "Enum",
  "moduledoc": "Module documentation...",
  "docs": [
    {
      "name": "map",
      "arity": 2,
      "kind": "function",
      "signature": "map(enumerable, fun)",
      "doc": "Function documentation...",
      "deprecated": null
    }
  ],
  "specs": [
    {
      "name": "map",
      "arity": 2,
      "specs": ["map(t(), (element() -> any())) :: list()"]
    }
  ]
}
```

#### Private Helpers

| Function | Purpose |
|----------|---------|
| `parse_module_name/1` | Safe atom conversion with "Elixir." prefix handling |
| `fetch_docs/1` | Wrapper around `Code.fetch_docs/1` |
| `extract_moduledoc/1` | Extract module-level docs from chunk |
| `extract_function_docs/3` | Extract and filter function docs |
| `matches_filter?/4` | Check function/arity filter match |
| `format_signature/1` | Format function signature |
| `extract_doc_text/1` | Extract text from doc map |
| `fetch_specs/3` | Retrieve and filter type specs |
| `matches_spec_filter?/4` | Check spec filter match |
| `format_error/1` | Format error messages |

### Telemetry

Emits telemetry at `[:jido_code, :elixir, :fetch_docs]` with:
- `duration` - Operation duration in microseconds
- `exit_code` - 0 for success, 1 for error
- `status` - `:ok` or `:error`
- `task` - Module name being queried

## Tests Added

### Handler Tests (16 tests)

**File:** `test/jido_code/tools/handlers/elixir_test.exs`

| Describe Block | Test Count |
|----------------|------------|
| Standard library module | 3 |
| Specific function | 2 |
| Function with arity | 2 |
| Includes specs | 2 |
| Undocumented module | 1 |
| Non-existent module | 2 |
| Error handling | 2 |
| Telemetry | 2 |
| Doc structure | 2 |

Key tests:
- Fetches docs for Enum/String modules
- Filters by function name and arity
- Includes type specifications
- Rejects non-existent modules
- Verifies atoms are not created for random module names
- Emits telemetry on success and error

### Definition Tests (8 tests)

**File:** `test/jido_code/tools/definitions/elixir_test.exs`

- Updated `all/0` test to expect 6 tools
- Added `fetch_elixir_docs/0 tool definition` describe block
- Added `fetch_elixir_docs executor integration` describe block

## Files Modified

| File | Change |
|------|--------|
| `lib/jido_code/tools/definitions/elixir.ex` | +60 lines (tool definition) |
| `lib/jido_code/tools/handlers/elixir.ex` | +250 lines (handler) |
| `test/jido_code/tools/handlers/elixir_test.exs` | +250 lines (handler tests) |
| `test/jido_code/tools/definitions/elixir_test.exs` | +122 lines (definition tests) |
| `notes/planning/tooling/phase-05-tools.md` | Marked 5.6 complete |

## Test Results

```
231 tests, 0 failures
```

All existing tests continue to pass after adding the new functionality.

## Design Decisions

1. **Safe Atom Handling:** Prioritized security by never creating atoms from user input. Only `String.to_existing_atom/1` is used.

2. **Graceful Degradation:** Returns empty lists for missing specs rather than failing. Handles undocumented modules with clear error messages.

3. **Filtering Support:** Supports filtering by function name and arity to reduce output size when users want specific documentation.

4. **Consistent Patterns:** Follows established handler patterns from other Elixir tools (MixTask, EtsInspect, etc.) for error handling, telemetry, and result formatting.

5. **Type Spec Formatting:** Uses `Code.Typespec.spec_to_quoted/2` and `Macro.to_string/1` to produce human-readable spec strings.

## Usage Examples

```elixir
# Get all docs for a module
FetchDocs.execute(%{"module" => "Enum"}, context)

# Get docs for specific function
FetchDocs.execute(%{"module" => "Enum", "function" => "map"}, context)

# Get docs for specific function/arity
FetchDocs.execute(%{"module" => "Enum", "function" => "map", "arity" => 2}, context)

# Handle non-existent module
FetchDocs.execute(%{"module" => "NonExistent"}, context)
# => {:error, "Module not found (only existing modules can be queried)"}
```
