# Task 3.1.2: Git Bridge Function Implementation

## Summary

Implemented the Git bridge function that enables git command execution from the Lua sandbox with full security validation, destructive operation blocking, and structured output parsing.

## Implementation Details

### Bridge Function (`lib/jido_code/tools/bridge.ex`)

Added `lua_git/3` function with the following features:

1. **Argument Parsing**: Handles multiple call patterns:
   - `git(subcommand)` - Simple command (e.g., `git("status")`)
   - `git(subcommand, args)` - With arguments (e.g., `git("log", {"-5", "--oneline"})`)
   - `git(subcommand, args, opts)` - With options (e.g., `git("push", {"--force"}, {allow_destructive = true})`)

2. **Security Validation**:
   - Subcommand allowlist validation (15 read-only + 26 modifying commands)
   - Destructive operation blocking (force push, hard reset, force clean, etc.)
   - Path traversal prevention for arguments containing paths
   - TOCTOU-safe execution

3. **Output Parsers**:
   - `parse_git_status/1` - Parses porcelain status output into structured data
   - `parse_git_log/1` - Parses log entries with hash, message, author, date
   - `parse_git_diff/1` - Extracts file changes, additions/deletions
   - `parse_git_branch/1` - Lists branches with current branch marker

4. **Return Format**:
   ```elixir
   # Success
   {[{"output", output}, {"parsed", parsed}, {"exit_code", 0}], state}

   # Error
   {[nil, error_message], state}
   ```

### Handler Update (`lib/jido_code/tools/handlers/git.ex`)

Updated `Git.Command` handler to delegate to the bridge function:

- Validates subcommand presence and type
- Validates project_root context
- Builds bridge arguments in correct format
- Converts Lua-style results to handler format (`{:ok, map}` / `{:error, string}`)
- Handles nested parsed data conversion (Lua tables to Elixir maps/lists)

### Key Security Features

| Feature | Implementation |
|---------|---------------|
| Subcommand allowlist | Uses `GitCommand.subcommand_allowed?/1` from definitions |
| Destructive blocking | Checks `GitCommand.destructive?/2` pattern matching |
| Path validation | Prevents `../` traversal in arguments |
| Timeout protection | Configurable timeout (default 30s) with graceful shutdown |

### Destructive Operations Blocked by Default

- `push --force` / `push -f`
- `reset --hard`
- `clean -f` / `clean -fd`
- `checkout --force`
- `branch -D`
- `stash drop`/`clear`
- `rebase --abort`

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/bridge.ex` | Added ~350 lines: `lua_git/3`, parsers, security validation |
| `lib/jido_code/tools/handlers/git.ex` | Replaced placeholder with bridge delegation (~160 lines) |
| `test/jido_code/tools/bridge_test.exs` | Added ~230 lines of git bridge tests |
| `test/jido_code/tools/handlers/git_test.exs` | Updated tests for real implementation |

## Test Coverage

### Bridge Tests (14 tests)
- Basic execution (status, log, diff, branch)
- Arguments handling (with and without)
- Destructive operation blocking
- Allow destructive with explicit opt-in
- Path traversal prevention
- Subcommand validation
- Output parsing

### Handler Tests (22 tests)
- Subcommand validation (nil, non-string, disallowed, unknown)
- Destructive operation blocking (force push, hard reset, clean, branch -D)
- Context validation (missing, nil, non-string project_root)
- Successful execution (status, log, diff)
- Allow destructive parameter
- Args handling (missing, empty, with values)

### Definition Tests (39 tests - from 3.1.1)
- All continue to pass

**Total: 166 tests, 0 failures**

## Usage Examples

### From Handler
```elixir
# Simple status check
Command.execute(%{"subcommand" => "status"}, %{project_root: "/path/to/repo"})
# => {:ok, %{output: "...", parsed: %{...}, exit_code: 0}}

# Log with arguments
Command.execute(
  %{"subcommand" => "log", "args" => ["-5", "--oneline"]},
  %{project_root: "/path/to/repo"}
)

# Force push (requires explicit permission)
Command.execute(
  %{"subcommand" => "push", "args" => ["--force", "origin", "main"], "allow_destructive" => true},
  %{project_root: "/path/to/repo"}
)
```

### From Lua Sandbox
```lua
-- Simple status
local result = jido.git("status")

-- Log with arguments
local result = jido.git("log", {"-5", "--oneline"})

-- Force push with explicit permission
local result = jido.git("push", {"--force", "origin", "main"}, {allow_destructive = true})
```

## Dependencies

- Uses `GitCommand` module from Task 3.1.1 for allowlist and destructive detection
- Integrates with existing `Bridge` architecture (Lua sandbox pattern)
- Follows same security patterns as `lua_shell/3`

## Next Steps (Phase 3 Remaining)

- **3.1.3**: Integration tests for git operations (blocked until bridge complete - now unblocked)
- **3.1.4**: Executor integration for git_command tool
- **3.2**: Diagnostics tools (compile errors, warnings)
