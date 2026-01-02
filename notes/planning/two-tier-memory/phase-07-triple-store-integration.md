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

## 7.2 Create Ontology Loader

### 7.2.1 OntologyLoader Module

- [ ] 7.2.1.1 Create `lib/jido_code/memory/long_term/ontology_loader.ex`:
  ```elixir
  defmodule JidoCode.Memory.LongTerm.OntologyLoader do
    @moduledoc """
    Loads the Jido ontology TTL files into a TripleStore.

    The ontology provides the class hierarchy, properties, and individuals
    that define the structure of long-term memory.
    """

    @ontology_files [
      "jido-core.ttl",
      "jido-knowledge.ttl",
      "jido-decision.ttl",
      "jido-convention.ttl",
      "jido-error.ttl",
      "jido-session.ttl",
      "jido-agent.ttl",
      "jido-project.ttl",
      "jido-task.ttl"
    ]

    @ontology_path "lib/ontology/long-term-context"

    @spec load_ontology(TripleStore.store()) :: {:ok, non_neg_integer()} | {:error, term()}
    def load_ontology(store) do
      # Load each ontology file
    end

    @spec ontology_loaded?(TripleStore.store()) :: boolean()
    def ontology_loaded?(store) do
      # Check if jido:MemoryItem class exists
    end
  end
  ```
- [ ] 7.2.1.2 Implement `load_ontology/1` to load all TTL files
- [ ] 7.2.1.3 Implement `ontology_loaded?/1` check
- [ ] 7.2.1.4 Add `reload_ontology/1` for development/updates
- [ ] 7.2.1.5 Cache ontology path resolution

### 7.2.2 Ontology Loader Tests

- [ ] 7.2.2.1 Test load_ontology/1 loads all files
- [ ] 7.2.2.2 Test ontology_loaded?/1 returns true after load
- [ ] 7.2.2.3 Test ontology classes are queryable via SPARQL
- [ ] 7.2.2.4 Test ontology individuals (High, Medium, Low) exist
- [ ] 7.2.2.5 Test ontology properties are defined

---

## 7.3 Create SPARQL Query Templates

### 7.3.1 SPARQLQueries Module

- [ ] 7.3.1.1 Create `lib/jido_code/memory/long_term/sparql_queries.ex`:
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
- [ ] 7.3.1.2 Implement insert_memory/1 SPARQL UPDATE
- [ ] 7.3.1.3 Implement query_by_session/2 SPARQL SELECT
- [ ] 7.3.1.4 Implement query_by_type/3 with type filtering
- [ ] 7.3.1.5 Implement query_by_id/1 for single memory lookup
- [ ] 7.3.1.6 Implement supersede_memory/2 UPDATE
- [ ] 7.3.1.7 Implement delete_memory/1 (soft delete via supersession)
- [ ] 7.3.1.8 Implement record_access/1 to update access count
- [ ] 7.3.1.9 Add helper functions for escaping, formatting

### 7.3.2 Advanced Queries

- [ ] 7.3.2.1 Implement query_related/2 using ontology relationships:
  ```elixir
  @spec query_related(String.t(), atom()) :: String.t()
  def query_related(memory_id, relationship) do
    # e.g., find all memories that :refines a hypothesis
    # or find :hasRootCause for an error
  end
  ```
- [ ] 7.3.2.2 Implement query_by_evidence/1 for evidence-linked memories
- [ ] 7.3.2.3 Implement query_decisions_with_alternatives/1
- [ ] 7.3.2.4 Implement query_lessons_for_error/1

### 7.3.3 SPARQL Query Tests

- [ ] 7.3.3.1 Test insert_memory/1 generates valid SPARQL
- [ ] 7.3.3.2 Test query_by_session/2 with various options
- [ ] 7.3.3.3 Test query_by_type/3 filters correctly
- [ ] 7.3.3.4 Test string escaping prevents injection
- [ ] 7.3.3.5 Test queries execute successfully against triple_store

---

## 7.4 Refactor StoreManager

### 7.4.1 StoreManager Updates

- [ ] 7.4.1.1 Change store_ref type from `:ets.tid()` to `TripleStore.store()`
- [ ] 7.4.1.2 Update `create_store/1` to use `TripleStore.open/2`:
  ```elixir
  defp create_store(session_id) do
    path = store_path(session_id)

    with {:ok, store} <- TripleStore.open(path, create_if_missing: true),
         :ok <- ensure_ontology_loaded(store) do
      {:ok, store}
    end
  end

  defp ensure_ontology_loaded(store) do
    if OntologyLoader.ontology_loaded?(store) do
      :ok
    else
      case OntologyLoader.load_ontology(store) do
        {:ok, _count} -> :ok
        error -> error
      end
    end
  end
  ```
- [ ] 7.4.1.3 Update `close/1` to use `TripleStore.close/1`
- [ ] 7.4.1.4 Update `close_all/0` to close all TripleStore handles
- [ ] 7.4.1.5 Add store health check using `TripleStore.health/1`
- [ ] 7.4.1.6 Update base_path to use appropriate directory structure

### 7.4.2 StoreManager State Changes

- [ ] 7.4.2.1 Update state type:
  ```elixir
  @type state :: %{
          stores: %{String.t() => TripleStore.store()},
          base_path: String.t(),
          config: map()
        }
  ```
- [ ] 7.4.2.2 Add store metadata tracking (open time, last access)
- [ ] 7.4.2.3 Add periodic health checks for open stores

### 7.4.3 StoreManager Tests

- [ ] 7.4.3.1 Test get_or_create/1 opens TripleStore
- [ ] 7.4.3.2 Test ontology is loaded on first open
- [ ] 7.4.3.3 Test close/1 properly closes TripleStore
- [ ] 7.4.3.4 Test store persists data between close/open cycles
- [ ] 7.4.3.5 Test concurrent access to same session store
- [ ] 7.4.3.6 Test health check integration

---

## 7.5 Refactor TripleStoreAdapter

### 7.5.1 Adapter Core Changes

- [ ] 7.5.1.1 Remove ETS-specific code entirely
- [ ] 7.5.1.2 Update persist/2 to use SPARQL INSERT:
  ```elixir
  @spec persist(memory_input(), TripleStore.store()) :: {:ok, String.t()} | {:error, term()}
  def persist(memory, store) do
    query = SPARQLQueries.insert_memory(memory)

    case TripleStore.update(store, query) do
      {:ok, _} -> {:ok, memory.id}
      {:error, reason} -> {:error, reason}
    end
  end
  ```
- [ ] 7.5.1.3 Update query_all/2 to use SPARQL SELECT
- [ ] 7.5.1.4 Update query_by_type/3 to use SPARQL with type filter
- [ ] 7.5.1.5 Update query_by_id/2 to use SPARQL
- [ ] 7.5.1.6 Update supersede/4 to use SPARQL UPDATE
- [ ] 7.5.1.7 Update record_access/2 to use SPARQL UPDATE

### 7.5.2 Result Mapping

- [ ] 7.5.2.1 Create `map_sparql_result/1` to convert SPARQL bindings to memory struct:
  ```elixir
  defp map_sparql_result(bindings) do
    %{
      id: extract_id(bindings["mem"]),
      content: bindings["content"],
      memory_type: iri_to_memory_type(bindings["type"]),
      confidence: iri_to_confidence(bindings["confidence"]),
      source_type: iri_to_source_type(bindings["source"]),
      timestamp: parse_datetime(bindings["timestamp"]),
      # ... other fields
    }
  end
  ```
- [ ] 7.5.2.2 Implement IRI-to-atom mapping functions
- [ ] 7.5.2.3 Handle optional fields (rationale, evidence_refs)
- [ ] 7.5.2.4 Add error handling for malformed results

### 7.5.3 Remove Vocab.Jido Dependency

- [ ] 7.5.3.1 Remove `alias JidoCode.Memory.LongTerm.Vocab.Jido, as: Vocab`
- [ ] 7.5.3.2 Replace Vocab.* calls with direct IRI construction or SPARQLQueries
- [ ] 7.5.3.3 Move any still-needed IRI helpers to SPARQLQueries module

### 7.5.4 Adapter Tests

- [ ] 7.5.4.1 Test persist/2 creates RDF triples
- [ ] 7.5.4.2 Test query_all/2 returns all session memories
- [ ] 7.5.4.3 Test query_by_type/3 filters by ontology class
- [ ] 7.5.4.4 Test supersede/4 creates supersededBy relationship
- [ ] 7.5.4.5 Test query excludes superseded memories by default
- [ ] 7.5.4.6 Test access count tracking works
- [ ] 7.5.4.7 Test round-trip persist → query preserves all fields

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

### 7.10.1 Data Migration

- [ ] 7.10.1.1 Create migration script for existing ETS data (if any):
  ```elixir
  defmodule JidoCode.Memory.Migration do
    @moduledoc """
    Migrates memory data from ETS format to TripleStore.
    """

    def migrate(session_id) do
      # Read from old ETS store
      # Transform to RDF triples
      # Insert into new TripleStore
    end
  end
  ```
- [ ] 7.10.1.2 Add version tracking for store format
- [ ] 7.10.1.3 Implement rollback capability

### 7.10.2 Backward Compatibility

- [ ] 7.10.2.1 Keep public API signatures unchanged where possible
- [ ] 7.10.2.2 Document breaking changes if any
- [ ] 7.10.2.3 Update CHANGELOG

---

## 7.11 Integration Tests

### 7.11.1 End-to-End Tests

- [ ] 7.11.1.1 Test full workflow: remember → recall → forget with TripleStore
- [ ] 7.11.1.2 Test ontology reasoning (if enabled) affects queries
- [ ] 7.11.1.3 Test persistence across application restart
- [ ] 7.11.1.4 Test multiple sessions with isolated stores
- [ ] 7.11.1.5 Test semantic search with RDF data

### 7.11.2 Performance Tests

- [ ] 7.11.2.1 Benchmark SPARQL queries vs old ETS queries
- [ ] 7.11.2.2 Test with large number of memories (1000+)
- [ ] 7.11.2.3 Test concurrent read/write performance

### 7.11.3 Ontology Consistency Tests

- [ ] 7.11.3.1 Verify all memory types map to ontology classes
- [ ] 7.11.3.2 Verify all relationships are valid per ontology
- [ ] 7.11.3.3 Test SHACL validation (if jido-ci-shacl.ttl is used)

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
