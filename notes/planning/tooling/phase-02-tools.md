# Phase 2: Code Search & Shell Execution

This phase implements code search capabilities using ripgrep and shell execution tools with background process support. These tools enable efficient codebase exploration and command execution.

## Tools in This Phase

| Tool | Purpose | Priority |
|------|---------|----------|
| grep_search | Regex-based code searching with ripgrep | MVP |
| bash_execute | Foreground command execution | MVP |
| bash_background | Background process spawning | MVP |
| bash_output | Background output retrieval | MVP |

---

## 2.1 Grep Search Tool

Implement the grep_search tool using ripgrep for regex-based code searching with context and filtering options.

### 2.1.1 Tool Definition

Create the grep_search tool definition with comprehensive options.

- [ ] 2.1.1.1 Create `lib/jido_code/tools/definitions/grep_search.ex`
- [ ] 2.1.1.2 Define comprehensive schema:
  ```elixir
  %{
    pattern: %{type: :string, required: true, description: "Regex pattern"},
    path: %{type: :string, required: false, description: "Search directory"},
    output_mode: %{type: :string, required: false, enum: ["content", "files_with_matches", "count"]},
    context_before: %{type: :integer, required: false, description: "Lines before match (-B)"},
    context_after: %{type: :integer, required: false, description: "Lines after match (-A)"},
    context: %{type: :integer, required: false, description: "Lines before and after (-C)"},
    file_type: %{type: :string, required: false, description: "File type filter (ex, js, py)"},
    case_insensitive: %{type: :boolean, required: false, description: "Case insensitive search"},
    multiline: %{type: :boolean, required: false, description: "Enable cross-line matching"},
    head_limit: %{type: :integer, required: false, description: "Limit number of results"}
  }
  ```

### 2.1.2 Grep Handler Implementation

Implement the handler for ripgrep-powered code search.

- [ ] 2.1.2.1 Create `lib/jido_code/tools/handlers/search/grep.ex`
- [ ] 2.1.2.2 Build ripgrep command with all options
- [ ] 2.1.2.3 Validate search path within boundary
- [ ] 2.1.2.4 Execute ripgrep with timeout (default 30 seconds)
- [ ] 2.1.2.5 Parse output based on output_mode:
  - `content`: Show matching lines with context
  - `files_with_matches`: Show only file paths
  - `count`: Show match counts per file
- [ ] 2.1.2.6 Handle case-insensitive option (-i flag)
- [ ] 2.1.2.7 Apply head_limit for large results
- [ ] 2.1.2.8 Return `{:ok, results}` or `{:error, reason}`

### 2.1.3 Unit Tests for Grep Search

- [ ] Test grep_search finds pattern matches
- [ ] Test grep_search with context_before lines
- [ ] Test grep_search with context_after lines
- [ ] Test grep_search with combined context
- [ ] Test grep_search with file type filter
- [ ] Test grep_search multiline mode
- [ ] Test grep_search output mode: content
- [ ] Test grep_search output mode: files_with_matches
- [ ] Test grep_search output mode: count
- [ ] Test grep_search case insensitive
- [ ] Test grep_search validates boundary
- [ ] Test grep_search handles no matches gracefully
- [ ] Test grep_search handles invalid regex

---

## 2.2 Bash Execute Tool

Implement the bash_execute tool for foreground command execution with timeout and output capture.

### 2.2.1 Tool Definition

Create the bash_execute tool definition for foreground commands.

- [ ] 2.2.1.1 Create `lib/jido_code/tools/definitions/bash_execute.ex`
- [ ] 2.2.1.2 Define schema:
  ```elixir
  %{
    command: %{type: :string, required: true, description: "Shell command to execute"},
    description: %{type: :string, required: false, description: "5-10 word description of command"},
    timeout: %{type: :integer, required: false, description: "Timeout in milliseconds (default: 120000)"},
    working_directory: %{type: :string, required: false, description: "Override working directory"}
  }
  ```
- [ ] 2.2.1.3 Document allowed command patterns in description

### 2.2.2 Bash Execute Handler Implementation

Implement the handler for foreground command execution.

- [ ] 2.2.2.1 Create `lib/jido_code/tools/handlers/shell/bash_execute.ex`
- [ ] 2.2.2.2 Validate command against allowlist (mix, git, npm, etc.)
- [ ] 2.2.2.3 Block shell interpreters (bash, sh, zsh directly)
- [ ] 2.2.2.4 Block dangerous patterns (rm -rf /, etc.)
- [ ] 2.2.2.5 Set working directory to project root (or override)
- [ ] 2.2.2.6 Execute command with System.cmd or Port
- [ ] 2.2.2.7 Apply timeout (default 120000ms, max 600000ms)
- [ ] 2.2.2.8 Capture stdout and stderr separately
- [ ] 2.2.2.9 Truncate output at 30,000 characters with indicator
- [ ] 2.2.2.10 Return `{:ok, %{output: output, exit_code: code, stderr: stderr}}` or `{:error, reason}`

### 2.2.3 Unit Tests for Bash Execute

- [ ] Test bash_execute runs allowed commands (mix compile)
- [ ] Test bash_execute runs git commands (git status)
- [ ] Test bash_execute blocks dangerous commands
- [ ] Test bash_execute blocks shell interpreters
- [ ] Test bash_execute respects timeout
- [ ] Test bash_execute handles timeout exceeded
- [ ] Test bash_execute captures exit code
- [ ] Test bash_execute captures stderr separately
- [ ] Test bash_execute truncates long output
- [ ] Test bash_execute uses project working directory
- [ ] Test bash_execute respects working_directory override

---

## 2.3 Bash Background Tool

Implement the bash_background tool for starting long-running processes in the background.

### 2.3.1 Tool Definition

Create the bash_background tool definition for background processes.

- [ ] 2.3.1.1 Create `lib/jido_code/tools/definitions/bash_background.ex`
- [ ] 2.3.1.2 Define schema:
  ```elixir
  %{
    command: %{type: :string, required: true, description: "Command to run in background"},
    description: %{type: :string, required: false, description: "Description for tracking"}
  }
  ```

### 2.3.2 Bash Background Handler Implementation

Implement the handler for background process management.

- [ ] 2.3.2.1 Create `lib/jido_code/tools/handlers/shell/bash_background.ex`
- [ ] 2.3.2.2 Validate command against allowlist
- [ ] 2.3.2.3 Start command as supervised Task
- [ ] 2.3.2.4 Generate unique shell_id (UUID or short hash)
- [ ] 2.3.2.5 Store process reference in session-scoped registry
- [ ] 2.3.2.6 Set up output streaming to accumulator
- [ ] 2.3.2.7 Return `{:ok, %{shell_id: id, description: desc}}` or `{:error, reason}`

### 2.3.3 Unit Tests for Bash Background

- [ ] Test bash_background starts process
- [ ] Test bash_background returns unique shell_id
- [ ] Test bash_background process runs in background
- [ ] Test bash_background validates commands
- [ ] Test bash_background stores process in registry
- [ ] Test bash_background handles process crash

---

## 2.4 Bash Output Tool

Implement the bash_output tool for retrieving output from background processes.

### 2.4.1 Tool Definition

Create the bash_output tool definition for output retrieval.

- [ ] 2.4.1.1 Create `lib/jido_code/tools/definitions/bash_output.ex`
- [ ] 2.4.1.2 Define schema:
  ```elixir
  %{
    shell_id: %{type: :string, required: true, description: "ID from bash_background"},
    block: %{type: :boolean, required: false, description: "Wait for completion (default: true)"},
    timeout: %{type: :integer, required: false, description: "Max wait time in ms (default: 30000)"}
  }
  ```

### 2.4.2 Bash Output Handler Implementation

Implement the handler for background output retrieval.

- [ ] 2.4.2.1 Create `lib/jido_code/tools/handlers/shell/bash_output.ex`
- [ ] 2.4.2.2 Look up process by shell_id in registry
- [ ] 2.4.2.3 Handle non-existent shell_id gracefully
- [ ] 2.4.2.4 Retrieve accumulated output
- [ ] 2.4.2.5 Determine status (running/completed/failed)
- [ ] 2.4.2.6 If block=true, wait for completion up to timeout
- [ ] 2.4.2.7 Truncate output at 30,000 characters
- [ ] 2.4.2.8 Return `{:ok, %{output: output, status: status, exit_code: code}}` or `{:error, reason}`

### 2.4.3 Unit Tests for Bash Output

- [ ] Test bash_output retrieves output from running process
- [ ] Test bash_output retrieves output from completed process
- [ ] Test bash_output returns correct status
- [ ] Test bash_output blocking mode waits for completion
- [ ] Test bash_output non-blocking mode returns immediately
- [ ] Test bash_output handles timeout
- [ ] Test bash_output for non-existent shell_id

---

## 2.5 Kill Shell Tool

Implement the kill_shell tool for terminating background processes.

### 2.5.1 Tool Definition

Create the kill_shell tool definition.

- [ ] 2.5.1.1 Create `lib/jido_code/tools/definitions/kill_shell.ex`
- [ ] 2.5.1.2 Define schema:
  ```elixir
  %{
    shell_id: %{type: :string, required: true, description: "ID of background shell to kill"}
  }
  ```

### 2.5.2 Kill Shell Handler Implementation

Implement the handler for process termination.

- [ ] 2.5.2.1 Create `lib/jido_code/tools/handlers/shell/kill_shell.ex`
- [ ] 2.5.2.2 Look up process by shell_id
- [ ] 2.5.2.3 Send termination signal
- [ ] 2.5.2.4 Remove from registry
- [ ] 2.5.2.5 Return `{:ok, :killed}` or `{:error, reason}`

### 2.5.3 Unit Tests for Kill Shell

- [ ] Test kill_shell terminates running process
- [ ] Test kill_shell handles already-terminated process
- [ ] Test kill_shell handles non-existent shell_id

---

## 2.6 Phase 2 Integration Tests

Integration tests for search and shell tools working together.

### 2.6.1 Search Integration

Test search tools in realistic scenarios.

- [ ] 2.6.1.1 Create `test/jido_code/integration/tools_phase2_test.exs`
- [ ] 2.6.1.2 Test: Create files with content -> grep finds matches -> context lines correct
- [ ] 2.6.1.3 Test: grep with file type filter only searches matching files
- [ ] 2.6.1.4 Test: grep respects project boundary

### 2.6.2 Shell Integration

Test shell tools in realistic scenarios.

- [ ] 2.6.2.1 Test: bash_execute runs mix commands successfully
- [ ] 2.6.2.2 Test: bash_execute -> verify output matches expected
- [ ] 2.6.2.3 Test: bash_background starts long-running process -> bash_output retrieves output
- [ ] 2.6.2.4 Test: Background process completion detected
- [ ] 2.6.2.5 Test: kill_shell terminates running background process

### 2.6.3 Security Integration

Test security measures across shell tools.

- [ ] 2.6.3.1 Test: grep respects project boundary
- [ ] 2.6.3.2 Test: bash commands blocked for shell injection patterns
- [ ] 2.6.3.3 Test: Commands run in project directory
- [ ] 2.6.3.4 Test: Dangerous command patterns rejected

---

## Phase 2 Success Criteria

1. **grep_search**: Ripgrep-powered search with context and output modes
2. **bash_execute**: Foreground command execution with timeout
3. **bash_background**: Background process spawning with shell_id
4. **bash_output**: Background output retrieval with blocking option
5. **kill_shell**: Background process termination
6. **Test Coverage**: Minimum 80% for Phase 2 tools

---

## Phase 2 Critical Files

**New Files:**
- `lib/jido_code/tools/definitions/grep_search.ex`
- `lib/jido_code/tools/definitions/bash_execute.ex`
- `lib/jido_code/tools/definitions/bash_background.ex`
- `lib/jido_code/tools/definitions/bash_output.ex`
- `lib/jido_code/tools/definitions/kill_shell.ex`
- `lib/jido_code/tools/handlers/search/grep.ex`
- `lib/jido_code/tools/handlers/shell/bash_execute.ex`
- `lib/jido_code/tools/handlers/shell/bash_background.ex`
- `lib/jido_code/tools/handlers/shell/bash_output.ex`
- `lib/jido_code/tools/handlers/shell/kill_shell.ex`
- `lib/jido_code/tools/handlers/shell/process_registry.ex`
- `test/jido_code/tools/handlers/search_test.exs`
- `test/jido_code/tools/handlers/shell_test.exs`
- `test/jido_code/integration/tools_phase2_test.exs`

**Modified Files:**
- `lib/jido_code/tools/definitions.ex` - Register new tools
