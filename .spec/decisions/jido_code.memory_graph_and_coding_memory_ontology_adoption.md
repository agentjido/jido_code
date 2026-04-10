---
id: jido_code.memory_graph_and_coding_memory_ontology_adoption
status: accepted
date: 2026-04-10
affects:
  - package.jido_code
  - architecture.agent_os_integration
  - architecture.source_code_graph_pod
  - architecture.memory_graph
  - architecture.memory_ontology
  - architecture.factory_control_plane
related:
  - jido_code.jido_agent_os_integration
  - jido_code.source_code_graph_pod_and_named_graph_ingestion
  - jido_code.source_code_graph_product_adoption
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->
<!-- covers: architecture.agent_os_integration.memory_graph_pod_singleton_when_enabled -->
<!-- covers: architecture.agent_os_integration.memory_graph_read_write_and_query_stay_workspace_bound -->
<!-- covers: architecture.source_code_graph_pod.code_entities_use_stable_iris_for_cross_graph_links -->
<!-- covers: architecture.memory_graph.repo_scoped_memory_graph_pod -->
<!-- covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs -->
<!-- covers: architecture.memory_graph.memory_named_graph_is_canonical_target -->
<!-- covers: architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target -->
<!-- covers: architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri -->
<!-- covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation -->
<!-- covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit -->
<!-- covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints -->
<!-- covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance -->
<!-- covers: architecture.memory_ontology.coding_memory_types_extend_core_memory_model -->
<!-- covers: architecture.memory_ontology.memories_anchor_to_code_entities_and_symbols -->
<!-- covers: architecture.memory_ontology.change_and_revision_provenance_is_explicit -->
<!-- covers: architecture.memory_ontology.decision_structure_supports_supersession_and_consequence -->
<!-- covers: architecture.memory_ontology.workflow_and_llm_provenance_entities_are_modeled -->
<!-- covers: architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit -->
<!-- covers: architecture.memory_ontology.work_sessions_capture_repo_and_runtime_context -->
<!-- covers: architecture.memory_ontology.rdf_type_and_first_class_tags_replace_stringly_type_fields -->
<!-- covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane -->

# Memory Graph And Coding Memory Ontology Adoption

## Context

`Jido.Code` already carries a repository-scoped `source_code` named graph backed
by `elixir-ontologies`, `triple_store`, and bounded SPARQL query entrypoints.
That graph is strong at representing code structure, runtime patterns, and
bounded impact relationships for one repository snapshot.

What it does not yet provide is durable semantic memory about how the factory
has worked in that repository over time. A coding LLM and the surrounding
specialist workflow benefit from more than a static code graph. They also need a
bounded semantic layer for:

- facts, conventions, invariants, known issues, patterns, and anti-patterns
- decisions and their rationale, alternatives, consequences, and supersession
- lessons learned and open questions discovered during work
- provenance about sessions, prompts, tool invocations, reviews, patches, and
  plans
- freshness and validation metadata tied to repo revisions, tests, and evidence

The previous discussion also established that this memory layer should not be a
free-form note store. It should be a semantic graph that links directly to code
entities, revisions, workflow activity, and governed product records while
remaining bounded behind product-owned and workspace-owned entrypoints.

## Decision

`Jido.Code` shall add a repository-scoped memory-graph architecture that
complements the existing source-code graph instead of replacing it.

The semantic stack is now:

- the `source_code` named graph models repository code structure and runtime
  semantics
- the `memory` named graph models durable coding memories such as facts,
  decisions, lessons, conventions, issues, patterns, and open questions
- the `workflow_provenance` named graph models sessions, revisions, agent runs,
  tool invocations, prompt turns, reviews, patches, plans, and related evidence
- all three graphs live in the repository-local `TripleStore` quad store and
  link through stable repository-scoped IRIs

The runtime boundary is:

- one optional repository-scoped `MemoryGraphPod` per managed repository kernel
- explicit actions for recording, querying, validating, invalidating, and
  refreshing memory-graph state
- bounded `AgentWorkspace` entrypoints over those actions for product and
  workflow callers

The ontology boundary is:

- the earlier Jido memory model expands from `Fact`, `Decision`, and
  `LessonLearned` into a coding-memory ontology that also includes `Invariant`,
  `Convention`, `KnownIssue`, `OpenQuestion`, `Pattern`, and `AntiPattern`
- memories link explicitly to repository, file, module, function, test,
  configuration, and symbol entities from the `source_code` graph
- workflow provenance entities such as `WorkSession`, `AgentRun`,
  `ToolInvocation`, `PromptTurn`, `Review`, `Patch`, and `Plan` remain explicit
  first-class nodes rather than flattened metadata blobs
- revision, freshness, validation, and evidence relationships remain explicit so
  the memory graph can say not only "what we learned" but also "where it came
  from", "what it applies to", and "whether it is still fresh"

This memory graph is a semantic support capability, not a competing control
plane. If memory-graph findings materially affect factory behavior, they must
rejoin governed product records rather than becoming an alternate durable truth
system.

## Consequences

- `Jido.Code` gains a semantic memory layer that can help coding specialists and
  operators reason across sessions and revisions instead of rediscovering the
  same facts repeatedly.
- The existing `source_code` graph becomes more valuable because code entities
  now serve as stable anchors for memory and workflow provenance.
- The local repository semantic store now has a clearer multi-graph shape, which
  improves expressiveness but increases the need for stable IRIs, freshness
  metadata, and explicit invalidation semantics.
- The ontology itself becomes more useful to coding workflows because it can
  represent conventions, invariants, known issues, evidence, and workflow
  provenance directly rather than as unstructured tags or prompt text.
- Product and runtime callers still must not talk to the triple store directly;
  they consume bounded services and workspace entrypoints that can explain stale
  state, freshness, and degraded behavior safely.
- Governed product truth remains in Ash-backed product records even when memory
  and provenance graphs inform planning, review, explanation, or follow-up work.

## Implementation Note

Phase 28.1 now establishes the first concrete runtime and store foundation for
this decision inside `jido_code`:

- `JidoCode.MemoryGraph` defines the canonical repository-scoped graph names,
  named-graph IRIs, ontology asset path, shared semantic-store path, and stable
  base IRIs used by the memory graph capability
- `MemoryGraphPod` now exists as a repository-scoped sibling to
  `SourceCodeGraphPod`
- the pod now includes one eager `MemoryGraphContext` agent and three lazy
  specialist contracts for recording, querying, and validating repository memory
  state
- the shared semantic-store shape now explicitly reserves `memory` and
  `workflow_provenance` beside `source_code`, while cross-graph code anchors
  continue to rely on stable repository-scoped source-code IRIs
