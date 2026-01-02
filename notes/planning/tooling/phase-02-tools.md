# Phase 2: Code Search & Shell Execution

This phase implements code search capabilities and shell execution tools with security validation. Tools use the Handler pattern (direct Elixir execution) for simpler implementation while maintaining security through path validation and command allowlisting.

## Handler Pattern Architecture

All search and shell tools follow this execution flow:

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                       │
│  e.g., {"name": "grep", "arguments": {...}}                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Executor.execute/2 dispatches to registered handler        │
│  Handler is resolved from tool definition                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Handler.execute/2 performs operation                       │
│  - Uses HandlerHelpers for session-aware context            │
│  - Direct Elixir implementation (no Lua bridge)             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  HandlerHelpers.validate_path/2 + Security checks           │
│  - Path boundary validation via Security module             │
│  - Command allowlist enforcement for shell tools            │
│  - Session-scoped isolation                                 │
└─────────────────────────────────────────────────────────────┘
```

> **Note:** The original plan specified a Lua sandbox architecture. The actual implementation uses the Handler pattern for simplicity while maintaining security through the Security module and HandlerHelpers.

## Tools in This Phase

| Tool | Implementation | Purpose | Status |
|------|----------------|---------|--------|
| grep | Handler pattern | Regex-based code searching | ✅ Implemented |
| run_command | Handler pattern | Foreground command execution | ✅ Implemented |
| bash_background | Handler pattern | Background process spawning | ✅ Implemented |
| bash_output | - | Background output retrieval | ❌ Deferred |
| kill_shell | - | Background process termination | ❌ Deferred |

> **Note:** The implementation uses the Handler pattern (direct Elixir execution) instead of the Lua bridge pattern for grep, run_command, and bash_background. Background output and kill tools (2.4-2.5) are deferred as their functionality is available through the BackgroundShell GenServer API.

---

## 2.1 Grep Tool ✅

Implement the grep tool for regex-based code searching. Uses the Handler pattern with direct Elixir execution.

### 2.1.1 Tool Definition ✅

Note: Implemented as `grep` in `lib/jido_code/tools/definitions/search.ex`

- [x] 2.1.1.1 Create tool definition in `lib/jido_code/tools/definitions/search.ex`
- [x] 2.1.1.2 Define schema with pattern, path, recursive, max_results parameters
- [x] 2.1.1.3 Register tool via `Search.all/0`

### 2.1.2 Handler Implementation ✅

Note: Uses Handler pattern instead of Lua bridge for simpler implementation.

- [x] 2.1.2.1 Create `Grep` handler in `lib/jido_code/tools/handlers/search.ex`
- [x] 2.1.2.2 Validate search path within boundary
- [x] 2.1.2.3 Search file contents with regex pattern
- [x] 2.1.2.4 Return matched lines with file paths and line numbers
- [x] 2.1.2.5 Apply max_results limit
- [x] 2.1.2.6 Handle recursive search option

### 2.1.3 Unit Tests for Grep ✅

- [x] Test grep finds pattern matches
- [x] Test grep with recursive search
- [x] Test grep with max_results limit
- [x] Test grep validates boundary
- [x] Test grep handles no matches gracefully
- [x] Test grep handles invalid regex

---

## 2.2 Run Command Tool ✅

Implement the run_command tool for foreground command execution. Uses the Handler pattern with security validation.

### 2.2.1 Tool Definition ✅

Note: Implemented as `run_command` in `lib/jido_code/tools/definitions/shell.ex`

- [x] 2.2.1.1 Create tool definition in `lib/jido_code/tools/definitions/shell.ex`
- [x] 2.2.1.2 Define schema with command, args, timeout parameters
- [x] 2.2.1.3 Document allowed command patterns in description
- [x] 2.2.1.4 Register tool via `Shell.all/0`

### 2.2.2 Handler Implementation ✅

Note: Uses Handler pattern instead of Lua bridge.

- [x] 2.2.2.1 Create `RunCommand` handler in `lib/jido_code/tools/handlers/shell.ex`
- [x] 2.2.2.2 Implement command allowlist validation:
  - Allowed: mix, git, npm, node, elixir, erl, rebar3, ls, cat, grep, etc.
  - Blocked: bash, sh, zsh, sudo, etc.
- [x] 2.2.2.3 Block shell interpreters (bash, sh, zsh directly)
- [x] 2.2.2.4 Block path traversal in arguments
- [x] 2.2.2.5 Set working directory to project root
- [x] 2.2.2.6 Execute command with timeout enforcement
- [x] 2.2.2.7 Apply timeout (default 25000ms)
- [x] 2.2.2.8 Capture stdout (stderr merged)
- [x] 2.2.2.9 Truncate output at 1MB
- [x] 2.2.2.10 Return JSON with exit_code and stdout

### 2.2.3 Unit Tests for Run Command ✅

- [x] Test run_command runs allowed commands (mix compile)
- [x] Test run_command runs git commands (git status)
- [x] Test run_command blocks dangerous commands
- [x] Test run_command blocks shell interpreters
- [x] Test run_command respects timeout
- [x] Test run_command captures exit code
- [x] Test run_command uses project working directory

---

## 2.3 Bash Background Tool ✅

Implemented the bash_background tool for starting long-running processes. Uses the Handler pattern (consistent with run_command) with a BackgroundShell GenServer for process management.

> **Note:** Implementation uses Handler pattern instead of Lua bridge for consistency. See [summary document](../../summaries/phase-02-section-2.3-bash-background.md) for details.

### 2.3.1 Tool Definition ✅

Tool definition added to `lib/jido_code/tools/definitions/shell.ex`.

- [x] 2.3.1.1 Add `bash_background/0` to `lib/jido_code/tools/definitions/shell.ex`
- [x] 2.3.1.2 Define schema with command, args, description parameters
- [x] 2.3.1.3 Register tool via `Shell.all/0`

### 2.3.2 Handler Implementation ✅

Handler added to `lib/jido_code/tools/handlers/shell.ex`.

- [x] 2.3.2.1 Add `BashBackground` handler module to `lib/jido_code/tools/handlers/shell.ex`
- [x] 2.3.2.2 Use `Shell.validate_command/1` to check against allowlist
- [x] 2.3.2.3 Delegate to BackgroundShell GenServer for process management
- [x] 2.3.2.4 Generate unique shell_id (base64-encoded random bytes)
- [x] 2.3.2.5 Store process reference in ETS-backed registry
- [x] 2.3.2.6 Set up output streaming to ETS accumulator
- [x] 2.3.2.7 Return JSON with shell_id and description
- [x] 2.3.2.8 Emit telemetry events

### 2.3.3 BackgroundShell GenServer ✅

Created `lib/jido_code/tools/background_shell.ex` with:

- [x] 2.3.3.1 ETS-backed shell registry and output accumulator
- [x] 2.3.3.2 `start_command/5` for starting background commands
- [x] 2.3.3.3 `get_output/2` for retrieving output (blocking/non-blocking)
- [x] 2.3.3.4 `kill/1` for terminating running processes
- [x] 2.3.3.5 `list/1` for listing shells by session
- [x] 2.3.3.6 Added to supervision tree in `application.ex`

### 2.3.4 Unit Tests for Bash Background ✅

Tests in `test/jido_code/tools/background_shell_test.exs`:

- [x] Test bash_background starts process and returns shell_id
- [x] Test bash_background returns unique shell_ids
- [x] Test bash_background validates commands against allowlist
- [x] Test bash_background blocks shell interpreters
- [x] Test get_output retrieves output from completed process
- [x] Test get_output returns not_found for invalid shell_id
- [x] Test kill terminates running process
- [x] Test kill returns not_found for invalid shell_id
- [x] Test list returns shells for session
- [x] Test BashBackground handler requires session_id
- [x] Test BashBackground handler requires command

---

## 2.4 Bash Output Tool ❌ Deferred

> **Note:** Background shell tools are deferred to a future phase.

Implement the bash_output tool for retrieving output from background processes through the Lua sandbox.

### 2.4.1 Tool Definition

Create the bash_output tool definition for output retrieval.

- [ ] 2.4.1.1 Create `lib/jido_code/tools/definitions/bash_output.ex`
- [ ] 2.4.1.2 Define schema:
  ```elixir
  %{
    name: "bash_output",
    description: "Get output from background shell process.",
    parameters: [
      %{name: "shell_id", type: :string, required: true, description: "ID from bash_background"},
      %{name: "block", type: :boolean, required: false, description: "Wait for completion (default: true)"},
      %{name: "timeout", type: :integer, required: false, description: "Max wait time in ms (default: 30000)"}
    ]
  }
  ```
- [ ] 2.4.1.3 Register tool in definitions module

### 2.4.2 Bridge Function Implementation

Implement the Bridge function for background output retrieval.

- [ ] 2.4.2.1 Add `lua_shell_output/3` to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_shell_output(args, state, project_root) do
    case args do
      [shell_id] -> do_shell_output(shell_id, %{block: true}, state, project_root)
      [shell_id, opts] -> do_shell_output(shell_id, decode_opts(opts), state, project_root)
      _ -> {[nil, "shell_output requires shell_id argument"], state}
    end
  end
  ```
- [ ] 2.4.2.2 Look up process by shell_id in session state
- [ ] 2.4.2.3 Handle non-existent shell_id gracefully
- [ ] 2.4.2.4 Retrieve accumulated output from process
- [ ] 2.4.2.5 Determine status (running/completed/failed)
- [ ] 2.4.2.6 If block=true, wait for completion up to timeout
- [ ] 2.4.2.7 Truncate output at 30,000 characters
- [ ] 2.4.2.8 Return `{[%{output: output, status: status, exit_code: code}], state}` or `{[nil, error], state}`
- [ ] 2.4.2.9 Register in `Bridge.register/2`

### 2.4.3 Manager API

- [ ] 2.4.3.1 Add `shell_output/2` to `Tools.Manager`
- [ ] 2.4.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 2.4.3.3 Call bridge function through Lua: `jido.shell_output(shell_id, opts)`

### 2.4.4 Unit Tests for Bash Output

- [ ] Test bash_output through sandbox retrieves output from running process
- [ ] Test bash_output retrieves output from completed process
- [ ] Test bash_output returns correct status
- [ ] Test bash_output blocking mode waits for completion
- [ ] Test bash_output non-blocking mode returns immediately
- [ ] Test bash_output handles timeout
- [ ] Test bash_output for non-existent shell_id

---

## 2.5 Kill Shell Tool ❌ Deferred

> **Note:** Background shell tools are deferred to a future phase.

Implement the kill_shell tool for terminating background processes through the Lua sandbox.

### 2.5.1 Tool Definition

Create the kill_shell tool definition.

- [ ] 2.5.1.1 Create `lib/jido_code/tools/definitions/kill_shell.ex`
- [ ] 2.5.1.2 Define schema:
  ```elixir
  %{
    name: "kill_shell",
    description: "Terminate a background shell process.",
    parameters: [
      %{name: "shell_id", type: :string, required: true, description: "ID of background shell to kill"}
    ]
  }
  ```
- [ ] 2.5.1.3 Register tool in definitions module

### 2.5.2 Bridge Function Implementation

Implement the Bridge function for process termination.

- [ ] 2.5.2.1 Add `lua_shell_kill/3` to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_shell_kill(args, state, _project_root) do
    case args do
      [shell_id] -> do_shell_kill(shell_id, state)
      _ -> {[nil, "shell_kill requires shell_id argument"], state}
    end
  end
  ```
- [ ] 2.5.2.2 Look up process by shell_id in session state
- [ ] 2.5.2.3 Send termination signal (Process.exit or Task.shutdown)
- [ ] 2.5.2.4 Remove from session state registry
- [ ] 2.5.2.5 Return `{[true], updated_state}` or `{[nil, error], state}`
- [ ] 2.5.2.6 Register in `Bridge.register/2`

### 2.5.3 Manager API

- [ ] 2.5.3.1 Add `shell_kill/2` to `Tools.Manager`
- [ ] 2.5.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 2.5.3.3 Call bridge function through Lua: `jido.shell_kill(shell_id)`

### 2.5.4 Unit Tests for Kill Shell

- [ ] Test kill_shell through sandbox terminates running process
- [ ] Test kill_shell handles already-terminated process
- [ ] Test kill_shell handles non-existent shell_id
- [ ] Test kill_shell removes process from session state

---

## 2.6 Phase 2 Integration Tests ✅

Integration tests for search and shell tools working through the Handler pattern.

> **Note:** Tests use the Handler pattern (Executor → Handler chain) instead of Lua sandbox as the implementation was changed. Background shell tools (2.3-2.5) are deferred, so related tests are not applicable.

### 2.6.1 Handler Integration ✅

Verify tools execute through the Executor → Handler chain correctly.

- [x] 2.6.1.1 Create `test/jido_code/integration/tools_phase2_test.exs`
- [x] 2.6.1.2 Test: All tools execute through `Executor` → `Handler` chain
- [x] 2.6.1.3 Test: Security validation enforced (path boundaries, command allowlist)
- [x] 2.6.1.4 Test: Session-scoped execution is isolated (each session sees only its files)

### 2.6.2 Search Integration ✅

Test search tools in realistic scenarios.

- [x] 2.6.2.1 Test: Create files with content → grep finds matches → line numbers correct
- [x] 2.6.2.2 Test: grep searches recursively by default
- [x] 2.6.2.3 Test: grep respects project boundary
- [x] 2.6.2.4 Test: grep respects max_results limit
- [x] 2.6.2.5 Test: grep handles no matches gracefully
- [x] 2.6.2.6 Test: grep handles invalid regex gracefully

### 2.6.3 Shell Integration ✅

Test shell tools in realistic scenarios.

- [x] 2.6.3.1 Test: run_command runs allowed development commands
- [x] 2.6.3.2 Test: run_command captures exit code correctly
- [x] 2.6.3.3 Test: run_command merges stderr into stdout
- [x] 2.6.3.4 Test: run_command respects timeout
- [ ] 2.6.3.5 Test: bash_background starts long-running process (deferred - not implemented)
- [ ] 2.6.3.6 Test: kill_shell terminates running background process (deferred - not implemented)

### 2.6.4 Security Integration ✅

Test security measures across shell tools.

- [x] 2.6.4.1 Test: grep respects project boundary (via HandlerHelpers.validate_path)
- [x] 2.6.4.2 Test: run_command blocks disallowed commands
- [x] 2.6.4.3 Test: run_command blocks shell interpreters (bash, sh, zsh)
- [x] 2.6.4.4 Test: run_command blocks path traversal in arguments
- [x] 2.6.4.5 Test: run_command blocks absolute paths outside project

---

## Phase 2 Success Criteria

| Criterion | Status |
|-----------|--------|
| **grep**: Regex search via Handler pattern | ✅ Implemented |
| **run_command**: Foreground execution via Handler pattern | ✅ Implemented |
| **bash_background**: Background spawning via Handler pattern | ✅ Implemented |
| **bash_output**: Output retrieval | ❌ Deferred (available via BackgroundShell.get_output) |
| **kill_shell**: Process termination | ❌ Deferred (available via BackgroundShell.kill) |
| **Handler pattern execution**: Tools execute through Executor → Handler chain | ✅ Implemented |
| **Security validation**: Path boundaries and command allowlist enforced | ✅ Implemented |
| **Session isolation**: Session-scoped execution via HandlerHelpers | ✅ Implemented |
| **Test Coverage**: Minimum 80% for Phase 2 tools | ✅ Achieved |

> **Note:** The original plan specified Lua sandbox architecture. The actual implementation uses the Handler pattern (direct Elixir execution) for simplicity while maintaining security through the Security module and HandlerHelpers.

---

## Phase 2 Critical Files

**Implemented Files:**
- `lib/jido_code/tools/definitions/search.ex` - grep, find_files tool definitions
- `lib/jido_code/tools/definitions/shell.ex` - run_command, bash_background tool definitions
- `lib/jido_code/tools/handlers/search.ex` - Grep, FindFiles handlers
- `lib/jido_code/tools/handlers/shell.ex` - RunCommand, BashBackground handlers
- `lib/jido_code/tools/background_shell.ex` - BackgroundShell GenServer for process management
- `lib/jido_code/tools/handler_helpers.ex` - Session-aware path validation
- `lib/jido_code/tools/security.ex` - Path boundary validation
- `test/jido_code/tools/handlers/search_test.exs` - Search handler tests
- `test/jido_code/tools/handlers/shell_test.exs` - Shell handler tests
- `test/jido_code/tools/background_shell_test.exs` - BackgroundShell tests
- `test/jido_code/integration/tools_phase2_test.exs` - Integration tests

**Deferred Files (not implemented):**
- `lib/jido_code/tools/definitions/bash_output.ex` - Functionality available via BackgroundShell.get_output/2
- `lib/jido_code/tools/definitions/kill_shell.ex` - Functionality available via BackgroundShell.kill/1
