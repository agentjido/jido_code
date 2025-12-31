# Phase 3: Git & LSP Integration

This phase implements version control and code intelligence tools. All tools route through the Lua sandbox for defense-in-depth security per [ADR-0001](../../decisions/0001-tool-security-architecture.md).

## Lua Sandbox Architecture

All Git and LSP tools follow this execution flow:

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                       │
│  e.g., {"name": "git_command", "arguments": {...}}          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Tools.Manager.git(subcommand, args, session_id: id)        │
│  GenServer call to session-scoped Lua sandbox               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Lua VM executes: "return jido.git(subcommand, args)"       │
│  (dangerous functions like os.execute already removed)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Bridge.lua_git/3 invoked from Lua                          │
│  (Elixir function registered as jido.git)                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Git subcommand validation + Security checks                │
│  - Subcommand allowlist enforcement                         │
│  - Destructive operation guards                             │
└─────────────────────────────────────────────────────────────┘
```

## Tools in This Phase

| Tool | Handler/Bridge | Purpose |
|------|----------------|---------|
| git_command | `jido.git(subcommand, args)` | Safe git CLI passthrough |
| get_diagnostics | Handler pattern | LSP error/warning retrieval |
| get_hover_info | Handler pattern | Type and documentation at position |
| go_to_definition | Handler pattern | Symbol definition navigation |
| find_references | Handler pattern | Symbol usage finding |

**Note:** LSP tools use the Handler pattern (direct Elixir execution) established in Phase 2, not the Lua sandbox. This provides better integration with the LSP client infrastructure planned in Phase 3.6.

---

## 3.1 Git Command Tool

Implement the git_command tool for safe git CLI passthrough through the Lua sandbox.

### 3.1.1 Tool Definition (DONE)

Create the git_command tool definition with safety constraints.

- [x] 3.1.1.1 Create `lib/jido_code/tools/definitions/git_command.ex`
- [x] 3.1.1.2 Define schema:
  ```elixir
  %{
    name: "git_command",
    description: "Execute git command. Some destructive operations blocked by default.",
    parameters: [
      %{name: "subcommand", type: :string, required: true, description: "Git subcommand (status, diff, log, etc.)"},
      %{name: "args", type: :array, required: false, description: "Additional arguments"},
      %{name: "allow_destructive", type: :boolean, required: false, description: "Allow destructive operations"}
    ]
  }
  ```
- [x] 3.1.1.3 Document allowed and blocked subcommands
- [x] 3.1.1.4 Register tool in definitions module

See `notes/summaries/tooling-3.1.1-git-command-definition.md` for implementation details.

### 3.1.2 Bridge Function Implementation (DONE)

Implement the Bridge function for git command execution within the Lua sandbox.

- [x] 3.1.2.1 Add `lua_git/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_git(args, state, project_root) do
    case args do
      [subcommand] -> do_git(subcommand, [], %{}, state, project_root)
      [subcommand, cmd_args] -> do_git(subcommand, cmd_args, %{}, state, project_root)
      [subcommand, cmd_args, opts] -> do_git(subcommand, cmd_args, decode_opts(opts), state, project_root)
      _ -> {[nil, "git requires subcommand argument"], state}
    end
  end
  ```
- [x] 3.1.2.2 Define allowed subcommands:
  - Always allowed: status, diff, log, show, branch, remote, fetch, stash list
  - With confirmation: add, commit, checkout, merge, rebase, stash push/pop
  - Blocked by default: push --force, reset --hard, clean -fd
- [x] 3.1.2.3 Validate subcommand against allowlist
- [x] 3.1.2.4 Block destructive operations unless allow_destructive=true
- [x] 3.1.2.5 Execute git command in project directory
- [x] 3.1.2.6 Parse common outputs for structured response:
  - status: Parse staged, unstaged, untracked files
  - diff: Parse file changes
  - log: Parse commits with hash, author, message
- [x] 3.1.2.7 Return `{[%{output: output, parsed: structured}], state}` or `{[nil, error], state}`
- [x] 3.1.2.8 Register in `Bridge.register/2`

See `notes/summaries/tooling-3.1.2-git-bridge-function.md` for implementation details.

### 3.1.3 Manager API

- [ ] 3.1.3.1 Add `git/3` to `Tools.Manager` that accepts subcommand and options
- [ ] 3.1.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 3.1.3.3 Call bridge function through Lua: `jido.git(subcommand, args, opts)`

### 3.1.4 Unit Tests for Git Command

- [ ] Test git_command through sandbox runs status
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

Implement the get_diagnostics tool for retrieving LSP errors, warnings, and hints through the Lua sandbox.

### 3.2.1 Tool Definition

Create the get_diagnostics tool definition for LSP integration.

- [ ] 3.2.1.1 Create `lib/jido_code/tools/definitions/get_diagnostics.ex`
- [ ] 3.2.1.2 Define schema:
  ```elixir
  %{
    name: "get_diagnostics",
    description: "Get LSP diagnostics (errors, warnings) for file or workspace.",
    parameters: [
      %{name: "path", type: :string, required: false, description: "File path (default: all)"},
      %{name: "severity", type: :string, required: false,
        enum: ["error", "warning", "info", "hint"], description: "Filter by severity"},
      %{name: "limit", type: :integer, required: false, description: "Maximum diagnostics to return"}
    ]
  }
  ```
- [ ] 3.2.1.3 Register tool in definitions module

### 3.2.2 Bridge Function Implementation

Implement the Bridge function for LSP diagnostics retrieval.

- [ ] 3.2.2.1 Add `lua_lsp_diagnostics/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_lsp_diagnostics(args, state, project_root) do
    case args do
      [] -> do_lsp_diagnostics(nil, %{}, state, project_root)
      [path] -> do_lsp_diagnostics(path, %{}, state, project_root)
      [path, opts] -> do_lsp_diagnostics(path, decode_opts(opts), state, project_root)
      _ -> {[nil, "lsp_diagnostics: invalid arguments"], state}
    end
  end
  ```
- [ ] 3.2.2.2 Use LSP client interface (abstraction over ElixirLS/Lexical)
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
- [ ] 3.2.2.8 Return `{[diagnostics], state}` or `{[nil, error], state}`
- [ ] 3.2.2.9 Register in `Bridge.register/2`

### 3.2.3 Manager API

- [ ] 3.2.3.1 Add `lsp_diagnostics/2` to `Tools.Manager`
- [ ] 3.2.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 3.2.3.3 Call bridge function through Lua: `jido.lsp_diagnostics(path, opts)`

### 3.2.4 Unit Tests for Get Diagnostics

- [ ] Test get_diagnostics through sandbox retrieves compilation errors
- [ ] Test get_diagnostics retrieves warnings
- [ ] Test get_diagnostics filters by file path
- [ ] Test get_diagnostics filters by severity
- [ ] Test get_diagnostics respects limit
- [ ] Test get_diagnostics handles no diagnostics
- [ ] Test get_diagnostics handles LSP connection failure

---

## 3.3 Get Hover Info Tool

Implement the get_hover_info tool for retrieving type information and documentation through the Lua sandbox.

### 3.3.1 Tool Definition (DONE)

Create the get_hover_info tool definition for code intelligence.

- [x] 3.3.1.1 Create `lib/jido_code/tools/definitions/lsp.ex` (combined LSP definitions)
- [x] 3.3.1.2 Define schema:
  ```elixir
  %{
    name: "get_hover_info",
    description: "Get type info and documentation at cursor position.",
    parameters: [
      %{name: "path", type: :string, required: true, description: "File path"},
      %{name: "line", type: :integer, required: true, description: "Line number (1-indexed)"},
      %{name: "character", type: :integer, required: true, description: "Character offset (1-indexed)"}
    ]
  }
  ```
- [x] 3.3.1.3 Register tool in definitions module
- [x] 3.3.1.4 Create handler `lib/jido_code/tools/handlers/lsp.ex` with `GetHoverInfo` module
- [x] 3.3.1.5 Add unit tests `test/jido_code/tools/definitions/lsp_test.exs` (13 tests)

### 3.3.2 Handler Implementation (DONE - uses Handler pattern instead of Lua bridge)

**Architectural Decision:** LSP tools use the Handler pattern (direct Elixir execution)
established in Phase 2, rather than the Lua sandbox bridge. This provides:
- Better integration with LSP client infrastructure (Phase 3.6)
- Consistent pattern with Phase 2 tools (Search, Shell)
- Simpler async/streaming support for LSP responses

The handler is implemented in `lib/jido_code/tools/handlers/lsp.ex`:

- [x] 3.3.2.1 Handler module `JidoCode.Tools.Handlers.LSP.GetHoverInfo` created
- [x] 3.3.2.2 Validate file path within boundary using `HandlerHelpers.validate_path/2`
- [x] 3.3.2.3 Position handling (1-indexed for display; 0-indexed conversion deferred to Phase 3.6)
- [x] 3.3.2.4 LSP server integration placeholder (awaiting Phase 3.6 LSP client)
- [x] 3.3.2.5 Response structure defined for type, docs, module, spec
- [x] 3.3.2.6 Markdown content formatting (deferred to Phase 3.6)
- [x] 3.3.2.7 Returns `{:ok, map}` or `{:error, string}` per Handler pattern
- [N/A] 3.3.2.8 No Lua bridge registration needed (Handler pattern)

### 3.3.3 Manager API (N/A - Handler pattern used)

Handler pattern tools execute via `Tools.Executor` directly, not through `Tools.Manager`.
The Executor handles session-aware context routing via `HandlerHelpers`.

- [N/A] 3.3.3.1 No Manager API needed (Handler pattern uses Executor)
- [x] 3.3.3.2 Session-aware routing via `context.session_id` in Handler
- [N/A] 3.3.3.3 No Lua call needed (Handler pattern)

### 3.3.4 Unit Tests for Get Hover Info (DONE)

Tests implemented in `test/jido_code/tools/definitions/lsp_test.exs` (13 tests):

- [x] Test tool definition has correct schema
- [x] Test generates valid LLM function format
- [x] Test get_hover_info works via executor for Elixir files
- [x] Test get_hover_info handles non-Elixir files (unsupported_file_type)
- [x] Test get_hover_info returns error for non-existent file
- [x] Test executor validates required arguments
- [x] Test get_hover_info validates line number (must be >= 1)
- [x] Test get_hover_info validates character number (must be >= 1)
- [x] Test results can be converted to LLM messages
- [x] Test get_hover_info blocks path traversal (security)
- [x] Test get_hover_info blocks absolute paths outside project (security)
- [x] Test session-aware context uses session_id when provided

Note: Full LSP integration tests (function docs, type info) deferred to Phase 3.6 when LSP client is implemented.

---

## 3.4 Go To Definition Tool

Implement the go_to_definition tool for navigating to symbol definitions.

**Note:** Uses Handler pattern (not Lua sandbox) per architectural decision in 3.3.2.
See `notes/summaries/tooling-3.3.2-lsp-handler-architecture.md` for rationale.

### 3.4.1 Tool Definition (add to existing lsp.ex)

Add the go_to_definition tool to the existing LSP definitions module.

- [x] 3.4.1.1 Add `go_to_definition/0` function to `lib/jido_code/tools/definitions/lsp.ex`
- [x] 3.4.1.2 Define schema:
  ```elixir
  %{
    name: "go_to_definition",
    description: "Find where a symbol is defined. Returns the file path and position of the definition.",
    parameters: [
      %{name: "path", type: :string, required: true, description: "File path (relative to project root)"},
      %{name: "line", type: :integer, required: true, description: "Line number (1-indexed, as shown in editors)"},
      %{name: "character", type: :integer, required: true, description: "Character offset (1-indexed, as shown in editors)"}
    ]
  }
  ```
- [x] 3.4.1.3 Update `LSP.all/0` to include `go_to_definition()`
- [x] 3.4.1.4 Create handler `GoToDefinition` in `lib/jido_code/tools/handlers/lsp.ex`

### 3.4.2 Handler Implementation (uses Handler pattern)

**Architectural Decision:** Same as 3.3.2 - LSP tools use the Handler pattern (direct
Elixir execution) established in Phase 2, rather than the Lua sandbox bridge. This provides:
- Better integration with LSP client infrastructure (Phase 3.6)
- Consistent pattern with Phase 2 tools and get_hover_info
- Simpler async/streaming support for LSP responses

The handler is implemented in `lib/jido_code/tools/handlers/lsp.ex`:

- [x] 3.4.2.1 Handler module `JidoCode.Tools.Handlers.LSP.GoToDefinition`
- [x] 3.4.2.2 Validate INPUT path using `HandlerHelpers.validate_path/2`
- [x] 3.4.2.3 Position handling (1-indexed for display; 0-indexed conversion in Phase 3.6)
- [x] 3.4.2.4 LSP server integration placeholder (awaiting Phase 3.6 LSP client)
- [x] 3.4.2.5 Validate OUTPUT path from LSP response (SECURITY):
  - Within project_root: Return relative path
  - In deps/ or _build/: Return relative path (allow read-only access)
  - In stdlib/OTP: Return sanitized indicator (e.g., `"elixir:File"`)
  - Outside all boundaries: Return error without revealing actual path
- [x] 3.4.2.6 Handle multiple definitions (LSP can return array of locations)
- [x] 3.4.2.7 Returns `{:ok, map}` or `{:error, string}` per Handler pattern
- [x] 3.4.2.8 Emit telemetry for `:go_to_definition` operation
- [x] 3.4.2.9 Add `format_error/2` clause for `:definition_not_found`

### 3.4.3 Manager API (N/A - Handler pattern used)

Handler pattern tools execute via `Tools.Executor` directly, not through `Tools.Manager`.
The Executor handles session-aware context routing via `HandlerHelpers`.

- [N/A] 3.4.3.1 No Manager API needed (Handler pattern uses Executor)
- [x] 3.4.3.2 Session-aware routing via `context.session_id` in Handler
- [N/A] 3.4.3.3 No Lua call needed (Handler pattern)

### 3.4.4 Unit Tests for Go To Definition (add to lsp_test.exs)

Tests should be added to `test/jido_code/tools/definitions/lsp_test.exs`:

**Schema & Format:**
- [x] Test tool definition has correct schema
- [x] Test generates valid LLM function format

**Executor Integration:**
- [x] Test go_to_definition works via executor for Elixir files
- [x] Test go_to_definition handles non-Elixir files (unsupported_file_type)
- [x] Test go_to_definition returns error for non-existent file
- [x] Test executor validates required arguments (path, line, character)

**Parameter Validation:**
- [x] Test validates line number (must be >= 1)
- [x] Test validates character number (must be >= 1)

**Functional:**
- [x] Test finds function definition (placeholder: lsp_not_configured)
- [x] Test finds module definition (placeholder: lsp_not_configured)
- [x] Test handles no definition found
- [x] Test handles multiple definitions (returns array)

**Security (CRITICAL):**
- [x] Test blocks path traversal in input
- [x] Test blocks absolute paths outside project in input
- [x] Test sanitizes external paths in output (does not reveal system paths)
- [x] Test error messages do not reveal external file paths

**Session & LLM:**
- [x] Test session-aware context uses session_id when provided
- [x] Test results can be converted to LLM messages

**Output Path Validation (3.4.2.5):**
- [x] Test returns relative path for project files
- [x] Test returns relative path for deps files
- [x] Test returns relative path for _build files
- [x] Test sanitizes Elixir stdlib paths
- [x] Test sanitizes Erlang OTP paths
- [x] Test returns error for external paths
- [x] Test validates multiple output paths

**LSP Response Processing (3.4.2.6):**
- [x] Test processes nil response as not found
- [x] Test processes empty array as not found
- [x] Test processes single definition
- [x] Test processes multiple definitions
- [x] Test filters out external paths from multiple definitions
- [x] Test returns not found when all definitions are external
- [x] Test handles stdlib definitions

Note: Full LSP integration tests (actual definition navigation) deferred to Phase 3.6
when LSP client is implemented.

### 3.4.5 Code Review Fixes (Post-Implementation)

Review conducted: 2025-12-29. See `notes/reviews/phase-03-section-3.4-implementation-review.md`.

**Concerns Addressed:**
- [x] Extract duplicated helper functions to parent LSP module
- [x] Move regex patterns to module attributes (compile-time optimization)
- [x] Improve truncate_path security with hash-based logging
- [x] Add case-insensitive file:// URI handling
- [x] Add missing stdlib patterns (mise, Nix, Homebrew, Docker)
- [x] Add shared test helpers to reduce duplication
- [x] Fix type spec inconsistency

**Edge Case Tests Added:**
- [x] Negative line/character number validation (4 tests)
- [x] Case-insensitive URI handling (4 tests)
- [x] Missing argument tests (4 tests)
- [x] Additional stdlib pattern tests (5 tests)

**Total Tests:** 57 (up from 40)

See `notes/summaries/phase-03-section-3.4-review-fixes.md` for full details.

---

## 3.5 Find References Tool

Implement the find_references tool for finding all usages of a symbol.

**Note:** Uses Handler pattern (not Lua sandbox) per architectural decision in 3.3.2.
See `notes/summaries/tooling-3.3.2-lsp-handler-architecture.md` for rationale.

### 3.5.1 Tool Definition (add to existing lsp.ex)

Add the find_references tool to the existing LSP definitions module.

- [x] 3.5.1.1 Add `find_references/0` function to `lib/jido_code/tools/definitions/lsp.ex`
- [x] 3.5.1.2 Define schema:
  ```elixir
  %{
    name: "find_references",
    description: "Find all usages of a symbol. Returns a list of locations where the symbol is used.",
    parameters: [
      %{name: "path", type: :string, required: true, description: "File path (relative to project root)"},
      %{name: "line", type: :integer, required: true, description: "Line number (1-indexed, as shown in editors)"},
      %{name: "character", type: :integer, required: true, description: "Character offset (1-indexed, as shown in editors)"},
      %{name: "include_declaration", type: :boolean, required: false, description: "Include the declaration in results (default: false)"}
    ]
  }
  ```
- [x] 3.5.1.3 Update `LSP.all/0` to include `find_references()`
- [x] 3.5.1.4 Create handler `FindReferences` in `lib/jido_code/tools/handlers/lsp.ex`

### 3.5.2 Handler Implementation (uses Handler pattern)

**Architectural Decision:** Same as 3.3.2 and 3.4.2 - LSP tools use the Handler pattern.

The handler is implemented in `lib/jido_code/tools/handlers/lsp.ex`:

- [x] 3.5.2.1 Handler module `JidoCode.Tools.Handlers.LSP.FindReferences`
- [x] 3.5.2.2 Validate INPUT path using `HandlerHelpers.validate_path/2`
- [x] 3.5.2.3 Position handling (1-indexed for display; 0-indexed conversion in Phase 3.6)
- [x] 3.5.2.4 Handle `include_declaration` parameter (default: false)
- [x] 3.5.2.5 LSP server integration placeholder (awaiting Phase 3.6 LSP client)
- [x] 3.5.2.6 Validate OUTPUT paths from LSP response (SECURITY):
  - Filter results to only include paths within project boundary
  - Include deps/ and _build/ as relative paths
  - Exclude and do not reveal stdlib/OTP paths
- [x] 3.5.2.7 Returns `{:ok, %{"references" => [...]}}` or `{:error, string}`
- [x] 3.5.2.8 Emit telemetry for `:find_references` operation
- [x] 3.5.2.9 Add `format_error/2` clause for `:no_references_found`

### 3.5.3 Manager API (N/A - Handler pattern used)

Handler pattern tools execute via `Tools.Executor` directly, not through `Tools.Manager`.

- [N/A] 3.5.3.1 No Manager API needed (Handler pattern uses Executor)
- [x] 3.5.3.2 Session-aware routing via `context.session_id` in Handler
- [N/A] 3.5.3.3 No Lua call needed (Handler pattern)

### 3.5.4 Unit Tests for Find References (add to lsp_test.exs)

Tests should be added to `test/jido_code/tools/definitions/lsp_test.exs`:

**Schema & Format:**
- [x] Test tool definition has correct schema (including include_declaration param)
- [x] Test generates valid LLM function format

**Executor Integration:**
- [x] Test find_references works via executor for Elixir files
- [x] Test find_references handles non-Elixir files (unsupported_file_type)
- [x] Test find_references returns error for non-existent file
- [x] Test executor validates required arguments

**Parameter Validation:**
- [x] Test validates line number (must be >= 1)
- [x] Test validates character number (must be >= 1)
- [x] Test include_declaration defaults to false

**Functional:**
- [x] Test finds function usages (placeholder: lsp_not_configured)
- [x] Test finds module usages (placeholder: lsp_not_configured)
- [x] Test handles no references found (empty array)
- [x] Test include_declaration=true includes declaration in results

**Security (CRITICAL):**
- [x] Test blocks path traversal in input
- [x] Test blocks absolute paths outside project in input
- [x] Test filters output paths to project boundary only
- [x] Test does not reveal stdlib paths in results

**Session & LLM:**
- [x] Test session-aware context uses session_id when provided
- [x] Test results can be converted to LLM messages

Note: Full LSP integration tests deferred to Phase 3.6 when LSP client is implemented.

### 3.5.5 Review Fixes (post-implementation)

Code review fixes implemented after completion of 3.5.1-3.5.4:

- [x] 3.5.5.1 Extract shared `execute_lsp_operation/4` to parent LSP module
- [x] 3.5.5.2 Move `get_line_from_location/1` and `get_character_from_location/1` to parent module
- [x] 3.5.5.3 Extract `stdlib_path?/1` helper to parent module
- [x] 3.5.5.4 Add negative number validation tests for find_references
- [x] 3.5.5.5 Add parameter validation tests for include_declaration
- [x] 3.5.5.6 Add invalid location structure test
- [x] 3.5.5.7 Add shared helper unit tests (stdlib_path?, location extraction)

See `notes/summaries/tooling-3.5-review-fixes.md` for implementation details.
See `notes/reviews/phase-03-section-3.5-implementation-review.md` for original review.

---

## 3.6 LSP Client Infrastructure

Implement the shared LSP client infrastructure to connect with Expert, the official
Elixir Language Server.

**Reference:** https://github.com/elixir-lang/expert

**Note:** The LSP client will be used by Handler modules (get_hover_info, go_to_definition,
find_references) via direct Elixir calls, not through Lua bridge functions.

### 3.6.1 Expert Connection Module (DONE)

Create a reusable LSP client that connects to Expert via stdio.

- [x] 3.6.1.1 Create `lib/jido_code/tools/lsp/client.ex`
- [x] 3.6.1.2 Spawn Expert process with `--stdio` flag
- [x] 3.6.1.3 Implement JSON-RPC message framing (Content-Length headers)
- [x] 3.6.1.4 Handle initialize/initialized handshake
- [x] 3.6.1.5 Implement request/response correlation (request IDs)
- [x] 3.6.1.6 Handle notifications (for diagnostics)
- [x] 3.6.1.7 Implement graceful shutdown
- [x] 3.6.1.8 Handle Expert process lifecycle (start, restart on crash)

See `notes/summaries/tooling-3.6.1-expert-client.md` for implementation details.

### 3.6.2 LSP Protocol Types (DONE)

Define LSP protocol types for Handler modules.

- [x] 3.6.2.1 Create `lib/jido_code/tools/lsp/protocol.ex`
- [x] 3.6.2.2 Define Position, Range, Location types
- [x] 3.6.2.3 Define Diagnostic type
- [x] 3.6.2.4 Define Hover type
- [x] 3.6.2.5 Define TextDocumentIdentifier type
- [x] 3.6.2.6 Define LSP method constants (textDocument/hover, textDocument/definition, etc.)

See `notes/summaries/tooling-3.6.2-lsp-protocol-types.md` for implementation details.

### 3.6.3 Handler Integration

Update existing LSP handlers to use the Expert client.

- [x] 3.6.3.1 Update GetHoverInfo to call Expert via client
- [x] 3.6.3.2 Update GoToDefinition to call Expert via client
- [x] 3.6.3.3 Update FindReferences to call Expert via client
- [x] 3.6.3.4 Convert 1-indexed positions to 0-indexed for LSP protocol
- [x] 3.6.3.5 Parse Expert responses into handler result format

See `notes/summaries/tooling-3.6.3-handler-integration.md` for implementation details.

### 3.6.4 Unit Tests for LSP Client

- [x] Test Expert process spawning and connection
- [x] Test JSON-RPC message encoding/decoding
- [x] Test initialize handshake sequence
- [x] Test request/response correlation
- [x] Test notification handling
- [x] Test graceful shutdown
- [x] Test reconnection on Expert crash

See `notes/summaries/tooling-3.6.4-lsp-client-tests.md` for implementation details.

---

## 3.7 Phase 3 Integration Tests

Integration tests for Git and LSP tools.

### 3.7.1 Tool Execution Integration

Verify tools execute through the correct patterns.

- [x] 3.7.1.1 Create `test/jido_code/integration/tools_phase3_test.exs`
- [ ] 3.7.1.2 Test: Git tools execute through `Tools.Manager` → Lua → Bridge chain (blocked: git tools not implemented)
- [x] 3.7.1.3 Test: LSP tools execute through `Tools.Executor` → Handler chain
- [x] 3.7.1.4 Test: Session-scoped context isolation works for both patterns

### 3.7.2 Git Integration

Test git tools in realistic scenarios through Lua sandbox.

**Note:** Git integration tests blocked pending git_command tool implementation (Section 3.1).

- [ ] 3.7.2.1 Test: git_command status works in initialized repo
- [ ] 3.7.2.2 Test: git_command diff shows file changes
- [ ] 3.7.2.3 Test: git_command log shows commit history
- [ ] 3.7.2.4 Test: git_command branch lists branches

### 3.7.3 LSP Integration

Test LSP tools with Expert (official Elixir LSP) via Handler pattern.

**Note:** LSP tools use Handler pattern (see 3.3.2 architectural decision), not Lua sandbox.

- [ ] 3.7.3.1 Test: diagnostics returned after file with syntax error (blocked: get_diagnostics not implemented)
- [ ] 3.7.3.2 Test: diagnostics returned for undefined function (blocked: get_diagnostics not implemented)
- [x] 3.7.3.3 Test: hover info available for standard library functions
- [x] 3.7.3.4 Test: hover info available for project functions
- [x] 3.7.3.5 Test: go_to_definition navigates to function
- [x] 3.7.3.6 Test: find_references locates function usages
- [x] 3.7.3.7 Test: Output path validation filters external paths (security)

See `notes/summaries/tooling-3.7-phase3-integration-tests.md` for implementation details.

---

## Phase 3 Success Criteria

**Git Tools (Lua Sandbox Pattern):**
1. **git_command**: Safe git passthrough via `jido.git` bridge

**LSP Tools (Handler Pattern):**
2. **get_diagnostics**: LSP diagnostics via Handler (Phase 3.2)
3. **get_hover_info**: Type and docs via `Handlers.LSP.GetHoverInfo` (DONE - 3.3)
4. **go_to_definition**: Definition navigation via `Handlers.LSP.GoToDefinition` (Phase 3.4)
5. **find_references**: Reference finding via `Handlers.LSP.FindReferences` (Phase 3.5)

**Infrastructure:**
6. **Expert Client**: Reliable connection to Expert (official Elixir LSP) (Phase 3.6)
7. **Security**: Output path validation for LSP tools returning file paths
8. **Git tools execute through Lua sandbox** (defense-in-depth)
9. **LSP tools execute through Handler pattern** (better async/LSP integration)
10. **Test Coverage**: Minimum 80% for Phase 3 tools

---

## Phase 3 Critical Files

**Git Tools (Lua Sandbox Pattern) - Modified Files:**
- `lib/jido_code/tools/bridge.ex` - Add git bridge functions
- `lib/jido_code/tools/manager.ex` - Expose git APIs

**Git Tools - New Files:**
- `lib/jido_code/tools/definitions/git_command.ex`
- `test/jido_code/tools/bridge_git_test.exs`

**LSP Tools (Handler Pattern) - New Files:**
- `lib/jido_code/tools/definitions/lsp.ex` - LSP tool definitions (get_hover_info, go_to_definition, find_references) ✓
- `lib/jido_code/tools/handlers/lsp.ex` - LSP handlers (GetHoverInfo, GoToDefinition, FindReferences) ✓
- `lib/jido_code/tools/definitions/get_diagnostics.ex` - Diagnostics tool definition
- `test/jido_code/tools/definitions/lsp_test.exs` - LSP tool tests ✓

**LSP Infrastructure (Phase 3.6) - New Files:**
- `lib/jido_code/tools/lsp/client.ex` - LSP client for Expert (official Elixir LSP)
- `lib/jido_code/tools/lsp/protocol.ex` - LSP protocol types

**Integration Tests:**
- `test/jido_code/integration/tools_phase3_test.exs`
