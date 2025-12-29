# Phase 2 Task 2.3.1 & 2.3.2 - TripleStoreAdapter

**Date:** 2025-12-29
**Branch:** `feature/phase2-triple-store-adapter`
**Task:** 2.3.1 TripleStoreAdapter Module and 2.3.2 Unit Tests

## Overview

Implemented the TripleStoreAdapter module for mapping Elixir memory structs to/from RDF-like triples. This adapter provides the interface between the high-level Memory API and the underlying ETS-backed store, using the Jido ontology vocabulary for semantic structure.

## Implementation Details

### Module Location
`lib/jido_code/memory/long_term/triple_store_adapter.ex`

### Architecture

```
TripleStoreAdapter
     │
     ├── Types
     │    ├── memory_input() - Input for persist operations
     │    └── stored_memory() - Output from query operations
     │
     ├── Persist API
     │    ├── persist/2 - Store memory to ETS
     │    └── build_triples/1 - Generate RDF-compatible triples
     │
     ├── Query API
     │    ├── query_by_type/4 - Filter by memory type
     │    ├── query_all/3 - All memories with options
     │    └── query_by_id/2 - Single memory lookup
     │
     ├── Lifecycle API
     │    ├── supersede/4 - Mark memory as superseded
     │    ├── delete/3 - Remove memory
     │    └── record_access/3 - Track access statistics
     │
     ├── Counting API
     │    └── count/3 - Count memories for session
     │
     └── IRI Utilities
          ├── extract_id/1 - Extract ID from memory IRI
          └── memory_iri/1 - Generate IRI from ID
```

### Store Backend

Uses ETS tables (from StoreManager) as the backing store. Each memory is stored as a tuple:
```elixir
{memory_id, %{
  id: String.t(),
  content: String.t(),
  memory_type: atom(),
  confidence: float(),
  source_type: atom(),
  session_id: String.t(),
  agent_id: String.t() | nil,
  project_id: String.t() | nil,
  rationale: String.t() | nil,
  evidence_refs: [String.t()],
  created_at: DateTime.t(),
  superseded_by: String.t() | nil,
  superseded_at: DateTime.t() | nil,
  access_count: non_neg_integer(),
  last_accessed: DateTime.t() | nil
}}
```

### Features Implemented

#### Types
| Type | Description |
|------|-------------|
| `memory_input()` | Input map for persist operations with required and optional fields |
| `stored_memory()` | Output map from queries with lifecycle tracking fields |

#### Persist API
| Function | Description |
|----------|-------------|
| `persist/2` | Store memory item to ETS, returns `{:ok, id}` |
| `build_triples/1` | Generate RDF-compatible triple representation |

#### Query API
| Function | Description |
|----------|-------------|
| `query_by_type/4` | Query memories by type with limit option |
| `query_all/3` | Query all memories with filters (min_confidence, type, include_superseded) |
| `query_by_id/2` | Get single memory by ID |

#### Lifecycle API
| Function | Description |
|----------|-------------|
| `supersede/4` | Mark memory as superseded by another |
| `delete/3` | Permanently remove memory |
| `record_access/3` | Increment access count and update last_accessed |

#### Utility Functions
| Function | Description |
|----------|-------------|
| `count/3` | Count memories for session (with include_superseded option) |
| `extract_id/1` | Extract memory ID from IRI |
| `memory_iri/1` | Generate IRI for memory ID |

### RDF-Compatible Triple Generation

The `build_triples/1` function generates RDF-compatible tuples:
```elixir
[
  {subject, Vocab.rdf_type(), Vocab.memory_type_to_class(type)},
  {subject, Vocab.summary(), {:literal, content}},
  {subject, Vocab.has_confidence(), Vocab.confidence_to_individual(confidence)},
  {subject, Vocab.has_source_type(), Vocab.source_type_to_individual(source_type)},
  {subject, Vocab.asserted_in(), Vocab.session_uri(session_id)},
  {subject, Vocab.has_timestamp(), {:literal, timestamp_iso8601}},
  # Plus optional: asserted_by, applies_to_project, rationale, derived_from
]
```

## Test Coverage

**Test File:** `test/jido_code/memory/long_term/triple_store_adapter_test.exs`

**55 tests covering:**
- persist/2 with all required and optional fields
- build_triples/1 for all triple types
- query_by_type/4 with type filtering, session isolation, limit
- query_all/3 with min_confidence, include_superseded, type options
- query_by_id/2 for found and not found cases
- supersede/4 with session validation
- delete/3 with session validation
- record_access/3 incrementing counts and timestamps
- count/3 with and without superseded memories
- extract_id/1 and memory_iri/1 IRI utilities
- All memory types and source types

## Test Results

```
TripleStoreAdapter Tests: 55 tests, 0 failures
All Memory Tests: 323 tests, 0 failures
```

## Files Created

| File | Purpose |
|------|---------|
| `lib/jido_code/memory/long_term/triple_store_adapter.ex` | TripleStoreAdapter module |
| `test/jido_code/memory/long_term/triple_store_adapter_test.exs` | Comprehensive unit tests |

## Files Modified

| File | Changes |
|------|---------|
| `notes/planning/two-tier-memory/phase-02-long-term-store.md` | Marked 2.3.1 and 2.3.2 tasks complete (40 checkboxes) |

## Design Notes

### ETS-First Approach
The implementation uses ETS tables instead of RDF libraries because:
1. No external RDF library dependency required
2. Fast in-memory operations
3. Same interface can support real triple store later
4. Vocabulary module provides RDF-compatible semantics

### Session Isolation
- All operations validate session_id to prevent cross-session access
- Returns `{:error, :session_mismatch}` for unauthorized access attempts
- Queries automatically filter by session_id

### Triple Representation
While using ETS internally, the adapter maintains RDF semantics:
- `build_triples/1` generates standard {subject, predicate, object} tuples
- Uses Vocab module for all IRI construction
- Supports future migration to real triple store

### Query Options
| Option | Default | Description |
|--------|---------|-------------|
| `:limit` | nil | Maximum results to return |
| `:min_confidence` | 0.0 | Minimum confidence threshold |
| `:include_superseded` | false | Include superseded memories |
| `:type` | nil | Filter by memory type |

## Next Steps

This completes Tasks 2.3.1 and 2.3.2. The TripleStoreAdapter is now ready for:
- Task 2.4 - Memory Facade (public API wrapper)
- Task 2.5 - Memory Supervisor (supervision tree)
- Task 2.6 - Phase 2 Integration Tests
