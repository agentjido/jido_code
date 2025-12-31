# Task 3.1.3: Manager Git API

## Summary

Added session-aware `git/3` function to `Tools.Manager` and `git/4` function to `Session.Manager` that execute git commands through the Lua sandbox with security validation.

## Implementation Details

### Tools.Manager (`lib/jido_code/tools/manager.ex`)

Added `git/3` client API function:

```elixir
@spec git(String.t(), [String.t()], keyword()) ::
        {:ok, map()} | {:error, String.t() | :not_found}
def git(subcommand, args \\ [], opts \\ [])
```

**Features:**
- Session-aware: Accepts `:session_id` option to delegate to Session.Manager
- Options support: `:allow_destructive` and `:timeout`
- Deprecation warning: Logs warning when used without session_id (global manager)
- Calls bridge through Lua sandbox: `jido.git(subcommand, args, opts)`

**GenServer Handler:**
- Added `handle_call({:sandbox_git, subcommand, args, allow_destructive}, ...)`
- Uses `call_git_bridge/4` helper to execute through Lua

**Private Helpers:**
- `call_git_bridge/4` - Builds and executes Lua script
- `build_lua_array/1` - Converts list to Lua array format
- `decode_git_result/2` - Decodes Lua table result to Elixir map

### Session.Manager (`lib/jido_code/session/manager.ex`)

Added `git/4` client API function:

```elixir
@spec git(String.t(), String.t(), [String.t()], keyword()) ::
        {:ok, map()} | {:error, :not_found | String.t()}
def git(session_id, subcommand, args \\ [], opts \\ [])
```

**Features:**
- Direct session-scoped execution
- Options: `:allow_destructive`, `:timeout`
- Returns `{:ok, %{output: _, parsed: _, exit_code: _}}` or error

**GenServer Handler:**
- Added `handle_call({:git, subcommand, args, allow_destructive}, ...)`
- Uses `call_git_bridge/4` helper

**Private Helpers:**
- `call_git_bridge/4` - Builds Lua script with proper escaping
- `build_lua_array/1` - Converts args to Lua table format
- `decode_git_result/2` - Converts Lua result to Elixir map
- `decode_lua_value/2` - Recursively decodes nested Lua tables

## API Usage

### Session-Aware (Preferred)

```elixir
# Through Tools.Manager with session_id
{:ok, result} = Manager.git("status", [], session_id: session.id)
{:ok, result} = Manager.git("log", ["--oneline", "-5"], session_id: session.id)

# Destructive operations require explicit opt-in
{:ok, result} = Manager.git("push", ["--force", "origin", "main"],
                            session_id: session.id,
                            allow_destructive: true)

# Through Session.Manager directly
{:ok, result} = Session.Manager.git(session.id, "status")
{:ok, result} = Session.Manager.git(session.id, "log", ["--oneline", "-5"])
```

### Global Manager (Deprecated)

```elixir
# Logs deprecation warning
{:ok, result} = Manager.git("status")
```

### Result Format

```elixir
{:ok, %{
  output: "On branch main\nnothing to commit, working tree clean\n",
  parsed: %{branch: "main", staged: [], unstaged: [], untracked: []},
  exit_code: 0
}}
```

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/manager.ex` | +100 lines: `git/3`, handler, helpers |
| `lib/jido_code/session/manager.ex` | +100 lines: `git/4`, handler, helpers |
| `test/jido_code/tools/manager_test.exs` | +87 lines: 6 tests for session-aware git API |
| `test/jido_code/session/manager_test.exs` | +116 lines: 9 tests for git/4 |

## Test Coverage

### Tools.Manager Tests (6 tests)
- `runs git status through session manager`
- `runs git log with arguments`
- `blocks destructive operations by default`
- `allows destructive operations with allow_destructive option`
- `rejects disallowed subcommands`
- `returns :not_found for unknown session_id`

### Session.Manager Tests (9 tests)
- `executes git status`
- `executes git log with arguments`
- `executes git diff`
- `executes git branch`
- `blocks destructive operations by default`
- `allows destructive with allow_destructive option`
- `rejects disallowed subcommands`
- `returns parsed data for status`
- `returns error for non-existent session`

**Total: 15 new tests, 111 manager tests pass**

## Security Features

- Subcommand validation via `GitCommand.subcommand_allowed?/1`
- Destructive operation blocking unless `allow_destructive: true`
- Path traversal prevention in args
- Timeout protection with configurable limit
- All execution through Lua sandbox

## Integration Points

- Uses `Bridge.lua_git/3` for actual execution (from Task 3.1.2)
- Uses `GitCommand` definitions for validation (from Task 3.1.1)
- Follows session-aware API pattern established in Phase 2
- Compatible with Tools.Executor workflow

## Next Steps

- **3.1.4**: Unit tests for git_command tool through Executor
- **3.2**: Get Diagnostics Tool (LSP-based)
