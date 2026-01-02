# Phase 5 Section 5.4.2 Budget Allocator Summary

## Overview

This task implements Section 5.4.2 of the Phase 5 plan: the Budget Allocator. This integrates the TokenCounter module into ContextBuilder to enable token-aware budget allocation and truncation during context assembly.

## Files Modified

### `lib/jido_code/memory/context_builder.ex`

Added TokenCounter integration for budget allocation and enforcement:

**New Import:**
```elixir
alias JidoCode.Memory.TokenCounter
```

**New Public Function - `allocate_budget/1`:**

| Function | Purpose |
|----------|---------|
| `allocate_budget/1` | Allocate tokens based on total budget with proportional distribution |

Budget distribution ratios:
- `system`: ~6% (capped at 2,000 tokens)
- `conversation`: ~62.5%
- `working`: ~12.5%
- `long_term`: ~19%

```elixir
@spec allocate_budget(pos_integer()) :: token_budget()
def allocate_budget(total) when is_integer(total) and total > 0 do
  %{
    total: total,
    system: min(2_000, div(total, 16)),
    conversation: div(total * 5, 8),
    working: div(total, 8),
    long_term: div(total * 3, 16)
  }
end

def allocate_budget(_), do: @default_budget
```

**Updated Private Functions:**

1. **`truncate_messages_to_budget/2`** - Now uses `TokenCounter.count_message/1`:
   - Processes messages in reverse order (most recent first)
   - Uses `reduce_while` to stop when budget exhausted
   - Returns messages that fit within budget

2. **`truncate_memories_to_budget/2`** - Now sorts by confidence and uses `TokenCounter.count_memory/1`:
   - Sorts memories by confidence descending (highest first)
   - Uses `reduce_while` to fill budget with highest confidence memories
   - Reverses result to maintain consistent ordering

3. **Token estimation functions** - Simplified to delegate to TokenCounter:
   ```elixir
   defp estimate_conversation_tokens(messages), do: TokenCounter.count_messages(messages)
   defp estimate_working_tokens(working), do: TokenCounter.count_working_context(working)
   defp estimate_memories_tokens(memories), do: TokenCounter.count_memories(memories)
   ```

### `test/jido_code/memory/context_builder_test.exs`

Added 7 new tests for budget allocation and truncation:

**`allocate_budget/1` tests (6 tests):**
- Distributes tokens correctly for 32,000 total
- Distributes tokens correctly for 16,000 total
- Caps system budget at 2,000 for large totals
- Handles small budgets
- Returns default budget for invalid input
- Produces valid budget structure

**Truncation tests (1 new test):**
- Preserves highest confidence memories when truncating

## Design Decisions

1. **Proportional distribution** - Budget ratios prioritize conversation history (~62.5%) as the primary context source, with smaller allocations for working context and long-term memories.

2. **System budget cap** - System budget is capped at 2,000 tokens to prevent excessive system prompt allocation for very large total budgets.

3. **Conversation truncation strategy** - Preserves most recent messages, as recent context is typically more relevant than older messages.

4. **Memory truncation strategy** - Preserves highest confidence memories, ensuring the most reliable information is kept when truncation is necessary.

5. **TokenCounter integration** - All token counting is now delegated to TokenCounter for consistency across the codebase.

## Usage Examples

```elixir
# Allocate budget for 32,000 total tokens
budget = ContextBuilder.allocate_budget(32_000)
# => %{total: 32_000, system: 2_000, conversation: 20_000, working: 4_000, long_term: 6_000}

# Build context with custom budget
{:ok, context} = ContextBuilder.build(session_id,
  token_budget: ContextBuilder.allocate_budget(16_000)
)

# Token counts are included in context
context.token_counts
# => %{conversation: 150, working: 20, long_term: 50, total: 220}
```

## Test Results

```
Finished in 0.7 seconds
53 tests, 0 failures (context_builder_test.exs)
46 tests, 0 failures (token_counter_test.exs)
```

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/memory/context_builder.ex` | Added allocate_budget/1, TokenCounter integration, updated truncation functions |
| `test/jido_code/memory/context_builder_test.exs` | Added 7 new tests for budget allocation and truncation |
| `notes/planning/two-tier-memory/phase-05-agent-integration.md` | Marked 5.4.2.1-5.4.2.4 and related tests complete |

## Branch

`feature/phase5-budget-allocator`

## Next Steps

The remaining 5.4 subtasks are now all complete. Section 5.5 (Phase 5 Integration Tests) is the next major section to implement.
