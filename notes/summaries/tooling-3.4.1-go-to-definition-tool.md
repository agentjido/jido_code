# Task 3.4.1 - Go To Definition Tool Definition

**Status**: Complete
**Branch**: `feature/3.4.1-go-to-definition-tool`
**Planning Reference**: `notes/planning/tooling/phase-03-tools.md` (Section 3.4.1)

## Summary

Implemented the `go_to_definition` LSP tool following the Handler pattern established in section 3.3. This tool allows navigation to symbol definitions by returning file path and position.

## Completed Tasks

### 3.4.1.1 Add go_to_definition/0 to definitions/lsp.ex

Added the tool definition function with:
- Name: `"go_to_definition"`
- Description: Find where a symbol is defined
- Handler: `Handlers.GoToDefinition`
- Parameters: path (string), line (integer), character (integer)

### 3.4.1.2 Define schema (path, line, character)

Same parameter schema as `get_hover_info`:
- `path` - File path to query (relative to project root)
- `line` - Line number (1-indexed, as shown in editors)
- `character` - Character offset in the line (1-indexed)

### 3.4.1.3 Update LSP.all/0 to include go_to_definition()

Updated `all/0` to return both LSP tools:
```elixir
def all do
  [
    get_hover_info(),
    go_to_definition()
  ]
end
```

### 3.4.1.4 Create GoToDefinition handler in handlers/lsp.ex

Created handler module `JidoCode.Tools.Handlers.LSP.GoToDefinition` with:
- `execute/2` function following Handler pattern
- Parameter extraction (path, line, character)
- File validation
- Path security validation via `HandlerHelpers.validate_path/2`
- Telemetry emission for `:go_to_definition` operation
- Placeholder LSP integration (awaiting Phase 3.6)

Also added `format_error(:definition_not_found, path)` clause to parent LSP module.

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/definitions/lsp.ex` | Added `go_to_definition/0`, updated `all/0` |
| `lib/jido_code/tools/handlers/lsp.ex` | Added `GoToDefinition` handler module, added `format_error` clause |
| `test/jido_code/tools/definitions/lsp_test.exs` | Added 12 tests for go_to_definition |

## Tests Added

### Schema & Format (2 tests)
- `go_to_definition/0 definition has correct schema`
- `go_to_definition/0 definition generates valid LLM function format`

### Executor Integration (5 tests)
- `go_to_definition works via executor for Elixir files`
- `go_to_definition handles non-Elixir files`
- `go_to_definition returns error for non-existent file`
- `go_to_definition validates required arguments`
- `go_to_definition results can be converted to LLM messages`

### Parameter Validation (2 tests)
- `go_to_definition validates line number`
- `go_to_definition validates character number`

### Security (2 tests)
- `go_to_definition blocks path traversal`
- `go_to_definition blocks absolute paths outside project`

### Session & LLM (1 test)
- `go_to_definition session-aware context uses session_id when provided`

## Test Results

```
25 tests, 0 failures
```

All tests pass including the 12 new go_to_definition tests and 13 existing get_hover_info tests.

## Architecture Notes

- Uses Handler pattern (not Lua sandbox) per architectural decision in 3.3.2
- Handler executes via `Tools.Executor` directly
- Session-aware path validation via `HandlerHelpers.validate_path/2`
- Telemetry emitted to `[:jido_code, :lsp, :go_to_definition]`
- Returns `{:ok, map()}` or `{:error, String.t()}`
- Placeholder response until LSP client infrastructure (Phase 3.6) is implemented

## Next Steps

- Task 3.4.2: Handler implementation details (output path validation, multiple definitions)
- Phase 3.6: LSP client infrastructure for actual LSP server integration
