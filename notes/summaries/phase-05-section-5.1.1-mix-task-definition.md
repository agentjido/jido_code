# Phase 5 Section 5.1.1 - Mix Task Tool Definition

**Branch:** `feature/phase5-section-5.1.1-mix-task-definition`
**Date:** 2026-01-01
**Status:** Complete

## Overview

This section implements the tool definition for the `mix_task` tool, which enables running Mix tasks with security controls. The definition includes the tool schema, parameter definitions, and registration via the `Elixir.all/0` function.

## Files Created

### Definition File
**`lib/jido_code/tools/definitions/elixir.ex`**

Defines the `mix_task` tool with:
- **Name:** `mix_task`
- **Description:** Run Mix task with allowlist-based security
- **Parameters:**
  - `task` (required, string) - Mix task name (e.g., 'compile', 'test')
  - `args` (optional, array) - Task arguments
  - `env` (optional, string, enum: dev|test) - Mix environment (prod blocked)

### Handler File (Stub with Full Implementation)
**`lib/jido_code/tools/handlers/elixir.ex`**

Contains:
- `ElixirHandler` module with shared helpers
- `MixTask` handler with full implementation
- Security validation functions
- Telemetry emission

### Test File
**`test/jido_code/tools/definitions/elixir_test.exs`**

20 tests covering:
- Tool definition structure
- Parameter validation
- Handler validation functions
- Executor integration
- Security enforcement

## Security Model

### Allowed Tasks
```elixir
~w(compile test format deps.get deps.compile deps.tree deps.unlock help credo dialyzer docs hex.info)
```

### Blocked Tasks
```elixir
~w(release archive.install escript.build local.hex local.rebar hex.publish deps.update do ecto.drop ecto.reset phx.gen.secret)
```

### Allowed Environments
- `dev` (default)
- `test`
- `prod` is **blocked** for safety

## Key Functions

| Function | Purpose |
|----------|---------|
| `Elixir.all/0` | Returns all Elixir tools for registration |
| `Elixir.mix_task/0` | Returns the mix_task tool definition |
| `ElixirHandler.validate_task/1` | Validates task against allowlist/blocklist |
| `ElixirHandler.validate_env/1` | Validates environment (blocks prod) |
| `MixTask.execute/2` | Executes mix task with security validation |

## Test Results

```
20 tests, 0 failures
```

## Usage Example

```elixir
# Register Elixir tools
for tool <- JidoCode.Tools.Definitions.Elixir.all() do
  :ok = JidoCode.Tools.Registry.register(tool)
end

# Execute via Executor
{:ok, context} = Executor.build_context(session_id)
Executor.execute(%{
  id: "call_123",
  name: "mix_task",
  arguments: %{"task" => "test", "args" => ["--trace"]}
}, context: context)
```

## Next Steps

Section 5.1.2 will enhance the handler implementation with:
- Additional task validation
- Better error handling
- Timeout configuration
- Output parsing
