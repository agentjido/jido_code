# ADR 0002: Memory Tool Executor Routing

## Status

Accepted

## Context

The tool executor (`lib/jido_code/tools/executor.ex`) handles tool calls from the LLM agent. Currently, all tools are routed through the Lua sandbox for security isolation. The memory system introduces three new tools (remember, recall, forget) that use the Jido Actions pattern.

### Problem Statement

Memory tools need different routing than standard tools:

1. **Standard tools** (file, shell, web): Route through Lua sandbox for security sandboxing
2. **Memory tools** (remember, recall, forget): Use Jido Actions pattern, require session context

### Key Considerations

1. **Security Model**:
   - Standard tools interact with filesystem, shell, and web - requiring sandbox isolation
   - Memory tools only interact with the internal memory storage system
   - Memory operations are trusted internal operations within session scope

2. **Architecture Patterns**:
   - Standard tools use `Tools.Registry` + Lua sandbox execution
   - Memory tools use `Jido.Action` with `Memory.Actions` registry
   - Both patterns coexist by design

3. **Session Context**:
   - Memory tools require `session_id` in context for session-scoped operations
   - Standard tools use `project_root` for security boundary

## Decision

Add a guard clause pattern to the executor that routes memory tools directly to Jido Actions, bypassing the Lua sandbox.

### Implementation

```elixir
# In executor.ex

@memory_tools ["remember", "recall", "forget"]

# Add a new function head before the existing execute/2
def execute(%{id: id, name: name, arguments: args} = tool_call, opts)
    when name in @memory_tools do
  context = Keyword.get(opts, :context, %{})
  session_id = get_session_id(context, Keyword.get(opts, :session_id))
  start_time = System.monotonic_time(:millisecond)

  # Broadcast tool call start
  broadcast_tool_call(session_id, name, args, id)

  result = execute_memory_action(id, name, args, context, start_time)

  # Broadcast tool result
  case result do
    {:ok, tool_result} -> broadcast_tool_result(session_id, tool_result)
    _ -> :ok
  end

  result
end

defp execute_memory_action(id, name, args, context, start_time) do
  case JidoCode.Memory.Actions.get(name) do
    {:ok, action_module} ->
      case action_module.run(args, context) do
        {:ok, result} ->
          duration = System.monotonic_time(:millisecond) - start_time
          {:ok, Result.success(id, name, result, duration)}

        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time
          {:ok, Result.error(id, name, reason, duration)}
      end

    {:error, :not_found} ->
      duration = System.monotonic_time(:millisecond) - start_time
      {:ok, Result.error(id, name, "Memory action '#{name}' not found", duration)}
  end
end
```

### Routing Diagram

```
LLM Tool Call
      │
      ▼
  Executor.execute/2
      │
      ├──────────────────────────────────────────┐
      │ name in ["remember", "recall", "forget"] │
      │ (guard clause)                           │
      ▼                                          ▼
Memory Path                              Standard Path
      │                                          │
      ▼                                          ▼
Memory.Actions.get(name)              validate_tool_exists(name)
      │                                          │
      ▼                                          ▼
action_module.run(args, context)      executor.(tool, args, context)
      │                                          │
      ▼                                          ▼
Result.success/error                   Lua Sandbox → Bridge → Handler
```

## Consequences

### Positive

1. **Clean Separation**: Memory tools use native Jido Actions without sandbox overhead
2. **Consistent API**: Both tool types flow through the same `execute/2` entry point
3. **PubSub Integration**: Memory tools emit the same `{:tool_call, ...}` and `{:tool_result, ...}` events
4. **Result Compatibility**: Memory tool results use the same `Result` struct for LLM formatting

### Negative

1. **Executor Complexity**: Adds conditional routing logic to executor
2. **Guard Clause Maintenance**: New memory tools require updating the `@memory_tools` list

### Neutral

1. **No Registry Integration**: Memory tools don't appear in `Tools.Registry` - they're discovered via `Memory.Actions`
2. **Different Validation**: Memory tools validate through Jido.Action schema, not Tool parameter schema

## Alternatives Considered

### 1. Register Memory Tools in Tools.Registry

**Rejected**: Would require adapting Jido Actions to the Tool/Handler pattern, losing the benefits of the action framework.

### 2. Separate Executor for Memory Tools

**Rejected**: Would fragment the tool execution path and complicate PubSub event handling.

### 3. Route Memory Tools Through Lua Sandbox

**Rejected**: Memory tools don't need security sandboxing (trusted internal operations), and the Lua bridge would add unnecessary complexity.

## References

- `notes/planning/two-tier-memory/conciliation.md` - Parallel development conflict analysis
- `notes/planning/two-tier-memory/phase-04-memory-tools.md` - Phase 4 implementation plan
- `lib/jido_code/memory/actions.ex` - Memory action registry
