<!-- covers: package.jido_code.spec_led_workspace -->

# Run Governance

This subject defines the governed run projection model for `Jido.Code`.

```spec-meta
id: architecture.run_governance
kind: policy
status: active
summary: Jido.Code treats governed `Run` as the canonical execution record linked to `WorkItem` and `ExecutionProfile`, keeps run evidence explainable and reviewable in first-class governance records, and lets those records inform posture without replacing the run-governance model itself.
decisions:
  - jido_code.compatibility_era_removal_and_canonical_cutover
  - jido_code.internal_domain_and_execution_canonicalization
  - jido_code.runic_execution_model
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.internal_cleanup_and_ui_convergence_foundation
  - jido_code.jido_os_public_turn_runtime_adoption
  - jido_code.runtime_evidence_posture_and_rollout_convergence
surface:
  - .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  - .spec/decisions/jido_code.internal_domain_and_execution_canonicalization.md
  - .spec/decisions/jido_code.runic_execution_model.md
  - .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  - .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  - .spec/decisions/jido_code.runtime_evidence_posture_and_rollout_convergence.md
  - lib/jido_code/conversations/turn_bridge.ex
  - lib/jido_code/governance/change_request.ex
  - lib/jido_code/governance/decision.ex
  - lib/jido_code/governance/evidence.ex
  - lib/jido_code/governance/policy_bridge.ex
  - lib/jido_code/governance/run_governance_bridge.ex
  - lib/jido_code/orchestration.ex
  - lib/jido_code/orchestration/execution_profile.ex
  - lib/jido_code/orchestration/run.ex
  - lib/jido_code/orchestration/run_bridge.ex
  - lib/jido_code/orchestration/run_summary_feed.ex
  - lib/jido_code/orchestration/workflow_run.ex
  - lib/jido_code/workbench/run_outcomes.ex
  - lib/jido_code_web/live/run_detail_live.ex
  - lib/jido_code/workbench/issue_triage_workflow_kickoff.ex
  - test/support/conn_case.ex
  - test/jido_code/orchestration/run_bridge_test.exs
  - test/jido_code_web/live/run_detail_live_test.exs
  - priv/repo/migrations/20260331100000_add_runs_and_execution_profiles.exs
  - priv/repo/migrations/20260331113000_add_run_governance_records.exs
```

## Requirements

```spec-requirements
- id: architecture.run_governance.run_is_preferred_execution_record
  statement: Jido.Code shall treat `Run` as the canonical control-plane execution record linked to managed repository scope and optional `WorkItem` context, and operator-facing execution behavior shall not depend on `WorkflowRun` as a supported parallel product record.
  priority: must
  stability: evolving

- id: architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model
  statement: Product-owned execution loaders, retry paths, and runtime materialization shall read and persist governed `Run` state first, using `WorkflowRun` only as bounded internal adapter or audit support where a current execution path still requires it.
  priority: must
  stability: evolving

- id: architecture.run_governance.greenfield_tests_and_fixtures_create_canonical_run_graph
  statement: Greenfield tests, fixtures, and setup helpers shall create canonical governed run, evidence, and decision records directly unless a migration-specific or audit-specific test explicitly requires lower-level workflow history.
  priority: should
  stability: evolving

- id: architecture.run_governance.execution_profile_governs_environment_defaults
  statement: Jido.Code shall describe sandbox shape, repo prep, validation defaults, and checkpoint or resume expectations through governed `ExecutionProfile` records instead of only ad hoc run-local maps.
  priority: must
  stability: evolving

- id: architecture.run_governance.execution_profile_preserves_repo_and_workflow_compatibility
  statement: Execution profile resolution shall preserve repo-level execution defaults and workflow-specific execution overrides as canonical execution inputs.
  priority: must
  stability: evolving

- id: architecture.run_governance.run_launch_resolves_effective_execution_profile
  statement: Governed run launch paths shall resolve an effective execution profile before persisting the preferred `Run` projection.
  priority: should
  stability: evolving

- id: architecture.run_governance.evidence_records_capture_run_outputs
  statement: Jido.Code shall persist durable `Evidence` records for run outputs such as validation summaries, approval context, failure context, and runtime diagnostics instead of leaving those artifacts only inside workflow step maps.
  priority: must
  stability: evolving

- id: architecture.run_governance.change_request_records_reviewable_run_state
  statement: Jido.Code shall persist durable `ChangeRequest` records when a run enters reviewable approval state so human judgment has a first-class control-plane object instead of only a run-local status.
  priority: must
  stability: evolving

- id: architecture.run_governance.decision_records_capture_governance_outcomes
  statement: Jido.Code shall persist durable `Decision` records for approve, reject, or defer outcomes with actor attribution and evidence references instead of keeping those governance outcomes only in transient run metadata.
  priority: must
  stability: evolving

- id: architecture.run_governance.review_policy_controls_change_request_creation
  statement: Repo-governance review policy shall determine whether runs create `ChangeRequest` review artifacts and whether issue-triage launches use auto-post or human-approval behavior instead of inferring review requirements only from legacy project settings.
  priority: must
  stability: evolving

- id: architecture.run_governance.blocked_review_context_preserves_typed_remediation
  statement: When review policy requires human approval but the review context is incomplete, the governed run layer shall preserve typed remediation and blocking diagnostics instead of leaving reviewers with an opaque awaiting state.
  priority: must
  stability: evolving

- id: architecture.run_governance.run_projection_preserves_explicit_stage_catalog
  statement: The governed run projection shall preserve explicit repo-prep, validation, approval, and cleanup stage plans from the effective execution profile so the control plane does not collapse execution into one opaque status.
  priority: must
  stability: evolving

- id: architecture.run_governance.workflow_run_audit_preserves_actor_class_attribution
  statement: Execution lifecycle audit state shall preserve explicit actor class attribution across approval, retry, and machine-driven issue-triage transitions so governed run and review records can distinguish operator, orchestrator, run-worker, and external-ingress actions.
  priority: must
  stability: evolving

- id: architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence
  statement: When coding conversations produce workflow-relevant terminal outputs, replay summaries, artifacts, or operator-review bundles through public `jido_os` turn surfaces, Jido.Code shall materialize the bounded results it needs into governed `Run` and `Evidence` records instead of treating runtime replay as the product's durable audit store.
  priority: must
  stability: evolving

- id: architecture.run_governance.turn_projection_failures_degrade_without_blocking_runtime_progress
  statement: If governed run or evidence projection of a terminal coding turn fails, Jido.Code shall degrade to typed warnings and preserve runtime progress or subscriber continuity instead of treating projection failure as turn execution failure.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.run_governance.scenario_workflow_run_projects_into_run
  covers:
    - architecture.run_governance.run_is_preferred_execution_record
    - architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model
  given:
    - A managed-repository execution is created for a governed work item or direct operator launch.
  when:
    - The orchestration layer persists and refreshes execution state.
  then:
    - A governed `Run` record remains the canonical product execution record with durable identity and workflow-state reference.

- id: architecture.run_governance.scenario_execution_profile_is_resolved_from_repo_defaults
  covers:
    - architecture.run_governance.execution_profile_governs_environment_defaults
    - architecture.run_governance.execution_profile_preserves_repo_and_workflow_compatibility
  given:
    - A managed repository has repo-level execution defaults and optional workflow-level overrides.
  when:
    - A governed run projection resolves its execution environment.
  then:
    - The effective `ExecutionProfile` is persisted from repo defaults plus workflow overrides while keeping explicit repo prep and validation plans.

- id: architecture.run_governance.scenario_review_state_creates_governance_records
  covers:
    - architecture.run_governance.evidence_records_capture_run_outputs
    - architecture.run_governance.change_request_records_reviewable_run_state
    - architecture.run_governance.decision_records_capture_governance_outcomes
    - architecture.run_governance.workflow_run_audit_preserves_actor_class_attribution
  given:
    - A governed run accumulates validation summaries and then reaches review or approval handling.
  when:
    - The workflow run projection is synchronized into control-plane governance records.
  then:
    - Evidence is stored durably, a reviewable change request is created when the run awaits approval, and approval or rejection outcomes are persisted as decision records with actor attribution and evidence references.
    - Retry, approval, and webhook-driven execution records keep explicit actor class attribution instead of collapsing machine and human actions into undifferentiated metadata.

- id: architecture.run_governance.scenario_policy_governs_review_artifacts_and_launches
  covers:
    - architecture.run_governance.review_policy_controls_change_request_creation
    - architecture.run_governance.blocked_review_context_preserves_typed_remediation
    - architecture.run_governance.run_projection_preserves_explicit_stage_catalog
  given:
    - A managed repository has a repo-governance review policy and an execution profile with explicit stage plans.
  when:
    - A run is launched or projected into approval handling.
  then:
    - Review behavior follows the repo policy, blocked review states keep typed remediation, and the run projection continues to expose explicit repo-prep, validation, approval, and cleanup stage plans.

- id: architecture.run_governance.scenario_coding_turn_terminal_outputs_feed_governed_evidence
  covers:
    - architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence
    - architecture.run_governance.evidence_records_capture_run_outputs
  given:
    - A coding conversation turn produces a terminal public turn projection with replayable events, artifacts, or operator-review output.
  when:
    - The product needs governed review, posture, or audit context from that runtime turn.
  then:
    - The bounded runtime outputs are expected to be projected into governed `Run` and `Evidence` records rather than left only in replay-oriented runtime storage.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  covers:
    - architecture.run_governance.run_is_preferred_execution_record

- kind: source_file
  target: .spec/decisions/jido_code.internal_domain_and_execution_canonicalization.md
  covers:
    - architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model
    - architecture.run_governance.greenfield_tests_and_fixtures_create_canonical_run_graph

- kind: source_file
  target: lib/jido_code/orchestration/run.ex
  covers:
    - architecture.run_governance.run_is_preferred_execution_record
    - architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model

- kind: source_file
  target: lib/jido_code/orchestration/execution_profile.ex
  covers:
    - architecture.run_governance.execution_profile_governs_environment_defaults
    - architecture.run_governance.execution_profile_preserves_repo_and_workflow_compatibility

- kind: source_file
  target: lib/jido_code/orchestration/run_bridge.ex
  covers:
    - architecture.run_governance.run_launch_resolves_effective_execution_profile
    - architecture.execution_pipeline.run_is_projection_of_workflow_state

- kind: source_file
  target: lib/jido_code/orchestration/run_summary_feed.ex
  covers:
    - architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model

- kind: source_file
  target: lib/jido_code/workbench/run_outcomes.ex
  covers:
    - architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model

- kind: source_file
  target: lib/jido_code/governance/evidence.ex
  covers:
    - architecture.run_governance.evidence_records_capture_run_outputs

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  covers:
    - architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence

- kind: source_file
  target: lib/jido_code/conversations/turn_bridge.ex
  covers:
    - architecture.run_governance.turn_projection_failures_degrade_without_blocking_runtime_progress

- kind: source_file
  target: test/jido_code/conversations/turn_bridge_test.exs
  covers:
    - architecture.run_governance.turn_projection_failures_degrade_without_blocking_runtime_progress

- kind: source_file
  target: lib/jido_code/governance/change_request.ex
  covers:
    - architecture.run_governance.change_request_records_reviewable_run_state

- kind: source_file
  target: lib/jido_code/governance/decision.ex
  covers:
    - architecture.run_governance.decision_records_capture_governance_outcomes

- kind: source_file
  target: lib/jido_code/governance/run_governance_bridge.ex
  covers:
    - architecture.run_governance.evidence_records_capture_run_outputs
    - architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence
    - architecture.run_governance.change_request_records_reviewable_run_state
    - architecture.run_governance.decision_records_capture_governance_outcomes
    - architecture.run_governance.review_policy_controls_change_request_creation
    - architecture.run_governance.blocked_review_context_preserves_typed_remediation

- kind: source_file
  target: lib/jido_code/governance/policy_bridge.ex
  covers:
    - architecture.run_governance.review_policy_controls_change_request_creation

- kind: source_file
  target: test/jido_code/orchestration/run_bridge_test.exs
  covers:
    - architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model

- kind: source_file
  target: lib/jido_code/orchestration/run_bridge.ex
  covers:
    - architecture.run_governance.run_projection_preserves_explicit_stage_catalog
    - architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence

- kind: source_file
  target: lib/jido_code/workbench/issue_triage_workflow_kickoff.ex
  covers:
    - architecture.run_governance.review_policy_controls_change_request_creation

- kind: source_file
  target: lib/jido_code/orchestration/workflow_run.ex
  covers:
    - architecture.run_governance.workflow_run_audit_preserves_actor_class_attribution

- kind: source_file
  target: test/jido_code/governance/run_governance_bridge_test.exs
  covers:
    - architecture.run_governance.evidence_records_capture_run_outputs
    - architecture.run_governance.change_request_records_reviewable_run_state
    - architecture.run_governance.decision_records_capture_governance_outcomes
    - architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence

- kind: source_file
  target: test/jido_code/orchestration/workflow_run_test.exs
  covers:
    - architecture.run_governance.workflow_run_audit_preserves_actor_class_attribution

- kind: source_file
  target: test/jido_code/conversations/phase_seven_integration_test.exs
  covers:
    - architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence
    - architecture.run_governance.evidence_records_capture_run_outputs

- kind: source_file
  target: test/jido_code/conversations/phase_nine_integration_test.exs
  covers:
    - architecture.run_governance.turn_projection_failures_degrade_without_blocking_runtime_progress

```
