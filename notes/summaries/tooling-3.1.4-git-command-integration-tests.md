# Task 3.1.4: Git Command Integration Tests

## Summary

Created comprehensive integration tests for the git_command tool through the Executor/Sandbox flow. Tests verify end-to-end execution from tool call to result parsing.

## Implementation Details

### Test File

`test/jido_code/tools/git_command_integration_test.exs`

**Test Categories (23 tests total):**

1. **Basic Command Execution (4 tests)**
   - `git status` execution and result parsing
   - `git status` showing untracked files
   - `git diff` on clean repo
   - `git diff` showing modified file content

2. **Git Log Tests (2 tests)**
   - `git log` execution with commit history
   - `git log` with format options (`--oneline`, `-1`)

3. **Git Branch Tests (2 tests)**
   - `git branch` listing
   - `git branch <name>` creation

4. **Destructive Operation Blocking (6 tests)**
   - Force push (`--force`, `-f`) blocked by default
   - Force push allowed with `allow_destructive: true`
   - `reset --hard` blocked by default
   - `reset --hard` allowed with `allow_destructive: true`
   - `clean -fd` blocked by default
   - `branch -D` blocked by default

5. **Project Directory Isolation (2 tests)**
   - Commands execute in context `project_root`
   - Different project roots are isolated

6. **Output Parsing (4 tests)**
   - Status output includes `parsed` data
   - Staged files appear in output
   - Diff output parsing
   - File changes tracked correctly

7. **Error Handling (3 tests)**
   - Non-existent ref returns non-zero exit code
   - Invalid subcommand rejected with error
   - Missing required parameters rejected

### Test Setup

```elixir
setup %{tmp_dir: tmp_dir} do
  Application.ensure_all_started(:jido_code)

  # Initialize git repo
  {_, 0} = System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)
  {_, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
  {_, 0} = System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)

  # Register tool
  Registry.clear()
  :ok = Registry.register(GitCommand.git_command())

  exec_opts = [context: %{project_root: tmp_dir}]
  %{tmp_dir: tmp_dir, exec_opts: exec_opts}
end
```

### Key Patterns

**Executor API Usage:**
```elixir
# Single tool call with options
{:ok, result} = Executor.execute(tool_call, context: %{project_root: tmp_dir})

# Result struct
%Result{status: :ok, content: json_string}
%Result{status: :error, content: error_message}
```

**Tool Call Building:**
```elixir
defp build_tool_call(subcommand, args \\ [], allow_destructive \\ false) do
  %{
    id: "call_#{:rand.uniform(100_000)}",
    name: "git_command",
    arguments: %{
      "subcommand" => subcommand,
      "args" => args,
      "allow_destructive" => allow_destructive
    }
  }
end
```

**Content Decoding:**
```elixir
{:ok, result} = Executor.execute(tool_call, exec_opts)
{:ok, decoded} = Jason.decode(result.content)
# decoded = %{"output" => "...", "exit_code" => 0, "parsed" => %{...}}
```

## Files Created

| File | Lines | Purpose |
|------|-------|---------|
| `test/jido_code/tools/git_command_integration_test.exs` | 443 | Integration tests |

## Test Coverage

**23 tests covering:**
- Tool registration and lookup
- Executor parsing and dispatch
- Handler execution through bridge
- Result formatting and JSON encoding
- Security controls (destructive operation blocking)
- Project directory isolation
- Error handling for edge cases

**All tests pass in ~0.7 seconds.**

## Integration Points

- Uses `JidoCode.Tools.Executor.execute/2` API
- Uses `JidoCode.Tools.Registry` for tool lookup
- Uses `JidoCode.Tools.Result` struct for responses
- Uses `JidoCode.Tools.Definitions.GitCommand` for tool definition
- Exercises git handler through Lua bridge

## Dependencies

- Requires git to be installed
- Uses ExUnit `:tmp_dir` for isolated test directories
- Each test has its own git repository

## Next Steps

- **3.2**: Get Diagnostics Tool (LSP-based)
- Consider adding performance benchmarks for large repos
