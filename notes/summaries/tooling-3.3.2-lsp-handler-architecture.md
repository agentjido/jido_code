# Task 3.3.2: LSP Handler Architecture Update

**Status**: Complete
**Branch**: `feature/3.3.2-lsp-hover-bridge-update`
**Plan Reference**: `notes/planning/tooling/phase-03-tools.md` - Section 3.3.2, 3.3.3, 3.3.4

## Summary

Updated the Phase 3 planning document to reflect the architectural decision that LSP tools use the **Handler pattern** (direct Elixir execution) established in Phase 2, rather than the Lua sandbox bridge originally planned.

## Architectural Decision

The original planning document specified Lua bridge functions for LSP tools (e.g., `jido.lsp_hover`). During implementation of task 3.3.1, the Handler pattern was used instead because:

1. **Consistency with Phase 2**: Search and Shell tools successfully use Handler pattern
2. **Better LSP Integration**: Direct Elixir handlers provide easier integration with LSP client infrastructure planned for Phase 3.6
3. **Async/Streaming Support**: Handler pattern simplifies async LSP response handling
4. **Session-Aware Context**: HandlerHelpers already provides session-aware path validation

## Changes Made

### Planning Document Updates

Updated `notes/planning/tooling/phase-03-tools.md`:

1. **Tools Table**: Changed from "Bridge Function" to "Handler/Bridge" column, noting LSP tools use Handler pattern
2. **Task 3.3.2**: Marked as DONE with architectural decision documented
3. **Task 3.3.3**: Marked as N/A (Handler pattern doesn't require Manager API)
4. **Task 3.3.4**: Marked as DONE with list of 13 existing tests

### Key Sections Updated

```markdown
| Tool | Handler/Bridge | Purpose |
|------|----------------|---------|
| git_command | `jido.git(subcommand, args)` | Safe git CLI passthrough |
| get_diagnostics | Handler pattern | LSP error/warning retrieval |
| get_hover_info | Handler pattern | Type and documentation at position |
...

**Note:** LSP tools use the Handler pattern (direct Elixir execution)
established in Phase 2, not the Lua sandbox.
```

## Implementation Status

The `get_hover_info` handler implementation from task 3.3.1 already provides:

| Original Subtask | Status | Implementation |
|-----------------|--------|----------------|
| 3.3.2.1 Lua bridge | Handler | `JidoCode.Tools.Handlers.LSP.GetHoverInfo` |
| 3.3.2.2 Path validation | Done | `HandlerHelpers.validate_path/2` |
| 3.3.2.3 Position conversion | Deferred | Will convert 1→0 indexed in Phase 3.6 |
| 3.3.2.4 LSP server request | Placeholder | Awaiting Phase 3.6 LSP client |
| 3.3.2.5 Response parsing | Structured | Returns status, message, position, hint |
| 3.3.2.6 Markdown formatting | Deferred | Phase 3.6 |
| 3.3.2.7 Return format | Done | `{:ok, map}` / `{:error, string}` |
| 3.3.2.8 Bridge registration | N/A | Handler pattern used |

## Test Coverage

13 tests in `test/jido_code/tools/definitions/lsp_test.exs`:
- Schema and LLM format validation
- Executor integration for Elixir/non-Elixir files
- Parameter validation (path, line, character)
- Security boundary enforcement
- Session-aware context handling

## Next Steps

- Tasks 3.4.x and 3.5.x (go_to_definition, find_references) should also use Handler pattern
- Phase 3.6 will implement the actual LSP client infrastructure
- Consider updating remaining LSP tool plans to reference Handler pattern
