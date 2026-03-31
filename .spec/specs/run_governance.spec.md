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
  - lib/jido_code/orchestration.ex
  - lib/jido_code/orchestration/execution_profile.ex
  - lib/jido_code/orchestration/run.ex
  - lib/jido_code/orchestration/run_bridge.ex
  - lib/jido_code/orchestration/workflow_run.ex
  - priv/repo/migrations/20260331100000_add_runs_and_execution_profiles.exs
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
```
