# Phase 3: Git & LSP Integration

This phase implements version control and code intelligence tools. Git integration provides safe VCS operations, while LSP tools offer real-time diagnostics and code information.

## Tools in This Phase

| Tool | Purpose | Priority |
|------|---------|----------|
| git_command | Safe git CLI passthrough | Core |
| get_diagnostics | LSP error/warning retrieval | Core |
| get_hover_info | Type and documentation at position | Core |

---

## 3.1 Git Command Tool

Implement the git_command tool for safe git CLI passthrough with guardrails against destructive operations.

### 3.1.1 Tool Definition

Create the git_command tool definition with safety constraints.

- [ ] 3.1.1.1 Create `lib/jido_code/tools/definitions/git_command.ex`
- [ ] 3.1.1.2 Define schema:
  ```elixir
  %{
    subcommand: %{type: :string, required: true, description: "Git subcommand (status, diff, log, etc.)"},
    args: %{type: :array, required: false, description: "Additional arguments"},
    allow_destructive: %{type: :boolean, required: false, description: "Allow destructive operations (default: false)"}
  }
  ```
- [ ] 3.1.1.3 Document allowed and blocked subcommands

### 3.1.2 Git Handler Implementation

Implement the handler for git command execution with safety guards.

- [ ] 3.1.2.1 Create `lib/jido_code/tools/handlers/git/command.ex`
- [ ] 3.1.2.2 Define allowed subcommands:
  - Always allowed: status, diff, log, show, branch, remote, fetch, stash list
  - With confirmation: add, commit, checkout, merge, rebase, stash push/pop
  - Blocked by default: push --force, reset --hard, clean -fd
- [ ] 3.1.2.3 Validate subcommand against allowlist
- [ ] 3.1.2.4 Block destructive operations unless allow_destructive=true
- [ ] 3.1.2.5 Execute git command in project directory
- [ ] 3.1.2.6 Parse common outputs for structured response:
  - status: Parse staged, unstaged, untracked files
  - diff: Parse file changes
  - log: Parse commits with hash, author, message
- [ ] 3.1.2.7 Return `{:ok, %{output: output, parsed: structured}}` or `{:error, reason}`

### 3.1.3 Unit Tests for Git Command

- [ ] Test git_command runs status
- [ ] Test git_command runs diff
- [ ] Test git_command runs log with format options
- [ ] Test git_command runs branch listing
- [ ] Test git_command blocks force push by default
- [ ] Test git_command allows force push with allow_destructive
- [ ] Test git_command blocks reset --hard by default
- [ ] Test git_command runs in project directory
- [ ] Test git_command parses status output
- [ ] Test git_command parses diff output
- [ ] Test git_command handles git errors

---

## 3.2 Get Diagnostics Tool

Implement the get_diagnostics tool for retrieving LSP errors, warnings, and hints.

### 3.2.1 Tool Definition

Create the get_diagnostics tool definition for LSP integration.

- [ ] 3.2.1.1 Create `lib/jido_code/tools/definitions/get_diagnostics.ex`
- [ ] 3.2.1.2 Define schema:
  ```elixir
  %{
    path: %{type: :string, required: false, description: "File path to get diagnostics for (default: all)"},
    severity: %{type: :string, required: false, enum: ["error", "warning", "info", "hint"], description: "Filter by severity"},
    limit: %{type: :integer, required: false, description: "Maximum diagnostics to return"}
  }
  ```

### 3.2.2 Diagnostics Handler Implementation

Implement the handler for LSP diagnostics retrieval.

- [ ] 3.2.2.1 Create `lib/jido_code/tools/handlers/lsp/diagnostics.ex`
- [ ] 3.2.2.2 Define LSP client interface (abstraction over ElixirLS/Lexical)
- [ ] 3.2.2.3 Connect to running language server
- [ ] 3.2.2.4 Retrieve diagnostics for file or workspace
- [ ] 3.2.2.5 Filter by severity if specified
- [ ] 3.2.2.6 Format diagnostics with:
  - severity: error/warning/info/hint
  - file: relative path
  - line: line number
  - column: column number
  - message: diagnostic message
  - code: diagnostic code if available
- [ ] 3.2.2.7 Apply limit if specified
- [ ] 3.2.2.8 Return `{:ok, diagnostics}` or `{:error, reason}`

### 3.2.3 Unit Tests for Get Diagnostics

- [ ] Test get_diagnostics retrieves compilation errors
- [ ] Test get_diagnostics retrieves warnings
- [ ] Test get_diagnostics filters by file path
- [ ] Test get_diagnostics filters by severity
- [ ] Test get_diagnostics respects limit
- [ ] Test get_diagnostics handles no diagnostics
- [ ] Test get_diagnostics handles LSP connection failure

---

## 3.3 Get Hover Info Tool

Implement the get_hover_info tool for retrieving type information and documentation at a position.

### 3.3.1 Tool Definition

Create the get_hover_info tool definition for code intelligence.

- [ ] 3.3.1.1 Create `lib/jido_code/tools/definitions/get_hover_info.ex`
- [ ] 3.3.1.2 Define schema:
  ```elixir
  %{
    path: %{type: :string, required: true, description: "File path"},
    line: %{type: :integer, required: true, description: "Line number (1-indexed)"},
    character: %{type: :integer, required: true, description: "Character offset (1-indexed)"}
  }
  ```

### 3.3.2 Hover Info Handler Implementation

Implement the handler for LSP hover information.

- [ ] 3.3.2.1 Create `lib/jido_code/tools/handlers/lsp/hover.ex`
- [ ] 3.3.2.2 Validate file path within boundary
- [ ] 3.3.2.3 Convert 1-indexed to 0-indexed for LSP protocol
- [ ] 3.3.2.4 Send hover request to LSP server
- [ ] 3.3.2.5 Parse response for:
  - Type signature
  - Documentation
  - Module information
  - Spec information
- [ ] 3.3.2.6 Format markdown content appropriately
- [ ] 3.3.2.7 Return `{:ok, %{type: type, docs: docs}}` or `{:error, reason}`

### 3.3.3 Unit Tests for Get Hover Info

- [ ] Test get_hover_info returns function documentation
- [ ] Test get_hover_info returns type information
- [ ] Test get_hover_info returns module docs
- [ ] Test get_hover_info handles unknown position
- [ ] Test get_hover_info validates file path
- [ ] Test get_hover_info handles LSP connection failure

---

## 3.4 Go To Definition Tool

Implement the go_to_definition tool for navigating to symbol definitions.

### 3.4.1 Tool Definition

Create the go_to_definition tool definition.

- [ ] 3.4.1.1 Create `lib/jido_code/tools/definitions/go_to_definition.ex`
- [ ] 3.4.1.2 Define schema:
  ```elixir
  %{
    path: %{type: :string, required: true, description: "File path"},
    line: %{type: :integer, required: true, description: "Line number (1-indexed)"},
    character: %{type: :integer, required: true, description: "Character offset (1-indexed)"}
  }
  ```

### 3.4.2 Go To Definition Handler Implementation

Implement the handler for definition navigation.

- [ ] 3.4.2.1 Create `lib/jido_code/tools/handlers/lsp/definition.ex`
- [ ] 3.4.2.2 Send definition request to LSP
- [ ] 3.4.2.3 Parse location response
- [ ] 3.4.2.4 Return `{:ok, %{path: path, line: line, character: char}}` or `{:error, :not_found}`

### 3.4.3 Unit Tests for Go To Definition

- [ ] Test go_to_definition finds function definition
- [ ] Test go_to_definition finds module definition
- [ ] Test go_to_definition handles no definition found

---

## 3.5 Find References Tool

Implement the find_references tool for finding all usages of a symbol.

### 3.5.1 Tool Definition

Create the find_references tool definition.

- [ ] 3.5.1.1 Create `lib/jido_code/tools/definitions/find_references.ex`
- [ ] 3.5.1.2 Define schema:
  ```elixir
  %{
    path: %{type: :string, required: true, description: "File path"},
    line: %{type: :integer, required: true, description: "Line number (1-indexed)"},
    character: %{type: :integer, required: true, description: "Character offset (1-indexed)"},
    include_declaration: %{type: :boolean, required: false, description: "Include declaration (default: false)"}
  }
  ```

### 3.5.2 Find References Handler Implementation

Implement the handler for reference finding.

- [ ] 3.5.2.1 Create `lib/jido_code/tools/handlers/lsp/references.ex`
- [ ] 3.5.2.2 Send references request to LSP
- [ ] 3.5.2.3 Parse location list response
- [ ] 3.5.2.4 Return `{:ok, [%{path: path, line: line, character: char}, ...]}` or `{:error, reason}`

### 3.5.3 Unit Tests for Find References

- [ ] Test find_references finds function usages
- [ ] Test find_references finds module usages
- [ ] Test find_references includes/excludes declaration

---

## 3.6 LSP Client Infrastructure

Implement the shared LSP client infrastructure used by all LSP tools.

### 3.6.1 LSP Client Module

Create a reusable LSP client.

- [ ] 3.6.1.1 Create `lib/jido_code/tools/lsp/client.ex`
- [ ] 3.6.1.2 Implement connection to ElixirLS via stdio
- [ ] 3.6.1.3 Implement connection to Lexical as alternative
- [ ] 3.6.1.4 Handle initialize/initialized handshake
- [ ] 3.6.1.5 Implement request/response correlation
- [ ] 3.6.1.6 Handle notifications
- [ ] 3.6.1.7 Implement graceful shutdown

### 3.6.2 LSP Protocol Types

Define LSP protocol types.

- [ ] 3.6.2.1 Create `lib/jido_code/tools/lsp/protocol.ex`
- [ ] 3.6.2.2 Define Position, Range, Location types
- [ ] 3.6.2.3 Define Diagnostic type
- [ ] 3.6.2.4 Define Hover type
- [ ] 3.6.2.5 Define TextDocumentIdentifier type

### 3.6.3 Unit Tests for LSP Client

- [ ] Test LSP client connection
- [ ] Test LSP request/response handling
- [ ] Test LSP notification handling
- [ ] Test LSP error handling

---

## 3.7 Phase 3 Integration Tests

Integration tests for Git and LSP tools.

### 3.7.1 Git Integration

Test git tools in realistic scenarios.

- [ ] 3.7.1.1 Create `test/jido_code/integration/tools_phase3_test.exs`
- [ ] 3.7.1.2 Test: git_command status works in initialized repo
- [ ] 3.7.1.3 Test: git_command diff shows file changes
- [ ] 3.7.1.4 Test: git_command log shows commit history
- [ ] 3.7.1.5 Test: git_command branch lists branches

### 3.7.2 LSP Integration

Test LSP tools with real language server.

- [ ] 3.7.2.1 Test: diagnostics returned after file with syntax error
- [ ] 3.7.2.2 Test: diagnostics returned for undefined function
- [ ] 3.7.2.3 Test: hover info available for standard library functions
- [ ] 3.7.2.4 Test: hover info available for project functions
- [ ] 3.7.2.5 Test: go_to_definition navigates to function
- [ ] 3.7.2.6 Test: find_references locates function usages

---

## Phase 3 Success Criteria

1. **git_command**: Safe git passthrough with destructive operation guards
2. **get_diagnostics**: LSP diagnostics with severity filtering
3. **get_hover_info**: Type and documentation retrieval
4. **go_to_definition**: Symbol definition navigation
5. **find_references**: Symbol usage finding
6. **LSP Client**: Reliable connection to ElixirLS/Lexical
7. **Test Coverage**: Minimum 80% for Phase 3 tools

---

## Phase 3 Critical Files

**New Files:**
- `lib/jido_code/tools/definitions/git_command.ex`
- `lib/jido_code/tools/definitions/get_diagnostics.ex`
- `lib/jido_code/tools/definitions/get_hover_info.ex`
- `lib/jido_code/tools/definitions/go_to_definition.ex`
- `lib/jido_code/tools/definitions/find_references.ex`
- `lib/jido_code/tools/handlers/git/command.ex`
- `lib/jido_code/tools/handlers/lsp/diagnostics.ex`
- `lib/jido_code/tools/handlers/lsp/hover.ex`
- `lib/jido_code/tools/handlers/lsp/definition.ex`
- `lib/jido_code/tools/handlers/lsp/references.ex`
- `lib/jido_code/tools/lsp/client.ex`
- `lib/jido_code/tools/lsp/protocol.ex`
- `test/jido_code/tools/handlers/git_test.exs`
- `test/jido_code/tools/handlers/lsp_test.exs`
- `test/jido_code/integration/tools_phase3_test.exs`

**Modified Files:**
- `lib/jido_code/tools/definitions.ex` - Register new tools
