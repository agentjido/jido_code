# Summary: LSP Diagnostics Integration Tests (3.7.3)

## Overview

Implementation of integration tests for the `get_diagnostics` LSP tool as part of Section 3.7.3.
These tests verify that diagnostics work correctly through the Executor → Handler chain
with proper security boundary enforcement.

## Files Modified

### `test/jido_code/integration/tools_phase3_test.exs`

Updated the Phase 3 integration test file to include comprehensive diagnostics testing:

1. **Updated moduledoc** - Added `get_diagnostics` to the list of tested tools
2. **Updated `register_phase3_tools/0`** - Added `LSPDefs.get_diagnostics()` registration
3. **Added two new describe blocks:**
   - `"LSP handler integration - get_diagnostics"` - Basic diagnostics tests
   - `"LSP diagnostics with Expert (when installed)"` - Expert-specific tests (3.7.3.1-3.7.3.2)

## Tests Added

### Basic Diagnostics Tests (8 tests)

| Test | Purpose |
|------|---------|
| `get_diagnostics returns structured response for workspace` | Verifies workspace-wide diagnostics structure |
| `get_diagnostics returns structured response for specific file` | Verifies file-specific diagnostics |
| `get_diagnostics filters by severity` | Tests severity filtering (error/warning/info/hint) |
| `get_diagnostics respects limit parameter` | Tests result limiting |
| `get_diagnostics rejects invalid severity` | Parameter validation for severity |
| `get_diagnostics rejects invalid limit` | Parameter validation for limit (positive integer) |
| `get_diagnostics blocks path traversal` | Security: prevents path escape attacks |
| `get_diagnostics returns error for nonexistent file` | Error handling for missing files |

### Expert Integration Tests (3 tests, tagged `:expert_required`)

| Test | Section | Purpose |
|------|---------|---------|
| `get_diagnostics detects syntax errors when Expert available` | 3.7.3.1 | Verifies syntax error detection |
| `get_diagnostics detects undefined function when Expert available` | 3.7.3.2 | Verifies undefined function detection |
| `get_diagnostics filters errors only when Expert available` | - | Severity filtering with real diagnostics |

## Test Structure

### Response Structure Verification

All diagnostics tests verify the expected response structure:

```elixir
%{
  "diagnostics" => [
    %{
      "severity" => "error" | "warning" | "info" | "hint",
      "file" => "relative/path.ex",
      "line" => 10,
      "column" => 5,
      "message" => "diagnostic message",
      "code" => "optional_code",
      "source" => "elixir"
    }
  ],
  "count" => 1,
  "truncated" => false
}
```

### Expert Detection Pattern

Expert integration tests use conditional execution based on Expert availability:

```elixir
case Client.find_expert_path() do
  {:ok, _path} ->
    # Run Expert-specific assertions
    ...
  {:error, :not_found} ->
    # Skip test when Expert not installed
    :ok
end
```

This allows tests to pass in both environments:
- **With Expert:** Full diagnostic verification
- **Without Expert:** Graceful skip

## Security Testing

The diagnostics tests include security boundary enforcement:

1. **Path traversal prevention** - Tests that `../../../etc/passwd` is rejected
2. **Project boundary enforcement** - Diagnostics only returned for files within project
3. **Input validation** - Invalid parameters are properly rejected

## Test Coverage Summary

| Category | Count |
|----------|-------|
| Basic diagnostics | 8 |
| Expert integration | 3 |
| **Total new tests** | **11** |
| **Total Phase 3 tests** | **35** |

## Running Tests

```bash
# Run all Phase 3 integration tests
mix test test/jido_code/integration/tools_phase3_test.exs

# Run only diagnostics tests
mix test test/jido_code/integration/tools_phase3_test.exs --only describe:"LSP handler integration - get_diagnostics"

# Run Expert integration tests (requires Expert)
mix test test/jido_code/integration/tools_phase3_test.exs --include expert_required
```

## Dependencies

- `JidoCode.Tools.Definitions.LSP` - LSP tool definitions including `get_diagnostics`
- `JidoCode.Tools.LSP.Client` - LSP client for Expert detection
- `JidoCode.Tools.Executor` - Tool execution framework
- `JidoCode.Session` - Session management for context building
