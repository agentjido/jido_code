# Task 3.5.1 - Find References Tool Definition

**Status**: Complete
**Branch**: `feature/3.5.1-find-references-tool`
**Planning Reference**: `notes/planning/tooling/phase-03-tools.md` (Section 3.5.1)

## Summary

Implemented the `find_references` tool definition and handler for finding all usages of a symbol across the codebase. The tool follows the established Handler pattern from Phase 2 and Section 3.4.

## Completed Tasks

### 3.5.1.1 Tool Definition

Added `find_references/0` function to `lib/jido_code/tools/definitions/lsp.ex`:

```elixir
def find_references do
  Tool.new!(%{
    name: "find_references",
    description: "Find all usages of a symbol...",
    handler: Handlers.FindReferences,
    parameters: [
      %{name: "path", type: :string, required: true},
      %{name: "line", type: :integer, required: true},
      %{name: "character", type: :integer, required: true},
      %{name: "include_declaration", type: :boolean, required: false}
    ]
  })
end
```

### 3.5.1.2 Schema

The tool schema includes 4 parameters:
- `path` (required) - File path relative to project root
- `line` (required) - Line number (1-indexed)
- `character` (required) - Character offset (1-indexed)
- `include_declaration` (optional) - Include declaration in results (default: false)

### 3.5.1.3 Updated LSP.all/0

Updated to return all three LSP tools:
```elixir
def all do
  [
    get_hover_info(),
    go_to_definition(),
    find_references()
  ]
end
```

### 3.5.1.4 FindReferences Handler

Created `JidoCode.Tools.Handlers.LSP.FindReferences` module with:

**Execute Function:**
- Uses shared helpers from parent LSP module
- Validates path, line, and character parameters
- Handles optional `include_declaration` parameter
- Emits telemetry for `:find_references` operation

**LSP Response Processing:**
- `process_lsp_references_response/2` for Phase 3.6 integration
- Filters out external paths (security)
- Filters out stdlib/OTP paths (not useful for references)
- Returns count and array of reference locations

**Response Format:**
```elixir
%{
  "status" => "found",
  "references" => [
    %{"path" => "lib/caller_a.ex", "line" => 10, "character" => 5},
    %{"path" => "lib/caller_b.ex", "line" => 22, "character" => 15}
  ],
  "count" => 2
}
```

**Security Features:**
- Input path validation via `HandlerHelpers.validate_path/2`
- Output path filtering (project-local paths only)
- Stdlib/OTP paths excluded from results (unlike go_to_definition)
- External paths filtered without revealing actual paths

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/definitions/lsp.ex` | Added `find_references/0` function (+80 lines) |
| `lib/jido_code/tools/handlers/lsp.ex` | Added `FindReferences` handler (+240 lines), `:no_references_found` error format |
| `test/jido_code/tools/definitions/lsp_test.exs` | Added 21 new tests (+420 lines) |
| `notes/planning/tooling/phase-03-tools.md` | Marked 3.5.1 tasks as complete |

## Tests Added

### Schema & Format (2 tests)
- Tool definition has correct schema (including include_declaration param)
- Generates valid LLM function format

### Executor Integration (9 tests)
- Works via executor for Elixir files
- Handles non-Elixir files (unsupported_file_type)
- Returns error for non-existent file
- Validates required arguments
- Validates line number (must be >= 1)
- Validates character number (must be >= 1)
- include_declaration defaults to false
- Respects include_declaration=true
- Results can be converted to LLM messages

### Security (2 tests)
- Blocks path traversal in input
- Blocks absolute paths outside project

### Session (1 test)
- Session-aware context uses session_id when provided

### LSP Response Processing (7 tests)
- Processes nil response as no references found
- Processes empty array as no references found
- Processes multiple references
- Filters out external paths from references
- Filters out stdlib paths from references
- Returns no references when all are external or stdlib
- Includes deps paths in references

## Test Results

```
78 tests, 0 failures
```

**Test counts:**
- Previous: 57 tests
- Added: 21 tests
- Total: 78 tests

## Architecture Notes

- Handler follows established pattern from get_hover_info and go_to_definition
- Uses shared parameter extraction functions from parent LSP module
- `include_declaration` parameter handled with string/boolean parsing for flexibility
- Output path filtering is stricter than go_to_definition (no stdlib in results)
- Phase 3.6 ready with `process_lsp_references_response/2`

## Key Differences from go_to_definition

| Aspect | go_to_definition | find_references |
|--------|------------------|-----------------|
| Stdlib in output | Yes (as "elixir:Module") | No (filtered out) |
| Response key | `definition` or `definitions` | `references` |
| Count included | No | Yes (`count` field) |
| Optional param | None | `include_declaration` |

## Next Steps

- Section 3.5.2: Handler implementation tasks (most already done in this task)
- Section 3.5.4: Additional unit tests (core tests implemented)
- Phase 3.6: LSP client infrastructure for actual LSP server integration
