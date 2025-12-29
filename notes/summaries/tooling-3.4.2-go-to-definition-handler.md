# Task 3.4.2 - Go To Definition Handler Implementation

**Status**: Complete
**Branch**: `feature/3.4.2-go-to-definition-handler`
**Planning Reference**: `notes/planning/tooling/phase-03-tools.md` (Section 3.4.2)

## Summary

Completed the remaining handler implementation tasks for the `go_to_definition` tool:
- Output path validation (security) - Task 3.4.2.5
- Multiple definitions handling - Task 3.4.2.6

## Completed Tasks

### 3.4.2.5 Validate OUTPUT Path from LSP Response (Security)

Added comprehensive output path validation to ensure LSP-returned paths are safe:

**Functions Added to `JidoCode.Tools.Handlers.LSP`:**

1. `validate_output_path/2` - Validates and sanitizes a single output path:
   - Within project_root → Returns relative path (e.g., `"lib/my_module.ex"`)
   - In deps/ or _build/ → Returns relative path (read-only access)
   - In Elixir stdlib → Returns sanitized indicator (e.g., `"elixir:File"`)
   - In Erlang/OTP → Returns sanitized indicator (e.g., `"erlang:file"`)
   - Outside all boundaries → Returns `{:error, :external_path}` without revealing actual path

2. `validate_output_paths/2` - Validates multiple paths and filters out invalid ones

**Security Features:**
- Path detection for Elixir stdlib (asdf, kiex, system installations)
- Path detection for Erlang/OTP
- External paths are logged with truncated form (max 30 chars) to avoid information disclosure
- Nil paths handled gracefully

### 3.4.2.6 Handle Multiple Definitions

Added `process_lsp_definition_response/2` to handle LSP responses:

**Response Handling:**
- `nil` → `{:error, :definition_not_found}`
- Empty array → `{:error, :definition_not_found}`
- Single Location → Returns with `"definition"` key
- Array of Locations → Returns with `"definitions"` key (after filtering external paths)

**Response Format:**

```elixir
# Single definition
%{
  "status" => "found",
  "definition" => %{
    "path" => "lib/my_module.ex",
    "line" => 15,
    "character" => 3
  }
}

# Multiple definitions
%{
  "status" => "found",
  "definitions" => [
    %{"path" => "lib/impl_a.ex", "line" => 10, "character" => 3},
    %{"path" => "lib/impl_b.ex", "line" => 20, "character" => 3}
  ]
}

# Stdlib definition
%{
  "status" => "found",
  "definition" => %{
    "path" => "elixir:File",
    "line" => nil,
    "character" => nil,
    "note" => "Definition is in standard library"
  }
}
```

**Position Handling:**
- Converts LSP 0-indexed positions to 1-indexed (editor conventions)
- Handles `file://` URI format from LSP servers

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/handlers/lsp.ex` | Added output path validation functions and LSP response processing |
| `test/jido_code/tools/definitions/lsp_test.exs` | Added 15 new tests for output path validation and response processing |

## Tests Added

### Output Path Validation (8 tests)
- Returns relative path for project files
- Returns relative path for deps files
- Returns relative path for _build files
- Sanitizes Elixir stdlib paths
- Sanitizes Erlang OTP paths
- Returns error for external paths without revealing path
- Returns error for nil path
- Validates multiple output paths

### LSP Response Processing (7 tests)
- Processes nil response as not found
- Processes empty array as not found
- Processes single definition
- Processes multiple definitions
- Filters out external paths from multiple definitions
- Returns not found when all definitions are external
- Handles stdlib definitions

## Test Results

```
40 tests, 0 failures
```

All tests pass including:
- 25 existing tests from 3.4.1
- 15 new tests for 3.4.2

## Architecture Notes

- Output path validation is implemented in the parent `LSPHandlers` module for reuse by other LSP tools
- `process_lsp_definition_response/2` is implemented in `GoToDefinition` handler as it's specific to that operation
- External paths are never exposed to the LLM - they are either filtered out or logged with truncated form
- Stdlib paths use a consistent format: `"elixir:ModuleName"` or `"erlang:module_name"`

## Phase 3.6 Integration

These functions are designed for Phase 3.6 LSP client integration:

```elixir
# When LSP client is implemented, the handler will call:
case LSPClient.definition(path, line, character) do
  {:ok, lsp_response} ->
    GoToDefinition.process_lsp_definition_response(lsp_response, context)
  {:error, reason} ->
    {:error, format_error(reason, path)}
end
```

## Next Steps

- Task 3.5: Implement find_references tool
- Phase 3.6: LSP client infrastructure for actual LSP server integration
