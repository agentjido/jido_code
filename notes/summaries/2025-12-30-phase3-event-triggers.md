# Phase 3.3.2: Event-Based Promotion Triggers Implementation

**Date:** 2025-12-30
**Branch:** `feature/phase3-event-triggers`
**Scope:** Implement event-based triggers for memory promotion

## Overview

This implementation adds event-based triggers that activate memory promotion in response to specific session lifecycle events. Unlike the periodic timer (which runs at fixed intervals), these triggers respond to events that indicate an optimal time to promote memories.

## Implementation Summary

### New Files Created

| File | Purpose |
|------|---------|
| `lib/jido_code/memory/promotion/triggers.ex` | Event-based promotion trigger functions |
| `test/jido_code/memory/promotion/triggers_test.exs` | Comprehensive unit tests (18 tests) |

### Modified Files

| File | Changes |
|------|---------|
| `lib/jido_code/session/state.ex` | Added trigger integration in callbacks |

## Trigger Types

| Trigger | Event | Behavior |
|---------|-------|----------|
| `on_session_pause/1` | Session paused | Synchronous promotion before pause completes |
| `on_session_close/1` | Session closing | Final promotion with lower threshold (0.4) |
| `on_memory_limit_reached/2` | Pending memories at capacity | Promotion to clear space |
| `on_agent_decision/2` | Agent explicitly requests remember | Immediate high-priority promotion |

## Trigger Flow

```
Session Events
     │
     ├─────────────────────────────────────────────────────┐
     │                                                      │
     ▼                                                      ▼
┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐
│ on_session_pause   │  │ on_session_close   │  │ on_agent_decision  │
│                    │  │                    │  │                    │
│ • Synchronous      │  │ • Lower threshold  │  │ • Immediate        │
│ • Before pause     │  │ • Final promotion  │  │ • Bypass threshold │
└────────────────────┘  └────────────────────┘  └────────────────────┘
           │                      │                      │
           └──────────────────────┼──────────────────────┘
                                  │
                                  ▼
                    ┌────────────────────────────┐
                    │   PromotionEngine.run()    │
                    │   or direct persist        │
                    └────────────────────────────┘
                                  │
                                  ▼
                    ┌────────────────────────────┐
                    │   emit_trigger_telemetry   │
                    │   [:jido_code, :memory,    │
                    │    :promotion, :triggered] │
                    └────────────────────────────┘
```

## Public API

```elixir
# Session lifecycle triggers
Triggers.on_session_pause(session_id, opts \\ [])
Triggers.on_session_close(session_id, opts \\ [])

# Capacity trigger
Triggers.on_memory_limit_reached(session_id, current_count, opts \\ [])

# High-priority trigger
Triggers.on_agent_decision(session_id, memory_item, opts \\ [])
```

### Options

| Option | Type | Purpose |
|--------|------|---------|
| `:agent_id` | String | Agent identifier for promoted memories |
| `:project_id` | String | Project identifier for promoted memories |
| `:threshold` | float | Custom promotion threshold (session_close uses 0.4) |

## Session.State Integration

### Memory Limit Trigger

When `add_pending_memory/2` is called and the pending memories reach capacity, the memory limit trigger fires asynchronously:

```elixir
def handle_call({:add_pending_memory, item}, _from, state) do
  updated_pending = PendingMemories.add_implicit(state.pending_memories, item)
  current_count = PendingMemories.size(updated_pending)

  if current_count >= @max_pending_memories do
    Task.start(fn ->
      PromotionTriggers.on_memory_limit_reached(state.session_id, current_count)
    end)
  end

  {:reply, :ok, %{state | pending_memories: updated_pending}}
end
```

### Agent Decision Trigger

When `add_agent_memory_decision/2` is called, the agent decision trigger fires asynchronously for immediate promotion:

```elixir
def handle_call({:add_agent_memory_decision, item}, _from, state) do
  updated_pending = PendingMemories.add_agent_decision(state.pending_memories, item)

  Task.start(fn ->
    PromotionTriggers.on_agent_decision(state.session_id, item)
  end)

  {:reply, :ok, %{state | pending_memories: updated_pending}}
end
```

## Telemetry Events

All triggers emit telemetry:

```elixir
:telemetry.execute(
  [:jido_code, :memory, :promotion, :triggered],
  %{promoted_count: count},
  %{
    session_id: session_id,
    trigger: :session_pause | :session_close | :memory_limit_reached | :agent_decision,
    status: :success | :error,
    # Additional metadata for specific triggers
    current_count: count  # for memory_limit_reached
  }
)
```

---

## Test Results

```
969 tests, 0 failures (session and memory tests)
18 tests in triggers_test.exs, 0 failures
```

### Test Coverage

**on_session_pause/1 (4 tests)**
- Runs promotion and returns count
- Returns {:ok, 0} when no candidates to promote
- Returns error for unknown session
- Emits telemetry event

**on_session_close/1 (4 tests)**
- Runs promotion and returns count
- Uses lower threshold for final promotion
- Returns error for unknown session
- Emits telemetry event

**on_memory_limit_reached/2 (3 tests)**
- Runs promotion to clear space
- Returns error for unknown session
- Emits telemetry with current_count

**on_agent_decision/2 (3 tests)**
- Promotes single memory item immediately
- Generates id if not provided
- Emits telemetry event

**Integration (1 test)**
- add_agent_memory_decision triggers promotion asynchronously

**Input Validation (3 tests)**
- on_session_pause requires binary session_id
- on_memory_limit_reached requires non-negative count
- on_agent_decision requires map item

---

## Usage Examples

### Session Pause/Close Triggers

```elixir
# During session pause
def handle_call(:pause, _from, state) do
  Triggers.on_session_pause(state.session_id)
  # ... pause logic ...
end

# During session close
def handle_call(:close, _from, state) do
  Triggers.on_session_close(state.session_id)
  # ... close logic ...
end
```

### Agent Decision Trigger

```elixir
# Agent explicitly decides to remember
memory_item = %{
  content: "User prefers explicit module aliases",
  memory_type: :convention,
  confidence: 1.0,
  source_type: :user,
  evidence: ["User stated preference"]
}

{:ok, 1} = Triggers.on_agent_decision(session_id, memory_item)
```

---

## Next Steps

The next tasks in Phase 3 are:
- **3.3.3** Unit Tests for Promotion Triggers (partially covered)
- **3.5** Phase 3 Integration Tests

---

## Conclusion

Task 3.3.2 (Event-Based Promotion Triggers) is complete. The implementation:

1. Creates a Triggers module with four event-based trigger functions
2. Integrates triggers with Session.State callbacks
3. Provides async promotion for memory limit and agent decisions
4. Emits telemetry for all trigger activations
5. Uses lower threshold for session close (more aggressive final promotion)
6. Has comprehensive test coverage (18 tests)
