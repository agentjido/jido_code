<!-- covers: package.jido_code.spec_led_workspace -->

# Run Governance

This subject defines the governed run projection model for `Jido.Code`.

```spec-meta
id: architecture.run_governance
kind: policy
status: active
summary: Jido.Code evolves execution from standalone workflow-run records into governed Run projections linked to WorkItem and ExecutionProfile while preserving WorkflowRun as the migration seam beneath the preferred control-plane model.
decisions:
  - jido_code.runic_execution_model
  - jido_code.factory_control_plane_and_runtime_overlay
surface:
  - .spec/decisions/jido_code.runic_execution_model.md
  - .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  - lib/jido_code/governance/change_request.ex
  - lib/jido_code/governance/decision.ex
  - lib/jido_code/governance/evidence.ex
  - lib/jido_code/governance/policy_bridge.ex
  - lib/jido_code/governance/run_governance_bridge.ex
  - lib/jido_code/orchestration.ex
  - lib/jido_code/orchestration/execution_profile.ex
  - lib/jido_code/orchestration/run.ex
  - lib/jido_code/orchestration/run_bridge.ex
  - lib/jido_code/orchestration/workflow_run.ex
  - lib/jido_code/workbench/issue_triage_workflow_kickoff.ex
  - priv/repo/migrations/20260331100000_add_runs_and_execution_profiles.exs
  - priv/repo/migrations/20260331113000_add_run_governance_records.exs
```

## Requirements

```spec-requirements
- id: architecture.run_governance.run_is_preferred_execution_record
  statement: Jido.Code shall treat `Run` as the preferred control-plane execution record linked to managed repository scope and optional `WorkItem` context, while preserving `WorkflowRun` as a transitional execution seam.
  priority: must
  stability: evolving

- id: architecture.run_governance.execution_profile_governs_environment_defaults
  statement: Jido.Code shall describe sandbox shape, repo prep, validation defaults, and checkpoint or resume expectations through governed `ExecutionProfile` records instead of only ad hoc run-local maps.
  priority: must
  stability: evolving

- id: architecture.run_governance.execution_profile_preserves_repo_and_workflow_compatibility
  statement: Execution profile resolution shall preserve compatibility with repo-level execution defaults and workflow-specific execution overrides during the migration from project and workflow-local settings.
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
```

## Scenarios

```spec-scenarios
- id: architecture.run_governance.scenario_workflow_run_projects_into_run
  covers:
    - architecture.run_governance.run_is_preferred_execution_record
  given:
    - A workflow run is created for a managed repository.
  when:
    - The orchestration layer persists the legacy workflow-run seam.
  then:
    - A governed `Run` projection is persisted with the same durable run identity and workflow-state reference without introducing a second step engine.

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
  given:
    - A governed run accumulates validation summaries and then reaches review or approval handling.
  when:
    - The workflow run projection is synchronized into control-plane governance records.
  then:
    - Evidence is stored durably, a reviewable change request is created when the run awaits approval, and approval or rejection outcomes are persisted as decision records with actor attribution and evidence references.

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
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/orchestration/run.ex
  covers:
    - architecture.run_governance.run_is_preferred_execution_record

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
  target: lib/jido_code/governance/evidence.ex
  covers:
    - architecture.run_governance.evidence_records_capture_run_outputs

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
    - architecture.run_governance.change_request_records_reviewable_run_state
    - architecture.run_governance.decision_records_capture_governance_outcomes
    - architecture.run_governance.review_policy_controls_change_request_creation
    - architecture.run_governance.blocked_review_context_preserves_typed_remediation

- kind: source_file
  target: lib/jido_code/governance/policy_bridge.ex
  covers:
    - architecture.run_governance.review_policy_controls_change_request_creation

- kind: source_file
  target: lib/jido_code/orchestration/run_bridge.ex
  covers:
    - architecture.run_governance.run_projection_preserves_explicit_stage_catalog

- kind: source_file
  target: lib/jido_code/workbench/issue_triage_workflow_kickoff.ex
  covers:
    - architecture.run_governance.review_policy_controls_change_request_creation
```
