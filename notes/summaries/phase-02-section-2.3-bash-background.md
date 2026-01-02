# Phase 2 Section 2.3: Bash Background Tool - Implementation Summary

## Overview

Implemented the `bash_background` tool for starting background shell processes. This implementation uses the Handler pattern (consistent with `run_command`) instead of the originally planned Lua bridge pattern, providing a simpler and more maintainable architecture.

## Implementation Date

2026-01-02

## Branch

`feature/phase2-section-2.3-bash-background`

## Files Created/Modified

### New Files

| File | Purpose |
|------|---------|
| `lib/jido_code/tools/background_shell.ex` | GenServer managing background shell processes with ETS-backed state |
| `test/jido_code/tools/background_shell_test.exs` | Unit and integration tests for BackgroundShell |

### Modified Files

| File | Change |
|------|--------|
| `lib/jido_code/tools/handlers/shell.ex` | Added `BashBackground` handler module |
| `lib/jido_code/tools/definitions/shell.ex` | Added `bash_background/0` tool definition |
| `lib/jido_code/application.ex` | Added `BackgroundShell` to supervision tree |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  BackgroundShell (GenServer)                                 │
│  - ETS table for shell registry                              │
│  - Maps shell_id -> process info and output                  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Task.Supervisor (JidoCode.TaskSupervisor)                   │
│  - Supervises background command Tasks                       │
│  - Handles crash isolation                                   │
└─────────────────────────────────────────────────────────────┘
```

## Key Components

### BackgroundShell GenServer

- **ETS Tables**: Uses two ETS tables:
  - `:jido_code_background_shells` - Shell registry (id, session, command, status, etc.)
  - `:jido_code_shell_output` - Output accumulator (id -> output string)

- **Key Functions**:
  - `start_command/5` - Start a background command
  - `get_output/2` - Get output (blocking or non-blocking)
  - `kill/1` - Kill a running process
  - `list/1` - List shells for a session
  - `clear_finished/1` - Clean up completed shells

### BashBackground Handler

Implements the tool handler for the LLM to invoke:

```elixir
def execute(%{"command" => command} = args, context) do
  with {:ok, session_id} <- get_session_id(context),
       {:ok, project_root} <- Shell.get_project_root(context),
       {:ok, shell_id} <- BackgroundShell.start_command(...) do
    {:ok, Jason.encode!(%{shell_id: shell_id, description: description})}
  end
end
```

### Tool Definition

```elixir
def bash_background do
  Tool.new!(%{
    name: "bash_background",
    description: "Start a command in the background...",
    handler: Handlers.BashBackground,
    parameters: [
      %{name: "command", type: :string, required: true},
      %{name: "args", type: :array, required: false},
      %{name: "description", type: :string, required: false}
    ]
  })
end
```

## Security

- Commands validated against Shell handler's allowlist
- Shell interpreters (bash, sh, zsh, etc.) are blocked
- Uses existing `Shell.validate_command/1` for consistency

## Telemetry Events

- `[:jido_code, :shell, :background_start]` - Process started
- `[:jido_code, :shell, :background_complete]` - Process completed
- `[:jido_code, :shell, :background_kill]` - Process killed
- `[:jido_code, :shell, :bash_background]` - Handler invocation

## Test Coverage

12 tests covering:
- Starting background processes
- Unique shell ID generation
- Command validation (allowlist and shell interpreter blocking)
- Output retrieval (blocking and non-blocking)
- Process killing
- Session-based listing
- Error handling for invalid shell IDs

## Design Decisions

1. **Handler Pattern over Lua Bridge**: Implemented using the Handler pattern for consistency with `run_command` and simpler maintenance.

2. **GenServer with ETS**: Used GenServer for process management with ETS tables for fast lookups and persistence across process restarts.

3. **Task.Supervisor**: Background commands run under `JidoCode.TaskSupervisor` for proper supervision and crash isolation.

4. **Output Truncation**: Output capped at 30,000 bytes to prevent memory exhaustion.

5. **Session Scoping**: Shell processes are scoped to sessions via `session_id` for isolation.

## Related Sections

- **Section 2.2**: `run_command` (foreground execution) - shares security validation
- **Section 2.4**: `bash_output` tool (deferred) - functionality integrated into `BackgroundShell.get_output/2`
- **Section 2.5**: `kill_shell` tool (deferred) - functionality integrated into `BackgroundShell.kill/1`

## Notes

The implementation covers the core functionality of sections 2.3, 2.4, and 2.5 in a unified `BackgroundShell` GenServer. The tool definitions for `bash_output` and `kill_shell` remain to be created if the LLM needs explicit tool calls for those operations, but the underlying functionality exists.
