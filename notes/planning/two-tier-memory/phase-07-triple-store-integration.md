# Phase 7: Triple Store Integration & Ontology Alignment

This phase refactors the long-term memory system to use the actual `triple_store` library with proper RDF/SPARQL support, replacing the temporary ETS-based implementation. It also aligns the code with the formal Jido ontology defined in the TTL files.

## Background & Motivation

The current implementation has a significant architectural gap:

1. **Formal ontology exists** in `lib/ontology/long-term-context/*.ttl` defining a rich class hierarchy
2. **Vocab.Jido module** is a partial, hand-coded duplicate that's out of sync
3. **TripleStoreAdapter uses ETS maps** instead of actual RDF triples
4. **No SPARQL queries** - everything uses Elixir pattern matching on maps
5. **triple_store library** exists at `~/code/triple_store` with full SPARQL 1.1 support

This phase corrects these issues by properly integrating with the triple store and ontology.

## Architecture After Refactoring

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         Memory System                                     │
│                                                                           │
│  ┌────────────────┐      ┌────────────────┐      ┌────────────────────┐  │
│  │ Remember/Recall│      │   Memory.ex    │      │  ContextBuilder    │  │
│  │ Actions        │─────▶│   (Facade)     │─────▶│                    │  │
│  └────────────────┘      └────────────────┘      └────────────────────┘  │
│           │                      │                                        │
│           ▼                      ▼                                        │
│  ┌───────────────────────────────────────────────────────────────────┐   │
│  │                     TripleStoreAdapter                             │   │
│  │  - Converts Elixir structs ⟷ RDF triples                          │   │
│  │  - Uses ontology IRIs from loaded TTL files                        │   │
│  │  - Generates SPARQL queries for all operations                     │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                  │                                        │
│                                  ▼                                        │
│  ┌───────────────────────────────────────────────────────────────────┐   │
│  │                       StoreManager                                 │   │
│  │  - Manages TripleStore handles per session                         │   │
│  │  - Loads ontology on store creation                                │   │
│  │  - Handles persistence paths                                       │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                  │                                        │
│                                  ▼                                        │
│  ┌───────────────────────────────────────────────────────────────────┐   │
│  │              TripleStore (external library)                        │   │
│  │  - RocksDB persistent storage                                      │   │
│  │  - SPARQL 1.1 Query & Update                                       │   │
│  │  - OWL 2 RL reasoning (optional)                                   │   │
│  │  - Dictionary encoding for compact storage                         │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                                                           │
│  ┌───────────────────────────────────────────────────────────────────┐   │
│  │                    TTL Ontology Files                              │   │
│  │  lib/ontology/long-term-context/                                   │   │
│  │  ├── jido-core.ttl        (MemoryItem, Confidence, Source)         │   │
│  │  ├── jido-knowledge.ttl   (Fact, Assumption, Hypothesis, etc.)     │   │
│  │  ├── jido-decision.ttl    (Decision, Alternative, TradeOff)        │   │
│  │  ├── jido-convention.ttl  (Convention, CodingStandard, etc.)       │   │
│  │  ├── jido-error.ttl       (Error, Bug, LessonLearned)              │   │
│  │  └── ...                                                           │   │
│  └───────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
```

## Module Structure Changes

```
lib/jido_code/memory/
├── long_term/
│   ├── store_manager.ex       # REFACTOR: Use TripleStore.open/close
│   ├── triple_store_adapter.ex # REFACTOR: Real RDF triples + SPARQL
│   ├── ontology_loader.ex     # NEW: Load TTL files into store
│   ├── sparql_queries.ex      # NEW: SPARQL query templates
│   └── vocab/
│       └── jido.ex            # DELETE: Replace with ontology access
├── types.ex                   # EXTEND: Full ontology type hierarchy
└── ...
```

---

## 7.1 Add TripleStore Dependency ✓

### 7.1.1 Update mix.exs

- [x] 7.1.1.1 Add triple_store as local dependency:
  ```elixir
  # In deps()
  {:triple_store, path: "../../triple_store"}
  ```
- [x] 7.1.1.2 Run `mix deps.get` to fetch dependency
- [x] 7.1.1.3 Verify compilation with `mix compile`
- [x] 7.1.1.4 Update application.ex if needed for TripleStore.Application (not needed - TripleStore handles its own supervision)

### 7.1.2 Verify TripleStore Integration

- [x] 7.1.2.1 Create simple integration test to verify triple_store works:
  ```elixir
  test "can open, insert, query, and close store" do
    {:ok, store} = TripleStore.open(temp_path())
    {:ok, 1} = TripleStore.insert(store, {RDF.iri("http://ex/s"), RDF.iri("http://ex/p"), RDF.iri("http://ex/o")})
    {:ok, results} = TripleStore.query(store, "SELECT ?s WHERE { ?s ?p ?o }")
    assert length(results) == 1
    :ok = TripleStore.close(store)
  end
  ```
- [x] 7.1.2.2 Test loading a TTL file from ontology directory
- [x] 7.1.2.3 Test SPARQL query against loaded ontology

---

## 7.2 Create Ontology Loader ✓

### 7.2.1 OntologyLoader Module

- [x] 7.2.1.1 Create `lib/jido_code/memory/long_term/ontology_loader.ex`
- [x] 7.2.1.2 Implement `load_ontology/1` to load all TTL files
- [x] 7.2.1.3 Implement `ontology_loaded?/1` check using ASK query for MemoryItem class
- [x] 7.2.1.4 Add `reload_ontology/1` for development/updates
- [x] 7.2.1.5 Cache ontology path resolution using `persistent_term`
- [x] 7.2.1.6 Added helper functions: `namespace/0`, `ontology_files/0`, `ontology_path/0`
- [x] 7.2.1.7 Added query functions: `list_classes/1`, `list_individuals/1`, `list_properties/1`

### 7.2.2 Ontology Loader Tests

- [x] 7.2.2.1 Test load_ontology/1 loads all files (10 TTL files, ~670 triples)
- [x] 7.2.2.2 Test ontology_loaded?/1 returns true after load
- [x] 7.2.2.3 Test ontology classes are queryable via SPARQL (MemoryItem, Entity, etc.)
- [x] 7.2.2.4 Test ontology individuals (High, Medium, Low, UserSource, AgentSource, etc.)
- [x] 7.2.2.5 Test ontology properties are defined (hasConfidence, summary, etc.)
- [x] 7.2.2.6 Test knowledge type subclasses of MemoryItem (Fact, Assumption, Hypothesis)
- [x] 7.2.2.7 Test list_classes/1, list_individuals/1, list_properties/1
- [x] 7.2.2.8 Test reload_ontology/1 works correctly

---

## 7.3 Create SPARQL Query Templates ✓

### 7.3.1 SPARQLQueries Module

- [x] 7.3.1.1 Create `lib/jido_code/memory/long_term/sparql_queries.ex`:
  ```elixir
  defmodule JidoCode.Memory.LongTerm.SPARQLQueries do
    @moduledoc """
    SPARQL query and update templates for memory operations.

    All queries use the jido: namespace prefix bound to https://jido.ai/ontology#
    """

    @jido_prefix "PREFIX jido: <https://jido.ai/ontology#>"
    @rdf_prefix "PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>"
    @xsd_prefix "PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>"

    @spec insert_memory(map()) :: String.t()
    def insert_memory(memory) do
      """
      #{@jido_prefix}
      #{@rdf_prefix}
      #{@xsd_prefix}

      INSERT DATA {
        jido:memory_#{memory.id} rdf:type jido:#{camelize(memory.memory_type)} ;
          jido:summary #{escape_string(memory.content)} ;
          jido:hasConfidence jido:#{confidence_individual(memory.confidence)} ;
          jido:hasSourceType jido:#{source_individual(memory.source_type)} ;
          jido:hasTimestamp "#{DateTime.to_iso8601(memory.created_at)}"^^xsd:dateTime ;
          jido:assertedIn jido:session_#{memory.session_id} .
      }
      """
    end

    @spec query_by_session(String.t(), keyword()) :: String.t()
    def query_by_session(session_id, opts \\ []) do
      """
      #{@jido_prefix}
      #{@rdf_prefix}

      SELECT ?mem ?type ?content ?confidence ?source ?timestamp
      WHERE {
        ?mem jido:assertedIn jido:session_#{session_id} ;
             rdf:type ?type ;
             jido:summary ?content ;
             jido:hasConfidence ?confidence ;
             jido:hasSourceType ?source ;
             jido:hasTimestamp ?timestamp .

        FILTER NOT EXISTS { ?mem jido:supersededBy ?newer }
        #{min_confidence_filter(opts[:min_confidence])}
      }
      ORDER BY DESC(?timestamp)
      #{limit_clause(opts[:limit])}
      """
    end

    @spec query_by_type(String.t(), atom(), keyword()) :: String.t()
    def query_by_type(session_id, memory_type, opts \\ [])

    @spec supersede_memory(String.t(), String.t()) :: String.t()
    def supersede_memory(old_id, new_id)

    @spec delete_memory(String.t()) :: String.t()
    def delete_memory(memory_id)

    @spec record_access(String.t()) :: String.t()
    def record_access(memory_id)
  end
  ```
- [x] 7.3.1.2 Implement insert_memory/1 SPARQL UPDATE
- [x] 7.3.1.3 Implement query_by_session/2 SPARQL SELECT
- [x] 7.3.1.4 Implement query_by_type/3 with type filtering
- [x] 7.3.1.5 Implement query_by_id/1 for single memory lookup
- [x] 7.3.1.6 Implement supersede_memory/2 UPDATE
- [x] 7.3.1.7 Implement delete_memory/1 (soft delete via supersession)
- [x] 7.3.1.8 Implement record_access/1 to update access count
- [x] 7.3.1.9 Add helper functions for escaping, formatting
- [x] 7.3.1.10 Add type mapping helpers (memory_type_to_class, class_to_memory_type, etc.)

### 7.3.2 Advanced Queries

- [x] 7.3.2.1 Implement query_related/2 using ontology relationships (refines, confirms, superseded_by)
- [x] 7.3.2.2 Implement query_by_evidence/1 for evidence-linked memories
- [x] 7.3.2.3 Implement query_decisions_with_alternatives/1
- [x] 7.3.2.4 Implement query_lessons_for_error/1

### 7.3.3 SPARQL Query Tests

- [x] 7.3.3.1 Test insert_memory/1 generates valid SPARQL (unit + integration)
- [x] 7.3.3.2 Test query_by_session/2 with various options (53 unit tests)
- [x] 7.3.3.3 Test query_by_type/3 filters correctly
- [x] 7.3.3.4 Test string escaping prevents injection
- [x] 7.3.3.5 Test queries execute successfully against triple_store (7 integration tests)

---

## 7.4 Refactor StoreManager ✓

### 7.4.1 StoreManager Updates

- [x] 7.4.1.1 Change store_ref type from `:ets.tid()` to `TripleStore.store()`
- [x] 7.4.1.2 Update `open_store/2` to use `TripleStore.open/2` with ontology loading
- [x] 7.4.1.3 Update `close/1` to use `TripleStore.close/1`
- [x] 7.4.1.4 Update `close_all/0` to close all TripleStore handles
- [x] 7.4.1.5 Add store health check using `TripleStore.health/1`
- [x] 7.4.1.6 Base path structure unchanged (session_<id>/ directories)

### 7.4.2 StoreManager State Changes

- [x] 7.4.2.1 Update state type with store_entry containing store + metadata
- [x] 7.4.2.2 Add store metadata tracking (opened_at, last_accessed, ontology_loaded)
- [x] 7.4.2.3 Added `get_metadata/2` function to retrieve store metadata

### 7.4.3 StoreManager Tests

- [x] 7.4.3.1 Test get_or_create/1 opens TripleStore
- [x] 7.4.3.2 Test ontology is loaded on first open
- [x] 7.4.3.3 Test close/1 properly closes TripleStore
- [x] 7.4.3.4 Test store persists data between close/open cycles
- [x] 7.4.3.5 Test concurrent access to same session store
- [x] 7.4.3.6 Test health check integration

### 7.4.4 Implementation Notes

- StoreManager now returns `TripleStore.store()` references instead of ETS table IDs
- Each session store is backed by RocksDB via TripleStore library
- Ontology is automatically loaded on first store open via OntologyLoader
- 37 tests pass for StoreManager with TripleStore backend
- Note: TripleStoreAdapter (Section 7.5) still uses ETS and needs refactoring

### 7.4.5 Post-Review Improvements (2026-01-02)

Based on code review, the following improvements were implemented:

- [x] Fixed health spec type mismatch (`{:unhealthy, status}` instead of `:unhealthy`)
- [x] Added `max_open_stores` configuration with LRU eviction (default: 100)
- [x] Added idle cleanup timer (`idle_timeout_ms`, `cleanup_interval_ms`)
- [x] Extracted `touch_last_accessed/3` helper to reduce duplication
- [x] Extracted `close_all_stores/1` and `close_all_stores_with_timeout/1` helpers
- [x] Fixed `if not` anti-pattern to use `unless`
- [x] Added timeout handling in `terminate/2` with parallel Task closing
- [x] Inlined `expand_path/1` wrapper function
- [x] Added test helpers (`unique_session_id/1`, `extract_rdf_value/1`, `@sparql_prefixes`)
- [x] Added 6 new tests for LRU eviction, idle cleanup, and configuration
- 43 tests pass for StoreManager (was 37)

---

## 7.5 Refactor TripleStoreAdapter ✓

### 7.5.1 Adapter Core Changes

- [x] 7.5.1.1 Remove ETS-specific code entirely
- [x] 7.5.1.2 Update persist/2 to use SPARQL INSERT (via SPARQLQueries.insert_memory)
- [x] 7.5.1.3 Update query_all/2 to use SPARQL SELECT (via SPARQLQueries.query_by_session)
- [x] 7.5.1.4 Update query_by_type/3 to use SPARQL with type filter (via SPARQLQueries.query_by_type)
- [x] 7.5.1.5 Update query_by_id/2 to use SPARQL (via SPARQLQueries.query_by_id)
- [x] 7.5.1.6 Update supersede/4 to use SPARQL UPDATE (via SPARQLQueries.supersede_memory)
- [x] 7.5.1.7 Update record_access/2 to use SPARQL UPDATE (via SPARQLQueries.record_access)

### 7.5.2 Result Mapping

- [x] 7.5.2.1 Create result mapping functions:
  - `map_type_result/3` - Maps query_by_type results
  - `map_session_result/2` - Maps query_by_session results
  - `map_id_result/2` - Maps query_by_id results
- [x] 7.5.2.2 Implement IRI-to-atom mapping functions:
  - `extract_memory_type/1` - Converts type IRI to atom
  - `extract_confidence/1` - Converts confidence IRI to level
  - `extract_source_type/1` - Converts source IRI to atom
  - `extract_session_id/1` - Extracts session ID from IRI
- [x] 7.5.2.3 Handle optional fields (rationale via extract_optional_string, evidence_refs defaults to [])
- [x] 7.5.2.4 Add error handling for malformed results (fallback values for all extractors)

### 7.5.3 Remove Vocab.Jido Dependency

- [x] 7.5.3.1 Remove `alias JidoCode.Memory.LongTerm.Vocab.Jido, as: Vocab` - No Vocab references
- [x] 7.5.3.2 Replace Vocab.* calls with SPARQLQueries functions
- [x] 7.5.3.3 Move IRI helpers to SPARQLQueries module (namespace, extract_memory_id, extract_session_id)

### 7.5.4 Adapter Tests

- [x] 7.5.4.1 Test persist/2 creates RDF triples (4 tests)
- [x] 7.5.4.2 Test query_all/2 returns all session memories (5 tests)
- [x] 7.5.4.3 Test query_by_type/3 filters by ontology class (5 tests)
- [x] 7.5.4.4 Test supersede/4 creates supersededBy relationship (4 tests)
- [x] 7.5.4.5 Test query excludes superseded memories by default (verified in query tests)
- [x] 7.5.4.6 Test access count tracking works (3 tests)
- [x] 7.5.4.7 Test round-trip persist → query preserves all fields (verified across all tests)

**38 tests pass** for TripleStoreAdapter

---

## 7.6 Extend Types Module

### 7.6.1 Align Types with Ontology

- [ ] 7.6.1.1 Add missing memory types from ontology:
  ```elixir
  @type memory_type ::
    # From jido-knowledge.ttl
    :fact | :assumption | :hypothesis | :discovery | :risk | :unknown |
    # From jido-decision.ttl
    :decision | :architectural_decision | :implementation_decision |
    :alternative | :trade_off |
    # From jido-convention.ttl
    :convention | :coding_standard | :architectural_convention |
    :agent_rule | :process_convention |
    # From jido-error.ttl
    :error | :bug | :failure | :incident |
    :root_cause | :lesson_learned
  ```
- [ ] 7.6.1.2 Add memory_type_to_iri/1 mapping
- [ ] 7.6.1.3 Add iri_to_memory_type/1 reverse mapping
- [ ] 7.6.1.4 Update memory_types/0 to return full list
- [ ] 7.6.1.5 Add type hierarchy helpers (e.g., `subtype_of?/2`)

### 7.6.2 Add Ontology Relationship Types

- [ ] 7.6.2.1 Define relationship types:
  ```elixir
  @type relationship ::
    :refines | :confirms | :contradicts |
    :has_alternative | :selected_alternative |
    :has_trade_off | :justified_by |
    :has_root_cause | :produced_lesson |
    :related_error | :superseded_by | :derived_from
  ```
- [ ] 7.6.2.2 Add relationship_to_iri/1 mapping
- [ ] 7.6.2.3 Document which relationships apply to which types

### 7.6.3 Add Ontology Individual Types

- [ ] 7.6.3.1 Add convention scope type:
  ```elixir
  @type convention_scope :: :global | :project | :agent
  ```
- [ ] 7.6.3.2 Add enforcement level type:
  ```elixir
  @type enforcement_level :: :advisory | :required | :strict
  ```
- [ ] 7.6.3.3 Add error status type:
  ```elixir
  @type error_status :: :reported | :investigating | :resolved | :deferred
  ```
- [ ] 7.6.3.4 Add evidence strength type:
  ```elixir
  @type evidence_strength :: :weak | :moderate | :strong
  ```

### 7.6.4 Types Tests

- [ ] 7.6.4.1 Test all memory types have IRI mappings
- [ ] 7.6.4.2 Test IRI round-trip conversion
- [ ] 7.6.4.3 Test type hierarchy relationships
- [ ] 7.6.4.4 Verify types match ontology definitions

---

## 7.7 Delete Vocab.Jido Module

### 7.7.1 Removal

- [ ] 7.7.1.1 Verify no remaining references to Vocab.Jido
- [ ] 7.7.1.2 Delete `lib/jido_code/memory/long_term/vocab/jido.ex`
- [ ] 7.7.1.3 Delete `lib/jido_code/memory/long_term/vocab/` directory if empty
- [ ] 7.7.1.4 Remove any related test files
- [ ] 7.7.1.5 Update any documentation referencing Vocab.Jido

---

## 7.8 Update Memory Facade

### 7.8.1 Memory.ex Updates

- [ ] 7.8.1.1 Update Memory.persist/2 to work with new adapter
- [ ] 7.8.1.2 Update Memory.query/2 to work with new adapter
- [ ] 7.8.1.3 Update Memory.query_by_type/3 to work with new adapter
- [ ] 7.8.1.4 Update Memory.supersede/3 to work with new adapter
- [ ] 7.8.1.5 Update Memory.record_access/2 to work with new adapter
- [ ] 7.8.1.6 Add Memory.query_related/3 for relationship queries
- [ ] 7.8.1.7 Add Memory.get_stats/1 using TripleStore.stats/1

### 7.8.2 Memory Facade Tests

- [ ] 7.8.2.1 Update existing tests to work with TripleStore backend
- [ ] 7.8.2.2 Add tests for new relationship query functions
- [ ] 7.8.2.3 Add tests for stats function

---

## 7.9 Update Actions

### 7.9.1 Remember Action Updates

- [ ] 7.9.1.1 Update to support extended memory types
- [ ] 7.9.1.2 Add support for relationship parameters (e.g., refines, derived_from)
- [ ] 7.9.1.3 Update validation for new type hierarchy

### 7.9.2 Recall Action Updates

- [ ] 7.9.2.1 Update to work with SPARQL-based queries
- [ ] 7.9.2.2 Add relationship-based recall (e.g., "recall lessons for error X")
- [ ] 7.9.2.3 Ensure semantic search still works with RDF data

### 7.9.3 Forget Action Updates

- [ ] 7.9.3.1 Update to work with SPARQL UPDATE for supersession
- [ ] 7.9.3.2 Ensure proper cascading of relationships

---

## 7.10 Migration Strategy

**N/A** - Greenfield project, no backward compatibility required. No existing ETS data to migrate.

---

## 7.11 Integration Tests ✓

### 7.11.1 End-to-End Tests

- [x] 7.11.1.1 Test full workflow: remember → recall → forget with TripleStore
- [x] 7.11.1.2 Test memory type filtering works correctly
- [x] 7.11.1.3 Test persistence across store close/open cycles
- [x] 7.11.1.4 Test multiple sessions with isolated stores
- [x] 7.11.1.5 Test supersession chain works correctly

### 7.11.2 Performance Tests

- [x] 7.11.2.1 Test with large number of memories (100+)
- [x] 7.11.2.2 Test concurrent read operations (10 parallel tasks)
- [x] 7.11.2.3 Test SPARQL query response time is reasonable (<2s)

### 7.11.3 Ontology Consistency Tests

- [x] 7.11.3.1 Verify all memory types map to ontology classes (round-trip)
- [x] 7.11.3.2 Verify all confidence levels map to ontology individuals (round-trip)
- [x] 7.11.3.3 Verify all source types map to ontology individuals (round-trip)
- [x] 7.11.3.4 Verify ontology classes exist in loaded TTL files
- [x] 7.11.3.5 Verify ontology individuals exist for confidence levels
- [x] 7.11.3.6 Verify ontology individuals exist for source types
- [x] 7.11.3.7 Verify memory IRI extraction works correctly
- [x] 7.11.3.8 Verify SPARQL prefixes are correctly formed

**37 tests pass** for TripleStore integration (including 16 new Section 7.11 tests)

---

## 7.12 Phase 7 Review Fixes ✓

Following the comprehensive Phase 7 review, the following blockers and concerns were addressed:

### 7.12.1 Blockers Fixed

- [x] **B1:** Fixed `unless/else` anti-pattern in store_manager.ex - Changed to `if/else`
- [x] **B2:** Reduced nested function depth in store_manager.ex - Extracted helper functions (`do_open_store/2`, `path_contained?/2`, `open_and_load_ontology/2`, `finalize_store_open/2`)

### 7.12.2 Concerns Fixed

- [x] **C3:** Inefficient count operation - Added `count_query/2` with SPARQL COUNT aggregate
- [x] **C5:** Memory ID validation - Added `Types.valid_memory_id?/1` to prevent SPARQL injection
- [x] **C6:** String escaping improvements - Added escaping for `\b`, `\f`, and null bytes
- [x] **C7:** Unbounded query results - Added `@default_query_limit 1000` constant
- [x] **C8:** Error handling for TripleStore.health/1 - Added `{:error, reason}` handling
- [x] **C9:** Used Enum.map_join/3 instead of map + join
- [x] **C10:** Reduced cyclomatic complexity - Replaced case statements with map lookups
- [x] **C11:** Removed inconsistent `@doc since: "0.1.0"` annotation
- [x] **C12:** Fixed test async setting - Changed to `async: false` for consistency
- [x] **C13:** Variable naming consistency - Standardized to `{:error, _}`
- [x] **C14:** Extracted `base_memory_map/1` function for DRY result mapping
- [x] **C15:** Extracted `extract_local_name/1` helper for IRI processing

### 7.12.3 Deferred Items

The following lower-priority items were not addressed in this PR:

- **C1:** Consolidate duplicated type mapping logic (Vocab.Jido vs SPARQLQueries)
- **C2:** Memory Facade load_ontology/1 no-op
- **C4:** Evidence references not queryable
- **C16-C18:** Test improvements (helper extraction, error handling tests, access count tests)

### 7.12.4 Test Results

**287 tests pass** for all Phase 7 components after review fixes.

### 7.12.5 Summary Document

See `notes/summaries/phase-07-review-fixes.md` for detailed documentation of all changes.

---

## Phase 7 Success Criteria

1. **TripleStore Integration**: All memory operations use TripleStore library
2. **SPARQL Queries**: All queries use proper SPARQL 1.1 syntax
3. **Ontology Alignment**: Code types match TTL ontology definitions exactly
4. **Vocab.Jido Removed**: No hand-coded duplicate of ontology
5. **Persistence**: Data persists in RocksDB across restarts
6. **Extended Types**: Full ontology type hierarchy available
7. **Relationships**: Ontology relationships can be queried
8. **Backward Compatible**: Existing tests pass (with updated backends)
9. **Performance**: No significant regression vs ETS (within 2x acceptable)
10. **Test Coverage**: Minimum 80% for Phase 7 components

---

## Phase 7 Critical Files

**New Files:**
- `lib/jido_code/memory/long_term/ontology_loader.ex`
- `lib/jido_code/memory/long_term/sparql_queries.ex`
- `lib/jido_code/memory/migration.ex`
- `test/jido_code/memory/long_term/ontology_loader_test.exs`
- `test/jido_code/memory/long_term/sparql_queries_test.exs`
- `test/jido_code/integration/triple_store_integration_test.exs`

**Modified Files:**
- `mix.exs` - Add triple_store dependency
- `lib/jido_code/memory/long_term/store_manager.ex` - Use TripleStore
- `lib/jido_code/memory/long_term/triple_store_adapter.ex` - Real RDF/SPARQL
- `lib/jido_code/memory/types.ex` - Extended type hierarchy
- `lib/jido_code/memory/memory.ex` - Updated facade
- `lib/jido_code/memory/actions/remember.ex` - Extended types support
- `lib/jido_code/memory/actions/recall.ex` - SPARQL-based queries

**Deleted Files:**
- `lib/jido_code/memory/long_term/vocab/jido.ex`

---

## Dependencies

- `triple_store` (local: `../triple_store`) - RDF triple store with SPARQL
- `rdf` (~> 2.0) - Already present, used by triple_store

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| SPARQL query performance | Medium | Benchmark early, optimize queries, use indices |
| RocksDB portability | Low | Library handles platform differences |
| Ontology changes break code | Medium | Version ontology, add compatibility checks |
| Migration data loss | High | Backup before migration, rollback capability |
| Learning curve for SPARQL | Low | Good query templates, documentation |

---

## Estimated Effort

| Section | Complexity | Notes |
|---------|------------|-------|
| 7.1 Add Dependency | Low | Straightforward |
| 7.2 Ontology Loader | Medium | New module |
| 7.3 SPARQL Queries | High | Core functionality, many queries |
| 7.4 StoreManager Refactor | Medium | API changes |
| 7.5 Adapter Refactor | High | Complete rewrite |
| 7.6 Extend Types | Medium | Alignment work |
| 7.7 Delete Vocab | Low | Cleanup |
| 7.8-7.9 Update Facade/Actions | Medium | Integration |
| 7.10 Migration | Medium | Data handling |
| 7.11 Integration Tests | Medium | Verification |
