# Memory Graph

This subject defines the repository-scoped memory-graph architecture that
complements the existing `source_code` graph with durable coding memory and
workflow provenance.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.memory_graph
kind: feature
status: proposed
summary: Jido.Code provides an optional repository-scoped MemoryGraphPod inside each managed-repository AgentOS kernel, reuses the repository-local TripleStore quad store that already hosts `source_code`, adds canonical `memory` and `workflow_provenance` named graphs, links those graphs to stable repository-scoped code IRIs, now includes the first concrete runtime foundation with a MemoryGraph boundary plus eager context and lazy recorder, querier, and validator specialist contracts, adds typed workflow-provenance capture envelopes and canonical writer boundaries for workflow provenance, durable memory insertion, and durable memory update operations, exposes explicit record/query/validate/invalidate/refresh actions rather than raw store access, preserves revision, freshness, stale, invalidated, latest-failure, cross-graph consistency, and durable-memory validation state through bounded AgentWorkspace entrypoints plus product-shaped feedback and repository-scoped recovery, now establishes bounded product-facing memory-service and memory-view adoption over those workspace entrypoints, prepares governed workflow surfaces and operator memory actions to consume the same bounded memory stack, and keeps memory-graph findings as semantic support that must rejoin governed product records before they affect factory truth.
decisions:
  - jido_code.jido_agent_os_integration
  - jido_code.source_code_graph_pod_and_named_graph_ingestion
  - jido_code.memory_capture_plane_and_insertion_seams
  - jido_code.memory_graph_and_coding_memory_ontology_adoption
  - jido_code.memory_graph_product_adoption
  - jido_code.memory_graph_workflow_and_operator_expansion
surface:
  - .spec/decisions/jido_code.memory_capture_plane_and_insertion_seams.md
  - .spec/decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md
  - .spec/decisions/jido_code.memory_graph_product_adoption.md
  - .spec/decisions/jido_code.memory_graph_workflow_and_operator_expansion.md
  - .spec/specs/agent_os_integration.spec.md
  - .spec/specs/memory_capture_plane.spec.md
  - .spec/specs/memory_graph_product_adoption.spec.md
  - .spec/specs/memory_graph_workflow_and_operator_expansion.spec.md
  - .spec/specs/source_code_graph_pod.spec.md
  - .spec/specs/memory_ontology.spec.md
  - lib/jido_code/agent_workspace.ex
  - lib/jido_code/memory_graph.ex
  - lib/jido_code/memory_graph/
  - lib/jido_code/memory_graph/capture_envelope.ex
  - lib/jido_code/memory_graph/capture_writer.ex
  - lib/jido_code/memory_graph/durable_memory_envelope.ex
  - lib/jido_code/memory_graph/durable_memory_writer.ex
  - lib/jido_code/memory_graph/durable_memory_update_envelope.ex
  - lib/jido_code/memory_graph/durable_memory_update_writer.ex
  - lib/jido_code/memory_graph/product_feedback.ex
  - lib/jido_code/source_code_graph.ex
  - lib/jido_code/pods/
  - lib/jido_code/actions/
  - lib/jido_code/agents/
  - test/jido_code/agent_os/
  - test/jido_code/memory_graph_test.exs
  - test/jido_code/memory_graph_actions_test.exs
  - test/jido_code/memory_graph_workspace_test.exs
  - test/jido_code/agent_os/phase_twenty_eight_integration_test.exs
  - test/jido_code/phase_thirty_one_integration_test.exs
```

## Requirements

```spec-requirements
- id: architecture.memory_graph.repo_scoped_memory_graph_pod
  statement: When coding-memory capability is enabled for a managed repository, Jido.Code shall provide one repository-scoped MemoryGraphPod inside that repository's AgentOS kernel rather than a cross-repository memory singleton.
  priority: must
  stability: proposed

- id: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  statement: The memory graph and workflow provenance graph shall live in the same repository-local TripleStore quad store that hosts the `source_code` graph so code, memory, and provenance links remain local, durable, and queryable together.
  priority: must
  stability: proposed

- id: architecture.memory_graph.memory_named_graph_is_canonical_target
  statement: The canonical named graph for repository coding memories shall be exactly `memory`.
  priority: must
  stability: proposed

- id: architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
  statement: The canonical named graph for repository workflow, agent, and evidence provenance shall be exactly `workflow_provenance`.
  priority: must
  stability: proposed

- id: architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
  statement: Memories and workflow provenance shall link to repository, file, module, function, test, config, and symbol entities in the `source_code` graph through stable repository-scoped IRIs rather than string-only labels.
  priority: must
  stability: proposed

- id: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  statement: Recording memories, querying memories, validating freshness, invalidating stale facts, and refreshing memory-graph state shall route through explicit Jido.Action tools rather than ambient helper calls or direct TripleStore access from callers.
  priority: must
  stability: proposed

- id: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  statement: Repository-scoped memory-graph status shall surface current workspace revision, latest validated revision, stale or invalidated state, bounded failure metadata, validation freshness, and repository-scoped recovery guidance so callers can reason safely about whether a memory still applies.
  priority: must
  stability: proposed

- id: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  statement: Product code, workflow services, and operator surfaces shall consume memory-graph capability through bounded product-owned services or AgentWorkspace entrypoints rather than by issuing raw SPARQL or reading pod/store internals.
  priority: must
  stability: proposed

- id: architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  statement: Memory and workflow provenance records shall preserve explicit links among work sessions, agent activity, tool use, code entities, revisions, and evidence artifacts so coding memories remain explainable over time.
  priority: should
  stability: proposed

- id: architecture.memory_graph.cross_graph_consistency_and_isolation_are_explainable
  statement: Memory-graph status shall expose bounded cross-graph consistency and repository isolation context for `source_code` and `workflow_provenance` so callers can distinguish aligned, stale-dependency, and unavailable-dependency states safely.
  priority: should
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.memory_graph.scenario_repo_scoped_memory_graph_joins_source_code_graph
  covers:
    - architecture.memory_graph.repo_scoped_memory_graph_pod
    - architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
    - architecture.memory_graph.memory_named_graph_is_canonical_target
    - architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
  given:
    - A managed repository has source-code graph capability and coding-memory capability enabled.
  when:
    - The repository kernel prepares semantic graph services.
  then:
    - One repository-scoped MemoryGraphPod is available alongside the SourceCodeGraphPod.
    - The repository-local quad store hosts the `source_code`, `memory`, and `workflow_provenance` named graphs together.

- id: architecture.memory_graph.scenario_memory_entry_links_to_code_entities_and_revision_context
  covers:
    - architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
    - architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  given:
    - A work session discovers an invariant, decision, or known issue about a repository module or function.
  when:
    - The memory entry is recorded.
  then:
    - The memory links to stable repository-scoped code IRIs.
    - The entry also links to session, revision, and evidence provenance rather than storing only free-form text.

- id: architecture.memory_graph.scenario_memory_recording_and_query_are_explicit_actions
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  given:
    - A workflow or operator wants to record or query coding memory.
  when:
    - The caller asks for memory recording or semantic recall.
  then:
    - The operation routes through explicit actions and bounded workspace or product entrypoints.
    - The caller does not open raw TripleStore or pod internals directly.

- id: architecture.memory_graph.scenario_stale_memory_is_visible_and_can_be_invalidated
  covers:
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  given:
    - A previously validated memory was recorded against an older repository revision.
  when:
    - The repository changes or validation later fails.
  then:
    - The memory graph exposes explicit stale or invalidated state.
    - Callers can invalidate or refresh that memory through bounded explicit actions.

- id: architecture.memory_graph.scenario_cross_graph_consistency_and_repo_isolation_remain_explainable
  covers:
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.cross_graph_consistency_and_isolation_are_explainable
    - architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  given:
    - Multiple repositories use the semantic stack, and one repository memory graph depends on linked `source_code` and `workflow_provenance` state.
  when:
    - Status, recovery, or query behavior runs under stale dependency, restart, or multi-repository conditions.
  then:
    - The memory graph exposes bounded cross-graph consistency and recovery context instead of hiding dependency state.
    - Memory and workflow provenance links remain coherent after repository-scoped recovery.
    - Repository-local memory state remains isolated from other repositories.

- id: architecture.memory_graph.scenario_memory_findings_support_but_do_not_replace_control_plane_truth
  covers:
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
    - architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  given:
    - A memory-graph finding suggests follow-up work or review evidence.
  when:
    - The factory decides to act on that finding.
  then:
    - The finding re-enters governed product records through bounded product services.
    - The memory graph remains a semantic support layer rather than the durable business system of record.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md
  covers:
    - architecture.memory_graph.repo_scoped_memory_graph_pod
    - architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
    - architecture.memory_graph.memory_named_graph_is_canonical_target
    - architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
    - architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
    - architecture.memory_graph.memory_graph_supports_cross_graph_provenance

- kind: source_file
  target: .spec/decisions/jido_code.memory_graph_product_adoption.md
  covers:
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit

- kind: source_file
  target: lib/jido_code/memory_graph.ex
  covers:
    - architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
    - architecture.memory_graph.memory_named_graph_is_canonical_target
    - architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit

- kind: source_file
  target: lib/jido_code/memory_graph/store.ex
  covers:
    - architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
    - architecture.memory_graph.memory_named_graph_is_canonical_target
    - architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target

- kind: source_file
  target: lib/jido_code/memory_graph/query.ex
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints

- kind: source_file
  target: lib/jido_code/actions/get_memory_graph_status.ex
  covers:
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation

- kind: source_file
  target: lib/jido_code/actions/refresh_memory_graph.ex
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs

- kind: source_file
  target: lib/jido_code/actions/validate_memory_graph.ex
  covers:
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation

- kind: source_file
  target: lib/jido_code/actions/query_memory_graph.ex
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit

- kind: source_file
  target: lib/jido_code/actions/invalidate_memory_graph.ex
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit

- kind: source_file
  target: lib/jido_code/actions/record_memory_graph.ex
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints

- kind: source_file
  target: lib/jido_code/memory_graph/durable_memory_writer.ex
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_supports_cross_graph_provenance
    - architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri

- kind: source_file
  target: lib/jido_code/memory_graph/durable_memory_update_envelope.ex
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit

- kind: source_file
  target: lib/jido_code/memory_graph/durable_memory_update_writer.ex
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.memory_graph_supports_cross_graph_provenance

- kind: source_file
  target: lib/jido_code/memory_graph/product_feedback.ex
  covers:
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
    - architecture.memory_graph.cross_graph_consistency_and_isolation_are_explainable

- kind: source_file
  target: lib/jido_code/pods/memory_graph_pod.ex
  covers:
    - architecture.memory_graph.repo_scoped_memory_graph_pod

- kind: source_file
  target: lib/jido_code/agent_workspace.ex
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints

- kind: source_file
  target: test/jido_code/memory_graph_test.exs
  covers:
    - architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
    - architecture.memory_graph.memory_named_graph_is_canonical_target
    - architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit

- kind: source_file
  target: test/jido_code/memory_graph_actions_test.exs
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit

- kind: source_file
  target: test/jido_code/memory_graph_workspace_test.exs
  covers:
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints

- kind: source_file
  target: test/jido_code/agent_os/phase_twenty_eight_integration_test.exs
  covers:
    - architecture.memory_graph.repo_scoped_memory_graph_pod
    - architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs

- kind: source_file
  target: test/jido_code/phase_thirty_one_integration_test.exs
  covers:
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.memory_graph_supports_cross_graph_provenance
    - architecture.memory_graph.cross_graph_consistency_and_isolation_are_explainable
    - architecture.memory_graph.memory_named_graph_is_canonical_target
    - architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
    - architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
    - architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
    - architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints

- kind: source_file
  target: test/jido_code/phase_thirty_integration_test.exs
  covers:
    - architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
    - architecture.memory_graph.memory_graph_supports_cross_graph_provenance
    - architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
```
