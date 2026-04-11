# Memory Ontology

This subject defines the enhanced coding-memory ontology that complements the
repository `source_code` graph with durable memory, decision, freshness, and
workflow provenance semantics.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.memory_ontology
kind: feature
status: proposed
summary: Jido.Code extends the base Jido memory model into a coding-memory ontology that adds memory classes such as Invariant, Convention, KnownIssue, OpenQuestion, Pattern, and AntiPattern, anchors memories to repository code entities and symbols, now complements that memory ontology with a companion governed control-plane ontology for product records such as ManagedRepo, Observation, Assessment, WorkItem, Run, Evidence, ChangeRequest, and governed Decision, models revision and change provenance explicitly, adds richer decision supersession and consequence structure, represents work sessions plus LLM and tool provenance as first-class entities, captures freshness, evidence, validation, invalidation, and supersession metadata explicitly, expects durable-memory update envelopes and writers to preserve those mutation semantics when operator or workflow actions evolve memory state, and replaces stringly memory typing or tag blobs with rdf:type-driven classes and first-class tag values.
decisions:
  - jido_code.memory_graph_and_coding_memory_ontology_adoption
  - jido_code.source_code_graph_pod_and_named_graph_ingestion
surface:
  - .spec/decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md
  - .spec/specs/memory_graph.spec.md
  - .spec/specs/source_code_graph_pod.spec.md
  - lib/jido_code/memory_graph/durable_memory_update_envelope.ex
  - lib/jido_code/memory_graph/durable_memory_update_writer.ex
  - priv/ontologies/jido-memory.ttl
```

## Requirements

```spec-requirements
- id: architecture.memory_ontology.coding_memory_types_extend_core_memory_model
  statement: The ontology shall extend the core Jido memory model beyond Fact, Decision, and LessonLearned to include at least Invariant, Convention, KnownIssue, OpenQuestion, Pattern, and AntiPattern as first-class memory classes.
  priority: must
  stability: proposed

- id: architecture.memory_ontology.companion_control_plane_ontology_models_governed_records
  statement: The semantic model shall include a companion governed control-plane ontology that models first-class product records such as ManagedRepo, Event, Observation, Assessment, WorkItem, Run, Evidence, ChangeRequest, and governed Decision without overloading the coding-memory ontology with mixed concerns.
  priority: must
  stability: proposed

- id: architecture.memory_ontology.memories_anchor_to_code_entities_and_symbols
  statement: The ontology shall provide explicit relationships that let memories anchor to repository, file, module, function, test, configuration, and symbol entities through relations such as `aboutRepository`, `aboutFile`, `aboutModule`, `aboutFunction`, `aboutTest`, `aboutConfig`, and `affectsSymbol`.
  priority: must
  stability: proposed

- id: architecture.memory_ontology.memory_and_provenance_link_to_governed_records_through_typed_relations
  statement: The ontology shall provide explicit relationships that let memories and workflow provenance link to governed product records through typed relations such as `aboutManagedRepo`, `aboutObservation`, `aboutAssessment`, `aboutWorkItem`, `aboutRun`, `aboutEvidence`, `aboutChangeRequest`, and `aboutDecision`.
  priority: must
  stability: proposed

- id: architecture.memory_ontology.change_and_revision_provenance_is_explicit
  statement: The ontology shall model revision and change provenance explicitly through relationships such as `introducedInCommit`, `validatedByTestRun`, `mentionedInPR`, `derivedFromIssue`, `observedAtRevision`, and `invalidatedByRevision`.
  priority: must
  stability: proposed

- id: architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
  statement: Decision memories shall support richer structure including `alternativeConsidered`, `decisionStatus`, `supersedes`, and `hasConsequence` so coding decisions can evolve over time without losing lineage.
  priority: must
  stability: proposed

- id: architecture.memory_ontology.workflow_and_llm_provenance_entities_are_modeled
  statement: The ontology shall model workflow and LLM provenance with first-class entities including WorkSession, AgentRun, ToolInvocation, PromptTurn, Review, Patch, and Plan rather than flattening those concepts into string metadata.
  priority: must
  stability: proposed

- id: architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit
  statement: Memories and workflow provenance shall support explicit freshness, evidence, and validation metadata including `freshnessScore`, `staleReason`, `lastValidatedAt`, `validForRevision`, `supportedBy`, `confidenceSource`, and `evidenceArtifact`.
  priority: must
  stability: proposed

- id: architecture.memory_ontology.memory_updates_preserve_mutation_lineage
  statement: Validation, invalidation, and supersession updates shall preserve explicit mutation lineage such as `lastValidatedAt`, `staleReason`, `invalidatedByRevision`, `supportedBy`, `evidenceArtifact`, and supersession links so later operator and workflow actions can explain why durable memory changed state.
  priority: must
  stability: proposed

- id: architecture.memory_ontology.work_sessions_capture_repo_and_runtime_context
  statement: WorkSession entities shall capture repository, branch, revision, actor, model, toolchain, goal, and outcome context so memories remain attributable to the runtime conditions under which they were recorded.
  priority: should
  stability: proposed

- id: architecture.memory_ontology.rdf_type_and_first_class_tags_replace_stringly_type_fields
  statement: The ontology shall prefer rdf:type-driven class membership and repeated first-class tag values or tag entities over stringly `memoryType` or comma-delimited tag blobs.
  priority: should
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.memory_ontology.scenario_decision_links_to_code_and_supersedes_prior_decision
  covers:
    - architecture.memory_ontology.coding_memory_types_extend_core_memory_model
    - architecture.memory_ontology.memory_and_provenance_link_to_governed_records_through_typed_relations
    - architecture.memory_ontology.memories_anchor_to_code_entities_and_symbols
    - architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
  given:
    - A repository already contains a prior architectural decision about a module or function.
  when:
    - A later work session records a new decision that replaces or refines the earlier one.
  then:
    - The new memory uses the Decision class.
    - It links to the affected code entities explicitly.
    - It can also link to the governed run or decision record it informed without confusing memory Decision with governed Decision.
    - It records rationale, alternatives, supersession, and consequences rather than only free-form prose.

- id: architecture.memory_ontology.scenario_companion_ontology_keeps_governed_records_distinct
  covers:
    - architecture.memory_ontology.companion_control_plane_ontology_models_governed_records
    - architecture.memory_ontology.memory_and_provenance_link_to_governed_records_through_typed_relations
  given:
    - Memory or workflow provenance needs to link to governed product records.
  when:
    - The semantic stack loads the memory ontology alongside the governed control-plane ontology.
  then:
    - Governed product records remain first-class semantic entities in the companion ontology.
    - Memory `Decision` and governed `Decision` remain distinguishable by namespace and role.
    - Typed `about*` relations connect memory or provenance to governed product records without relying on generic artifact paths.

- id: architecture.memory_ontology.scenario_known_issue_is_tracked_across_revisions
  covers:
    - architecture.memory_ontology.coding_memory_types_extend_core_memory_model
    - architecture.memory_ontology.change_and_revision_provenance_is_explicit
    - architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit
  given:
    - A repository has a recurring bug or operational weakness.
  when:
    - The system records that knowledge as durable memory and later validates or invalidates it.
  then:
    - The memory can be typed as a KnownIssue.
    - The ontology records the revision where it was observed, later validations, and any revision that invalidates it.
    - Freshness and evidence metadata remain explicit.

- id: architecture.memory_ontology.scenario_workflow_activity_is_provenance_not_blob_metadata
  covers:
    - architecture.memory_ontology.workflow_and_llm_provenance_entities_are_modeled
    - architecture.memory_ontology.work_sessions_capture_repo_and_runtime_context
  given:
    - An agent-assisted coding workflow plans, edits, reviews, and validates a change.
  when:
    - The system records the resulting memories and provenance.
  then:
    - WorkSession, AgentRun, ToolInvocation, PromptTurn, Review, Patch, and Plan can each appear as first-class linked entities.
    - Repository, revision, actor, model, toolchain, goal, and outcome context remain attached to the session.

- id: architecture.memory_ontology.scenario_tags_and_types_are_not_stringly
  covers:
    - architecture.memory_ontology.rdf_type_and_first_class_tags_replace_stringly_type_fields
  given:
    - A memory entry needs multiple classifications or tags.
  when:
    - The memory is stored in the ontology.
  then:
    - Memory class is expressed through rdf:type rather than a string field.
    - Tags remain repeated values or tag entities rather than one delimited text blob.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md
  covers:
    - architecture.memory_ontology.coding_memory_types_extend_core_memory_model
    - architecture.memory_ontology.companion_control_plane_ontology_models_governed_records
    - architecture.memory_ontology.memories_anchor_to_code_entities_and_symbols
    - architecture.memory_ontology.memory_and_provenance_link_to_governed_records_through_typed_relations
    - architecture.memory_ontology.change_and_revision_provenance_is_explicit
    - architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
    - architecture.memory_ontology.workflow_and_llm_provenance_entities_are_modeled
    - architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit
    - architecture.memory_ontology.work_sessions_capture_repo_and_runtime_context
    - architecture.memory_ontology.rdf_type_and_first_class_tags_replace_stringly_type_fields

- kind: source_file
  target: priv/ontologies/jido-memory.ttl
  covers:
    - architecture.memory_ontology.coding_memory_types_extend_core_memory_model
    - architecture.memory_ontology.memories_anchor_to_code_entities_and_symbols
    - architecture.memory_ontology.memory_and_provenance_link_to_governed_records_through_typed_relations
    - architecture.memory_ontology.change_and_revision_provenance_is_explicit
    - architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
    - architecture.memory_ontology.workflow_and_llm_provenance_entities_are_modeled
    - architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit
    - architecture.memory_ontology.work_sessions_capture_repo_and_runtime_context
    - architecture.memory_ontology.rdf_type_and_first_class_tags_replace_stringly_type_fields

- kind: source_file
  target: priv/ontologies/jido-control-plane.ttl
  covers:
    - architecture.memory_ontology.companion_control_plane_ontology_models_governed_records
    - architecture.memory_ontology.memory_and_provenance_link_to_governed_records_through_typed_relations

- kind: source_file
  target: lib/jido_code/memory_graph/durable_memory_update_envelope.ex
  covers:
    - architecture.memory_ontology.change_and_revision_provenance_is_explicit
    - architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
    - architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit
    - architecture.memory_ontology.memory_updates_preserve_mutation_lineage

- kind: source_file
  target: lib/jido_code/memory_graph/durable_memory_update_writer.ex
  covers:
    - architecture.memory_ontology.change_and_revision_provenance_is_explicit
    - architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
    - architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit
    - architecture.memory_ontology.memory_updates_preserve_mutation_lineage
```
