# Phase 7D: Knowledge Graph Query Tool

## Overview

Implemented Section 7.8 `knowledge_graph_query` from the Phase 7D planning document. This P3 tool enables LLM traversal of the knowledge graph to find related memories via various relationship types.

## Changes Made

### New Tool: `knowledge_graph_query`

A new LLM-callable tool that traverses the knowledge graph to find memories related to a starting memory via specified relationships.

**Parameters:**
- `start_from` (required) - Memory ID to start traversal from
- `relationship` (required) - One of: `derived_from`, `superseded_by`, `supersedes`, `same_type`, `same_project`
- `depth` (optional) - Maximum traversal depth (default: 1, max: 5)
- `limit` (optional) - Maximum results per level (default: 10)
- `include_superseded` (optional) - Include superseded memories (default: false)

**Relationship Types:**
- `derived_from` - Follow evidence chain to find referenced memories
- `superseded_by` - Find the memory that replaced this one
- `supersedes` - Find memories that this one replaced
- `same_type` - Find other memories of the same type
- `same_project` - Find memories in the same project

### API Additions

#### TripleStoreAdapter

```elixir
@spec query_related(store_ref(), String.t(), String.t(), relationship(), keyword()) ::
        {:ok, [stored_memory()]} | {:error, term()}
def query_related(store, session_id, start_memory_id, relationship, opts \\ [])

@spec get_stats(store_ref(), String.t()) :: {:ok, map()} | {:error, term()}
def get_stats(store, session_id)

@spec relationship_types() :: [relationship()]
def relationship_types()
```

#### Memory Facade

```elixir
@spec query_related(String.t(), String.t(), relationship(), keyword()) ::
        {:ok, [stored_memory()]} | {:error, term()}
def query_related(session_id, memory_id, relationship, opts \\ [])

@spec get_stats(String.t()) :: {:ok, map()} | {:error, term()}
def get_stats(session_id)

@spec relationship_types() :: [relationship()]
def relationship_types()
```

### Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/memory/long_term/triple_store_adapter.ex` | Added `query_related/4`, `get_stats/2`, relationship types |
| `lib/jido_code/memory/memory.ex` | Added facade methods for graph traversal and stats |
| `lib/jido_code/tools/definitions/knowledge.ex` | Added `knowledge_graph_query/0`, updated `all/0` to return 8 tools |
| `lib/jido_code/tools/handlers/knowledge.ex` | Added `KnowledgeGraphQuery` handler module |
| `test/jido_code/tools/handlers/knowledge_test.exs` | Added ~35 new tests for graph query functionality |

## Implementation Details

### Graph Traversal Algorithm

The `query_related/4` function implements recursive graph traversal with:
- Cycle detection via `MapSet` to prevent infinite loops
- Configurable depth limiting (max 5 levels)
- Per-level result limiting
- Optional inclusion of superseded memories

### Relationship Resolution

Each relationship type uses different traversal strategies:
- `derived_from` - Parses `evidence_refs` field for memory ID references
- `superseded_by` - Follows `superseded_by` field links
- `supersedes` - Searches for memories where `superseded_by` matches start ID
- `same_type` - Queries memories with matching type
- `same_project` - Queries all memories in the session (project scope)

### Statistics API

The `get_stats/2` function returns:
```elixir
%{
  total_count: integer(),
  by_type: %{atom() => integer()},
  by_confidence: %{
    high: integer(),      # >= 0.8
    medium: integer(),    # 0.5 - 0.8
    low: integer()        # < 0.5
  },
  with_evidence: integer(),
  with_rationale: integer(),
  superseded_count: integer()
}
```

## Test Coverage

Added comprehensive tests covering:
- Handler validation (missing params, invalid relationship, invalid memory ID format)
- All 5 relationship types
- Depth and limit options
- Telemetry emission
- Empty result handling
- Direct TripleStoreAdapter API tests
- Memory facade integration tests
- Statistics API tests

**Total tests:** 173 (all passing)

## Telemetry

Emits telemetry event:
```elixir
[:jido_code, :knowledge, :graph_query]
```

With metadata: `session_id`, `relationship`, `depth`, `result_count`, `duration`
