# Phase 7.9: Knowledge Context Tool

## Overview

Implemented Section 7.9 `knowledge_context` from the Phase 7 planning document. This P3 tool enables LLM auto-retrieval of relevant context using a multi-factor relevance scoring algorithm.

## Changes Made

### New Tool: `knowledge_context`

An LLM-callable tool that automatically retrieves the most relevant memories based on a context hint, without requiring explicit queries.

**Parameters:**
- `context_hint` (required) - Description of what context is needed (3-1000 chars)
- `include_types` (optional) - Filter to specific memory types
- `min_confidence` (optional) - Minimum confidence threshold (default: 0.5)
- `max_results` (optional) - Maximum results to return (default: 5, max: 50)
- `recency_weight` (optional) - Weight for recency in scoring (default: 0.3)
- `include_superseded` (optional) - Include superseded memories (default: false)

**Relevance Scoring Algorithm:**
- **Text Similarity (40%)** - Word overlap between context hint and memory content
- **Recency (30%)** - Exponential decay based on time since last access/creation
- **Confidence (20%)** - Memory's confidence level
- **Access Frequency (10%)** - Normalized access count

### API Additions

#### TripleStoreAdapter

```elixir
@spec get_context(store_ref(), String.t(), String.t(), keyword()) ::
        {:ok, [{stored_memory(), float()}]} | {:error, term()}
def get_context(store, session_id, context_hint, opts \\ [])
```

#### Memory Facade

```elixir
@spec get_context(String.t(), String.t(), keyword()) ::
        {:ok, [{map(), float()}]} | {:error, term()}
def get_context(session_id, context_hint, opts \\ [])
```

### Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/definitions/knowledge.ex` | Added `knowledge_context/0`, updated `all/0` to return 9 tools |
| `lib/jido_code/tools/handlers/knowledge.ex` | Added `KnowledgeContext` handler module |
| `lib/jido_code/memory/memory.ex` | Added `get_context/3` facade method |
| `lib/jido_code/memory/long_term/triple_store_adapter.ex` | Added `get_context/4` with scoring algorithm |
| `test/jido_code/tools/handlers/knowledge_test.exs` | Added ~25 new tests for context functionality |

## Implementation Details

### Relevance Scoring Algorithm

The `get_context/4` function implements multi-factor relevance scoring:

1. **Text Similarity** - Uses Jaccard-like word overlap:
   - Extracts words from context hint and memory content/rationale
   - Calculates coverage of context words in memory
   - Weighted 70% context coverage, 30% memory coverage

2. **Recency** - Exponential decay function:
   - Uses `last_accessed` or `created_at` timestamp
   - 7-day decay period (score approaches 0 after 7 days)
   - Formula: `e^(-seconds_ago / 604800)`

3. **Confidence** - Direct use of memory's confidence value

4. **Access Frequency** - Normalized by max access count in session

### Configurable Weights

The `recency_weight` parameter allows tuning the scoring balance:
- Default: 0.3 (30% recency, 40% text, 20% confidence, 10% access)
- Higher values favor recently accessed memories
- Weights automatically rebalance to sum to 1.0

### Handler Validation

- Validates `context_hint` length (3-1000 characters)
- Validates numeric parameters are within bounds
- Safe atom conversion for `include_types`

## Test Coverage

Added comprehensive tests covering:
- Handler validation (missing params, length limits)
- Relevance scoring behavior
- Parameter options (max_results, min_confidence, include_types)
- Superseded memory filtering
- Telemetry emission (success and failure)
- Memory facade API tests
- Scoring algorithm tests (text similarity, confidence effects)

**Total tests:** 205 (all passing)
**New tests added:** 25

## Telemetry

Emits telemetry event:
```elixir
[:jido_code, :knowledge, :context]
```

With metadata: `session_id`, `status`, `duration`

## Usage Example

```elixir
# Via handler
args = %{
  "context_hint" => "authentication flow using Guardian",
  "include_types" => ["decision", "convention"],
  "max_results" => 5
}
{:ok, json} = KnowledgeContext.execute(args, %{session_id: session_id})

# Via Memory facade
{:ok, scored} = Memory.get_context(session_id, "error handling patterns",
  include_types: [:convention],
  min_confidence: 0.8
)
# Returns: [{%{id: "mem-...", content: "...", ...}, 0.75}, ...]
```
