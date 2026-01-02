# Phase 7 Section 7.3: SPARQL Query Templates

**Date:** 2026-01-02
**Branch:** `feature/phase7-section7.3-sparql-queries`

## Overview

This section implements the `SPARQLQueries` module that provides SPARQL query and update templates for all memory operations. The module generates standards-compliant SPARQL 1.1 queries that work with the Jido ontology.

## Implementation Summary

### New File: `lib/jido_code/memory/long_term/sparql_queries.ex`

The SPARQLQueries module provides comprehensive SPARQL query generation:

**SPARQL Prefixes:**
- `jido:` - Jido ontology namespace (`https://jido.ai/ontology#`)
- `rdf:` - RDF syntax namespace
- `rdfs:` - RDF Schema namespace
- `xsd:` - XML Schema datatypes
- `owl:` - OWL ontology namespace

**Core Query Functions:**

| Function | Purpose |
|----------|---------|
| `insert_memory/1` | INSERT DATA query for creating memory triples |
| `query_by_session/2` | SELECT query for session memories with options |
| `query_by_type/3` | SELECT query filtered by memory type |
| `query_by_id/1` | SELECT query for single memory lookup |
| `supersede_memory/2` | INSERT DATA to mark memory as superseded |
| `delete_memory/1` | Soft delete via DeletedMarker supersession |
| `record_access/1` | UPDATE to track lastAccessed timestamp |

**Advanced Query Functions:**

| Function | Purpose |
|----------|---------|
| `query_related/2` | Find memories by relationship (refines, confirms, superseded_by) |
| `query_by_evidence/1` | Find memories derived from specific evidence |
| `query_decisions_with_alternatives/1` | Find Decision memories with their alternatives |
| `query_lessons_for_error/1` | Find LessonLearned memories for an error |

**Type Mapping Functions:**

| Function | Purpose |
|----------|---------|
| `memory_type_to_class/1` | Convert atom to OWL class name (`:fact` → `"Fact"`) |
| `class_to_memory_type/1` | Convert OWL class to atom (`"Fact"` → `:fact`) |
| `confidence_to_individual/1` | Convert to OWL individual (`:high` → `"High"`) |
| `individual_to_confidence/1` | Reverse mapping for confidence |
| `source_type_to_individual/1` | Convert source type (`:user` → `"UserSource"`) |
| `individual_to_source_type/1` | Reverse mapping for source types |

**Utility Functions:**

| Function | Purpose |
|----------|---------|
| `namespace/0` | Returns Jido namespace IRI |
| `prefixes/0` | Returns all SPARQL prefix declarations |
| `escape_string/1` | Safely escapes strings for SPARQL literals |
| `extract_memory_id/1` | Extracts ID from full IRI |
| `extract_session_id/1` | Extracts session ID from full IRI |

### Query Options

The `query_by_session/2` and `query_by_type/3` functions support these options:

| Option | Description |
|--------|-------------|
| `:include_superseded` | Include superseded memories (default: false) |
| `:limit` | Maximum number of results |
| `:min_confidence` | Filter by minimum confidence (`:high`, `:medium`) |
| `:order_by` | Order by `:timestamp` or `:access_count` |
| `:order` | Sort order `:asc` or `:desc` (default: `:desc`) |

### New File: `test/jido_code/memory/long_term/sparql_queries_test.exs`

Comprehensive unit tests covering all functions:
- 53 unit tests for query generation
- Tests for all memory types, confidence levels, source types
- Tests for type mapping and reverse mapping
- Tests for string escaping and edge cases

### Modified File: `test/jido_code/integration/triple_store_integration_test.exs`

Added 7 integration tests that verify SPARQL queries execute correctly against a real TripleStore:
- `insert_memory generates executable SPARQL`
- `query_by_session retrieves inserted memories`
- `query_by_type filters memories by type`
- `supersede_memory marks memory as superseded`
- `query_by_id retrieves single memory`
- `delete_memory soft deletes via supersession`
- `string escaping prevents SPARQL injection`

## Bug Workaround

During integration testing, discovered that `FILTER NOT EXISTS` clauses in the triple_store library return 0 results even when there are no matching triples.

**Original pattern (broken):**
```sparql
FILTER NOT EXISTS { ?mem jido:supersededBy ?newer }
```

**Working pattern:**
```sparql
OPTIONAL { ?mem jido:supersededBy ?superseded }
FILTER(!BOUND(?superseded))
```

This workaround was applied to all query functions that filter out superseded memories:
- `query_by_session/2`
- `query_by_type/3`
- `query_by_evidence/1`
- `query_decisions_with_alternatives/1`
- `query_lessons_for_error/1`

## Test Results

```
74 tests, 0 failures
```

Breakdown:
- 53 unit tests for SPARQLQueries module
- 21 integration tests (14 existing + 7 new for SPARQLQueries)

## Files Changed

| File | Change |
|------|--------|
| `lib/jido_code/memory/long_term/sparql_queries.ex` | New - 600+ lines |
| `test/jido_code/memory/long_term/sparql_queries_test.exs` | New - 53 tests |
| `test/jido_code/integration/triple_store_integration_test.exs` | Modified - Added 7 tests |
| `notes/planning/two-tier-memory/phase-07-triple-store-integration.md` | Modified - Marked 7.3 complete |

## Usage Example

```elixir
alias JidoCode.Memory.LongTerm.SPARQLQueries

# Insert a memory
memory = %{
  id: "mem_123",
  content: "User prefers dark mode",
  memory_type: :fact,
  confidence: :high,
  source_type: :user,
  session_id: "session_abc"
}
insert_query = SPARQLQueries.insert_memory(memory)
{:ok, _} = TripleStore.update(store, insert_query)

# Query memories by session
select_query = SPARQLQueries.query_by_session("session_abc",
  limit: 10,
  min_confidence: :medium
)
{:ok, results} = TripleStore.query(store, select_query)

# Query by type
type_query = SPARQLQueries.query_by_type("session_abc", :fact)
{:ok, facts} = TripleStore.query(store, type_query)

# Mark memory as superseded
supersede_query = SPARQLQueries.supersede_memory("old_id", "new_id")
{:ok, _} = TripleStore.update(store, supersede_query)
```

## Known Limitations

1. **FILTER NOT EXISTS bug**: The triple_store library has a bug where `FILTER NOT EXISTS` returns 0 results. Workaround implemented using `OPTIONAL + FILTER(!BOUND(...))` pattern.

2. **No SPARQL validation**: Generated queries are not validated at compile time. Integration tests verify correctness.

## Next Steps

With Section 7.3 complete, the next sections of Phase 7 can proceed:
- **7.4**: Refactor StoreManager to use TripleStore
- **7.5**: Refactor TripleStoreAdapter for real RDF/SPARQL
- **7.6**: Extend Types module with full ontology hierarchy
