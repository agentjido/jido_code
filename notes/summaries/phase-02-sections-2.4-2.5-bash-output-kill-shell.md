# Phase 2 Sections 2.4-2.5: Bash Output & Kill Shell Tools - Implementation Summary

## Overview

Implemented the `bash_output` and `kill_shell` tools for managing background shell processes. These tools complement the `bash_background` tool (Section 2.3) to provide a complete background process management workflow.

## Implementation Date

2026-01-02

## Branch

`feature/phase2-sections-2.4-2.5-bash-output-kill-shell`

## Files Modified

| File | Change |
|------|--------|
| `lib/jido_code/tools/definitions/shell.ex` | Added `bash_output/0` and `kill_shell/0` tool definitions |
| `lib/jido_code/tools/handlers/shell.ex` | Added `BashOutput` and `KillShell` handler modules |
| `test/jido_code/tools/background_shell_test.exs` | Added 9 new tests for the handlers |
| `notes/planning/tooling/phase-02-tools.md` | Marked Sections 2.4-2.5 as complete |

## Tools Implemented

### bash_output

Retrieves output from a background shell process.

**Parameters:**
- `shell_id` (required, string) - Shell ID returned by bash_background
- `block` (optional, boolean) - Wait for completion (default: true)
- `timeout` (optional, integer) - Max wait time in ms (default: 30000)

**Output:**
```json
{
  "output": "command output...",
  "status": "completed",
  "exit_code": 0
}
```

**Status values:** `running`, `completed`, `failed`, `killed`

### kill_shell

Terminates a background shell process.

**Parameters:**
- `shell_id` (required, string) - Shell ID returned by bash_background

**Output:**
```json
{
  "success": true,
  "message": "Shell terminated: abc123"
}
```

## Handler Implementation

Both handlers delegate to the existing `BackgroundShell` GenServer:

```elixir
# BashOutput
def execute(%{"shell_id" => shell_id} = args, context) do
  opts = [block: Map.get(args, "block", true), timeout: Map.get(args, "timeout", 30_000)]
  case BackgroundShell.get_output(shell_id, opts) do
    {:ok, result} -> {:ok, Jason.encode!(result)}
    {:error, reason} -> {:error, format_error(reason)}
  end
end

# KillShell
def execute(%{"shell_id" => shell_id}, context) do
  case BackgroundShell.kill(shell_id) do
    :ok -> {:ok, Jason.encode!(%{success: true, message: "..."})}
    {:error, reason} -> {:error, format_error(reason)}
  end
end
```

## Telemetry Events

- `[:jido_code, :shell, :bash_output]` - Output retrieval
- `[:jido_code, :shell, :kill_shell]` - Process termination

## Test Coverage

9 new tests added (total 21 tests in background_shell_test.exs):

**BashOutput tests:**
- Retrieves output from completed process
- Returns running status for in-progress process
- Defaults to blocking mode
- Returns error for non-existent shell_id
- Requires shell_id argument

**KillShell tests:**
- Kills a running process
- Handles already-finished process
- Returns error for non-existent shell_id
- Requires shell_id argument

## Complete Background Shell Workflow

```
1. Start background process:
   bash_background(command: "mix test", args: ["--trace"])
   → returns: {shell_id: "abc123", description: "..."}

2. Check status (non-blocking):
   bash_output(shell_id: "abc123", block: false)
   → returns: {output: "...", status: "running", exit_code: null}

3. Wait for completion:
   bash_output(shell_id: "abc123", block: true, timeout: 60000)
   → returns: {output: "...", status: "completed", exit_code: 0}

4. Or terminate early:
   kill_shell(shell_id: "abc123")
   → returns: {success: true, message: "Shell terminated: abc123"}
```

## Phase 2 Completion

With Sections 2.4-2.5 complete, Phase 2 is now **100% complete**:

| Section | Tool | Status |
|---------|------|--------|
| 2.1 | grep | ✅ Complete |
| 2.2 | run_command | ✅ Complete |
| 2.3 | bash_background | ✅ Complete |
| 2.4 | bash_output | ✅ Complete |
| 2.5 | kill_shell | ✅ Complete |
| 2.6 | Integration Tests | ✅ Complete |
