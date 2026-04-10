# Memory Capture Plane

This subject defines the bounded write seam that inserts workflow provenance and
durable coding memories into the repository semantic store over time.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.memory_capture_plane
kind: feature
status: proposed
summary: Jido.Code inserts memory-graph individuals through a bounded memory capture plane that accepts typed capture envelopes instead of raw triples, records workflow provenance at AgentWorkspace and workflow-boundary transitions into `workflow_provenance`, records durable classified memories into `memory` only through explicit product or governed adoption paths, now includes typed workflow-provenance envelope normalization plus canonical writer boundaries for both workflow provenance and durable memory, adds typed durable-memory update envelopes plus a canonical update writer for validation, invalidation, and supersession, keeps explicit record/query/validate/invalidate/refresh and repository-scoped recovery workspace entrypoints so callers stop assuming direct store writes, updates freshness and invalidation metadata when revision or test evidence changes, requires explicit repository, work-item, workspace, actor, and revision context for any durable insertion, and now supports product-owned memory inspection and adoption surfaces that still emit typed capture requests instead of bypassing the canonical write seam.
decisions:
  - jido_code.memory_graph_and_coding_memory_ontology_adoption
  - jido_code.memory_capture_plane_and_insertion_seams
  - jido_code.source_code_graph_product_adoption
  - jido_code.memory_graph_product_adoption
surface:
  - .spec/decisions/jido_code.memory_capture_plane_and_insertion_seams.md
  - .spec/specs/memory_graph.spec.md
  - .spec/specs/memory_ontology.spec.md
  - .spec/specs/memory_graph_product_adoption.spec.md
  - .spec/specs/agent_os_integration.spec.md
  - .spec/specs/source_code_graph_product_adoption.spec.md
  - lib/jido_code/agent_workspace.ex
  - lib/jido_code/memory_graph/capture_envelope.ex
  - lib/jido_code/memory_graph/capture_writer.ex
  - lib/jido_code/memory_graph/durable_memory_envelope.ex
  - lib/jido_code/memory_graph/durable_memory_writer.ex
  - lib/jido_code/memory_graph/durable_memory_update_envelope.ex
  - lib/jido_code/memory_graph/durable_memory_update_writer.ex
  - lib/jido_code/actions/record_memory_graph.ex
  - lib/jido_code/source_code_graph/workflow_service.ex
  - lib/jido_code/source_code_graph/governed_adoption.ex
  - lib/jido_code/source_code_graph/memory_capture.ex
  - lib/jido_code/source_code_graph/materialization.ex
  - priv/ontologies/jido-memory.ttl
  - test/jido_code/memory_graph_actions_test.exs
  - test/jido_code/memory_graph_workspace_test.exs
```

## Requirements

```spec-requirements
- id: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
  statement: Jido.Code shall insert memory-graph individuals and relationships through one bounded memory capture plane rather than allowing direct graph writes from UI surfaces, specialist agents, or ad hoc helpers.
  priority: must
  stability: proposed

- id: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  statement: Workflow provenance individuals such as WorkSession, AgentRun, ToolInvocation, PromptTurn, Plan, Patch, and Review shall be inserted at AgentWorkspace and explicit workflow-boundary transitions where repository, work-item, actor, workspace, and revision context are already explicit.
  priority: must
  stability: proposed

- id: architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
  statement: Durable memory classes such as Fact, Decision, LessonLearned, Invariant, Convention, KnownIssue, OpenQuestion, Pattern, and AntiPattern shall be inserted only after explicit classification or adoption through product-owned workflow, semantic, or governed-adoption boundaries rather than from raw intermediate runtime output.
  priority: must
  stability: proposed

- id: architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
  statement: Freshness, validation, and invalidation relationships shall be inserted or updated when revision movement, test validation, explicit review, or recovery behavior produces bounded evidence that a memory still applies or no longer applies.
  priority: must
  stability: proposed

- id: architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
  statement: Durable memory capture shall require explicit repository identity, actor identity, and revision context, and shall include work-item or workflow context whenever the memory originated from bounded work execution.
  priority: must
  stability: proposed

- id: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  statement: Product and runtime callers shall emit typed capture envelopes or bounded capture requests rather than authoring raw RDF triples directly.
  priority: should
  stability: proposed

- id: architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  statement: Workflow provenance activity shall be written to the `workflow_provenance` named graph, while durable coding memories shall be written to the `memory` named graph, with explicit cross-graph links instead of flattening both concerns into one graph.
  priority: must
  stability: proposed

- id: architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption
  statement: Transient model text, intermediate reasoning artifacts, or unadopted helper output shall not be inserted as durable memory unless a bounded product or governed boundary explicitly classifies and adopts them.
  priority: must
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.memory_capture_plane.scenario_agent_workspace_starts_work_session_provenance
  covers:
    - architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
    - architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
    - architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
    - architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  given:
    - A repository-scoped workflow begins through AgentWorkspace with explicit managed-repo, actor, workspace, and revision context.
  when:
    - Planning, execution, review, explanation, or semantic workflow preparation starts.
  then:
    - The memory capture plane records a WorkSession and relevant AgentRun provenance in `workflow_provenance`.
    - The caller does not write raw triples directly.

- id: architecture.memory_capture_plane.scenario_tool_and_patch_activity_remain_workflow_provenance
  covers:
    - architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
    - architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
    - architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  given:
    - A specialist run performs tool calls or produces a plan, patch, or review artifact.
  when:
    - The system records that workflow activity.
  then:
    - The activity is inserted as workflow provenance in `workflow_provenance`.
    - It does not become a durable memory class merely because it happened.

- id: architecture.memory_capture_plane.scenario_classified_semantic_finding_becomes_memory
  covers:
    - architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
    - architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
    - architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
    - architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption
  given:
    - A bounded workflow or semantic product service identifies a reusable convention, decision, known issue, lesson, or pattern.
  when:
    - The result is explicitly classified or adopted as durable memory.
  then:
    - The capture plane inserts the corresponding memory individual into `memory`.
    - The inserted memory links to source-code entities, provenance, and governed context when available.
    - Unadopted raw intermediate output is not inserted.

- id: architecture.memory_capture_plane.scenario_revision_or_test_evidence_updates_memory_freshness
  covers:
    - architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
    - architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  given:
    - A repository already contains one or more durable memories tied to prior revisions.
  when:
    - A later test run validates the memory or a later revision invalidates it.
  then:
    - The capture plane updates freshness, validation, or invalidation metadata explicitly.
    - The memory remains durable, but its applicability becomes queryable and explainable.

- id: architecture.memory_capture_plane.scenario_operator_authored_memory_uses_same_capture_boundary
  covers:
    - architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
    - architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
    - architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  given:
    - An operator wants to record a bounded convention, invariant, or open question for a repository.
  when:
    - The product accepts that input.
  then:
    - The product emits a typed capture request through the same memory capture plane.
    - The operator path does not bypass the canonical memory insertion seam.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.memory_capture_plane_and_insertion_seams.md
  covers:
    - architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
    - architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
    - architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
    - architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
    - architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
    - architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
    - architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
    - architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption

- kind: source_file
  target: .spec/decisions/jido_code.memory_graph_product_adoption.md
  covers:
    - architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
    - architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
    - architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples

- kind: source_file
  target: lib/jido_code/agent_workspace.ex
  covers:
    - architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
    - architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
    - architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples

- kind: source_file
  target: lib/jido_code/memory_graph/capture_envelope.ex
  covers:
    - architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
    - architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context

- kind: source_file
  target: lib/jido_code/memory_graph/capture_writer.ex
  covers:
    - architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
    - architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
    - architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs

- kind: source_file
  target: lib/jido_code/memory_graph/durable_memory_envelope.ex
  covers:
    - architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
    - architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
    - architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption

- kind: source_file
  target: lib/jido_code/memory_graph/durable_memory_writer.ex
  covers:
    - architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
    - architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs

- kind: source_file
  target: lib/jido_code/memory_graph/durable_memory_update_envelope.ex
  covers:
    - architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
    - architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
    - architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples

- kind: source_file
  target: lib/jido_code/memory_graph/durable_memory_update_writer.ex
  covers:
    - architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
    - architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs

- kind: source_file
  target: lib/jido_code/source_code_graph/memory_capture.ex
  covers:
    - architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
    - architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries

- kind: source_file
  target: lib/jido_code/actions/record_memory_graph.ex
  covers:
    - architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
    - architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
    - architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption

- kind: source_file
  target: test/jido_code/memory_graph_actions_test.exs
  covers:
    - architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
    - architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
    - architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
    - architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption
    - architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence

- kind: source_file
  target: test/jido_code/memory_graph_workspace_test.exs
  covers:
    - architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
    - architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries

- kind: source_file
  target: test/jido_code/agent_os/phase_twenty_nine_integration_test.exs
  covers:
    - architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
    - architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
    - architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
    - architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples

- kind: source_file
  target: test/jido_code/phase_thirty_integration_test.exs
  covers:
    - architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
    - architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
    - architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption
```
