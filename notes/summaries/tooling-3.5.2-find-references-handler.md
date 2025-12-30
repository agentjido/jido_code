# Task 3.5.2 - Find References Handler Implementation

**Status**: Complete
**Branch**: `feature/3.5.2-find-references-handler`
**Planning Reference**: `notes/planning/tooling/phase-03-tools.md` (Section 3.5.2, 3.5.4)

## Summary

Section 3.5.2 (Handler Implementation) and 3.5.4 (Unit Tests) were already fully implemented during the 3.5.1 task. This task marks the formal completion of those sections in the planning document.

## Implementation Details

The FindReferences handler was implemented with all required features during 3.5.1:

### 3.5.2.1 Handler Module

`JidoCode.Tools.Handlers.LSP.FindReferences` provides:

- `execute/2` - Main entry point for tool execution
- `process_lsp_references_response/2` - LSP response processing (Phase 3.6 ready)

### 3.5.2.2 Input Path Validation

Uses shared helpers from parent LSP module:
```elixir
with {:ok, path} <- LSPHandlers.extract_path(params),
     {:ok, line} <- LSPHandlers.extract_line(params),
     {:ok, character} <- LSPHandlers.extract_character(params),
     {:ok, safe_path} <- LSPHandlers.validate_path(path, context),
     :ok <- LSPHandlers.validate_file_exists(safe_path) do
```

### 3.5.2.3 Position Handling

- 1-indexed positions for display (editor convention)
- 0-indexed conversion in `process_lsp_references_response/2` for LSP protocol

### 3.5.2.4 include_declaration Parameter

```elixir
defp extract_include_declaration(%{"include_declaration" => value}) when is_boolean(value) do
  value
end
defp extract_include_declaration(%{"include_declaration" => "true"}), do: true
defp extract_include_declaration(%{"include_declaration" => "false"}), do: false
defp extract_include_declaration(_), do: false
```

### 3.5.2.5 LSP Server Placeholder

Returns structured response until Phase 3.6:
```elixir
%{
  "status" => "lsp_not_configured",
  "message" => "LSP integration is not yet configured...",
  "position" => %{"path" => path, "line" => line, "character" => character},
  "include_declaration" => include_declaration,
  "hint" => "To enable LSP features..."
}
```

### 3.5.2.6 Output Path Security

- Project paths → Relative paths
- deps/ and _build/ → Relative paths
- Stdlib/OTP paths → Filtered out (not exposed)
- External paths → Filtered out (not exposed)

### 3.5.2.7 Response Format

```elixir
{:ok, %{
  "status" => "found",
  "references" => [
    %{"path" => "lib/caller.ex", "line" => 10, "character" => 5}
  ],
  "count" => 1
}}
```

### 3.5.2.8 Telemetry

```elixir
LSPHandlers.emit_lsp_telemetry(:find_references, start_time, path, context, :success)
```

### 3.5.2.9 Error Format

```elixir
def format_error(:no_references_found, path),
  do: "No references found for symbol at this position in: #{path}"
```

## Test Coverage (3.5.4)

All 21 tests for find_references were implemented:

| Category | Tests |
|----------|-------|
| Schema & Format | 2 |
| Executor Integration | 9 |
| Security | 2 |
| Session | 1 |
| LSP Response Processing | 7 |
| **Total** | **21** |

## Files Modified

| File | Changes |
|------|---------|
| `notes/planning/tooling/phase-03-tools.md` | Marked 3.5.2 and 3.5.4 tasks complete |

## Notes

- No code changes were required; all implementation was done in 3.5.1
- This task formalizes the completion of handler and test sections
- Phase 3.6 (LSP Client Infrastructure) will provide actual LSP server integration

## Next Steps

- Phase 3.6: LSP Client Infrastructure for actual LSP server integration
- The `process_lsp_references_response/2` function is ready for Phase 3.6 integration
