# Phase 7: Knowledge Graph Tools

This phase implements LLM-facing tools for interacting with the Jido knowledge ontology. The tools expose the knowledge graph to the LLM through the Handler pattern, enabling semantic memory operations.

## Ontology Foundation

The canonical ontology is defined in TTL files:

| TTL File | Purpose |
|----------|---------|
| `lib/ontology/long-term-context/jido-core.ttl` | Base classes (MemoryItem, Entity), confidence levels, source types |
| `lib/ontology/long-term-context/jido-knowledge.ttl` | Knowledge types (Fact, Assumption, Hypothesis, Discovery, Risk, Unknown) |
| `lib/ontology/long-term-context/jido-convention.ttl` | Convention types (CodingStandard, ArchitecturalConvention, AgentRule, ProcessConvention) |
| `lib/ontology/long-term-context/jido-decision.ttl` | Decision types (ArchitecturalDecision, ImplementationDecision, Alternative, TradeOff) |

> **Note:** The `lib/jido_code/memory/long_term/vocab/jido.ex` module provides Elixir mappings to the TTL ontology for use in handlers.

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
│  Memory Module API                                               │
│  - Memory.persist/2, Memory.query/2, Memory.supersede/3         │
│  - TripleStoreAdapter for storage                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Result formatted as JSON for LLM                               │
│  - Memory IDs, types, confidence levels                         │
│  - Relationship information                                     │
└─────────────────────────────────────────────────────────────────┘
```

## Tools in This Phase

| Tool | Priority | Purpose | Status |
|------|----------|---------|--------|
| `knowledge_remember` | P0 | Store new knowledge with ontology typing | ✅ Complete + Improved |
| `knowledge_recall` | P0 | Query knowledge with semantic filters | ✅ Complete + Improved |
| `knowledge_supersede` | P1 | Replace outdated knowledge | ⬜ Initial |
| `knowledge_update` | P2 | Update confidence/evidence on existing | ⬜ Initial |
| `project_conventions` | P1 | Get all conventions and standards | ⬜ Initial |
| `project_decisions` | P2 | Get architectural decisions | ⬜ Initial |
| `project_risks` | P2 | Get known risks and issues | ⬜ Initial |
| `knowledge_graph_query` | P3 | Advanced relationship traversal | ⏸️ Deferred |
| `knowledge_context` | P3 | Auto-retrieve relevant context | ⏸️ Deferred |

> **Note:** P0-P2 tools (7 total) will be implemented initially. P3 tools are deferred for a later phase.

## Phase 7A Improvements (Review Findings) ✅

Based on code review findings, the following improvements were made to the P0 tools:

| Issue | Type | Resolution |
|-------|------|------------|
| Overly broad rescue clause in filter_by_types | Concern | Extracted safe_to_existing_atom/1 with narrow rescue scope |
| Missing session ID validation | Concern | Added get_session_id/2 with byte_size check |
| Potential nil crash in DateTime.to_iso8601 | Concern | Added format_timestamp/1 helper |
| Duplicated get_session_id/1 | Concern | Extracted to parent Knowledge module |
| Missing content size limits | Concern | Added @max_content_size (64KB) and validate_content/1 |
| Process.sleep in tests | Concern | Removed - operations are synchronous |
| Telemetry duplication | Suggestion | Added with_telemetry/3 wrapper |
| Type normalization duplication | Suggestion | Added safe_to_type_atom/1 to parent module |
| Variable rebinding in build_query_opts | Suggestion | Refactored to pipeline pattern |
| Missing telemetry tests | Suggestion | Added 3 telemetry emission tests |
| Missing edge case tests | Suggestion | Added 19 tests for edge cases and shared functions |

**Test Count:** 25 → 47 tests (22 new tests added)
**Summary Document:** `notes/summaries/2026-01-02-phase7a-improvements.md`
**Review Document:** `notes/reviews/phase-7a-knowledge-tools-review.md`

## Memory Types (from TTL Ontology)

The following memory types are defined in the ontology and can be used with `knowledge_remember`:

**Knowledge Types** (jido-knowledge.ttl):
- `fact` - Verified or strongly established knowledge
- `assumption` - Unverified belief held for working purposes
- `hypothesis` - Testable theory or explanation
- `discovery` - Newly uncovered important information
- `risk` - Potential future negative outcome
- `unknown` - Known unknown; explicitly acknowledged knowledge gap

**Convention Types** (jido-convention.ttl):
- `convention` - General project-wide or system-wide standard
- `coding_standard` - Convention related to coding style, formatting, or structure
- `architectural_convention` - Convention governing architectural patterns
- `agent_rule` - Rule governing agent behavior and authority
- `process_convention` - Convention governing workflow or operational processes

**Decision Types** (jido-decision.ttl):
- `decision` - General committed choice impacting the project
- `architectural_decision` - High-impact structural or architectural choice
- `implementation_decision` - Low-to-medium level implementation choice
- `alternative` - Considered option that was not selected
- `trade_off` - Compromise relationship between competing goals

---

## 7.1 knowledge_remember Tool (P0) ✅

Store new knowledge in the graph with full ontology support.

### 7.1.1 Tool Definition

- [x] Create `lib/jido_code/tools/definitions/knowledge.ex`
- [x] Define schema:
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
- [x] Register in `Knowledge.all/0`

### 7.1.2 Handler Implementation

- [x] Create `lib/jido_code/tools/handlers/knowledge.ex`
- [x] Add `KnowledgeRemember` handler module
- [x] Validate memory type against ontology types
- [x] Get session_id and project_id from context via HandlerHelpers
- [x] Apply default confidence based on type:
  - Facts: 0.8
  - Assumptions/Hypotheses: 0.5
  - Risks: 0.6
- [x] Build memory input with ontology mappings
- [x] Call `TripleStoreAdapter.persist/2`
- [x] Return JSON with memory_id, type, confidence
- [x] Emit telemetry `[:jido_code, :knowledge, :remember]`

### 7.1.3 Unit Tests

- [x] Test stores fact with high confidence
- [x] Test stores assumption with medium confidence
- [x] Test validates memory type enum
- [x] Test validates confidence bounds (0.0-1.0)
- [x] Test requires session context
- [x] Test handles evidence_refs
- [x] Test handles related_to linking
- [x] Test applies default confidence by type

---

## 7.2 knowledge_recall Tool (P0) ✅

Query the knowledge graph with semantic filters.

### 7.2.1 Tool Definition

- [x] Add `knowledge_recall/0` to definitions
- [x] Define schema:
  ```elixir
  %{
    name: "knowledge_recall",
    description: "Search for previously stored knowledge. Can filter by type, confidence, and scope.",
    parameters: [
      %{name: "query", type: :string, required: false,
        description: "Text search within memory content"},
      %{name: "types", type: :array, required: false,
        description: "Filter by memory types (e.g., ['fact', 'decision'])"},
      %{name: "min_confidence", type: :float, required: false,
        description: "Minimum confidence threshold (default: 0.5)"},
      %{name: "project_scope", type: :boolean, required: false,
        description: "If true, search across all sessions for this project (default: false)"},
      %{name: "include_superseded", type: :boolean, required: false,
        description: "Include superseded memories (default: false)"},
      %{name: "limit", type: :integer, required: false,
        description: "Maximum results to return (default: 10)"}
    ]
  }
  ```

### 7.2.2 Handler Implementation

- [x] Add `KnowledgeRecall` handler module
- [x] Support text search via `query` parameter (substring match in content)
- [x] Support type filtering via `types` array
- [x] Support confidence threshold filtering
- [ ] Support cross-session project queries via `project_scope` (deferred to 7B)
- [x] Support include_superseded option
- [x] Format results with id, content, type, confidence, created_at
- [ ] Record access via `TripleStoreAdapter.record_access/3` (deferred)
- [x] Emit telemetry `[:jido_code, :knowledge, :recall]`

### 7.2.3 Unit Tests

- [x] Test retrieves all memories for session
- [x] Test filters by single type
- [x] Test filters by multiple types
- [x] Test filters by confidence threshold
- [x] Test text search within content
- [x] Test respects limit
- [x] Test returns empty for no matches
- [x] Test excludes superseded by default
- [x] Test includes superseded when requested
- [ ] Test project_scope queries across sessions (deferred to 7B)

---

## 7.3 knowledge_supersede Tool (P1)

Mark knowledge as superseded and optionally create replacement.

### 7.3.1 Tool Definition

- [ ] Add `knowledge_supersede/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "knowledge_supersede",
    description: "Mark knowledge as outdated and optionally replace it with new knowledge.",
    parameters: [
      %{name: "old_memory_id", type: :string, required: true,
        description: "ID of the memory to supersede"},
      %{name: "new_content", type: :string, required: false,
        description: "Content for the replacement memory (creates new if provided)"},
      %{name: "new_type", type: :string, required: false,
        description: "Type for replacement (defaults to original type)"},
      %{name: "reason", type: :string, required: false,
        description: "Reason for superseding"}
    ]
  }
  ```

### 7.3.2 Handler Implementation

- [ ] Add `KnowledgeSupersede` handler module
- [ ] Validate old_memory_id exists
- [ ] Validate session ownership
- [ ] Call `TripleStoreAdapter.supersede/4`
- [ ] If new_content provided, create replacement memory
- [ ] Link new to old via supersededBy relationship
- [ ] Return old_id, new_id (if created), status
- [ ] Emit telemetry `[:jido_code, :knowledge, :supersede]`

### 7.3.3 Unit Tests

- [ ] Test marks memory as superseded
- [ ] Test creates replacement when content provided
- [ ] Test links replacement to original
- [ ] Test handles non-existent memory_id
- [ ] Test session ownership validation
- [ ] Test inherits type from original when not specified

---

## 7.4 knowledge_update Tool (P2)

Update confidence or add evidence to existing knowledge.

### 7.4.1 Tool Definition

- [ ] Add `knowledge_update/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "knowledge_update",
    description: "Update confidence level or add evidence to existing knowledge.",
    parameters: [
      %{name: "memory_id", type: :string, required: true,
        description: "ID of the memory to update"},
      %{name: "new_confidence", type: :float, required: false,
        description: "New confidence level (0.0-1.0)"},
      %{name: "add_evidence", type: :array, required: false,
        description: "Evidence references to add"},
      %{name: "add_rationale", type: :string, required: false,
        description: "Additional rationale to append"}
    ]
  }
  ```

### 7.4.2 Handler Implementation

- [ ] Add `KnowledgeUpdate` handler module
- [ ] Validate memory exists and owned by session
- [ ] Update confidence if provided (validate 0.0-1.0)
- [ ] Append evidence refs if provided
- [ ] Append rationale if provided
- [ ] Return updated memory summary
- [ ] Emit telemetry `[:jido_code, :knowledge, :update]`

### 7.4.3 Unit Tests

- [ ] Test updates confidence
- [ ] Test adds evidence refs
- [ ] Test appends rationale
- [ ] Test validates ownership
- [ ] Test validates confidence bounds
- [ ] Test handles non-existent memory

---

## 7.5 project_conventions Tool (P1)

Get all conventions and coding standards for the project.

### 7.5.1 Tool Definition

- [ ] Add `project_conventions/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "project_conventions",
    description: "Retrieve all conventions and coding standards for the project.",
    parameters: [
      %{name: "category", type: :string, required: false,
        description: "Filter by category: coding, architectural, agent, process"},
      %{name: "enforcement_level", type: :string, required: false,
        description: "Filter by enforcement: advisory, required, strict"}
    ]
  }
  ```

### 7.5.2 Handler Implementation

- [ ] Add `ProjectConventions` handler module
- [ ] Query for types: [:convention, :coding_standard, :architectural_convention, :agent_rule, :process_convention]
- [ ] Map category to specific types
- [ ] Use project_scope to get all project conventions
- [ ] Format as structured list with enforcement level
- [ ] Emit telemetry `[:jido_code, :knowledge, :project_conventions]`

### 7.5.3 Unit Tests

- [ ] Test retrieves all conventions
- [ ] Test retrieves coding standards specifically
- [ ] Test category filtering
- [ ] Test enforcement level filtering
- [ ] Test returns empty when none exist

---

## 7.6 project_decisions Tool (P2)

Get architectural decisions with rationale.

### 7.6.1 Tool Definition

- [ ] Add `project_decisions/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "project_decisions",
    description: "Retrieve architectural and implementation decisions for the project.",
    parameters: [
      %{name: "include_superseded", type: :boolean, required: false,
        description: "Include superseded decisions (default: false)"},
      %{name: "decision_type", type: :string, required: false,
        description: "Filter: architectural, implementation, or all (default: all)"},
      %{name: "include_alternatives", type: :boolean, required: false,
        description: "Include considered alternatives (default: false)"}
    ]
  }
  ```

### 7.6.2 Handler Implementation

- [ ] Add `ProjectDecisions` handler module
- [ ] Query for types: [:decision, :architectural_decision, :implementation_decision]
- [ ] Include/exclude superseded based on parameter
- [ ] Optionally include :alternative type memories linked to decisions
- [ ] Return with rationale field
- [ ] Emit telemetry `[:jido_code, :knowledge, :project_decisions]`

### 7.6.3 Unit Tests

- [ ] Test retrieves decisions
- [ ] Test excludes superseded by default
- [ ] Test includes superseded when requested
- [ ] Test filters by decision type
- [ ] Test includes alternatives when requested

---

## 7.7 project_risks Tool (P2)

Get known risks and issues.

### 7.7.1 Tool Definition

- [ ] Add `project_risks/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "project_risks",
    description: "Retrieve known risks and potential issues for the project.",
    parameters: [
      %{name: "min_confidence", type: :float, required: false,
        description: "Minimum confidence threshold (default: 0.5)"},
      %{name: "include_mitigated", type: :boolean, required: false,
        description: "Include mitigated/superseded risks (default: false)"}
    ]
  }
  ```

### 7.7.2 Handler Implementation

- [ ] Add `ProjectRisks` handler module
- [ ] Query for type: :risk
- [ ] Filter by confidence threshold
- [ ] Sort by confidence descending (highest risk first)
- [ ] Support include_mitigated for superseded risks
- [ ] Emit telemetry `[:jido_code, :knowledge, :project_risks]`

### 7.7.3 Unit Tests

- [ ] Test retrieves risks
- [ ] Test filters by confidence
- [ ] Test sorts by confidence descending
- [ ] Test excludes mitigated by default
- [ ] Test includes mitigated when requested

---

## 7.8 knowledge_graph_query Tool (P3) ⏸️ DEFERRED

> **Deferred**: Advanced relationship traversal will be implemented in a future phase.

### 7.8.1 Tool Definition (Deferred)

- Parameters: start_from, relationship, depth
- Relationship types from ontology:
  - `derivedFrom` - Evidence chain
  - `supersededBy` - Replacement chain
  - `refines` - Hypothesis refinement
  - `confirms` / `contradicts` - Evidence relationships
  - `hasAlternative` - Decision alternatives

---

## 7.9 knowledge_context Tool (P3) ⏸️ DEFERRED

> **Deferred**: Auto-relevance context will be implemented in a future phase.

### 7.9.1 Tool Definition (Deferred)

- Parameters: context_hint, include_types
- Auto-scoring based on current task context
- Retrieves most relevant memories without explicit query

---

## 7.10 Phase 7 Integration Tests

### 7.10.1 Handler Integration

- [ ] Create `test/jido_code/integration/tools_phase7_test.exs`
- [ ] Test all tools execute through Executor → Handler chain
- [ ] Test session isolation (default queries are session-scoped)
- [ ] Test telemetry events are emitted

### 7.10.2 Knowledge Lifecycle

- [ ] Test: remember → recall → verify content
- [ ] Test: remember → supersede → recall excludes old
- [ ] Test: remember → update confidence → recall with new confidence
- [ ] Test: remember fact → update with evidence → confidence preserved

### 7.10.3 Cross-Tool Integration

- [ ] Test project_conventions finds convention type memories
- [ ] Test project_decisions finds decision type memories
- [ ] Test project_risks finds risk type memories
- [ ] Test project_scope queries work across sessions

---

## 7.11 Phase 7 Success Criteria

| Criterion | Priority | Status |
|-----------|----------|--------|
| **knowledge_remember**: Store with ontology types | P0 | ⬜ |
| **knowledge_recall**: Query with filters + project_scope | P0 | ⬜ |
| **knowledge_supersede**: Replace outdated knowledge | P1 | ⬜ |
| **project_conventions**: List conventions/standards | P1 | ⬜ |
| **knowledge_update**: Modify confidence/evidence | P2 | ⬜ |
| **project_decisions**: List decisions with rationale | P2 | ⬜ |
| **project_risks**: List risks by confidence | P2 | ⬜ |
| **Cross-session queries**: project_scope=true works | P0 | ⬜ |
| **Session isolation**: Default queries session-scoped | P0 | ⬜ |
| **Test coverage**: Minimum 80% | - | ⬜ |
| **knowledge_graph_query**: Traverse relationships | P3 | ⏸️ Deferred |
| **knowledge_context**: Auto-relevance | P3 | ⏸️ Deferred |

---

## 7.12 Phase 7 Critical Files

**New Files:**
- `lib/jido_code/tools/definitions/knowledge.ex` - All knowledge tool definitions
- `lib/jido_code/tools/handlers/knowledge.ex` - All knowledge handlers
- `test/jido_code/tools/handlers/knowledge_test.exs` - Handler unit tests
- `test/jido_code/integration/tools_phase7_test.exs` - Integration tests

**Modified Files:**
- `lib/jido_code/tools/definitions.ex` - Register knowledge tools
- `lib/jido_code/memory/long_term/triple_store_adapter.ex` - Add project-scoped queries

**Reference Files (read-only):**
- `lib/ontology/long-term-context/jido-core.ttl` - Core ontology
- `lib/ontology/long-term-context/jido-knowledge.ttl` - Knowledge types
- `lib/ontology/long-term-context/jido-convention.ttl` - Convention types
- `lib/ontology/long-term-context/jido-decision.ttl` - Decision types
- `lib/jido_code/memory/long_term/vocab/jido.ex` - Elixir vocab mappings
- `lib/jido_code/memory/long_term/triple_store_adapter.ex` - Storage API
- `lib/jido_code/memory/types.ex` - Type definitions

---

## Design Decisions

1. **Cross-Session Project Scope**: YES - Memories can be queried across sessions if they belong to the same project. This requires:
   - `project_id` to be tracked when memories are created
   - Query functions to support project-level filtering
   - TripleStoreAdapter to support cross-session queries

2. **Tool Naming**: Use `knowledge_*` prefix for core tools, `project_*` for specialized query tools

3. **Initial Scope**: All P0-P2 tools (7 tools total)
   - `knowledge_remember`, `knowledge_recall` (P0)
   - `knowledge_supersede`, `project_conventions` (P1)
   - `knowledge_update`, `project_decisions`, `project_risks` (P2)
   - P3 tools (`knowledge_graph_query`, `knowledge_context`) deferred

4. **Ontology Source**: TTL files in `lib/ontology/long-term-context/` are the canonical source; `vocab/jido.ex` provides Elixir mappings

---

## Implementation Order

### Phase 7A: Core Infrastructure + P0 Tools
1. Create `lib/jido_code/tools/definitions/knowledge.ex`
2. Create `lib/jido_code/tools/handlers/knowledge.ex`
3. Implement `knowledge_remember` with project_id support
4. Implement `knowledge_recall` with project_scope parameter
5. Unit tests for both handlers
6. Basic integration tests

### Phase 7B: Lifecycle + Project Tools (P1)
1. Add `knowledge_supersede` handler
2. Add `project_conventions` handler
3. Tests for new handlers

### Phase 7C: Extended Tools (P2)
1. Add `knowledge_update` handler
2. Add `project_decisions` handler
3. Add `project_risks` handler
4. Full integration tests
5. Update planning document

### Phase 7D: Advanced Tools (P3 - Deferred)
1. Add `knowledge_graph_query` - relationship traversal
2. Add `knowledge_context` - auto-relevance
3. Advanced integration tests

---

## Cross-Session Project Queries

To support `project_scope: true`:

1. **Memory Creation**: Ensure `project_id` is captured when memories are created
   - Handler should extract project_id from context or allow explicit parameter
   - Default to current session's project

2. **Query Modification**: Add project-level query to TripleStoreAdapter
   ```elixir
   # New function needed
   def query_by_project(store, project_id, opts \\ [])
   ```

3. **Handler Logic**:
   ```elixir
   if project_scope do
     TripleStoreAdapter.query_by_project(store, project_id, opts)
   else
     TripleStoreAdapter.query_all(store, session_id, opts)
   end
   ```
