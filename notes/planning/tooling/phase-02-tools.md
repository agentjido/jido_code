# Phase 2: Code Search & Shell Execution

This phase implements code search capabilities using ripgrep and shell execution tools with background process support. All tools route through the Lua sandbox for defense-in-depth security per [ADR-0001](../../decisions/0001-tool-security-architecture.md).

## Lua Sandbox Architecture

All search and shell tools follow this execution flow:

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                       │
│  e.g., {"name": "grep_search", "arguments": {...}}          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Tools.Manager.grep(pattern, opts, session_id: id)          │
│  GenServer call to session-scoped Lua sandbox               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Lua VM executes: "return jido.grep(pattern, opts)"         │
│  (dangerous functions like os.execute already removed)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Bridge.lua_grep/3 invoked from Lua                         │
│  (Elixir function registered as jido.grep)                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Security.validate_path(path, project_root) +               │
│  Security.validate_command(cmd) for shell tools             │
│  - Path boundary validation                                 │
│  - Command allowlist enforcement                            │
└─────────────────────────────────────────────────────────────┘
```

## Tools in This Phase

| Tool | Implementation | Purpose | Status |
|------|----------------|---------|--------|
| grep | Handler pattern | Regex-based code searching | ✅ Implemented |
| run_command | Handler pattern | Foreground command execution | ✅ Implemented |
| bash_background | - | Background process spawning | ❌ Deferred |
| bash_output | - | Background output retrieval | ❌ Deferred |
| kill_shell | - | Background process termination | ❌ Deferred |

> **Note:** The implementation uses the Handler pattern (direct Elixir execution) instead of the Lua bridge pattern for grep and run_command. Background shell tools (2.3-2.5) are deferred to a future phase.

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

## 2.3 Bash Background Tool ❌ Deferred

> **Note:** Background shell tools are deferred to a future phase. The current implementation focuses on foreground execution via `run_command`.

Implement the bash_background tool for starting long-running processes through the Lua sandbox.

### 2.3.1 Tool Definition

Create the bash_background tool definition for background processes.

- [ ] 2.3.1.1 Create `lib/jido_code/tools/definitions/bash_background.ex`
- [ ] 2.3.1.2 Define schema:
  ```elixir
  %{
    name: "bash_background",
    description: "Start command in background. Returns shell_id for output retrieval.",
    parameters: [
      %{name: "command", type: :string, required: true, description: "Command to run"},
      %{name: "description", type: :string, required: false, description: "Description for tracking"}
    ]
  }
  ```
- [ ] 2.3.1.3 Register tool in definitions module

### 2.3.2 Bridge Function Implementation

Implement the Bridge function for background process management.

- [ ] 2.3.2.1 Add `lua_shell_background/3` to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_shell_background(args, state, project_root) do
    case args do
      [command] -> do_shell_background(command, %{}, state, project_root)
      [command, opts] -> do_shell_background(command, decode_opts(opts), state, project_root)
      _ -> {[nil, "shell_background requires command argument"], state}
    end
  end
  ```
- [ ] 2.3.2.2 Use `Security.validate_command/1` to check against allowlist
- [ ] 2.3.2.3 Start command as supervised Task
- [ ] 2.3.2.4 Generate unique shell_id (UUID or short hash)
- [ ] 2.3.2.5 Store process reference in session-scoped registry (in state)
- [ ] 2.3.2.6 Set up output streaming to accumulator
- [ ] 2.3.2.7 Return `{[%{shell_id: id, description: desc}], state}` with updated state
- [ ] 2.3.2.8 Register in `Bridge.register/2`

### 2.3.3 Manager API

- [ ] 2.3.3.1 Add `shell_background/2` to `Tools.Manager`
- [ ] 2.3.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 2.3.3.3 Call bridge function through Lua: `jido.shell_background(command, opts)`

### 2.3.4 Unit Tests for Bash Background

- [ ] Test bash_background through sandbox starts process
- [ ] Test bash_background returns unique shell_id
- [ ] Test bash_background process runs in background
- [ ] Test bash_background validates commands through Security module
- [ ] Test bash_background stores process in session state
- [ ] Test bash_background handles process crash

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

1. **grep_search**: Ripgrep search via `jido.grep` bridge
2. **bash_execute**: Foreground execution via `jido.shell` bridge
3. **bash_background**: Background spawning via `jido.shell_background` bridge
4. **bash_output**: Output retrieval via `jido.shell_output` bridge
5. **kill_shell**: Process termination via `jido.shell_kill` bridge
6. **All tools execute through Lua sandbox** (defense-in-depth)
7. **Test Coverage**: Minimum 80% for Phase 2 tools

---

## Phase 2 Critical Files

**Modified Files:**
- `lib/jido_code/tools/bridge.ex` - Add/update bridge functions for grep and shell
- `lib/jido_code/tools/manager.ex` - Expose grep and shell APIs
- `lib/jido_code/tools/security.ex` - Ensure `validate_command/1` exists

**New Files:**
- `lib/jido_code/tools/definitions/grep_search.ex`
- `lib/jido_code/tools/definitions/bash_execute.ex`
- `lib/jido_code/tools/definitions/bash_background.ex`
- `lib/jido_code/tools/definitions/bash_output.ex`
- `lib/jido_code/tools/definitions/kill_shell.ex`
- `test/jido_code/tools/bridge_search_shell_test.exs`
- `test/jido_code/integration/tools_phase2_test.exs`
