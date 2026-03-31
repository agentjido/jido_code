# Factory Control Plane

This subject defines `Jido.Code` as a governed software-factory control plane for
Git-backed repositories.

```spec-meta
id: architecture.factory_control_plane
kind: policy
status: active
summary: Jido.Code centers the product on a governed software-factory control plane whose primary managed repository object is `ManagedRepo`, whose durable loop turns repo demand into governed work, and whose repo-native state layers inform but do not replace Ash-backed product truth.
decisions:
  - jido_code.namespace_and_control_naming
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.operator_surface_managed_repo_and_governed_run_adoption
surface:
  - .spec/decisions/jido_code.namespace_and_control_naming.md
  - .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  - .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  - lib/jido_code/control.ex
  - lib/jido_code/control/source_repo.ex
  - lib/jido_code/control/managed_repo.ex
  - lib/jido_code/control/repo_bridge.ex
  - lib/jido_code/workbench/inventory.ex
  - lib/jido_code/workbench/project_detail.ex
  - lib/jido_code/workbench/run_outcomes.ex
  - lib/jido_code/governance.ex
  - lib/jido_code/governance/change_request.ex
  - lib/jido_code/governance/decision.ex
  - lib/jido_code/governance/evidence.ex
  - lib/jido_code/governance/run_governance_bridge.ex
  - lib/jido_code/governance/policy_set.ex
  - lib/jido_code/governance/policy_bridge.ex
  - lib/jido_code/operations.ex
  - lib/jido_code/operations/event.ex
  - lib/jido_code/operations/assessment.ex
  - lib/jido_code/operations/external_object.ex
  - lib/jido_code/operations/observation.ex
  - lib/jido_code/operations/repo_native_state.ex
  - lib/jido_code/governance/repo_posture.ex
  - lib/jido_code/governance/posture_check.ex
  - lib/jido_code/governance/posture_bridge.ex
  - lib/jido_code/operations/intake.ex
  - lib/jido_code/operations/ingress.ex
  - lib/jido_code/conversations/ingress.ex
  - lib/jido_code/conversations/driver.ex
  - lib/jido_code/conversations/event_bridge.ex
  - lib/jido_code/conversations/policy.ex
  - lib/jido_code/operations/synthesis.ex
  - lib/jido_code/operations/work_item.ex
  - lib/jido_code/operations/work_synthesis.ex
  - test/jido_code/operations/repo_native_state_test.exs
  - lib/jido_code/projects/project.ex
  - lib/jido_code/orchestration/workflow_run.ex
  - lib/jido_code/orchestration/execution_profile.ex
  - lib/jido_code/orchestration/run.ex
  - lib/jido_code/orchestration/run_bridge.ex
  - lib/jido_code/orchestration/run_summary_feed.ex
  - lib/jido_code/code_server.ex
  - lib/jido_code_web/live/workbench_live.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - lib/jido_code_web/live/dashboard_live.ex
  - lib/jido_code_web/live/run_detail_live.ex
  - priv/repo/migrations/20260330143000_add_control_plane_repo_resources.exs
  - priv/repo/migrations/20260330161500_add_governance_policy_sets.exs
  - priv/repo/migrations/20260330183000_add_operations_ingress_resources.exs
  - priv/repo/migrations/20260330193000_add_operations_event_and_assessment_resources.exs
  - priv/repo/migrations/20260330195000_add_operations_work_items.exs
  - priv/repo/migrations/20260331100000_add_runs_and_execution_profiles.exs
  - priv/repo/migrations/20260331113000_add_run_governance_records.exs
  - priv/repo/migrations/20260331143000_add_repo_posture_records.exs
  - test/jido_code/governance/posture_bridge_test.exs
```

## Requirements

```spec-requirements
- id: architecture.factory_control_plane.product_is_governed_software_factory
  statement: Jido.Code shall treat the product as a governed software factory for Git-backed repositories rather than as a chat-first assistant or passive dashboard.
  priority: must
  stability: evolving

- id: architecture.factory_control_plane.source_repo_and_managed_repo_are_primary_repo_objects
  statement: The preferred control-plane repository model shall distinguish `SourceRepo` as the external Git identity and `ManagedRepo` as the durable internal managed wrapper, with current `Project` naming treated as transitional implementation vocabulary and carrying enough source identity to represent either hosted or local repositories during the transition.
  priority: must
  stability: evolving

- id: architecture.factory_control_plane.durable_control_loop_normalizes_demand_into_work
  statement: The product architecture shall normalize repository sync, policy loading, observation, intake, assessment, work creation, execution, evidence, and decision-making through one durable managed-repository control loop.
  priority: must
  stability: evolving

- id: architecture.factory_control_plane.repo_native_state_layers_inform_control_plane
  statement: Repo-native state layers such as `.spec/` and optional Git-native planning state shall inform posture, planning, review, and work selection without replacing the Ash-backed product control plane.
  priority: must
  stability: evolving

- id: architecture.factory_control_plane.lightweight_hosted_multi_user_posture
  statement: The architecture shall remain single-user-first while supporting lightweight hosted multi-user supervision with at least admin and standard operator distinction.
  priority: must
  stability: evolving

- id: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  statement: Operator-facing workbench, repo-detail, dashboard, and run-detail surfaces shall prefer `ManagedRepo` and governed `Run` records while preserving compatibility identifiers and route shapes during the migration away from `Project` and `WorkflowRun`.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.factory_control_plane.scenario_repo_demand_becomes_governed_work
  covers:
    - architecture.factory_control_plane.product_is_governed_software_factory
    - architecture.factory_control_plane.source_repo_and_managed_repo_are_primary_repo_objects
    - architecture.factory_control_plane.durable_control_loop_normalizes_demand_into_work
  given:
    - A Git-backed repository is under product supervision.
  when:
    - New demand arrives from repo sync, operator input, or an external integration.
  then:
    - The repository is treated as a managed control-plane object, and the demand is expected to flow through the durable work loop instead of being handled as an isolated chat or UI event.

- id: architecture.factory_control_plane.scenario_repo_native_state_guides_factory_decisions
  covers:
    - architecture.factory_control_plane.repo_native_state_layers_inform_control_plane
  given:
    - A managed repository contains `.spec/` state and may also contain Git-native planning state.
  when:
    - The factory evaluates planning, review, or execution readiness.
  then:
    - Repo-native state may inform control decisions while the product retains its own durable control-plane records and governance boundaries.

- id: architecture.factory_control_plane.scenario_hosted_mode_stays_lightweight
  covers:
    - architecture.factory_control_plane.lightweight_hosted_multi_user_posture
  given:
    - The product is deployed in a hosted multi-user mode.
  when:
    - Multiple humans supervise the same factory instance.
  then:
    - The system retains a lightweight admin-versus-operator distinction without requiring a heavyweight enterprise permission model in the first version.

- id: architecture.factory_control_plane.scenario_operator_surfaces_shift_without_route_breakage
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  given:
    - Managed repositories and governed runs already exist behind compatibility-oriented product routes.
  when:
    - An operator opens workbench, repo detail, dashboard, or run detail through existing route shapes.
  then:
    - The product resolves and presents control-plane records first while keeping the route and identifier contracts stable enough for mixed-mode rollout.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  covers:
    - architecture.factory_control_plane.product_is_governed_software_factory
    - architecture.factory_control_plane.source_repo_and_managed_repo_are_primary_repo_objects
    - architecture.factory_control_plane.durable_control_loop_normalizes_demand_into_work
    - architecture.factory_control_plane.repo_native_state_layers_inform_control_plane
    - architecture.factory_control_plane.lightweight_hosted_multi_user_posture

- kind: source_file
  target: .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

- kind: source_file
  target: lib/jido_code/operations/repo_native_state.ex
  covers:
    - architecture.factory_control_plane.repo_native_state_layers_inform_control_plane

- kind: source_file
  target: test/jido_code/operations/repo_native_state_test.exs
  covers:
    - architecture.factory_control_plane.repo_native_state_layers_inform_control_plane

- kind: source_file
  target: lib/jido_code/governance/posture_bridge.ex
  covers:
    - architecture.factory_control_plane.repo_native_state_layers_inform_control_plane

- kind: source_file
  target: lib/jido_code/control/repo_bridge.ex
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

- kind: source_file
  target: lib/jido_code/workbench/project_detail.ex
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

- kind: source_file
  target: lib/jido_code/orchestration/run_summary_feed.ex
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
```
