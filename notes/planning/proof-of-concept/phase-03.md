# Phase 3: Tool Calling and Sandbox

This phase implements the tool calling infrastructure that enables the LLM agent to interact with the codebase. All tool execution is sandboxed through a Lua-based tool manager that enforces security boundaries, preventing direct shell access and restricting operations to the current project directory.

## 3.1 Tool Infrastructure

The tool system defines a schema for tools, handles registration, and manages the execution flow between the LLM agent and the sandboxed tool manager.

### 3.1.1 Tool Schema and Registration
- [ ] **Task 3.1.1 Complete**

Define the tool schema and implement tool registration.

- [ ] 3.1.1.1 Create `JidoCode.Tools` namespace module
- [ ] 3.1.1.2 Define tool schema struct: `%Tool{name, description, parameters, handler}`
- [ ] 3.1.1.3 Define parameter schema: `%Param{name, type, description, required}`
- [ ] 3.1.1.4 Create `JidoCode.Tools.Registry` for tool registration and lookup
- [ ] 3.1.1.5 Implement `Registry.register/1` to add tools at startup
- [ ] 3.1.1.6 Implement `Registry.list/0` returning all registered tools
- [ ] 3.1.1.7 Implement `Registry.get/1` to lookup tool by name
- [ ] 3.1.1.8 Generate tool descriptions in LLM-compatible format for system prompt
- [ ] 3.1.1.9 Write registry tests (success: tools register and lookup correctly)

### 3.1.2 Tool Execution Flow
- [ ] **Task 3.1.2 Complete**

Implement the flow from LLM tool call to sandboxed execution and result handling.

- [ ] 3.1.2.1 Create `JidoCode.Tools.Executor` module for tool execution coordination
- [ ] 3.1.2.2 Parse tool calls from LLM response (JSON function calling format)
- [ ] 3.1.2.3 Validate tool name exists in registry
- [ ] 3.1.2.4 Validate parameters against tool schema (type checking, required fields)
- [ ] 3.1.2.5 Delegate execution to ToolManager (never execute directly)
- [ ] 3.1.2.6 Handle tool execution timeout (configurable, default 30s)
- [ ] 3.1.2.7 Format tool results for LLM consumption
- [ ] 3.1.2.8 Support sequential tool calls (one result feeds into next call)
- [ ] 3.1.2.9 Write execution flow tests with mock tool manager (success: full round-trip)

## 3.2 Lua Sandbox Tool Manager

All tool execution is delegated to a Lua-based sandbox using the `luerl` Erlang library. The tool manager enforces security boundaries: no direct shell access, no operations outside project directory, controlled API access.

### 3.2.1 Luerl Integration
- [ ] **Task 3.2.1 Complete**

Set up the Luerl Lua runtime integration for sandboxed execution.

- [ ] 3.2.1.1 Add `luerl` dependency to mix.exs
- [ ] 3.2.1.2 Create `JidoCode.Tools.Manager` module wrapping Luerl
- [ ] 3.2.1.3 Initialize Lua state with restricted standard library (no `os.execute`, `io.popen`, `loadfile`)
- [ ] 3.2.1.4 Implement `Manager.start_link/1` as GenServer for state management
- [ ] 3.2.1.5 Store project root path in Manager state for boundary enforcement
- [ ] 3.2.1.6 Implement `Manager.execute/3` accepting tool name, params, and timeout
- [ ] 3.2.1.7 Add Manager to supervision tree under AgentSupervisor
- [ ] 3.2.1.8 Write Luerl integration tests (success: Lua code executes in sandbox)

### 3.2.2 Security Boundaries
- [ ] **Task 3.2.2 Complete**

Implement security restrictions to prevent unauthorized access.

- [ ] 3.2.2.1 Define project boundary as current working directory at startup
- [ ] 3.2.2.2 Implement `validate_path/1` ensuring all paths resolve within project boundary
- [ ] 3.2.2.3 Reject any path containing `..` that escapes project root after resolution
- [ ] 3.2.2.4 Reject absolute paths outside project directory
- [ ] 3.2.2.5 Reject symlinks pointing outside project directory
- [ ] 3.2.2.6 Block all direct shell execution (no `os.execute`, `io.popen` equivalents)
- [ ] 3.2.2.7 Whitelist allowed Lua standard library functions
- [ ] 3.2.2.8 Implement resource limits: memory cap, execution time cap
- [ ] 3.2.2.9 Log all security boundary violations for debugging
- [ ] 3.2.2.10 Write security boundary tests (success: escape attempts blocked)

### 3.2.3 Erlang Bridge Functions
- [ ] **Task 3.2.3 Complete**

Expose controlled Erlang functions to Lua for file, shell, and API operations.

- [ ] 3.2.3.1 Create `JidoCode.Tools.Manager.Bridge` module for Erlang-Lua bindings
- [ ] 3.2.3.2 Implement `bridge_read_file/2` - read file contents (path validated)
- [ ] 3.2.3.3 Implement `bridge_write_file/3` - write file contents (path validated)
- [ ] 3.2.3.4 Implement `bridge_list_dir/2` - list directory contents (path validated)
- [ ] 3.2.3.5 Implement `bridge_file_exists/2` - check file existence (path validated)
- [ ] 3.2.3.6 Implement `bridge_shell/2` - execute shell command via controlled subprocess
- [ ] 3.2.3.7 Shell bridge captures stdout/stderr, enforces timeout, runs in project dir
- [ ] 3.2.3.8 Implement `bridge_http/2` - HTTP requests via Req (allowlist domains if needed)
- [ ] 3.2.3.9 Register all bridge functions in Lua state as `jido.*` namespace
- [ ] 3.2.3.10 Write bridge function tests (success: operations work within boundaries)

## 3.3 Core Coding Tools

Implement the essential tools for coding assistance: file operations, search, and shell execution.

### 3.3.1 File System Tools
- [ ] **Task 3.3.1 Complete**

Create tools for reading and writing files.

- [ ] 3.3.1.1 Create `read_file` tool: read file contents, params: `{path: string}`
- [ ] 3.3.1.2 Create `write_file` tool: write/overwrite file, params: `{path: string, content: string}`
- [ ] 3.3.1.3 Create `list_directory` tool: list files/dirs, params: `{path: string, recursive: boolean}`
- [ ] 3.3.1.4 Create `file_info` tool: get file metadata, params: `{path: string}`
- [ ] 3.3.1.5 Create `create_directory` tool: create dir, params: `{path: string}`
- [ ] 3.3.1.6 Create `delete_file` tool: remove file, params: `{path: string}` (with confirmation flag)
- [ ] 3.3.1.7 All file tools delegate to ToolManager bridge functions
- [ ] 3.3.1.8 Return structured results: `{ok: content}` or `{error: reason}`
- [ ] 3.3.1.9 Write file tool tests (success: CRUD operations work)

### 3.3.2 Search Tools
- [ ] **Task 3.3.2 Complete**

Create tools for searching the codebase.

- [ ] 3.3.2.1 Create `grep` tool: search file contents, params: `{pattern: string, path: string, recursive: boolean}`
- [ ] 3.3.2.2 Create `find_files` tool: find files by name/glob, params: `{pattern: string, path: string}`
- [ ] 3.3.2.3 Grep tool returns matched lines with file paths and line numbers
- [ ] 3.3.2.4 Find tool returns list of matching file paths
- [ ] 3.3.2.5 Implement result truncation for large result sets (configurable limit)
- [ ] 3.3.2.6 Search tools delegate to ToolManager for execution
- [ ] 3.3.2.7 Write search tool tests (success: patterns match correctly)

### 3.3.3 Shell Execution Tool
- [ ] **Task 3.3.3 Complete**

Create controlled shell execution tool.

- [ ] 3.3.3.1 Create `run_command` tool: execute shell command, params: `{command: string, args: [string]}`
- [ ] 3.3.3.2 Command runs in project directory (cwd enforced)
- [ ] 3.3.3.3 Capture stdout and stderr separately
- [ ] 3.3.3.4 Return exit code with output: `{exit_code: int, stdout: string, stderr: string}`
- [ ] 3.3.3.5 Enforce execution timeout (default 60s, configurable)
- [ ] 3.3.3.6 Optionally allow/block specific commands via configuration
- [ ] 3.3.3.7 Shell tool delegates to ToolManager bridge (never direct execution)
- [ ] 3.3.3.8 Write shell tool tests with safe commands (success: commands execute in sandbox)

## 3.4 Tool Result Handling

Display tool calls and results in the TUI for transparency.

### 3.4.1 Tool Call Display
- [ ] **Task 3.4.1 Complete**

Show tool invocations and results in the TUI conversation.

- [ ] 3.4.1.1 Broadcast `{:tool_call, tool_name, params}` via PubSub when tool is invoked
- [ ] 3.4.1.2 Broadcast `{:tool_result, tool_name, result}` when tool completes
- [ ] 3.4.1.3 TUI displays tool calls with distinct styling (e.g., dimmed, prefixed with "⚙")
- [ ] 3.4.1.4 Display tool parameters in condensed format
- [ ] 3.4.1.5 Display tool results with syntax highlighting for code/file contents
- [ ] 3.4.1.6 Truncate long results with "Show more" indicator
- [ ] 3.4.1.7 Handle tool errors with red error styling
- [ ] 3.4.1.8 Add toggle keybinding (Ctrl+T) to show/hide tool call details
- [ ] 3.4.1.9 Write TUI tool display tests (success: tool calls render correctly)
