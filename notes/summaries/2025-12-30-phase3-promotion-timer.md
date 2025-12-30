# Phase 3.3.1: Periodic Promotion Timer Implementation

**Date:** 2025-12-30
**Branch:** `feature/phase3-promotion-timer`
**Scope:** Implement periodic promotion timer in Session.State

## Overview

This implementation adds a periodic timer to Session.State that automatically runs the Promotion.Engine to evaluate and promote worthy short-term memories to long-term storage.

## Implementation Summary

### Modified Files

| File | Changes |
|------|---------|
| `lib/jido_code/session/state.ex` | Added promotion timer logic and public API |
| `test/jido_code/session/state_test.exs` | Added 22 new tests for promotion timer |

### New Configuration Constants

```elixir
@default_promotion_interval_ms 30_000  # 30 seconds
@default_promotion_enabled true
```

### New State Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `promotion_enabled` | boolean | true | Whether timer is active |
| `promotion_interval_ms` | pos_integer | 30,000 | Timer interval |
| `promotion_timer_ref` | reference \| nil | nil | Timer reference |
| `promotion_stats` | map | see below | Tracking stats |

Promotion stats structure:
```elixir
%{
  last_run: DateTime.t() | nil,
  total_promoted: non_neg_integer(),
  runs: non_neg_integer()
}
```

### New Public API

| Function | Purpose |
|----------|---------|
| `enable_promotion/1` | Enable timer and schedule promotion |
| `disable_promotion/1` | Disable timer and cancel pending |
| `get_promotion_stats/1` | Get promotion statistics |
| `set_promotion_interval/2` | Change promotion interval |
| `run_promotion_now/1` | Trigger immediate promotion run |

### Timer Flow

```
Session.State.init/1
       │
       ▼
┌─────────────────────────────────────────┐
│         schedule_promotion/1            │
│  • Cancel existing timer if any         │
│  • Schedule :run_promotion message      │
│  • Store timer_ref in state             │
└─────────────────────────────────────────┘
       │
       ▼ (after interval_ms)
┌─────────────────────────────────────────┐
│    handle_info(:run_promotion)          │
│  • Check if enabled                     │
│  • Build promotion state                │
│  • Call PromotionEngine.run_with_state  │
│  • Clear promoted items                 │
│  • Update stats                         │
│  • Reschedule timer                     │
└─────────────────────────────────────────┘
       │
       ▼
    (loops)
```

### Session Config Integration

The timer reads configuration from the Session struct:

```elixir
# Session config can override defaults
session.config.promotion_enabled     # default: true
session.config.promotion_interval_ms # default: 30_000
```

---

## Test Results

```
951 tests, 0 failures (session and memory tests)
130 tests in state_test.exs, 0 failures
```

### New Test Coverage (22 tests)

**Promotion Timer Initialization (5 tests)**
- Initializes with promotion_enabled = true by default
- Initializes with default promotion_interval_ms
- Initializes with nil promotion_timer_ref when disabled
- Schedules timer when promotion is enabled
- Initializes empty promotion_stats

**enable_promotion/1 (3 tests)**
- Enables promotion and schedules timer
- Is idempotent when already enabled
- Returns :not_found for unknown session

**disable_promotion/1 (3 tests)**
- Disables promotion and cancels timer
- Cancels pending timer message
- Returns :not_found for unknown session

**get_promotion_stats/1 (2 tests)**
- Returns all promotion statistics
- Returns :not_found for unknown session

**set_promotion_interval/2 (3 tests)**
- Updates promotion interval
- Rejects non-positive intervals
- Returns :not_found for unknown session

**run_promotion_now/1 (4 tests)**
- Runs promotion immediately and returns count
- Updates promotion stats after run
- Promotes pending memories that meet threshold
- Returns :not_found for unknown session

**handle_info(:run_promotion) (3 tests)**
- Runs promotion when enabled
- Reschedules timer after promotion
- Does not reschedule when disabled

---

## Key Implementation Details

### Timer Scheduling

```elixir
defp schedule_promotion(state) do
  if state.promotion_timer_ref do
    Process.cancel_timer(state.promotion_timer_ref)
  end

  timer_ref = Process.send_after(self(), :run_promotion, state.promotion_interval_ms)
  %{state | promotion_timer_ref: timer_ref}
end
```

### Promotion Execution

```elixir
def handle_info(:run_promotion, state) do
  if state.promotion_enabled do
    promotion_state = %{
      working_context: state.working_context,
      pending_memories: state.pending_memories,
      access_log: state.access_log
    }

    case PromotionEngine.run_with_state(promotion_state, state.session_id, []) do
      {:ok, count, promoted_ids} when count > 0 ->
        # Clear promoted, update stats, reschedule
        ...
      {:ok, 0} ->
        # Update stats, reschedule
        ...
      {:error, _reason} ->
        # Log warning, reschedule
        ...
    end
  else
    {:noreply, state}
  end
end
```

---

## Integration Points

| Module | Integration |
|--------|-------------|
| `Promotion.Engine` | Called via `run_with_state/3` |
| `PendingMemories` | Clears promoted items via `clear_promoted/2` |
| `WorkingContext` | Passed to engine for candidate evaluation |
| `AccessLog` | Passed to engine for importance scoring |

---

## Usage Examples

```elixir
# Get promotion stats
{:ok, stats} = State.get_promotion_stats(session_id)
# => %{enabled: true, interval_ms: 30000, last_run: nil, total_promoted: 0, runs: 0}

# Disable promotion temporarily
:ok = State.disable_promotion(session_id)

# Re-enable promotion
:ok = State.enable_promotion(session_id)

# Change interval to 1 minute
:ok = State.set_promotion_interval(session_id, 60_000)

# Trigger immediate promotion
{:ok, count} = State.run_promotion_now(session_id)
```

---

## Next Steps

The next tasks in Phase 3 are:
- **3.3.2** Event-based Promotion Triggers (context threshold, tool completion)
- **3.4** Session.State Promotion Integration (end-of-session promotion)

---

## Conclusion

Task 3.3.1 (Periodic Promotion Timer) is complete. The implementation:

1. Adds configurable periodic timer to Session.State
2. Integrates with Promotion.Engine for automatic memory promotion
3. Provides public API for runtime control (enable/disable/stats)
4. Cleans up promoted items from pending memories
5. Tracks promotion statistics for observability
6. Has comprehensive test coverage (22 new tests)
