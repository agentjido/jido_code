# Factory Control Plane

This subject defines `Jido.Code` as a governed software-factory control plane for
Git-backed repositories.

```spec-meta
id: architecture.factory_control_plane
kind: policy
status: active
summary: Jido.Code centers the product on a governed software-factory control plane whose primary managed repository object is `ManagedRepo`, whose durable loop turns repo demand into governed work, whose semantic repository insights may inform operator understanding and work synthesis through canonical managed-repository surfaces while preserving explicit freshness, recovery, and provenance metadata when those findings rejoin governed product records, and whose repo-native or runtime-derived analysis layers inform but do not replace Ash-backed product truth.
decisions:
  - jido_code.compatibility_era_removal_and_canonical_cutover
  - jido_code.internal_domain_and_execution_canonicalization
  - jido_code.namespace_and_control_naming
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.internal_cleanup_and_ui_convergence_foundation
  - jido_code.runtime_evidence_posture_and_rollout_convergence
  - jido_code.source_code_graph_product_adoption
  - jido_code.operator_surface_managed_repo_and_governed_run_adoption
surface:
  - .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  - .spec/decisions/jido_code.internal_domain_and_execution_canonicalization.md
  - .spec/decisions/jido_code.namespace_and_control_naming.md
  - .spec/decisions/jido_code.factory_control_plane.md
  - .spec/decisions/jido_code.runtime_evidence_posture_and_rollout_convergence.md
  - .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  - lib/jido_code/control.ex
  - lib/jido_code/control/source_repo.ex
  - lib/jido_code/control/managed_repo.ex
  - lib/jido_code/control/repo_bridge.ex
  - lib/jido_code/workbench/inventory.ex
  - lib/jido_code/workbench/project_semantic_inspection.ex
  - lib/jido_code/workbench/project_detail.ex
  - lib/jido_code/workbench/run_outcomes.ex
  - lib/jido_code/governance.ex
  - lib/jido_code/governance/change_request.ex
  - lib/jido_code/governance/decision.ex
  - lib/jido_code/governance/evidence.ex
  - lib/jido_code/governance/run_governance_bridge.ex
  - lib/jido_code/governance/runtime_evidence_feed.ex
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
  - lib/jido_code/operations/synthesis.ex
  - lib/jido_code/operations/work_item.ex
  - lib/jido_code/operations/work_synthesis.ex
  - test/jido_code/operations/repo_native_state_test.exs
  - lib/jido_code/orchestration/execution_profile.ex
  - lib/jido_code/orchestration/run.ex
  - lib/jido_code/orchestration/run_bridge.ex
  - lib/jido_code/orchestration/run_summary_feed.ex
  - lib/jido_code_web/live/workbench_live.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - lib/jido_code_web/live/dashboard_live.ex
  - lib/jido_code_web/components/operator_state_components.ex
  - lib/jido_code_web/live/DashboardRunSummaryWidget.vue
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
  - test/jido_code/governance/runtime_evidence_feed_test.exs
  - test/jido_code_web/live/dashboard_live_test.exs
  - test/jido_code_web/live/phase_sixteen_integration_test.exs
  - test/jido_code_web/live/run_detail_live_test.exs
  - test/jido_code_web/live/phase_eleven_integration_test.exs
  - test/jido_code_web/live/phase_twenty_five_integration_test.exs
```

## Requirements

```spec-requirements
- id: architecture.factory_control_plane.product_is_governed_software_factory
  statement: Jido.Code shall treat the product as a governed software factory for Git-backed repositories rather than as a chat-first assistant or passive dashboard.
  priority: must
  stability: evolving

- id: architecture.factory_control_plane.source_repo_and_managed_repo_are_primary_repo_objects
  statement: The control-plane repository model shall distinguish `SourceRepo` as the external Git identity and `ManagedRepo` as the durable internal managed wrapper, and product contracts shall not preserve `Project` as a supported parallel repository object.
  priority: must
  stability: evolving

- id: architecture.factory_control_plane.internal_repo_loaders_use_canonical_repo_graph
  statement: Product-owned repo loaders, setup helpers, and fixtures shall create and read the canonical `SourceRepo` plus `ManagedRepo` graph directly instead of defaulting to `Project`-era rows and bridge repair.
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
  statement: Operator-facing workbench, repo-detail, dashboard, and run-detail surfaces shall use `ManagedRepo` and governed `Run` as their canonical product records, identifiers, and route shapes instead of preserving `Project`- or `WorkflowRun`-era compatibility vocabulary.
  priority: must
  stability: evolving

- id: architecture.factory_control_plane.runtime_overlay_preserves_product_truth
  statement: Even as `jido_os` grows richer admitted runtime services and authority-backed facades, those services shall remain runtime overlays whose typed outcomes rejoin managed-repository governance rather than displacing product-owned control-plane truth.
  priority: must
  stability: evolving

- id: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane
  statement: Repository-scoped semantic analysis may inform operator understanding, work synthesis, and review, but any graph-backed finding that matters to the factory shall rejoin governed product records rather than becoming an alternate durable truth system.
  priority: should
  stability: evolving

- id: architecture.factory_control_plane.compatibility_repo_resolution_uses_explicit_control_plane_actors
  statement: Canonical managed-repository scope resolution and source-repo identity updates shall use explicit factory-system, operator, or orchestrator actors for control-plane reads and writes instead of anonymous repair or compatibility bypasses.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.factory_control_plane.scenario_repo_demand_becomes_governed_work
  covers:
    - architecture.factory_control_plane.product_is_governed_software_factory
    - architecture.factory_control_plane.source_repo_and_managed_repo_are_primary_repo_objects
    - architecture.factory_control_plane.internal_repo_loaders_use_canonical_repo_graph
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
    - architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane
  given:
    - A managed repository contains `.spec/` state and may also contain Git-native planning state.
  when:
    - The factory evaluates planning, review, execution readiness, or semantic repository findings.
  then:
    - Repo-native or semantic analysis state may inform control decisions while the product retains its own durable control-plane records and governance boundaries.

- id: architecture.factory_control_plane.scenario_hosted_mode_stays_lightweight
  covers:
    - architecture.factory_control_plane.lightweight_hosted_multi_user_posture
  given:
    - The product is deployed in a hosted multi-user mode.
  when:
    - Multiple humans supervise the same factory instance.
  then:
    - The system retains a lightweight admin-versus-operator distinction without requiring a heavyweight enterprise permission model in the first version.

- id: architecture.factory_control_plane.scenario_operator_surfaces_use_canonical_repo_and_run_routes
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  given:
    - Managed repositories and governed runs already exist as the canonical control-plane records.
  when:
    - An operator opens workbench, repo detail, dashboard, or run detail.
  then:
    - The product resolves and presents canonical managed-repository and governed-run records directly.
    - Hybrid summary widgets may appear inside those routes so long as they continue to present managed-repository and governed-run state from product-owned records instead of introducing a parallel browser truth lane.

```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.factory_control_plane.md
  covers:
    - architecture.factory_control_plane.product_is_governed_software_factory
    - architecture.factory_control_plane.durable_control_loop_normalizes_demand_into_work
    - architecture.factory_control_plane.repo_native_state_layers_inform_control_plane
    - architecture.factory_control_plane.lightweight_hosted_multi_user_posture

- kind: source_file
  target: .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  covers:
    - architecture.factory_control_plane.source_repo_and_managed_repo_are_primary_repo_objects
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
    - architecture.factory_control_plane.compatibility_repo_resolution_uses_explicit_control_plane_actors

- kind: source_file
  target: .spec/decisions/jido_code.internal_domain_and_execution_canonicalization.md
  covers:
    - architecture.factory_control_plane.internal_repo_loaders_use_canonical_repo_graph

- kind: source_file
  target: .spec/decisions/jido_code.runtime_evidence_posture_and_rollout_convergence.md
  covers:
    - architecture.factory_control_plane.runtime_overlay_preserves_product_truth

- kind: source_file
  target: .spec/decisions/jido_code.source_code_graph_product_adoption.md
  covers:
    - architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane

- kind: source_file
  target: lib/jido_code/workbench/project_semantic_inspection.ex
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
    - architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane

- kind: source_file
  target: lib/jido_code/source_code_graph/governed_adoption.ex
  covers:
    - architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane

- kind: source_file
  target: lib/jido_code/governance/runtime_evidence_feed.ex
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
    - architecture.factory_control_plane.runtime_overlay_preserves_product_truth

- kind: source_file
  target: test/jido_code/governance/runtime_evidence_feed_test.exs
  covers:
    - architecture.factory_control_plane.runtime_overlay_preserves_product_truth

- kind: source_file
  target: test/jido_code_web/live/dashboard_live_test.exs
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

- kind: source_file
  target: test/jido_code_web/live/phase_eleven_integration_test.exs
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

- kind: source_file
  target: test/jido_code_web/live/phase_twenty_five_integration_test.exs
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
    - architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane

- kind: source_file
  target: test/jido_code/phase_twenty_six_integration_test.exs
  covers:
    - architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane

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
  target: lib/jido_code/control/source_repo.ex
  covers:
    - architecture.factory_control_plane.compatibility_repo_resolution_uses_explicit_control_plane_actors

- kind: source_file
  target: lib/jido_code/workbench/project_detail.ex
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

- kind: source_file
  target: lib/jido_code/orchestration/run_summary_feed.ex
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

- kind: source_file
  target: lib/jido_code_web/live/DashboardRunSummaryWidget.vue
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records

```
