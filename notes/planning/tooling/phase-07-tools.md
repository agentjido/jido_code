# Phase 7: Knowledge Graph Tools (TripleStore Rewrite)

This phase implements LLM-facing tools for interacting with the Jido knowledge ontology using **TripleStore with named graphs**. The tools expose the knowledge graph to the LLM through the Handler pattern, enabling semantic memory operations via SPARQL queries.

> **STATUS:** This phase rewrites the existing ETS-based Phase 7 tools to use TripleStore with named graphs. The original tools remain functional until the rewrite is complete.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  TripleStore Instance (per project)                             │
├─────────────────────────────────────────────────────────────────┤
│  Default Graph: Jido Ontology (read-only reference)            │
│  Named Graph 1: urn:jido:graph:memory:{project_id}              │
│    - Knowledge items (facts, decisions, risks, conventions)     │
│  Named Graph 2: urn:jido:graph:code:{project_id} (Phase 8)     │
└─────────────────────────────────────────────────────────────────┘
```

## Handler Pattern Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                           │
│  e.g., {"name": "knowledge_remember", "arguments": {...}}       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Handler.execute/2 validates and processes                      │
│  - Uses HandlerHelpers for session context                      │
│  - Validates against ontology types                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  TripleStoreManager.get_project_context/1                       │
│  - Returns context with db, memory_graph_iri                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  MemoryStore (SPARQL-based operations)                          │
│  - insert_memory/2, query_by_type/3, get_memory/2               │
│  - All operations use SPARQL with GRAPH clause                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Result formatted as JSON for LLM                               │
│  - Memory IDs, types, confidence levels                         │
│  - Relationship information                                     │
└─────────────────────────────────────────────────────────────────┘
```

## Ontology Foundation

The canonical ontology is defined in TTL files:

| TTL File | Purpose |
|----------|---------|
| `lib/ontology/long-term-context/jido-core.ttl` | Base classes (MemoryItem, Entity), confidence levels, source types |
| `lib/ontology/long-term-context/jido-knowledge.ttl` | Knowledge types (Fact, Assumption, Hypothesis, Discovery, Risk, Unknown) |
| `lib/ontology/long-term-context/jido-convention.ttl` | Convention types (CodingStandard, ArchitecturalConvention, AgentRule, ProcessConvention) |
| `lib/ontology/long-term-context/jido-decision.ttl` | Decision types (ArchitecturalDecision, ImplementationDecision, Alternative, TradeOff) |

## Tools in This Phase

| Tool | Priority | Purpose | Status |
|------|----------|---------|--------|
| `knowledge_remember` | P0 | Store new knowledge with ontology typing | ⬜ To be rewritten |
| `knowledge_recall` | P0 | Query knowledge with semantic filters | ⬜ To be rewritten |
| `knowledge_supersede` | P1 | Replace outdated knowledge | ⬜ To be rewritten |
| `project_conventions` | P1 | Get all conventions and standards | ⬜ To be rewritten |
| `knowledge_update` | P2 | Update confidence/evidence on existing | ⬜ To be rewritten |
| `project_decisions` | P2 | Get architectural decisions | ⬜ To be rewritten |
| `project_risks` | P2 | Get known risks and issues | ⬜ To be rewritten |
| `knowledge_graph_query` | P3 | Advanced relationship traversal | ⬜ To be rewritten |
| `knowledge_context` | P3 | Auto-retrieve relevant context | ⬜ To be rewritten |

> **Note:** Original ETS-based implementations exist and will be replaced by SPARQL-based versions.

---

## Section 7.0: Foundation Layer

### 7.0.1 TripleStoreManager Supervisor

**Status:** ⬜ Initial

Create the supervisor for managing TripleStore instances per project.

#### Tasks

- [ ] 7.0.1.1 Create `lib/jido_code/triple_store_manager.ex` DynamicSupervisor
  - [ ] Implement `start_link/1` for supervisor initialization
  - [ ] Implement `get_or_create_project/1` to get or start project store
  - [ ] Implement `close_project/1` to terminate project store
  - [ ] Register with Registry for project tracking

- [ ] 7.0.1.2 Create unit tests for TripleStoreManager
  - [ ] Test supervisor starts correctly
  - [ ] Test get_or_create_project returns existing PID
  - [ ] Test get_or_create_project starts new project
  - [ ] Test close_project terminates child process

### 7.0.2 TripleStore.Project GenServer

**Status:** ⬜ Initial

Create a per-project GenServer that wraps a TripleStore instance with named graphs.

#### Tasks

- [ ] 7.0.2.1 Create `lib/jido_code/triple_store/project.ex` GenServer
  - [ ] Implement `start_link/1` with project_id option
  - [ ] Implement `init/1` to open TripleStore database
  - [ ] Define memory_graph_iri: `urn:jido:graph:memory:{project_id}`
  - [ ] Define code_graph_iri: `urn:jido:graph:code:{project_id}`
  - [ ] Implement `get_context/0` to return store context map
  - [ ] Implement `terminate/2` to close TripleStore on shutdown
  - [ ] Register project in Registry

- [ ] 7.0.2.2 Create unit tests for TripleStore.Project
  - [ ] Test GenServer starts and opens TripleStore
  - [ ] Test get_context returns valid context map
  - [ ] Test memory_graph_iri format is correct
  - [ ] Test code_graph_iri format is correct
  - [ ] Test graceful shutdown closes TripleStore

### 7.0.3 ProjectRegistry

**Status:** ⬜ Initial

Create a registry for tracking active project stores.

#### Tasks

- [ ] 7.0.3.1 Create `lib/jido_code/project_registry.ex`
  - [ ] Use Registry for key-based process registration
  - [ ] Keys are project_id values
  - [ ] Support lookup by project_id

- [ ] 7.0.3.2 Add to application supervision tree
  - [ ] Register ProjectRegistry before TripleStoreManager

### 7.0.4 MemoryStore Module

**Status:** ⬜ Initial

Create a wrapper module for memory graph operations using SPARQL.

#### Tasks

- [ ] 7.0.4.1 Create `lib/jido_code/memory_store.ex`
  - [ ] Implement `insert_memory/2` - INSERT DATA with GRAPH clause
  - [ ] Implement `query_by_type/3` - SELECT with type filter
  - [ ] Implement `get_memory/2` - CONSTRUCT by memory URI
  - [ ] Implement `supersede_memory/3` - INSERT supersededBy triple
  - [ ] Implement `update_memory/3` - SPARQL UPDATE for properties
  - [ ] Implement `record_access/2` - UPDATE access count and timestamp
  - [ ] Implement `get_context/3` - Multi-factor relevance scoring

- [ ] 7.0.4.2 Create unit tests for MemoryStore
  - [ ] Test insert_memory creates triples in correct graph
  - [ ] Test query_by_type returns matching memories
  - [ ] Test get_memory retrieves full memory details
  - [ ] Test supersede_memory adds supersededBy relationship
  - [ ] Test update_memory modifies properties
  - [ ] Test record_access updates access tracking

### 7.0.5 SPARQLQueries Module

**Status:** ⬜ Initial

Create a module with reusable SPARQL query templates.

#### Tasks

- [ ] 7.0.5.1 Create `lib/jido_code/memory/sparql_queries.ex`
  - [ ] Implement `query_by_type/3` template with type filters
  - [ ] Implement `get_by_id/2` template for memory lookup
  - [ ] Implement `supersede/3` template for supersession
  - [ ] Implement `project_conventions/2` template
  - [ ] Implement `project_decisions/2` template
  - [ ] Implement `project_risks/2` template
  - [ ] Implement `graph_traversal/5` template for relationship queries
  - [ ] Implement `context_query/3` template for relevance queries

- [ ] 7.0.5.2 Add unit tests for SPARQLQueries
  - [ ] Test query_by_type generates valid SPARQL
  - [ ] Test filters are correctly applied
  - [ ] Test GRAPH clause includes correct IRI
  - [ ] Test graph_traversal generates property paths

---

## Section 7.1: knowledge_remember Tool (P0)

**Status:** ⬜ To be rewritten

Store new knowledge in the named graph with full ontology support.

### 7.1.1 Tool Definition

- [ ] Update `lib/jido_code/tools/definitions/knowledge.ex`
- [ ] Verify existing schema is compatible:
  ```elixir
  %{
    name: "knowledge_remember",
    description: "Store knowledge for future reference. Types include: fact, assumption, hypothesis, discovery, risk, unknown, convention, coding_standard, decision, architectural_decision.",
    parameters: [
      %{name: "content", type: :string, required: true,
        description: "The knowledge content to store"},
      %{name: "type", type: :string, required: true,
        description: "Memory type (fact, assumption, hypothesis, discovery, risk, unknown, convention, coding_standard, decision, etc.)"},
      %{name: "confidence", type: :float, required: false,
        description: "Confidence level 0.0-1.0 (default: 0.8 for facts, 0.5 for assumptions)"},
      %{name: "rationale", type: :string, required: false,
        description: "Explanation for why this is worth remembering"},
      %{name: "evidence_refs", type: :array, required: false,
        description: "References to supporting evidence (file paths, URLs, memory IDs)"},
      %{name: "related_to", type: :string, required: false,
        description: "ID of related memory item for linking"}
    ]
  }
  ```

### 7.1.2 Handler Implementation

- [ ] Rewrite `KnowledgeRemember` handler in `lib/jido_code/tools/handlers/knowledge.ex`
  - [ ] Validate memory type against ontology types
  - [ ] Get project_id from context via HandlerHelpers
  - [ ] Call `TripleStoreManager.get_project_context/1`
  - [ ] Build memory triple map with ontology IRIs
  - [ ] Call `MemoryStore.insert_memory/2` with SPARQL INSERT DATA
  - [ ] Return JSON with memory_id, type, confidence
  - [ ] Emit telemetry `[:jido_code, :knowledge, :remember]`

**SPARQL Query Template:**
```sparql
PREFIX jido: <https://jido.ai/ontology#>

INSERT DATA {
  GRAPH <urn:jido:graph:memory:{project_id}> {
    <urn:jido:memory:{memory_id}> a jido:{Type} ;
        jido:summary "{content}" ;
        jido:hasConfidence jido:{ConfidenceLevel} ;
        jido:hasSourceType jido:Agent ;
        jido:assertedIn <urn:jido:session:{session_id}> ;
        jido:hasTimestamp "{timestamp}"^^xsd:dateTime .
  }
}
```

### 7.1.3 Unit Tests

- [ ] Test stores fact with high confidence
- [ ] Test stores assumption with medium confidence
- [ ] Test validates memory type enum
- [ ] Test validates confidence bounds (0.0-1.0)
- [ ] Test requires project context
- [ ] Test handles evidence_refs
- [ ] Test handles related_to linking
- [ ] Test applies default confidence by type
- [ ] Test triples are inserted into correct named graph
- [ ] Test telemetry emission

---

## Section 7.2: knowledge_recall Tool (P0)

**Status:** ⬜ To be rewritten

Query the knowledge graph with semantic filters using SPARQL.

### 7.2.1 Tool Definition

- [ ] Verify existing schema in `knowledge.ex`

### 7.2.2 Handler Implementation

- [ ] Rewrite `KnowledgeRecall` handler
  - [ ] Get project_id from context
  - [ ] Call `TripleStoreManager.get_project_context/1`
  - [ ] Build SPARQL SELECT query with filters
  - [ ] Support text search via FILTER CONTAINS
  - [ ] Support type filtering via `VALUES ?type { jido:Fact jido:Decision }`
  - [ ] Support confidence threshold filtering
  - [ ] Support include_superseded via FILTER NOT EXISTS
  - [ ] Call `MemoryStore.query_by_type/3` or direct SPARQL
  - [ ] Format results as JSON
  - [ ] Emit telemetry `[:jido_code, :knowledge, :recall]`

**SPARQL Query Template:**
```sparql
PREFIX jido: <https://jido.ai/ontology#>

SELECT ?id ?content ?type ?confidence ?timestamp ?rationale
WHERE {
  GRAPH <urn:jido:graph:memory:{project_id}> {
    ?id a ?type ;
        jido:summary ?content ;
        jido:hasConfidence ?conf_iri ;
        jido:hasTimestamp ?timestamp .
    OPTIONAL { ?id jido:rationale ?rationale }
    FILTER NOT EXISTS { ?id jido:supersededBy ?superseded }
    FILTER(?confidence >= {min_confidence})
  }
}
ORDER BY DESC(?timestamp)
LIMIT {limit}
```

### 7.2.3 Unit Tests

- [ ] Test retrieves all memories for project
- [ ] Test filters by single type
- [ ] Test filters by multiple types
- [ ] Test filters by confidence threshold
- [ ] Test text search within content
- [ ] Test respects limit
- [ ] Test returns empty for no matches
- [ ] Test excludes superseded by default
- [ ] Test includes superseded when requested
- [ ] Test telemetry emission

---

## Section 7.3: knowledge_supersede Tool (P1)

**Status:** ⬜ To be rewritten

Mark knowledge as superseded and optionally create replacement.

### 7.3.1 Tool Definition

- [ ] Verify existing schema in `knowledge.ex`

### 7.3.2 Handler Implementation

- [ ] Rewrite `KnowledgeSupersede` handler
  - [ ] Get project_id from context
  - [ ] Validate old_memory_id exists via SPARQL ASK
  - [ ] If new_content provided, create replacement memory
  - [ ] Insert supersededBy relationship via SPARQL INSERT DATA
  - [ ] Link new to old via evidence_refs
  - [ ] Return old_id, new_id (if created), status
  - [ ] Emit telemetry `[:jido_code, :knowledge, :supersede]`

**SPARQL Query Template:**
```sparql
PREFIX jido: <https://jido.ai/ontology#>

INSERT DATA {
  GRAPH <urn:jido:graph:memory:{project_id}> {
    <urn:jido:memory:{old_id}> jido:supersededBy <urn:jido:memory:{new_id}> ;
        jido:supersededAt "{timestamp}"^^xsd:dateTime .
  }
}
```

### 7.3.3 Unit Tests

- [ ] Test marks memory as superseded
- [ ] Test creates replacement when content provided
- [ ] Test links replacement to original
- [ ] Test handles non-existent memory_id
- [ ] Test requires project context
- [ ] Test inherits type from original when not specified
- [ ] Test allows specifying new type
- [ ] Test validates new_content size
- [ ] Test telemetry emission

---

## Section 7.4: knowledge_update Tool (P2)

**Status:** ⬜ To be rewritten

Update confidence or add evidence to existing knowledge.

### 7.4.1 Tool Definition

- [ ] Verify existing schema in `knowledge.ex`

### 7.4.2 Handler Implementation

- [ ] Rewrite `KnowledgeUpdate` handler
  - [ ] Validate memory exists via SPARQL ASK
  - [ ] Update confidence if provided via SPARQL DELETE/INSERT
  - [ ] Append evidence refs via SPARQL INSERT
  - [ ] Append rationale via SPARQL INSERT
  - [ ] Return updated memory summary
  - [ ] Emit telemetry `[:jido_code, :knowledge, :update]`

**SPARQL Query Template:**
```sparql
PREFIX jido: <https://jido.ai/ontology#>

DELETE {
  GRAPH <urn:jido:graph:memory:{project_id}> {
    <urn:jido:memory:{id}> jido:hasConfidence ?old .
  }
}
INSERT {
  GRAPH <urn:jido:graph:memory:{project_id}> {
    <urn:jido:memory:{id}> jido:hasConfidence jido:{NewConfidenceLevel} .
  }
}
WHERE {
  GRAPH <urn:jido:graph:memory:{project_id}> {
    <urn:jido:memory:{id}> jido:hasConfidence ?old .
  }
}
```

### 7.4.3 Unit Tests

- [ ] Test updates confidence
- [ ] Test adds evidence refs
- [ ] Test appends rationale
- [ ] Test validates ownership
- [ ] Test validates confidence bounds
- [ ] Test handles non-existent memory
- [ ] Test telemetry emission

---

## Section 7.5: project_conventions Tool (P1)

**Status:** ⬜ To be rewritten

Get all conventions and coding standards for the project.

### 7.5.1 Tool Definition

- [ ] Verify existing schema in `knowledge.ex`

### 7.5.2 Handler Implementation

- [ ] Rewrite `ProjectConventions` handler
  - [ ] Build SPARQL SELECT for Convention types
  - [ ] Map category to specific type IRIs
  - [ ] Filter by min_confidence threshold
  - [ ] Sort by confidence descending
  - [ ] Exclude superseded conventions
  - [ ] Emit telemetry `[:jido_code, :knowledge, :project_conventions]`

**SPARQL Query Template:**
```sparql
PREFIX jido: <https://jido.ai/ontology#>

SELECT ?id ?content ?confidence ?timestamp
WHERE {
  GRAPH <urn:jido:graph:memory:{project_id}> {
    ?id a jido:Convention ;
        jido:summary ?content ;
        jido:hasConfidence ?conf_iri ;
        jido:hasTimestamp ?timestamp .
    FILTER NOT EXISTS { ?id jido:supersededBy ?superseded }
  }
}
ORDER BY DESC(?timestamp)
LIMIT {limit}
```

### 7.5.3 Unit Tests

- [ ] Test retrieves all conventions
- [ ] Test retrieves coding standards specifically
- [ ] Test category filtering (architectural)
- [ ] Test confidence threshold filtering
- [ ] Test returns empty when none exist
- [ ] Test requires project context
- [ ] Test handles case-insensitive category
- [ ] Test sorts by confidence descending
- [ ] Test excludes superseded conventions
- [ ] Test telemetry emission

---

## Section 7.6: project_decisions Tool (P2)

**Status:** ⬜ To be rewritten

Get architectural decisions with rationale.

### 7.6.1 Tool Definition

- [ ] Verify existing schema in `knowledge.ex`

### 7.6.2 Handler Implementation

- [ ] Rewrite `ProjectDecisions` handler
  - [ ] Build SPARQL SELECT for Decision types
  - [ ] Include/exclude superseded based on parameter
  - [ ] Optionally include :alternative type memories
  - [ ] Return with rationale field
  - [ ] Emit telemetry `[:jido_code, :knowledge, :project_decisions]`

### 7.6.3 Unit Tests

- [ ] Test retrieves decisions
- [ ] Test excludes superseded by default
- [ ] Test includes superseded when requested
- [ ] Test filters by decision type
- [ ] Test includes alternatives when requested
- [ ] Test telemetry emission

---

## Section 7.7: project_risks Tool (P2)

**Status:** ⬜ To be rewritten

Get known risks and issues.

### 7.7.1 Tool Definition

- [ ] Verify existing schema in `knowledge.ex`

### 7.7.2 Handler Implementation

- [ ] Rewrite `ProjectRisks` handler
  - [ ] Build SPARQL SELECT for Risk type
  - [ ] Filter by confidence threshold
  - [ ] Sort by confidence descending
  - [ ] Support include_mitigated for superseded risks
  - [ ] Emit telemetry `[:jido_code, :knowledge, :project_risks]`

### 7.7.3 Unit Tests

- [ ] Test retrieves risks
- [ ] Test filters by confidence
- [ ] Test sorts by confidence descending
- [ ] Test excludes mitigated by default
- [ ] Test includes mitigated when requested
- [ ] Test telemetry emission

---

## Section 7.8: knowledge_graph_query Tool (P3)

**Status:** ⬜ To be rewritten

Traverse the knowledge graph to find memories related to a starting memory via relationship types.

### 7.8.1 Tool Definition

- [ ] Verify existing schema in `knowledge.ex`

### 7.8.2 Handler Implementation

- [ ] Rewrite `KnowledgeGraphQuery` handler
  - [ ] Validate start_from memory ID format
  - [ ] Validate relationship type against allowed values
  - [ ] Build SPARQL property path query for traversal
  - [ ] Support recursive traversal with cycle detection
  - [ ] Return list of related memories with relationship info
  - [ ] Emit telemetry `[:jido_code, :knowledge, :graph_query]`

**SPARQL Query Templates:**
```sparql
# derived_from
SELECT ?id ?content WHERE {
  GRAPH <graph> {
    <start> jido:derivedFrom ?evidence .
    ?id jido:summary ?content ; jido:derivedFrom ?evidence .
  }
}

# superseded_by
SELECT ?id ?content WHERE {
  GRAPH <graph> {
    <start> jido:supersededBy ?id ; jido:summary ?content .
  }
}

# same_type
SELECT ?id ?content WHERE {
  GRAPH <graph> {
    <start> a ?type .
    ?id a ?type ; jido:summary ?content .
    FILTER(?id != <start>)
  }
}
```

### 7.8.3 Unit Tests

- [ ] Test validates start_from parameter
- [ ] Test validates relationship parameter
- [ ] Test handles invalid memory ID format
- [ ] Test handles invalid relationship type
- [ ] Test depth option (1-5)
- [ ] Test limit option
- [ ] Test include_superseded option
- [ ] Test telemetry emission
- [ ] Test each relationship type traversal
- [ ] Test empty results handling

---

## Section 7.9: knowledge_context Tool (P3)

**Status:** ⬜ To be rewritten

Automatically retrieve contextually relevant memories using multi-factor relevance scoring.

### 7.9.1 Tool Definition

- [ ] Verify existing schema in `knowledge.ex`

### 7.9.2 Handler Implementation

- [ ] Rewrite `KnowledgeContext` handler
  - [ ] Validate context_hint length (3-1000 chars)
  - [ ] Build SPARQL SELECT for candidate memories
  - [ ] Implement multi-factor relevance scoring in Elixir
  - [ ] Return scored memories with relevance_score field
  - [ ] Emit telemetry `[:jido_code, :knowledge, :context]`

### 7.9.3 Relevance Scoring Algorithm

- **Text Similarity (40%)** - Word overlap between context and content
- **Recency (30%)** - Exponential decay (7-day half-life)
- **Confidence (20%)** - Memory's confidence level
- **Access Frequency (10%)** - Normalized access count

### 7.9.4 Unit Tests

- [ ] Test requires context_hint parameter
- [ ] Test validates context_hint length
- [ ] Test returns memories sorted by relevance score
- [ ] Test respects limit parameter
- [ ] Test respects min_confidence parameter
- [ ] Test respects include_types filter
- [ ] Test respects recency_weight parameter
- [ ] Test excludes superseded by default
- [ ] Test includes superseded when requested
- [ ] Test telemetry emission

---

## Section 7.10: Integration Tests

**Status:** ⬜ Initial

### 7.10.1 Handler Integration

- [ ] Create `test/jido_code/integration/tools_phase7_triplestore_test.exs`
- [ ] Test all tools execute through Executor → Handler chain
- [ ] Test project context propagation
- [ ] Test telemetry events are emitted

### 7.10.2 Knowledge Lifecycle

- [ ] Test: remember → recall → verify content
- [ ] Test: remember → supersede → recall excludes old
- [ ] Test: remember → update confidence → recall with new confidence
- [ ] Test: remember fact → update with evidence → confidence preserved

### 7.10.3 Named Graph Isolation

- [ ] Test memories are stored in correct named graph
- [ ] Test different projects have separate graphs
- [ ] Test queries only return from project's graph

---

## Section 7.11: Application Integration

**Status:** ⬜ Initial

### 7.11.1 Update Application Supervision Tree

- [ ] Add `ProjectRegistry` to `lib/jido_code/application.ex` children
- [ ] Add `TripleStoreManager` to children
- [ ] Remove old `StoreManager` from children (after migration complete)

### 7.11.2 Update Tool Registration

- [ ] Update `lib/jido_code/tools/definitions.ex` to register new tools
- [ ] Ensure both ETS and TripleStore versions don't conflict during transition

---

## Section 7.12: Cleanup (After Migration)

**Status:** ⬜ Deferred

### 7.12.1 Remove Old Files

- [ ] Delete `lib/jido_code/memory/long_term/triple_store_adapter.ex`
- [ ] Delete `lib/jido_code/memory/long_term/store_manager.ex`
- [ ] Remove old tests

### 7.12.2 Update Memory Facade

- [ ] Update `lib/jido_code/memory/memory.ex` to use TripleStoreManager
- [ ] Remove ETS-based code paths

---

## Phase 7 Success Criteria

| Criterion | Priority | Status |
|-----------|----------|--------|
| **TripleStoreManager**: Project store lifecycle | P0 | ⬜ |
| **MemoryStore**: SPARQL-based operations | P0 | ⬜ |
| **knowledge_remember**: Store with ontology types | P0 | ⬜ |
| **knowledge_recall**: Query with filters | P0 | ⬜ |
| **knowledge_supersede**: Replace outdated knowledge | P1 | ⬜ |
| **project_conventions**: List conventions/standards | P1 | ⬜ |
| **knowledge_update**: Modify confidence/evidence | P2 | ⬜ |
| **project_decisions**: List decisions with rationale | P2 | ⬜ |
| **project_risks**: List risks by confidence | P2 | ⬜ |
| **knowledge_graph_query**: Traverse relationships | P3 | ⬜ |
| **knowledge_context**: Auto-relevance | P3 | ⬜ |
| **Named graph isolation**: Separate memory/code graphs | P0 | ⬜ |
| **Test coverage**: Minimum 80% | - | ⬜ |

---

## Phase 7 Critical Files

### Files to CREATE

| File | Purpose |
|------|---------|
| `lib/jido_code/triple_store_manager.ex` | Supervisor for project stores |
| `lib/jido_code/triple_store/project.ex` | Per-project GenServer wrapper |
| `lib/jido_code/memory_store.ex` | Memory graph operations wrapper |
| `lib/jido_code/memory/sparql_queries.ex` | SPARQL query templates |
| `lib/jido_code/project_registry.ex` | Registry for tracking projects |

### Files to MODIFY

| File | Changes |
|------|---------|
| `lib/jido_code/memory/memory.ex` | Update to use TripleStoreManager |
| `lib/jido_code/tools/handlers/knowledge.ex` | Rewrite all 9 handlers for SPARQL |
| `lib/jido_code/application.ex` | Add TripleStoreManager to supervision tree |

### Files to DELETE (after migration)

| File | Reason |
|------|--------|
| `lib/jido_code/memory/long_term/triple_store_adapter.ex` | ETS-based, replaced by MemoryStore |
| `lib/jido_code/memory/long_term/store_manager.ex` | ETS-based, replaced by TripleStoreManager |

---

## Dependencies

**Blocking:** TripleStore named graph refactor must complete before implementation begins.

**Ontologies:**
- Jido: `lib/ontology/long-term-context/*.ttl`
- Must be loaded into TripleStore default graph

**External:**
- `:triple_store` dependency added to mix.exs
- TripleStore library must support named graphs (GRAPH clauses, INSERT with GRAPH)

---

## Implementation Order

### Phase 7.0: Foundation Layer
1. Create ProjectRegistry
2. Create TripleStoreManager supervisor
3. Create TripleStore.Project GenServer
4. Create MemoryStore module
5. Create SPARQLQueries module
6. Test foundation components

### Phase 7.1-7.2: P0 Tools Rewrite
1. Rewrite knowledge_remember handler
2. Rewrite knowledge_recall handler
3. Test P0 tools

### Phase 7.3-7.5: P1 Tools Rewrite
1. Rewrite knowledge_supersede handler
2. Rewrite project_conventions handler
3. Test P1 tools

### Phase 7.6-7.7: P2 Tools Rewrite
1. Rewrite knowledge_update handler
2. Rewrite project_decisions handler
3. Rewrite project_risks handler
4. Test P2 tools

### Phase 7.8-7.9: P3 Tools Rewrite
1. Rewrite knowledge_graph_query handler
2. Rewrite knowledge_context handler
3. Test P3 tools

### Phase 7.10-7.12: Integration & Cleanup
1. Integration tests
2. Update application supervision tree
3. Remove old ETS-based files
4. Full test suite verification
