# Work Synthesis

This subject defines how durable assessments become canonical operational work
records before execution begins.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.work_synthesis
kind: feature
status: active
summary: Jido.Code turns durable assessments into canonical `WorkItem` records that preserve origin links and initiating actor context, can stop at durable work creation without immediate execution, and reconcile equivalent work candidates through deduplication and reprioritization rather than chaotic duplicate launch paths, even when those assessments were informed by repo-native state signals upstream or admitted through canonical repo-import scope.
decisions:
  - jido_code.namespace_and_control_naming
  - jido_code.factory_control_plane_and_runtime_overlay
surface:
  - lib/jido_code/operations/work_item.ex
  - lib/jido_code/operations/work_synthesis.ex
  - lib/jido_code/operations/synthesis.ex
  - lib/jido_code/operations/ingress.ex
  - priv/repo/migrations/20260330195000_add_operations_work_items.exs
  - test/jido_code/operations/work_synthesis_test.exs
  - test/jido_code/operations/phase_two_integration_test.exs
```

## Requirements

```spec-requirements
- id: architecture.work_synthesis.work_item_is_canonical_operational_record
  statement: Jido.Code shall create durable `WorkItem` records as the canonical operational object between assessment and execution instead of hiding work creation inside feature-specific launch paths.
  priority: must
  stability: evolving

- id: architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
  statement: Each `WorkItem` shall preserve managed-repository scope, originating assessment and event links, initiating demand references, category, priority, status, recommended action, and initiating actor metadata.
  priority: must
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
    - architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
    - architecture.work_synthesis.work_item_creation_can_stop_before_execution
    - architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
    - architecture.work_synthesis.work_item_auditability_preserved

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

```
