# Work Synthesis

<!-- current_truth.reconciled_with_branch: conversation-driven work handoff into canonical work items remains part of this synthesis subject, and bounded long-term conversation provenance now preserves enough origin linkage for later work-item recall without making transcript history the work record itself. -->

This subject defines how durable assessments become canonical operational work
records before execution begins.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.work_synthesis
kind: feature
status: active
summary: Jido.Code turns durable assessments and productive conversation demand into canonical `WorkItem` records that preserve origin links and initiating actor context, can stop at durable work creation without immediate execution, reconcile equivalent work candidates through deduplication and reprioritization rather than chaotic duplicate launch paths, make `WorkItem` the canonical anchor for active productive conversation identity when governed work is conversationally supervised, and preserve bounded conversation-provenance linkage for later origin recall without turning transcript history into the work record itself, even when those assessments were informed by repo-native state signals upstream or admitted through canonical repo-import scope.
decisions:
  - jido_code.namespace_and_control_naming
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.work_item_scoped_conversations_as_canonical_productive_threads
surface:
  - lib/jido_code/conversations.ex
  - lib/jido_code/conversations/work_resolution.ex
  - lib/jido_code/operations/work_item.ex
  - lib/jido_code/operations/work_synthesis.ex
  - lib/jido_code/operations/synthesis.ex
  - lib/jido_code/operations/ingress.ex
  - .spec/decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md
  - priv/repo/migrations/20260330195000_add_operations_work_items.exs
  - test/jido_code/conversations_test.exs
  - test/jido_code/operations/work_synthesis_test.exs
  - test/jido_code/operations/phase_two_integration_test.exs
  - test/jido_code/phase_forty_seven_integration_test.exs
```

## Requirements

```spec-requirements
- id: architecture.work_synthesis.work_item_is_canonical_operational_record
  statement: Jido.Code shall create durable `WorkItem` records as the canonical operational object between assessment and execution instead of hiding work creation inside feature-specific launch paths.
  priority: must
  stability: evolving

- id: architecture.work_synthesis.productive_conversations_route_through_work_resolution
  statement: Productive repository conversations that transition into durable planning, implementation, review, or governed follow-up shall create, attach, or reuse canonical `WorkItem` records through work synthesis or an equivalent product-owned work-resolution boundary instead of launching hidden work directly from conversation-local state.
  priority: must
  stability: evolving

- id: architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
  statement: Each `WorkItem` shall preserve managed-repository scope, originating assessment and event links, initiating demand references, category, priority, status, recommended action, and initiating actor metadata.
  priority: must
  stability: evolving

- id: architecture.work_synthesis.work_item_origin_can_preserve_conversation_context
  statement: When governed work originates from a productive conversation, the synthesized or reused `WorkItem` shall preserve enough conversation, turn, and initiating actor linkage for later steering, runtime routing, and governance to explain that origin without reconstructing it from transcript text.
  priority: should
  stability: evolving

- id: architecture.work_synthesis.active_conversation_identity_rejoins_work_item
  statement: When governed work is supervised through productive conversation, the canonical active conversation identity shall rejoin the `WorkItem` so separate work items in the same managed repository can keep separate productive threads without collapsing continuation onto one repo-global conversation.
  priority: must
  stability: evolving

- id: architecture.work_synthesis.historical_conversation_lineage_stays_attached_to_work_item
  statement: When governed work completes or later reopens, historical productive conversation lineage shall remain attached to the canonical `WorkItem` so operator surfaces can explain prior conversation-driven work without reviving the historical thread as the active default.
  priority: should
  stability: evolving

- id: architecture.work_synthesis.work_item_creation_can_stop_before_execution
  statement: Work synthesis shall be able to stop at durable `WorkItem` creation without requiring immediate run launch so the control plane can record actionable work even when execution stays deferred or optional.
  priority: must
  stability: evolving

- id: architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
  statement: Equivalent work candidates for the same managed-repository context shall reconcile through reprioritization or duplicate suppression rather than always creating a new open work item.
  priority: must
  stability: evolving

- id: architecture.work_synthesis.work_item_auditability_preserved
  statement: Work synthesis shall preserve auditability for why a work item was created, refreshed, reprioritized, or treated as a suppressed duplicate.
  priority: must
  stability: evolving

- id: architecture.work_synthesis.work_item_audit_preserves_ingress_actor_class
  statement: Work synthesis shall preserve ingress actor class attribution in initiating-actor metadata and audit context so durable work remains explainable across operator and machine entrypoints.
  priority: should
  stability: evolving

- id: architecture.work_synthesis.work_item_audit_can_fall_back_to_persisted_ingress_actor_identity
  statement: Work synthesis shall remain able to explain initiating actor identity from normalized ingress source metadata when compact requested-by envelopes omit the original actor identifier.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.work_synthesis.scenario_assessment_creates_repo_scoped_work
  covers:
    - architecture.work_synthesis.work_item_is_canonical_operational_record
    - architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
    - architecture.work_synthesis.work_item_creation_can_stop_before_execution
  given:
    - A managed repository has a durable assessment derived from normalized demand.
  when:
    - The control plane synthesizes operational work.
  then:
    - A durable open `WorkItem` is created with repo scope, origin links, recommended action, and initiating actor metadata even if no run launches immediately.

- id: architecture.work_synthesis.scenario_equivalent_work_is_reconciled
  covers:
    - architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
    - architecture.work_synthesis.work_item_auditability_preserved
  given:
    - Fresh assessments describe equivalent work demand for the same managed repository.
  when:
    - The control plane synthesizes work from those assessments.
  then:
    - Existing open work is updated or duplicate demand is suppressed with an audit trail instead of spawning uncontrolled duplicate work items.

- id: architecture.work_synthesis.scenario_productive_conversation_creates_or_reuses_work
  covers:
    - architecture.work_synthesis.work_item_is_canonical_operational_record
    - architecture.work_synthesis.productive_conversations_route_through_work_resolution
    - architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
    - architecture.work_synthesis.work_item_origin_can_preserve_conversation_context
    - architecture.work_synthesis.active_conversation_identity_rejoins_work_item
  given:
    - A managed repository has a productive conversation turn that should become durable planning, implementation, review, or follow-up work.
  when:
    - The product resolves that conversation turn into canonical governed work.
  then:
    - A canonical open `WorkItem` is created or an equivalent existing work item is reused instead of keeping the work implicit in conversation-only runtime state.
    - The durable work record preserves repo scope, actor context, and enough conversation linkage to explain the work origin and later steering behavior.

- id: architecture.work_synthesis.scenario_parallel_work_items_keep_separate_conversation_identity
  covers:
    - architecture.work_synthesis.productive_conversations_route_through_work_resolution
    - architecture.work_synthesis.work_item_origin_can_preserve_conversation_context
    - architecture.work_synthesis.active_conversation_identity_rejoins_work_item
  given:
    - A managed repository has multiple open `WorkItem`s that each originated from or are supervised through productive conversation.
  when:
    - Operators resume governed conversation work on those work items.
  then:
    - Each work item preserves separate productive conversation linkage and continuation identity.
    - The product does not require operators to route that resumed work through one repo-global latest conversation.

- id: architecture.work_synthesis.scenario_reopened_work_item_preserves_historical_conversation_lineage
  covers:
    - architecture.work_synthesis.active_conversation_identity_rejoins_work_item
    - architecture.work_synthesis.historical_conversation_lineage_stays_attached_to_work_item
  given:
    - A governed `WorkItem` already has a productive conversation that later became historical because the work completed or was cancelled.
  when:
    - The same work item is reopened for fresh governed work.
  then:
    - A new active productive conversation can attach to the reopened work item.
    - The historical conversation remains explainable as prior lineage on that same work item rather than being discarded or revived as the active default.

```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/operations/work_item.ex
  covers:
    - architecture.work_synthesis.work_item_is_canonical_operational_record
    - architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
    - architecture.work_synthesis.work_item_creation_can_stop_before_execution
    - architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
    - architecture.work_synthesis.work_item_auditability_preserved

- kind: source_file
  target: lib/jido_code/operations/work_synthesis.ex
  covers:
    - architecture.work_synthesis.work_item_is_canonical_operational_record
    - architecture.work_synthesis.productive_conversations_route_through_work_resolution
    - architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
    - architecture.work_synthesis.work_item_origin_can_preserve_conversation_context
    - architecture.work_synthesis.work_item_creation_can_stop_before_execution
    - architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
    - architecture.work_synthesis.work_item_auditability_preserved

- kind: source_file
  target: lib/jido_code/conversations/work_resolution.ex
  covers:
    - architecture.work_synthesis.productive_conversations_route_through_work_resolution

- kind: source_file
  target: lib/jido_code/conversations.ex
  covers:
    - architecture.work_synthesis.productive_conversations_route_through_work_resolution
    - architecture.work_synthesis.work_item_origin_can_preserve_conversation_context
    - architecture.work_synthesis.historical_conversation_lineage_stays_attached_to_work_item

- kind: source_file
  target: .spec/decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md
  covers:
    - architecture.work_synthesis.active_conversation_identity_rejoins_work_item

- kind: source_file
  target: lib/jido_code/operations/synthesis.ex
  covers:
    - architecture.work_synthesis.work_item_audit_can_fall_back_to_persisted_ingress_actor_identity

- kind: source_file
  target: lib/jido_code/operations/ingress.ex
  covers:
    - architecture.work_synthesis.work_item_audit_preserves_ingress_actor_class
    - architecture.work_synthesis.work_item_audit_can_fall_back_to_persisted_ingress_actor_identity

- kind: source_file
  target: test/jido_code/operations/work_synthesis_test.exs
  covers:
    - architecture.work_synthesis.work_item_is_canonical_operational_record
    - architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
    - architecture.work_synthesis.work_item_creation_can_stop_before_execution
    - architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
    - architecture.work_synthesis.work_item_auditability_preserved

- kind: source_file
  target: test/jido_code/operations/phase_two_integration_test.exs
  covers:
    - architecture.work_synthesis.work_item_is_canonical_operational_record
    - architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
    - architecture.work_synthesis.work_item_creation_can_stop_before_execution
    - architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
    - architecture.work_synthesis.work_item_auditability_preserved

- kind: command
  target: mix test test/jido_code/operations/work_synthesis_test.exs
  covers:
    - architecture.work_synthesis.work_item_is_canonical_operational_record
    - architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
    - architecture.work_synthesis.work_item_creation_can_stop_before_execution
    - architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
    - architecture.work_synthesis.work_item_auditability_preserved

- kind: source_file
  target: .spec/planning/phase-47-conversation-to-governed-work-convergence.md
  covers:
    - architecture.work_synthesis.productive_conversations_route_through_work_resolution
    - architecture.work_synthesis.work_item_origin_can_preserve_conversation_context

- kind: source_file
  target: .spec/planning/phase-49-work-item-conversation-identity-and-canonical-admission.md
  covers:
    - architecture.work_synthesis.active_conversation_identity_rejoins_work_item

- kind: source_file
  target: test/jido_code/phase_forty_nine_integration_test.exs
  covers:
    - architecture.work_synthesis.active_conversation_identity_rejoins_work_item

- kind: source_file
  target: test/jido_code/conversations_test.exs
  covers:
    - architecture.work_synthesis.productive_conversations_route_through_work_resolution
    - architecture.work_synthesis.work_item_origin_can_preserve_conversation_context

- kind: source_file
  target: test/jido_code/phase_forty_seven_integration_test.exs
  covers:
    - architecture.work_synthesis.productive_conversations_route_through_work_resolution
    - architecture.work_synthesis.work_item_origin_can_preserve_conversation_context
    - architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression

- kind: source_file
  target: test/jido_code/phase_fifty_one_integration_test.exs
  covers:
    - architecture.work_synthesis.active_conversation_identity_rejoins_work_item
    - architecture.work_synthesis.historical_conversation_lineage_stays_attached_to_work_item

```
