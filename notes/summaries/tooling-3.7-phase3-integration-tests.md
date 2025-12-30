# Task 3.7 Phase 3 Integration Tests

**Status**: Complete
**Branch**: `feature/3.7-phase3-integration-tests`
**Planning Reference**: `notes/planning/tooling/phase-03-tools.md` Section 3.7

## Summary

This task implements integration tests for Phase 3 LSP tools. The tests verify that LSP tools work correctly through the Executor → Handler chain with proper security boundary enforcement and session-scoped context isolation.

## Test Coverage

### Test File

| File | Tests | Status |
|------|-------|--------|
| `test/jido_code/integration/tools_phase3_test.exs` | 24 | All Pass |

### Test Categories

| Category | Tests | Description |
|----------|-------|-------------|
| Executor → Handler Chain | 3 | LSP tools execute through correct execution path |
| Session Context Isolation | 3 | Each session uses its own project directory |
| Hover Info Integration | 3 | get_hover_info handler tests |
| Go To Definition Integration | 2 | go_to_definition handler tests |
| Find References Integration | 3 | find_references handler tests |
| Output Path Security | 3 | Path validation and traversal prevention |
| Expert Integration | 3 | Tests requiring Expert (skipped if not installed) |
| Parameter Validation | 4 | Required parameter and type validation |

## Tests Implemented

### 3.7.1.3 - LSP Tools Execute Through Executor → Handler Chain

```elixir
describe "Executor → Handler chain execution for LSP tools" do
  test "get_hover_info executes through Executor and returns result"
  test "go_to_definition executes through Executor and returns result"
  test "find_references executes through Executor and returns result"
end
```

### 3.7.1.4 - Session-Scoped Context Isolation

```elixir
describe "session-scoped context isolation for LSP tools" do
  test "get_hover_info uses session's project directory"
  test "LSP tools reject paths outside session project"
  test "go_to_definition respects session project boundary"
end
```

### 3.7.3.3 & 3.7.3.4 - Hover Info Integration

```elixir
describe "LSP handler integration - hover info" do
  test "get_hover_info for Elixir file returns structured response"
  test "get_hover_info for non-Elixir file returns unsupported status"
  test "get_hover_info for nonexistent file returns error"
end
```

### 3.7.3.5 - Go To Definition Integration

```elixir
describe "LSP handler integration - go to definition" do
  test "go_to_definition for Elixir file returns structured response"
  test "go_to_definition for non-Elixir file returns unsupported status"
end
```

### 3.7.3.6 - Find References Integration

```elixir
describe "LSP handler integration - find references" do
  test "find_references for Elixir file returns structured response"
  test "find_references with include_declaration option"
  test "find_references for non-Elixir file returns unsupported status"
end
```

### 3.7.3.7 - Output Path Validation (Security)

```elixir
describe "output path validation and security" do
  test "LSP handlers validate input paths against project boundary"
  test "LSP handlers accept valid project paths"
  test "absolute paths within project are accepted"
end
```

### Expert Integration Tests

```elixir
describe "integration with Expert (when installed)" do
  @tag :expert_required

  test "get_hover_info returns actual hover content when Expert available"
  test "go_to_definition navigates to function definition when Expert available"
  test "find_references locates function usages when Expert available"
end
```

### Parameter Validation Tests

```elixir
describe "parameter validation" do
  test "get_hover_info requires path parameter"
  test "get_hover_info requires line parameter"
  test "get_hover_info requires character parameter"
  test "line and character must be positive integers"
end
```

## Test Pattern

The tests follow the established pattern from `tools_phase2_test.exs`:

```elixir
setup do
  # 1. Start application
  {:ok, _} = Application.ensure_all_started(:jido_code)

  # 2. Wait for SessionSupervisor
  wait_for_supervisor()

  # 3. Clear existing sessions
  SessionRegistry.clear()

  # 4. Create temp directory
  tmp_base = Path.join(System.tmp_dir!(), "phase3_integration_#{:rand.uniform(100_000)}")

  # 5. Register Phase 3 tools
  register_phase3_tools()

  # 6. Cleanup on exit
  on_exit(fn -> ... end)

  {:ok, tmp_base: tmp_base}
end
```

## Security Tests

The tests verify that LSP handlers properly validate input paths:

| Path Type | Expected Behavior |
|-----------|------------------|
| `../../../etc/passwd` | Rejected (path traversal) |
| `../../other_project/secret.ex` | Rejected (escapes boundary) |
| `/etc/passwd` | Rejected (absolute outside project) |
| `/home/user/.ssh/id_rsa` | Rejected (absolute outside project) |
| `lib/module.ex` | Accepted (relative within project) |
| `./lib/module.ex` | Accepted (explicit relative) |
| `/project/path/module.ex` | Accepted (absolute within project) |

## Running the Tests

```bash
# Run all Phase 3 integration tests
mix test test/jido_code/integration/tools_phase3_test.exs

# Run with verbose output
mix test test/jido_code/integration/tools_phase3_test.exs --trace

# Run only Expert integration tests (requires Expert installed)
mix test test/jido_code/integration/tools_phase3_test.exs --only expert_required

# Run Phase 3 tagged tests across all files
mix test --only phase3
```

## Notes

### Git Tools (Section 3.7.2)

Git tools (sections 3.1-3.1.4) are not yet implemented, so git integration tests are not included. These would be added when git_command tool is implemented.

### Expert Integration

When Expert (the official Elixir LSP) is not installed:
- LSP handlers return `{"status": "lsp_not_available", ...}`
- Integration tests that require Expert are tagged with `@tag :expert_required`
- These tests skip gracefully when Expert is not found

### Response Status Values

| Status | Meaning |
|--------|---------|
| `lsp_not_available` | Expert not installed |
| `found` | LSP returned valid result |
| `no_info` | Position has no hover info |
| `not_found` | No definition found |
| `no_references` | No references found |
| `unsupported_file_type` | Not an Elixir file |

## Reference

- Phase 2 Integration Tests: `test/jido_code/integration/tools_phase2_test.exs`
- LSP Handler Tests: `test/jido_code/tools/definitions/lsp_test.exs`
- LSP Client Tests: `test/jido_code/tools/lsp/client_test.exs`
