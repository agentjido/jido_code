# Task 3.6.1 Expert Connection Module

**Status**: Complete
**Branch**: `feature/3.6.1-expert-client`
**Planning Reference**: `notes/planning/tooling/phase-03-tools.md` Section 3.6.1

## Summary

This task implements the LSP client GenServer that connects to Expert, the official Elixir Language Server. The client handles all communication with Expert via stdio, including JSON-RPC message framing, the LSP handshake, and request/response correlation.

## Implementation

### New Files

| File | Purpose |
|------|---------|
| `lib/jido_code/tools/lsp/client.ex` | GenServer managing Expert connection |
| `test/jido_code/tools/lsp/client_test.exs` | Unit tests (16 tests) |

### Key Features

#### 1. Expert Process Management
- Spawns Expert with `--stdio` flag
- Sets working directory to project root
- Handles process crashes with automatic restart (1 second delay)
- Graceful shutdown via LSP shutdown/exit sequence

#### 2. JSON-RPC Message Framing
- Encodes messages with `Content-Length` headers
- Parses incoming messages by extracting Content-Length and reading body
- Handles partial messages via buffer accumulation

#### 3. LSP Handshake
- Sends `initialize` request with client capabilities
- Handles `initialize` response to extract server capabilities
- Sends `initialized` notification to complete handshake

#### 4. Request/Response Correlation
- Assigns unique integer IDs to each request
- Maintains pending requests map for response matching
- Supports configurable timeout (default 30 seconds)

#### 5. Notification Handling
- Subscriber pattern for receiving LSP notifications
- Monitors subscriber processes for cleanup on exit
- Broadcasts notifications to all subscribers

### Client API

```elixir
# Start the client
{:ok, pid} = Client.start_link(project_root: "/path/to/project")

# Check if Expert is available
Client.expert_available?()

# Send LSP request
{:ok, result} = Client.request(pid, "textDocument/hover", %{
  "textDocument" => %{"uri" => "file:///path/to/file.ex"},
  "position" => %{"line" => 10, "character" => 5}
})

# Send LSP notification
:ok = Client.notify(pid, "textDocument/didOpen", %{...})

# Subscribe to notifications
:ok = Client.subscribe(pid, self())

# Get client status
status = Client.status(pid)

# Graceful shutdown
:ok = Client.shutdown(pid)
```

### Expert Discovery

The client looks for Expert in:
1. `EXPERT_PATH` environment variable
2. `expert` in system PATH

### Client Capabilities Advertised

```elixir
%{
  "textDocument" => %{
    "hover" => %{"contentFormat" => ["markdown", "plaintext"]},
    "definition" => %{"linkSupport" => true},
    "references" => %{},
    "publishDiagnostics" => %{"relatedInformation" => true},
    "synchronization" => %{"didSave" => true}
  },
  "workspace" => %{"workspaceFolders" => true}
}
```

## Test Coverage

| Category | Tests | Status |
|----------|-------|--------|
| Expert path detection | 4 | Pass |
| Client initialization | 3 | Pass |
| Status reporting | 1 | Pass |
| Request handling | 1 | Pass |
| Subscription | 1 | Pass |
| Message encoding | 1 | Pass |
| Message parsing | 1 | Pass |
| Shutdown | 1 | Pass |
| Notification broadcasting | 1 | Pass |
| Integration (Expert required) | 2 | Skipped if Expert not installed |
| **Total** | **16** | **All Pass** |

## Architecture Notes

### State Structure

```elixir
%{
  port: port() | nil,           # Port to Expert process
  project_root: String.t(),     # Project root directory
  request_id: integer(),        # Next request ID
  pending_requests: map(),      # ID => {from, ref, method}
  buffer: binary(),             # Partial message buffer
  initialized: boolean(),       # LSP handshake complete
  capabilities: map(),          # Server capabilities
  subscribers: [pid()],         # Notification subscribers
  expert_path: String.t() | nil # Custom Expert path
}
```

### Message Flow

```
JidoCode Handler → Client.request/3
         │
         ▼
   GenServer call
         │
         ▼
   send_request/4
         │
         ▼
   encode_request/3 → JSON-RPC with Content-Length
         │
         ▼
   Port.command/2 → Expert (stdio)
         │
         ▼
   handle_info({port, {:data, data}})
         │
         ▼
   parse_messages/2 → Extract JSON-RPC
         │
         ▼
   handle_message/2 → Match request ID
         │
         ▼
   GenServer.reply/2 → {:ok, result}
```

## Next Steps

Section 3.6.2 (LSP Protocol Types) and 3.6.3 (Handler Integration) will:
- Define typed structs for LSP messages
- Update existing handlers to use this client
- Handle 1-indexed to 0-indexed position conversion

## Reference

- Expert: https://github.com/elixir-lang/expert
- LSP Specification: https://microsoft.github.io/language-server-protocol/
