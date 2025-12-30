# Phase 2: Long-Term Memory Store

This phase implements the persistent semantic memory layer using the triple_store library with session isolation. Long-term memory uses the Jido ontology for semantic structure and provenance tracking.

## Long-Term Memory Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         LONG-TERM MEMORY                                  │
│                    (Triple Store per Session)                             │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                    Memory Supervisor                                │  │
│  │  ┌──────────────────────────────────────────────────────────────┐  │  │
│  │  │                    StoreManager (GenServer)                   │  │  │
│  │  │   • Manages session-isolated RocksDB stores                   │  │  │
│  │  │   • Opens/closes stores on demand                             │  │  │
│  │  │   • Handles store lifecycle (backup, restore)                 │  │  │
│  │  └──────────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                              │                                            │
│                              ▼                                            │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                    TripleStoreAdapter                               │  │
│  │   • Maps Elixir structs to RDF triples                             │  │
│  │   • Uses Jido ontology vocabulary                                  │  │
│  │   • Handles SPARQL queries and updates                             │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                              │                                            │
│                              ▼                                            │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │   Uses Existing Jido Ontology Classes:                              │  │
│  │                                                                      │  │
│  │   jido:MemoryItem (base)                                            │  │
│  │      ├── jido:Fact              "The project uses Phoenix 1.7"      │  │
│  │      ├── jido:Assumption        "User prefers explicit type specs"  │  │
│  │      ├── jido:Hypothesis        "This bug might be a race cond."    │  │
│  │      ├── jido:Discovery         "Found undocumented API endpoint"   │  │
│  │      ├── jido:Risk              "Migration may break old clients"   │  │
│  │      ├── jido:Decision          "Chose GenServer over Agent"        │  │
│  │      ├── jido:Convention        "Use @moduledoc in all modules"     │  │
│  │      └── jido:LessonLearned     "Always check ETS table exists"     │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

## Module Structure

```
lib/jido_code/memory/
├── memory.ex                      # Public API facade
├── supervisor.ex                  # Memory subsystem supervisor
└── long_term/
    ├── store_manager.ex           # Session-isolated store lifecycle
    ├── triple_store_adapter.ex    # Jido ontology ↔ triple_store
    └── vocab/
        └── jido.ex                # Jido vocabulary namespace
```

---

## 2.1 Jido Vocabulary Namespace

Create an Elixir module for working with Jido ontology IRIs. This provides type-safe access to ontology terms and properties.

### 2.1.1 Vocabulary Module

- [x] 2.1.1.1 Create `lib/jido_code/memory/long_term/vocab/jido.ex` with comprehensive moduledoc
- [x] 2.1.1.2 Define namespace module attributes:
  ```elixir
  @jido_ns "https://jido.ai/ontology#"
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @xsd_ns "http://www.w3.org/2001/XMLSchema#"
  ```
- [x] 2.1.1.3 Implement `iri/1` helper to construct full IRI from local name:
  ```elixir
  @spec iri(String.t()) :: String.t()
  def iri(local_name), do: @jido_ns <> local_name
  ```
- [x] 2.1.1.4 Implement `rdf_type/0` returning the rdf:type IRI
- [x] 2.1.1.5 Implement class functions for all memory types:
  ```elixir
  def memory_item, do: iri("MemoryItem")
  def fact, do: iri("Fact")
  def assumption, do: iri("Assumption")
  def hypothesis, do: iri("Hypothesis")
  def discovery, do: iri("Discovery")
  def risk, do: iri("Risk")
  def unknown, do: iri("Unknown")
  def decision, do: iri("Decision")
  def architectural_decision, do: iri("ArchitecturalDecision")
  def convention, do: iri("Convention")
  def coding_standard, do: iri("CodingStandard")
  def lesson_learned, do: iri("LessonLearned")
  def error, do: iri("Error")
  def bug, do: iri("Bug")
  ```
- [x] 2.1.1.6 Implement `memory_type_to_class/1` to map atom to IRI:
  ```elixir
  @spec memory_type_to_class(atom()) :: String.t()
  def memory_type_to_class(:fact), do: fact()
  def memory_type_to_class(:assumption), do: assumption()
  # ... etc for all types
  ```
- [x] 2.1.1.7 Implement `class_to_memory_type/1` to map IRI to atom:
  ```elixir
  @spec class_to_memory_type(String.t()) :: atom()
  ```
- [x] 2.1.1.8 Implement confidence level individual IRIs:
  ```elixir
  def confidence_high, do: iri("High")
  def confidence_medium, do: iri("Medium")
  def confidence_low, do: iri("Low")
  ```
- [x] 2.1.1.9 Implement `confidence_to_individual/1` (float -> IRI):
  ```elixir
  @spec confidence_to_individual(float()) :: String.t()
  def confidence_to_individual(c) when c >= 0.8, do: confidence_high()
  def confidence_to_individual(c) when c >= 0.5, do: confidence_medium()
  def confidence_to_individual(_), do: confidence_low()
  ```
- [x] 2.1.1.10 Implement `individual_to_confidence/1` (IRI -> float):
  ```elixir
  @spec individual_to_confidence(String.t()) :: float()
  ```
  - High -> 0.9, Medium -> 0.6, Low -> 0.3
- [x] 2.1.1.11 Implement source type individual IRIs:
  ```elixir
  def source_user, do: iri("UserSource")
  def source_agent, do: iri("AgentSource")
  def source_tool, do: iri("ToolSource")
  def source_external, do: iri("ExternalDocumentSource")
  ```
- [x] 2.1.1.12 Implement `source_type_to_individual/1` (atom -> IRI)
- [x] 2.1.1.13 Implement `individual_to_source_type/1` (IRI -> atom)
- [x] 2.1.1.14 Implement property IRIs:
  ```elixir
  def summary, do: iri("summary")
  def detailed_explanation, do: iri("detailedExplanation")
  def rationale, do: iri("rationale")
  def has_confidence, do: iri("hasConfidence")
  def has_source_type, do: iri("hasSourceType")
  def has_timestamp, do: iri("hasTimestamp")
  def asserted_by, do: iri("assertedBy")
  def asserted_in, do: iri("assertedIn")
  def applies_to_project, do: iri("appliesToProject")
  def derived_from, do: iri("derivedFrom")
  def superseded_by, do: iri("supersededBy")
  def invalidated_by, do: iri("invalidatedBy")
  ```
- [x] 2.1.1.15 Implement entity IRI generators:
  ```elixir
  def memory_uri(id), do: iri("memory_" <> id)
  def session_uri(id), do: iri("session_" <> id)
  def agent_uri(id), do: iri("agent_" <> id)
  def project_uri(id), do: iri("project_" <> id)
  def evidence_uri(ref), do: iri("evidence_" <> hash_ref(ref))
  ```

### 2.1.2 Unit Tests for Vocabulary

- [x] Test iri/1 constructs correct full IRI with namespace prefix
- [x] Test rdf_type/0 returns correct RDF type IRI
- [x] Test all memory type class functions return correct IRIs
- [x] Test memory_type_to_class/1 for all memory types
- [x] Test memory_type_to_class/1 raises for unknown types
- [x] Test class_to_memory_type/1 for all class IRIs
- [x] Test class_to_memory_type/1 returns :unknown for unrecognized IRIs
- [x] Test confidence_to_individual maps 0.8+ to High
- [x] Test confidence_to_individual maps 0.5-0.79 to Medium
- [x] Test confidence_to_individual maps <0.5 to Low
- [x] Test individual_to_confidence returns expected float values
- [x] Test source_type_to_individual for all source types
- [x] Test individual_to_source_type for all source IRIs
- [x] Test all property functions return correct IRIs
- [x] Test memory_uri/1 generates valid IRI from id
- [x] Test session_uri/1 generates valid IRI from id

---

## 2.2 Store Manager

Implement session-isolated triple store lifecycle management. Each session gets its own RocksDB-backed triple store.

### 2.2.1 StoreManager GenServer

- [x] 2.2.1.1 Create `lib/jido_code/memory/long_term/store_manager.ex` with comprehensive moduledoc
- [x] 2.2.1.2 Implement `use GenServer` with restart: :permanent
- [x] 2.2.1.3 Define state struct:
  ```elixir
  defstruct [
    stores: %{},          # %{session_id => store_handle}
    base_path: nil,       # Base directory for all stores
    config: %{}           # Store configuration options
  ]
  ```
- [x] 2.2.1.4 Define default configuration:
  ```elixir
  @default_base_path "~/.jido_code/memory_stores"
  @default_config %{
    create_if_missing: true
  }
  ```
- [x] 2.2.1.5 Implement `start_link/1` with optional base_path and config:
  ```elixir
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ [])
  ```
- [x] 2.2.1.6 Implement `init/1` to initialize state:
  - Expand ~ in base_path
  - Create base directory if missing
  - Initialize empty stores map
- [x] 2.2.1.7 Implement `get_or_create/1` client function:
  ```elixir
  @spec get_or_create(String.t()) :: {:ok, store_handle()} | {:error, term()}
  def get_or_create(session_id)
  ```
  - Return existing store if already open
  - Open new store if not exists
- [x] 2.2.1.8 Implement `get/1` client function:
  ```elixir
  @spec get(String.t()) :: {:ok, store_handle()} | {:error, :not_found}
  def get(session_id)
  ```
  - Return store only if already open
  - Return error if not open (don't auto-create)
- [x] 2.2.1.9 Implement `close/1` client function:
  ```elixir
  @spec close(String.t()) :: :ok | {:error, term()}
  def close(session_id)
  ```
  - Close and remove store from state
  - Handle already-closed gracefully
- [x] 2.2.1.10 Implement `close_all/0` client function:
  ```elixir
  @spec close_all() :: :ok
  def close_all()
  ```
  - Close all open stores
  - Used during shutdown
- [x] 2.2.1.11 Implement `list_open/0` to list currently open session stores
- [x] 2.2.1.12 Implement private `store_path/2` to generate session-specific path:
  ```elixir
  defp store_path(base_path, session_id) do
    Path.join(base_path, "session_" <> session_id)
  end
  ```
- [x] 2.2.1.13 Implement private `open_store/1` wrapping `TripleStore.open/2`:
  ```elixir
  defp open_store(path) do
    TripleStore.open(path, create_if_missing: true)
  end
  ```
- [x] 2.2.1.14 Implement `handle_call({:get_or_create, session_id}, ...)` callback
- [x] 2.2.1.15 Implement `handle_call({:get, session_id}, ...)` callback
- [x] 2.2.1.16 Implement `handle_call({:close, session_id}, ...)` callback
- [x] 2.2.1.17 Implement `handle_call(:close_all, ...)` callback
- [x] 2.2.1.18 Implement `handle_call(:list_open, ...)` callback
- [x] 2.2.1.19 Implement `terminate/2` to close all stores on shutdown:
  ```elixir
  def terminate(_reason, state) do
    Enum.each(state.stores, fn {_id, store} ->
      TripleStore.close(store)
    end)
    :ok
  end
  ```

### 2.2.2 Unit Tests for StoreManager

- [x] Test start_link/0 starts GenServer with default base_path
- [x] Test start_link/1 accepts custom base_path option
- [x] Test start_link/1 accepts custom config options
- [x] Test get_or_create/1 creates new store for unknown session
- [x] Test get_or_create/1 returns existing store for known session
- [x] Test get_or_create/1 creates store directory if missing
- [x] Test get/1 returns store for known session
- [x] Test get/1 returns {:error, :not_found} for unknown session
- [x] Test close/1 closes and removes store from state
- [x] Test close/1 handles already-closed session gracefully
- [x] Test close_all/0 closes all open stores
- [x] Test list_open/0 returns list of open session ids
- [x] Test terminate/2 closes all stores on shutdown
- [x] Test store paths are isolated per session
- [x] Test concurrent get_or_create calls for same session return same store

---

## 2.3 Triple Store Adapter

Implement the adapter layer for mapping Elixir memory structs to/from RDF triples using the Jido ontology vocabulary.

### 2.3.1 Adapter Module

- [x] 2.3.1.1 Create `lib/jido_code/memory/long_term/triple_store_adapter.ex` with moduledoc
- [x] 2.3.1.2 Define `memory_input()` type for persist input:
  ```elixir
  @type memory_input :: %{
    id: String.t(),
    content: String.t(),
    memory_type: memory_type(),
    confidence: float(),
    source_type: source_type(),
    session_id: String.t(),
    agent_id: String.t() | nil,
    project_id: String.t() | nil,
    evidence_refs: [String.t()],
    rationale: String.t() | nil,
    created_at: DateTime.t()
  }
  ```
- [x] 2.3.1.3 Define `stored_memory()` type for query results:
  ```elixir
  @type stored_memory :: %{
    id: String.t(),
    content: String.t(),
    memory_type: memory_type(),
    confidence: float(),
    source_type: source_type(),
    session_id: String.t(),
    agent_id: String.t() | nil,
    project_id: String.t() | nil,
    rationale: String.t() | nil,
    timestamp: DateTime.t(),
    superseded_by: String.t() | nil
  }
  ```
- [x] 2.3.1.4 Implement `persist/2` to store memory as RDF triples:
  ```elixir
  @spec persist(memory_input(), store_handle()) :: {:ok, String.t()} | {:error, term()}
  def persist(memory, store)
  ```
  Implementation steps:
  - Generate memory IRI from id using Vocab.memory_uri/1
  - Build triple list using build_triples/2
  - Insert all triples via TripleStore.insert/2
  - Return {:ok, memory.id} on success
- [x] 2.3.1.5 Implement `build_triples/2` private function:
  ```elixir
  defp build_triples(memory, session_id) do
    subject = Vocab.memory_uri(memory.id)
    [
      # Type assertion
      {subject, Vocab.rdf_type(), Vocab.memory_type_to_class(memory.memory_type)},
      # Content
      {subject, Vocab.summary(), RDF.literal(memory.content)},
      # Confidence
      {subject, Vocab.has_confidence(), Vocab.confidence_to_individual(memory.confidence)},
      # Source type
      {subject, Vocab.has_source_type(), Vocab.source_type_to_individual(memory.source_type)},
      # Session scoping
      {subject, Vocab.asserted_in(), Vocab.session_uri(session_id)},
      # Timestamp
      {subject, Vocab.has_timestamp(), RDF.literal(memory.created_at, datatype: XSD.dateTime())}
    ]
    |> add_optional_triple(memory.agent_id, subject, Vocab.asserted_by(), &Vocab.agent_uri/1)
    |> add_optional_triple(memory.project_id, subject, Vocab.applies_to_project(), &Vocab.project_uri/1)
    |> add_optional_triple(memory.rationale, subject, Vocab.rationale(), &RDF.literal/1)
    |> add_evidence_triples(memory.evidence_refs, subject)
  end
  ```
- [x] 2.3.1.6 Implement `query_by_type/3` to retrieve memories by type:
  ```elixir
  @spec query_by_type(store_handle(), String.t(), memory_type(), keyword()) ::
    {:ok, [stored_memory()]} | {:error, term()}
  def query_by_type(store, session_id, memory_type, opts \\ [])
  ```
  - Build SPARQL SELECT query for type
  - Filter by session_id
  - Apply limit from opts
  - Map results to stored_memory structs
- [x] 2.3.1.7 Implement `query_all/3` to retrieve all memories for session:
  ```elixir
  @spec query_all(store_handle(), String.t(), keyword()) ::
    {:ok, [stored_memory()]} | {:error, term()}
  def query_all(store, session_id, opts \\ [])
  ```
  - Query for all MemoryItem instances scoped to session
  - Apply optional min_confidence filter
  - Apply limit
  - Exclude superseded memories by default (option to include)
- [x] 2.3.1.8 Implement `query_by_id/2` to retrieve single memory:
  ```elixir
  @spec query_by_id(store_handle(), String.t()) ::
    {:ok, stored_memory()} | {:error, :not_found}
  def query_by_id(store, memory_id)
  ```
- [x] 2.3.1.9 Implement `supersede/4` to mark memory as superseded:
  ```elixir
  @spec supersede(store_handle(), String.t(), String.t(), String.t() | nil) ::
    :ok | {:error, term()}
  def supersede(store, session_id, old_memory_id, new_memory_id \\ nil)
  ```
  - Add supersededBy triple if new_memory_id provided
  - Add supersession timestamp
- [x] 2.3.1.10 Implement `delete/3` to remove memory triples:
  ```elixir
  @spec delete(store_handle(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete(store, session_id, memory_id)
  ```
  - Delete all triples with memory as subject
  - Use SPARQL DELETE WHERE
- [x] 2.3.1.11 Implement `record_access/3` to track memory access:
  ```elixir
  @spec record_access(store_handle(), String.t(), String.t()) :: :ok
  def record_access(store, session_id, memory_id)
  ```
  - Update access count triple
  - Update last accessed timestamp triple
- [x] 2.3.1.12 Implement `count/2` to count memories for session:
  ```elixir
  @spec count(store_handle(), String.t()) :: {:ok, non_neg_integer()}
  def count(store, session_id)
  ```
- [x] 2.3.1.13 Implement private `build_select_query/3` for SPARQL generation
- [x] 2.3.1.14 Implement private `parse_query_result/1` to convert query result to stored_memory
- [x] 2.3.1.15 Implement private `extract_id/1` to extract id from memory IRI

### 2.3.2 Unit Tests for TripleStoreAdapter

- [x] Test persist/2 creates correct type triple
- [x] Test persist/2 creates summary triple with content
- [x] Test persist/2 creates confidence triple with correct level
- [x] Test persist/2 creates source type triple
- [x] Test persist/2 creates session scoping triple (assertedIn)
- [x] Test persist/2 creates timestamp triple
- [x] Test persist/2 includes optional agent triple when present
- [x] Test persist/2 includes optional project triple when present
- [x] Test persist/2 includes optional rationale triple when present
- [x] Test persist/2 creates evidence triples for each reference
- [x] Test persist/2 returns {:ok, id} on success
- [x] Test query_by_type/3 returns memories of specified type only
- [x] Test query_by_type/3 respects limit option
- [x] Test query_by_type/3 filters by session_id
- [x] Test query_all/3 returns all memories for session
- [x] Test query_all/3 filters by min_confidence
- [x] Test query_all/3 excludes superseded memories by default
- [x] Test query_all/3 includes superseded with option
- [x] Test query_by_id/2 returns specific memory
- [x] Test query_by_id/2 returns {:error, :not_found} for missing id
- [x] Test supersede/4 adds supersededBy triple
- [x] Test supersede/4 adds supersession timestamp
- [x] Test delete/3 removes all triples for memory
- [x] Test record_access/3 updates access tracking
- [x] Test count/2 returns correct count

---

## 2.4 Memory Facade Module

High-level convenience functions providing the public API for memory operations.

### 2.4.1 Memory Module Public API

- [x] 2.4.1.1 Create `lib/jido_code/memory/memory.ex` with comprehensive moduledoc
- [x] 2.4.1.2 Implement `persist/2` facade:
  ```elixir
  @spec persist(memory_input(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def persist(memory, session_id) do
    with {:ok, store} <- StoreManager.get_or_create(session_id) do
      TripleStoreAdapter.persist(memory, store)
    end
  end
  ```
- [x] 2.4.1.3 Implement `query/2` facade with options:
  ```elixir
  @spec query(String.t(), keyword()) :: {:ok, [stored_memory()]} | {:error, term()}
  def query(session_id, opts \\ [])
  ```
  - Options: type, min_confidence, limit, include_superseded
- [x] 2.4.1.4 Implement `query_by_type/3` facade:
  ```elixir
  @spec query_by_type(String.t(), memory_type(), keyword()) ::
    {:ok, [stored_memory()]} | {:error, term()}
  def query_by_type(session_id, memory_type, opts \\ [])
  ```
- [x] 2.4.1.5 Implement `get/2` facade for single memory:
  ```elixir
  @spec get(String.t(), String.t()) :: {:ok, stored_memory()} | {:error, :not_found}
  def get(session_id, memory_id)
  ```
- [x] 2.4.1.6 Implement `supersede/3` facade:
  ```elixir
  @spec supersede(String.t(), String.t(), String.t() | nil) :: :ok | {:error, term()}
  def supersede(session_id, old_memory_id, new_memory_id \\ nil)
  ```
- [x] 2.4.1.7 Implement `forget/2` facade (supersede with nil replacement):
  ```elixir
  @spec forget(String.t(), String.t()) :: :ok | {:error, term()}
  def forget(session_id, memory_id) do
    supersede(session_id, memory_id, nil)
  end
  ```
- [x] 2.4.1.8 Implement `count/1` facade:
  ```elixir
  @spec count(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(session_id)
  ```
- [x] 2.4.1.9 Implement `record_access/2` facade:
  ```elixir
  @spec record_access(String.t(), String.t()) :: :ok
  def record_access(session_id, memory_id)
  ```
- [x] 2.4.1.10 Implement `load_ontology/1` to load Jido TTL files into store:
  ```elixir
  @spec load_ontology(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_ontology(session_id)
  ```
  - Load jido-core.ttl and jido-knowledge.ttl

### 2.4.2 Unit Tests for Memory Facade

- [x] Test persist/2 stores memory via StoreManager and Adapter
- [x] Test persist/2 creates store if not exists
- [x] Test query/2 returns memories for session
- [x] Test query/2 applies type filter
- [x] Test query/2 applies min_confidence filter
- [x] Test query_by_type/3 filters by type
- [x] Test get/2 retrieves single memory
- [x] Test get/2 returns error for non-existent id
- [x] Test supersede/3 marks memory as superseded
- [x] Test forget/2 marks memory as superseded without replacement
- [x] Test count/1 returns memory count
- [x] Test record_access/2 updates access tracking
- [x] Test load_ontology/1 loads TTL files

---

## 2.5 Memory Supervisor

Supervision tree for memory subsystem processes.

### 2.5.1 Supervisor Module

- [ ] 2.5.1.1 Create `lib/jido_code/memory/supervisor.ex` with moduledoc
- [ ] 2.5.1.2 Implement `use Supervisor`
- [ ] 2.5.1.3 Implement `start_link/1` with named registration:
  ```elixir
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  ```
- [ ] 2.5.1.4 Implement `init/1` with children:
  ```elixir
  def init(opts) do
    children = [
      {JidoCode.Memory.LongTerm.StoreManager, opts}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
  ```
- [ ] 2.5.1.5 Add `JidoCode.Memory.Supervisor` to application supervision tree in application.ex:
  ```elixir
  children = [
    # ... existing children ...
    JidoCode.Memory.Supervisor
  ]
  ```

### 2.5.2 Unit Tests for Memory Supervisor

- [ ] Test supervisor starts with StoreManager child
- [ ] Test StoreManager restarts on crash (permanent)
- [ ] Test supervisor handles StoreManager failure gracefully
- [ ] Test supervisor starts successfully in application

---

## 2.6 Phase 2 Integration Tests

Integration tests for long-term memory store functionality.

### 2.6.1 Store Lifecycle Integration

- [ ] 2.6.1.1 Create `test/jido_code/integration/memory_phase2_test.exs`
- [ ] 2.6.1.2 Test: StoreManager creates isolated RocksDB store per session
- [ ] 2.6.1.3 Test: Store persists data across get_or_create calls
- [ ] 2.6.1.4 Test: Multiple sessions have completely isolated data
- [ ] 2.6.1.5 Test: Closing store allows clean shutdown
- [ ] 2.6.1.6 Test: Store reopens correctly after close

### 2.6.2 Memory CRUD Integration

- [ ] 2.6.2.1 Test: Full lifecycle - persist, query, update, supersede, query again
- [ ] 2.6.2.2 Test: Multiple memory types stored and retrieved correctly
- [ ] 2.6.2.3 Test: Confidence filtering works correctly across types
- [ ] 2.6.2.4 Test: Memory with all optional fields persists and retrieves correctly
- [ ] 2.6.2.5 Test: Superseded memories excluded from normal queries
- [ ] 2.6.2.6 Test: Superseded memories included with include_superseded option
- [ ] 2.6.2.7 Test: Access tracking updates correctly on queries

### 2.6.3 Ontology Integration

- [ ] 2.6.3.1 Test: Vocabulary IRIs match TTL file definitions
- [ ] 2.6.3.2 Test: Load Jido ontology into store via load_ontology/1
- [ ] 2.6.3.3 Test: SPARQL queries work correctly with loaded ontology
- [ ] 2.6.3.4 Test: Memory type class hierarchy is correct

### 2.6.4 Concurrency Integration

- [ ] 2.6.4.1 Test: Concurrent persist operations to same session
- [ ] 2.6.4.2 Test: Concurrent queries during persist operations
- [ ] 2.6.4.3 Test: Multiple sessions with concurrent operations

---

## Phase 2 Success Criteria

1. **Vocabulary Module**: Complete Jido ontology IRI mappings implemented
2. **StoreManager**: Session-isolated RocksDB stores via triple_store working
3. **TripleStoreAdapter**: Elixir struct to RDF triple bidirectional mapping functional
4. **Memory Facade**: High-level API for all memory operations
5. **Supervisor**: Memory subsystem supervision tree running
6. **Isolation**: Each session has completely isolated persistent storage
7. **CRUD Operations**: persist, query, supersede, forget all functional
8. **Ontology**: Jido ontology classes correctly used for memory types
9. **Test Coverage**: Minimum 80% for all Phase 2 modules

---

## Phase 2 Critical Files

**New Files:**
- `lib/jido_code/memory/long_term/vocab/jido.ex`
- `lib/jido_code/memory/long_term/store_manager.ex`
- `lib/jido_code/memory/long_term/triple_store_adapter.ex`
- `lib/jido_code/memory/memory.ex`
- `lib/jido_code/memory/supervisor.ex`
- `test/jido_code/memory/long_term/vocab/jido_test.exs`
- `test/jido_code/memory/long_term/store_manager_test.exs`
- `test/jido_code/memory/long_term/triple_store_adapter_test.exs`
- `test/jido_code/memory/memory_test.exs`
- `test/jido_code/memory/supervisor_test.exs`
- `test/jido_code/integration/memory_phase2_test.exs`

**Modified Files:**
- `lib/jido_code/application.ex` - Add Memory.Supervisor to supervision tree
- `mix.exs` - Add triple_store dependency path

---

## Code Review Fixes (2025-12-30)

After completing sections 2.1-2.4, a comprehensive code review was performed. The following fixes were implemented:

### Security Fixes

- [x] Session ID validation to prevent atom exhaustion attacks
- [x] Path traversal prevention via session ID format validation
- [x] Path containment check for defense-in-depth

### API Improvements

- [x] Session ownership verification in `query_by_id/3`
- [x] Input validation for memory fields (memory_type, source_type, confidence)
- [x] Guards added to all public Memory facade functions
- [x] Added `list_sessions/0` and `close_session/1` to Memory facade

### Documentation

- [x] Documented `record_access/2` intentional error swallowing
- [x] Documented ETS public access limitation and rationale

### Test Coverage

- [x] Session ID validation tests (security)
- [x] Input validation tests (Types module)
- [x] `delete/2` behavioral tests

**Review Document:** `notes/reviews/2025-12-30-phase2-section-2.4-review.md`
**Summary Document:** `notes/summaries/2025-12-30-phase2-section2.4-review-fixes.md`
