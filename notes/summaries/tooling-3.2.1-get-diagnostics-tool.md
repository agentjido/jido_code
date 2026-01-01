# Summary: Get Diagnostics Tool Implementation (3.2.1)

## Overview

Implementation of the `get_diagnostics` tool for retrieving LSP diagnostics (errors, warnings, info, hints) for a specific file or the entire workspace.

**Architecture Decision:** Uses Handler pattern (not Lua sandbox) consistent with other LSP tools (get_hover_info, go_to_definition, find_references) per Section 3.3.2.

## Files Created/Modified

### New Files

1. **`lib/jido_code/tools/definitions/get_diagnostics.ex`**
   - Tool definition with schema
   - Three optional parameters: `path`, `severity`, `limit`
   - Severity enum: `["error", "warning", "info", "hint"]`
   - Helper functions: `valid_severities/0`, `valid_severity?/1`

### Modified Files

1. **`lib/jido_code/tools/handlers/lsp.ex`**
   - Added `GetDiagnostics` handler module at end of file
   - Handler includes parameter validation, LSP client integration, diagnostic processing
   - Filtering by severity and path
   - Limit application with truncation flag
   - Telemetry emission

2. **`lib/jido_code/tools/definitions/lsp.ex`**
   - Added `get_diagnostics/0` delegating to `GetDiagnostics` module
   - Updated `all/0` to include `get_diagnostics()`
   - Updated moduledoc to list `get_diagnostics` tool

3. **`lib/jido_code/tools/lsp/client.ex`**
   - Added `diagnostics` map to state for caching
   - Added `get_diagnostics/2` public API function
   - Added `clear_diagnostics/2` public API function
   - Added `handle_notification/3` for `textDocument/publishDiagnostics`
   - Added helper functions: `get_diagnostics_from_state/2`, `path_to_uri/2`

4. **`lib/jido_code/tools.ex`**
   - Added `Definitions.LSP.all()` to `register_all/0`

5. **`test/jido_code/tools/definitions/lsp_test.exs`**
   - Updated `all/0` test to expect 4 tools
   - Added 15 new tests for get_diagnostics:
     - Schema and LLM format tests
     - Executor integration tests
     - Parameter validation tests
     - Security tests
     - Session-aware context tests
     - Edge case tests

## Implementation Details

### Handler Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                           │
│  e.g., {"name": "get_diagnostics", "arguments": {...}}          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Handler.execute(params, context)                               │
│  - Validate parameters (severity, limit, optional path)         │
│  - Get LSP client via get_lsp_client/1                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  LSP Client.get_diagnostics(client, path)                       │
│  - Returns cached diagnostics from publishDiagnostics           │
│  - Filters by path if specified                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Process and format diagnostics                                 │
│  - Filter by severity                                           │
│  - Apply limit with truncation flag                             │
│  - Sort by severity priority                                    │
└─────────────────────────────────────────────────────────────────┘
```

### Diagnostic Caching

LSP diagnostics are received as `textDocument/publishDiagnostics` notifications from the language server. The Client caches these in its state:

```elixir
# State includes diagnostics map
state = %{
  ...
  diagnostics: %{
    "file:///path/to/file.ex" => [%{...}, %{...}],
    ...
  }
}
```

When `Client.get_diagnostics/2` is called, it returns the cached diagnostics filtered by path if specified.

### Response Format

```elixir
%{
  "diagnostics" => [
    %{
      "severity" => "error",
      "file" => "lib/my_module.ex",
      "line" => 10,
      "column" => 5,
      "message" => "undefined function foo/0",
      "code" => "undefined_function",  # optional
      "source" => "elixir"             # optional
    }
  ],
  "count" => 1,
  "truncated" => false
}
```

When LSP is not available:
```elixir
%{
  "status" => "lsp_not_configured",
  "diagnostics" => [],
  "count" => 0,
  "truncated" => false,
  "message" => "LSP server is not available..."
}
```

### Security Considerations

1. **Input path validation** - Uses `HandlerHelpers.validate_path/2` for session-aware validation
2. **Output path filtering** - Uses `validate_output_path/2` to filter external paths from results
3. **No path exposure** - External paths are filtered, not exposed in error messages

## Tests

Added 15 tests in `test/jido_code/tools/definitions/lsp_test.exs`:

| Test Category | Count |
|---------------|-------|
| Schema & Format | 2 |
| Executor Integration | 5 |
| Parameter Validation | 4 |
| Security | 2 |
| Session & LLM | 2 |

Total LSP tests: 107 (up from 92)

## Future Work

1. **Phase 3.7 Integration Tests** - Test with actual Expert LSP server
2. **Diagnostic Sources** - Handle diagnostics from multiple sources (Elixir compiler, Credo, Dialyzer)
3. **Workspace Diagnostics** - Implement `workspace/diagnostic` request for on-demand refresh
