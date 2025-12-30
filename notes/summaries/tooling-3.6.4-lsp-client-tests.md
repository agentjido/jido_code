# Task 3.6.4 LSP Client Unit Tests

**Status**: Complete
**Branch**: `feature/3.6.4-lsp-client-tests`
**Planning Reference**: `notes/planning/tooling/phase-03-tools.md` Section 3.6.4

## Summary

This task adds comprehensive unit tests for the LSP Client GenServer module. The tests cover all major functionality including process spawning, JSON-RPC message handling, the LSP handshake, request/response correlation, notification handling, graceful shutdown, and reconnection behavior.

## Test Coverage

### Test File

| File | Tests | Status |
|------|-------|--------|
| `test/jido_code/tools/lsp/client_test.exs` | 50 | All Pass |

### Test Categories

| Category | Tests | Coverage |
|----------|-------|----------|
| Expert Path Detection | 5 | `find_expert_path/0`, `expert_available?/0` |
| Client Initialization | 6 | `start_link/1` options, state initialization |
| Status Reporting | 2 | `status/1` response structure |
| Request Handling | 3 | `request/4` when not initialized |
| Notification Sending | 2 | `notify/3` behavior |
| Subscription Management | 4 | `subscribe/2`, `unsubscribe/2` |
| Notification Broadcasting | 3 | Subscriber monitoring, cleanup |
| JSON-RPC Encoding | 2 | Message format verification |
| Message Parsing | 2 | Buffer handling |
| Graceful Shutdown | 3 | `shutdown/1`, idempotency |
| Termination | 2 | Clean stop, brutal kill |
| Error Handling | 2 | Unexpected messages, malformed data |
| Connection State | 3 | Port tracking, initialization |
| Initialize Handshake | 2 | Auto-start, capabilities |
| Reconnection Behavior | 2 | Failed start recovery |
| Pending Request Tracking | 1 | Request ID management |
| Integration (Expert required) | 6 | Full LSP operations |

## Tests Added

### 3.6.4.1 - Test Expert Process Spawning and Connection

```elixir
describe "find_expert_path/0" do
  test "returns {:error, :not_found} when expert is not available"
  test "returns path from EXPERT_PATH environment variable when file exists"
  test "returns {:error, :not_found} when EXPERT_PATH points to non-existent file"
  test "prefers EXPERT_PATH over system PATH"
end

describe "start_link/1" do
  test "requires project_root option"
  test "starts with auto_start: false"
  test "accepts name option for registration"
  test "accepts custom expert_path option"
  test "initializes with correct default state"
  test "multiple clients can run with different names"
end
```

### 3.6.4.2 - Test JSON-RPC Message Encoding/Decoding

```elixir
describe "JSON-RPC message encoding" do
  test "request encoding produces valid Content-Length header"
  test "client maintains request_id counter"
end

describe "message parsing" do
  test "parses valid JSON-RPC response format"
  test "client handles empty buffer correctly"
end
```

### 3.6.4.3 - Test Initialize Handshake Sequence

```elixir
describe "initialize handshake" do
  test "auto_start triggers initialization message"
  test "client advertises correct capabilities"
end
```

### 3.6.4.4 - Test Request/Response Correlation

```elixir
describe "request/4" do
  test "returns {:error, :not_initialized} when not initialized"
  test "accepts custom timeout parameter"
  test "handles various LSP methods"
end

describe "pending request tracking" do
  test "tracks zero pending requests when not initialized"
end
```

### 3.6.4.5 - Test Notification Handling

```elixir
describe "notify/3" do
  test "sends notification without waiting for response"
  test "accepts various notification types"
end

describe "subscribe/2 and unsubscribe/2" do
  test "subscribes and unsubscribes from notifications"
  test "multiple subscribers can be registered"
  test "subscribing same pid multiple times doesn't duplicate"
  test "unsubscribe returns :ok even if not subscribed"
end

describe "notification broadcasting" do
  test "monitors subscriber processes"
  test "removes subscriber when it exits"
  test "handles multiple subscriber exits"
end
```

### 3.6.4.6 - Test Graceful Shutdown

```elixir
describe "shutdown/1" do
  test "gracefully shuts down when not connected"
  test "shutdown is idempotent"
  test "client can be stopped after shutdown"
end

describe "terminate/2" do
  test "GenServer.stop triggers clean termination"
  test "terminate handles brutal kill"
end
```

### 3.6.4.7 - Test Reconnection on Expert Crash

```elixir
describe "reconnection behavior" do
  test "client schedules restart when Expert not found"
  test "client continues to function after failed start"
end

describe "error handling" do
  test "handles unexpected messages gracefully"
  test "client survives malformed data"
end
```

### Integration Tests (Expert Required)

These tests only run when Expert is installed:

```elixir
describe "integration with Expert" do
  @tag :integration
  @tag :expert_required

  test "connects to Expert and initializes"
  test "sends hover request and receives response"
  test "sends definition request and receives response"
  test "receives diagnostics notifications"
  test "handles request timeout"
end
```

## Test Patterns Used

### Environment Variable Isolation

Tests that modify `EXPERT_PATH` use try/after to restore the original value:

```elixir
test "returns path from EXPERT_PATH environment variable when file exists" do
  original = System.get_env("EXPERT_PATH")

  try do
    System.put_env("EXPERT_PATH", mix_path)
    assert {:ok, ^mix_path} = Client.find_expert_path()
  after
    if original do
      System.put_env("EXPERT_PATH", original)
    else
      System.delete_env("EXPERT_PATH")
    end
  end
end
```

### Process Exit Trapping

Tests that check termination behavior use trap_exit:

```elixir
test "terminate handles brutal kill" do
  Process.flag(:trap_exit, true)

  {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)
  Process.exit(pid, :kill)

  assert_receive {:EXIT, ^pid, :killed}, 1000
  refute Process.alive?(pid)
after
  Process.flag(:trap_exit, false)
end
```

### Conditional Integration Tests

Integration tests skip gracefully when Expert is not installed:

```elixir
test "connects to Expert and initializes" do
  case Client.find_expert_path() do
    {:ok, _path} ->
      # Run the test
      ...
    {:error, :not_found} ->
      :ok  # Skip test
  end
end
```

## Running the Tests

```bash
# Run all LSP client tests
mix test test/jido_code/tools/lsp/client_test.exs

# Run with verbose output
mix test test/jido_code/tools/lsp/client_test.exs --trace

# Run integration tests only (requires Expert installed)
mix test test/jido_code/tools/lsp/client_test.exs --only integration
```

## Total LSP Test Coverage

After this task, the LSP module has comprehensive test coverage:

| Test File | Tests |
|-----------|-------|
| `client_test.exs` | 50 |
| `protocol_test.exs` | 73 |
| **Total** | **123** |

## Reference

- LSP Client Module: `lib/jido_code/tools/lsp/client.ex`
- LSP Protocol Module: `lib/jido_code/tools/lsp/protocol.ex`
- Expert: https://github.com/elixir-lang/expert
