# Task 3.6.3 Handler Integration

**Status**: Complete
**Branch**: `feature/3.6.3-handler-integration`
**Planning Reference**: `notes/planning/tooling/phase-03-tools.md` Section 3.6.3

## Summary

This task integrates the Expert LSP client with the existing LSP handlers (GetHoverInfo, GoToDefinition, FindReferences). The handlers now communicate with Expert when available, properly converting between 1-indexed editor positions and 0-indexed LSP positions.

## Implementation

### New Files

| File | Purpose |
|------|---------|
| `lib/jido_code/tools/lsp/supervisor.ex` | DynamicSupervisor for per-project LSP clients |

### Modified Files

| File | Changes |
|------|---------|
| `lib/jido_code/tools/handlers/lsp.ex` | Added Expert integration to all three handlers |
| `test/jido_code/tools/definitions/lsp_test.exs` | Updated tests for new status values |

### Key Features

#### 1. LSP Client Supervisor

Created a DynamicSupervisor to manage per-project LSP clients:

```elixir
# Get or start a client for a project
{:ok, client} = LSP.Supervisor.get_or_start_client("/path/to/project")

# Check if client exists
LSP.Supervisor.client_exists?("/path/to/project")

# Stop a client
LSP.Supervisor.stop_client("/path/to/project")

# Check if Expert is available
LSP.Supervisor.expert_available?()
```

Each project gets its own client with a unique name based on a hash of the project root.

#### 2. Handler Integration Pattern

All three handlers now follow the same pattern:

```elixir
defp get_hover_info(path, line, character, context) do
  if LSPHandlers.elixir_file?(path) do
    case LSPHandlers.get_lsp_client(context) do
      {:ok, client} ->
        request_hover_from_expert(client, path, line, character)
      {:error, :lsp_not_available} ->
        lsp_not_available_response(path, line, character)
    end
  else
    {:ok, %{"status" => "unsupported_file_type", ...}}
  end
end
```

#### 3. Position Conversion

The Protocol module handles 1-indexed (editor) to 0-indexed (LSP) conversion:

```elixir
# Input: line=10, character=5 (1-indexed, as displayed in editors)
# Output: LSP params with line=9, character=4 (0-indexed)
params = Protocol.hover_params(path, line, character)
params = Protocol.definition_params(path, line, character)
params = Protocol.references_params(path, line, character, include_declaration: true)
```

The response parsing already converts back to 1-indexed positions.

#### 4. Response Handling

Each handler processes Expert responses appropriately:

| Handler | Expert Response | Handler Result |
|---------|-----------------|----------------|
| GetHoverInfo | `null` | `{"status" => "no_info", ...}` |
| GetHoverInfo | `{contents, range}` | `{"status" => "found", "content" => ..., ...}` |
| GoToDefinition | `null` | `{"status" => "not_found", ...}` |
| GoToDefinition | `Location` or `[Location]` | `{"status" => "found", "definition" => ...}` |
| FindReferences | `null` or `[]` | `{"status" => "no_references", ...}` |
| FindReferences | `[Location, ...]` | `{"status" => "found", "references" => [...], "count" => N}` |

#### 5. Error Handling

Handlers gracefully handle various error conditions:

| Condition | Status | Message |
|-----------|--------|---------|
| Expert not installed | `lsp_not_available` | Install instructions with link |
| Request timeout | Error result | "LSP request timed out" |
| Client error | Error result | Log warning, return error |
| Non-Elixir file | `unsupported_file_type` | Informative message |

### Helper Function

Added `get_lsp_client/1` to the parent LSP module:

```elixir
@spec get_lsp_client(map()) :: {:ok, pid()} | {:error, :lsp_not_available}
def get_lsp_client(context) do
  with {:ok, project_root} <- get_project_root(context),
       {:ok, client} <- Supervisor.get_or_start_client(project_root) do
    # Wait for initialization if needed
    case Client.status(client) do
      %{initialized: true} -> {:ok, client}
      %{initialized: false} ->
        Process.sleep(500)
        case Client.status(client) do
          %{initialized: true} -> {:ok, client}
          _ -> {:error, :lsp_not_available}
        end
    end
  else
    {:error, :expert_not_available} -> {:error, :lsp_not_available}
    {:error, _reason} -> {:error, :lsp_not_available}
  end
end
```

## Test Updates

Updated 3 tests to expect `lsp_not_available` instead of `lsp_not_configured`:

| Test | Old Status | New Status |
|------|------------|------------|
| get_hover_info works via executor | `lsp_not_configured` | `lsp_not_available` |
| go_to_definition works via executor | `lsp_not_configured` | `lsp_not_available` |
| find_references works via executor | `lsp_not_configured` | `lsp_not_available` |

All 179 LSP-related tests pass.

## Architecture

### Component Interaction

```
Handler.execute/2
    │
    ├─ extract params (path, line, character)
    ├─ validate path
    ├─ check if Elixir file
    │
    ▼
get_lsp_client(context)
    │
    ├─ get_project_root(context)
    │       │
    │       ▼
    │   Supervisor.get_or_start_client(root)
    │       │
    │       ├─ Process.whereis(client_name)
    │       │   ├─ nil → start_client()
    │       │   └─ pid → {:ok, pid}
    │       │
    │       ▼
    │   Client.status(client)
    │       │
    │       ├─ initialized: true → {:ok, client}
    │       └─ initialized: false → wait and retry
    │
    ▼
request_*_from_expert(client, path, line, character)
    │
    ├─ Protocol.*_params() - converts positions
    ├─ Client.request(client, method, params)
    │
    ▼
process_*_response()
    │
    └─ Format result for handler return
```

### Supervisor Structure

```
Application Supervisor
    │
    └─ LSP.Supervisor (DynamicSupervisor)
           │
           ├─ LSP.Client (project_a) [lsp_client_123456]
           ├─ LSP.Client (project_b) [lsp_client_789012]
           └─ ...
```

## Subtasks Completed

| Task | Description | Status |
|------|-------------|--------|
| 3.6.3.1 | Update GetHoverInfo to call Expert via client | Complete |
| 3.6.3.2 | Update GoToDefinition to call Expert via client | Complete |
| 3.6.3.3 | Update FindReferences to call Expert via client | Complete |
| 3.6.3.4 | Convert 1-indexed positions to 0-indexed | Complete |
| 3.6.3.5 | Parse Expert responses into handler result format | Complete |

## Reference

- Expert: https://github.com/elixir-lang/expert
- LSP Specification: https://microsoft.github.io/language-server-protocol/
- Protocol Types: `lib/jido_code/tools/lsp/protocol.ex`
- Client Module: `lib/jido_code/tools/lsp/client.ex`
