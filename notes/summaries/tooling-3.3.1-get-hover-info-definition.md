# Task 3.3.1: Get Hover Info Tool Definition

**Status**: Complete
**Branch**: `feature/3.3.1-get-hover-info-definition`
**Plan Reference**: `notes/planning/tooling/phase-03-tools.md` - Section 3.3.1

## Summary

Implemented the `get_hover_info` LSP tool definition following the Handler pattern established in Phase 2. This tool provides type information and documentation at a specific cursor position in source files.

## Changes Made

### New Files

1. **`lib/jido_code/tools/definitions/lsp.ex`**
   - New module `JidoCode.Tools.Definitions.LSP`
   - Comprehensive module documentation
   - `get_hover_info/0` function returning `Tool.t()` with three required parameters
   - `all/0` function for batch registration

2. **`lib/jido_code/tools/handlers/lsp.ex`**
   - New module `JidoCode.Tools.Handlers.LSP` with shared helpers
   - Contains `GetHoverInfo` handler module
   - Path validation via `HandlerHelpers.validate_path/2`
   - Telemetry integration for observability
   - Error formatting for various failure modes
   - Placeholder response until LSP client infrastructure (Phase 3.6) is implemented

3. **`test/jido_code/tools/definitions/lsp_test.exs`**
   - 13 test cases covering:
     - Tool struct validation
     - Parameter schemas (path, line, character)
     - LLM format conversion
     - Executor integration for Elixir and non-Elixir files
     - Security tests (path traversal, absolute paths)
     - Session-aware context handling
     - Argument validation

## Tool Schema

```elixir
%Tool{
  name: "get_hover_info",
  description: "Get type information and documentation at a cursor position...",
  handler: JidoCode.Tools.Handlers.LSP.GetHoverInfo,
  parameters: [
    %{name: "path", type: :string, required: true, description: "File path to query..."},
    %{name: "line", type: :integer, required: true, description: "Line number (1-indexed)"},
    %{name: "character", type: :integer, required: true, description: "Character offset (1-indexed)"}
  ]
}
```

## Test Results

```
13 tests, 0 failures
```

All tests pass including:
- Schema and LLM format validation
- Executor integration tests
- Security boundary enforcement
- Session-aware context support

## Architecture Notes

This tool uses the Handler pattern established in Phase 2:

```
LLM Tool Call → Tool Executor → Handler.execute/2 → Security.validate_path → Result
```

The handler currently returns a placeholder response:
- `lsp_not_configured` for Elixir files (`.ex`, `.exs`)
- `unsupported_file_type` for other file types

Full LSP integration will be implemented in Phase 3.6 when the LSP client infrastructure is built.

### Key Design Decisions

1. **1-indexed positions**: Line and character positions use 1-indexed values to match editor display (consistent with Claude Code's LSP tool)
2. **Handler pattern**: Uses direct Elixir execution via handler modules rather than Lua sandbox
3. **Session-aware**: Supports both `session_id` and `project_root` context modes
4. **Telemetry**: Emits telemetry events for observability

## Next Steps

- Task 3.3.2: Additional LSP tools (go_to_definition, find_references)
- Phase 3.6: LSP client infrastructure for actual ElixirLS/Lexical integration
