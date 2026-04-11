---
id: jido_code.memory_capture_plane_and_insertion_seams
status: accepted
date: 2026-04-10
affects:
  - package.jido_code
  - architecture.agent_os_integration
  - architecture.memory_graph
  - architecture.memory_ontology
  - architecture.memory_capture_plane
  - architecture.factory_control_plane
  - architecture.source_code_graph_product_adoption
related:
  - jido_code.jido_agent_os_integration
  - jido_code.source_code_graph_product_adoption
  - jido_code.memory_graph_and_coding_memory_ontology_adoption
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->
<!-- covers: architecture.agent_os_integration.memory_graph_capture_stays_workspace_bound -->
<!-- covers: architecture.agent_os_integration.durable_memory_adoption_stays_workspace_or_product_bound -->
<!-- covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary -->
<!-- covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries -->
<!-- covers: architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption -->
<!-- covers: architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence -->
<!-- covers: architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context -->
<!-- covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples -->
<!-- covers: architecture.memory_capture_plane.typed_governed_reference_contract_is_canonical -->
<!-- covers: architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs -->
<!-- covers: architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption -->

# Memory Capture Plane And Insertion Seams

## Context

The new coding-memory ontology and repository-scoped memory graph define what we
want to remember, but they do not yet answer how those individuals are created
over time or which product/runtime boundaries are allowed to insert them.

That distinction matters. If pods, specialists, UI surfaces, or ad hoc helpers
can all write triples directly, the memory graph will quickly become a second
unbounded truth lane full of partial prompts, transient model output, and
contextless facts. The semantic memory layer needs a bounded write seam just as
much as it needs a bounded query seam.

The repository already has the right architectural ingredients to define such a
seam:

- `AgentWorkspace` is the product-owned runtime facade where repository, work
  item, actor, and workspace context are explicit
- source-code-graph workflow services already classify bounded semantic context
  before it re-enters product behavior
- governed adoption and materialization boundaries already control when semantic
  findings become Ash-backed product records

The missing step is to define where memory/provenance individuals are inserted
and to forbid all other insertion paths.

## Decision

`Jido.Code` shall add a bounded memory capture plane as the canonical write
boundary for the memory graph.

The capture plane sits between runtime/workflow activity and semantic memory
storage. It accepts typed capture envelopes rather than raw triples and decides
which named graph receives which individual or relationship.

The insertion seams are:

- `AgentWorkspace` and its bounded workflow/runtime boundaries insert
  `WorkSession`, `AgentRun`, `ToolInvocation`, `PromptTurn`, `Plan`, `Patch`,
  and `Review` provenance into the `workflow_provenance` graph when repository,
  work-item, actor, workspace, and revision context are explicit
- product-owned workflow services and governed adoption boundaries insert
  durable memory classes such as `Fact`, `Decision`, `LessonLearned`,
  `Invariant`, `Convention`, `KnownIssue`, `OpenQuestion`, `Pattern`, and
  `AntiPattern` into the `memory` graph only after explicit classification or
  adoption
- validation, freshness, and invalidation updates are inserted when revision
  movement, test validation, explicit review, or recovery logic produces
  evidence about whether a memory still applies

The capture plane explicitly does not persist every transient model output. Raw
LLM text, intermediate chain-of-thought-like artifacts, and unadopted helper
results do not become durable memory simply because they existed during a run.

The canonical shape is therefore:

- runtime/workflow boundaries emit typed capture envelopes
- the capture plane turns those envelopes into ontology-aligned individuals and
  relationships
- the `workflow_provenance` graph stores activity/provenance individuals
- the `memory` graph stores durable coding memories
- cross-graph links bind both back to stable `source_code` IRIs and, when
  relevant, to governed product records through one typed governed-reference
  contract instead of generic artifact naming

The first concrete implementation slice of this plane should therefore land as:

- typed envelope normalization modules that validate provenance capture context
  before any write occurs
- a canonical writer boundary that owns TripleStore interaction for
  `workflow_provenance`
- bounded action and workspace entrypoints that can accept workflow-provenance
  envelopes now while durable `memory`-graph adoption remains a later phase

The next implementation slice extends the same plane to durable coding memory:

- typed durable-memory envelopes that require explicit classification or
  governed adoption metadata before insertion
- a canonical durable-memory writer that owns `memory`-graph insertion and
  cross-graph linkage to `source_code`, `workflow_provenance`, and governed
  product artifacts
- bounded product and governed adoption helpers that can intentionally record
  `Fact`, `Decision`, `LessonLearned`, `Invariant`, `Convention`,
  `KnownIssue`, `OpenQuestion`, `Pattern`, and `AntiPattern` without exposing
  raw triple authoring to callers

The following slice extends the same write seam again for explainable memory
evolution over time:

- repository-scoped memory status should expose stale, invalidated, failure, and
  cross-graph consistency state through product-shaped feedback rather than raw
  store diagnostics
- recovery actions stay product-owned and repository-scoped, with callers using
  bounded workspace recovery entrypoints instead of reaching into TripleStore
  or pod internals directly
- contributor verification should include repo-owned `mix memory.verify` so the
  capture plane, ontology, and durable-memory behavior stay discoverable in the
  normal workflow

- typed durable-memory update envelopes for validation, invalidation, and
  decision supersession
- a canonical durable-memory update writer that preserves freshness,
  validation, invalidation, test-run, revision, and evidence relationships in
  the `memory` graph without introducing a second update pathway
- stale-safe update routing so revision movement can invalidate or revalidate
  durable memories through the same bounded capture plane instead of bypassing
  it

## Consequences

- The memory graph gains a safe write path instead of becoming an open semantic
  sink.
- Workflow provenance is captured where runtime context is strongest, while
  durable memory is inserted where product/governed meaning is strongest.
- The repo now has an explicit answer to "where should this individual be
  created?" instead of leaving that choice implicit in each caller.
- Durable coding memory can now be inserted through explicit workflow or
  governed adoption while still preserving a later freshness and invalidation
  phase for revision and test evidence.
- Durable coding memory can now evolve over time through explicit validation,
  invalidation, and supersession updates that remain queryable and bounded.
- Memory freshness and invalidation become part of the write boundary itself,
  not a later cleanup concern.
- The control plane remains canonical because semantic memory is created through
  bounded product/runtime seams and still has to rejoin governed records when it
  materially affects factory behavior.
