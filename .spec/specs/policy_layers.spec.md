# Policy Layers

This subject defines the layered policy model for `Jido.Code`.

```spec-meta
id: architecture.policy_layers
kind: policy
status: active
summary: "Jido.Code uses three interlocking policy layers: repository governance policy in product records, Ash policy as a first-class data-plane authority membrane, and `jido_os` runtime policy for session and turn capability admission, with per-project source identity and repo-native observations feeding repo governance independently from the global deployment-mode hint."
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.jido_os_public_turn_runtime_adoption
surface:
  - .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  - .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  - lib/jido_code/accounts/user.ex
  - lib/jido_code/control/actor.ex
  - lib/jido_code/control/checks/actor_class_in.ex
  - lib/jido_code/conversations/ingress.ex
  - lib/jido_code/conversations/policy.ex
  - lib/jido_code/control/source_repo.ex
  - lib/jido_code/control/managed_repo.ex
  - lib/jido_code/governance.ex
  - lib/jido_code/governance/change_request.ex
  - lib/jido_code/governance/decision.ex
  - lib/jido_code/governance/evidence.ex
  - lib/jido_code/governance/run_governance_bridge.ex
  - lib/jido_code/governance/review_policy.ex
  - lib/jido_code/governance/policy_set.ex
  - lib/jido_code/governance/policy_bridge.ex
  - lib/jido_code/governance/repo_posture.ex
  - lib/jido_code/governance/posture_check.ex
  - lib/jido_code/governance/posture_bridge.ex
  - lib/jido_code/github/webhook_pipeline.ex
  - lib/jido_code/operations/event.ex
  - lib/jido_code/operations/assessment.ex
  - lib/jido_code/operations/external_object.ex
  - lib/jido_code/operations/observation.ex
  - lib/jido_code/operations/repo_native_state.ex
  - lib/jido_code/operations/intake.ex
  - lib/jido_code/operations/ingress.ex
  - lib/jido_code/operations/synthesis.ex
  - lib/jido_code/operations/work_item.ex
  - lib/jido_code/operations/work_synthesis.ex
  - lib/jido_code/projects/project.ex
  - lib/jido_code/jido_os_runtime.ex
  - lib/jido_code/workbench/issue_triage_workflow_kickoff.ex
  - test/jido_code/conversations/phase_four_integration_test.exs
  - priv/repo/migrations/20260330161500_add_governance_policy_sets.exs
  - priv/repo/migrations/20260330183000_add_operations_ingress_resources.exs
  - priv/repo/migrations/20260330193000_add_operations_event_and_assessment_resources.exs
  - priv/repo/migrations/20260330195000_add_operations_work_items.exs
  - priv/repo/migrations/20260331113000_add_run_governance_records.exs
  - priv/repo/migrations/20260331143000_add_repo_posture_records.exs
```

## Requirements

```spec-requirements
- id: architecture.policy_layers.repository_governance_policy_is_repo_control_layer
  statement: Repository behavior, approval thresholds, autonomy limits, review expectations, and per-project source identity shall be governed through repo-level governance objects such as `PolicySet` and adjacent posture or review rules instead of being inferred from the global deployment mode.
  priority: must
  stability: evolving

- id: architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane
  statement: Ash policy shall be treated as a first-class control-plane membrane for who can read or mutate product resources rather than as a thin authentication wrapper.
  priority: must
  stability: evolving

- id: architecture.policy_layers.runtime_policy_governs_session_and_turn_capability
  statement: `jido_os` runtime policy shall govern what sessions, turns, and runtime execution paths are admitted or denied at the interaction layer.
  priority: must
  stability: evolving

- id: architecture.policy_layers.policy_layers_interlock_without_collapsing
  statement: Repository governance policy, Ash data-plane policy, and `jido_os` runtime policy shall interlock but remain distinct instead of collapsing into one merged policy system.
  priority: must
  stability: evolving

- id: architecture.policy_layers.explicit_human_and_machine_actor_classes
  statement: The architecture shall model explicit human and machine actor classes for data-plane authorization, including at least admin, operator, factory-system, managed-repo-orchestrator, run-worker, and external-ingress actors, with bootstrap administrators and later member accounts remaining explicit local-user actor roles instead of implicit side effects of authentication.
  priority: must
  stability: evolving

- id: architecture.policy_layers.repo_posture_can_shape_effective_review_policy
  statement: Repo-governance posture may narrow or relax the effective review policy used by product entrypoints, while the configured repo policy remains separately visible as source state instead of being overwritten.
  priority: must
  stability: evolving

- id: architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context
  statement: Transitional repo, workflow, and GitHub-ingress surfaces shall fail closed without explicit human or machine actor context in product code paths, and trusted machine entrypoints shall use named actor classes instead of anonymous authorization bypass mutations.
  priority: must
  stability: evolving

- id: architecture.policy_layers.public_turn_materialization_preserves_layered_policy
  statement: When `jido_code` adopts public `jido_os` turn replay, review, and terminal materialization, product-side ingress and Ash authorization shall remain explicit before runtime turn start, and bounded runtime outputs shall only re-enter governed product records through actor-aware product bridges instead of bypassing repo governance or data-plane policy.
  priority: must
  stability: evolving

- id: architecture.policy_layers.operator_surfaces_propagate_current_actor_for_repo_mutations
  statement: Operator-facing settings flows and source-repo identity upserts shall propagate the current operator or system actor into Ash mutations, and external-ingress actors shall remain denied for human-only repo identity mutation paths.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.policy_layers.scenario_repo_action_crosses_policy_layers
  covers:
    - architecture.policy_layers.repository_governance_policy_is_repo_control_layer
    - architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane
    - architecture.policy_layers.runtime_policy_governs_session_and_turn_capability
    - architecture.policy_layers.policy_layers_interlock_without_collapsing
    - architecture.policy_layers.explicit_human_and_machine_actor_classes
  given:
    - A managed repository request arrives through a product-facing or runtime-facing path.
  when:
    - The system decides whether work may be created, executed, or exposed.
  then:
    - Repo governance, Ash data-plane authorization, and runtime capability policy each contribute to the decision through their own boundary rather than being treated as one undifferentiated rule set.
    - Repository source identity remains a repo-governance concern instead of a shortcut derived from deployment flavor.
    - Repo-native `.spec/` and optional Git-native planning observations may inform repo-governance choices without bypassing Ash-backed durable records or runtime capability admission.
    - Effective review behavior may be tightened or relaxed by repo posture while the configured policy remains explicit repo-governance state.
    - Conversation-triggered work follows the same layered policy path instead of bypassing Ash authorization or repo governance because it originated in chat.
    - Legacy project, workflow-run, and GitHub-ingress compatibility paths still carry explicit operator, run-worker, or external-ingress actor context rather than mutating data through anonymous trusted bypasses.

- id: architecture.policy_layers.scenario_public_turn_replay_and_governance_stay_policy_bound
  covers:
    - architecture.policy_layers.runtime_policy_governs_session_and_turn_capability
    - architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context
    - architecture.policy_layers.public_turn_materialization_preserves_layered_policy
  given:
    - A coding turn is started through the product boundary and runtime turn capability is admitted by `jido_os`.
  when:
    - The product replays turn progress and projects terminal outputs into governed records.
  then:
    - Runtime capability policy remains the authority for turn execution, while actor-aware product bridges preserve repo governance and Ash data-plane policy when those bounded outputs become product truth.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  covers:
    - architecture.policy_layers.repository_governance_policy_is_repo_control_layer
    - architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane
    - architecture.policy_layers.runtime_policy_governs_session_and_turn_capability
    - architecture.policy_layers.policy_layers_interlock_without_collapsing
    - architecture.policy_layers.explicit_human_and_machine_actor_classes

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  covers:
    - architecture.policy_layers.public_turn_materialization_preserves_layered_policy

- kind: source_file
  target: lib/jido_code/conversations/policy.ex
  covers:
    - architecture.policy_layers.repository_governance_policy_is_repo_control_layer
    - architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane
    - architecture.policy_layers.policy_layers_interlock_without_collapsing

- kind: source_file
  target: lib/jido_code/governance/policy_bridge.ex
  covers:
    - architecture.policy_layers.repository_governance_policy_is_repo_control_layer
    - architecture.policy_layers.policy_layers_interlock_without_collapsing
    - architecture.policy_layers.repo_posture_can_shape_effective_review_policy

- kind: source_file
  target: lib/jido_code/control/actor.ex
  covers:
    - architecture.policy_layers.explicit_human_and_machine_actor_classes
    - architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context

- kind: source_file
  target: lib/jido_code/control/checks/actor_class_in.ex
  covers:
    - architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane
    - architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context

- kind: source_file
  target: lib/jido_code/control/source_repo.ex
  covers:
    - architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context
    - architecture.policy_layers.operator_surfaces_propagate_current_actor_for_repo_mutations

- kind: source_file
  target: lib/jido_code_web/live/settings_live.ex
  covers:
    - architecture.policy_layers.operator_surfaces_propagate_current_actor_for_repo_mutations

- kind: source_file
  target: lib/jido_code/projects/project.ex
  covers:
    - architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane
    - architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context

- kind: source_file
  target: lib/jido_code/github/webhook_pipeline.ex
  covers:
    - architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context

- kind: source_file
  target: test/jido_code/conversations/phase_four_integration_test.exs
  covers:
    - architecture.policy_layers.repository_governance_policy_is_repo_control_layer
    - architecture.policy_layers.policy_layers_interlock_without_collapsing

- kind: source_file
  target: test/jido_code/governance/policy_set_test.exs
  covers:
    - architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context
    - architecture.policy_layers.operator_surfaces_propagate_current_actor_for_repo_mutations

- kind: source_file
  target: test/jido_code_web/live/csrf_protection_live_test.exs
  covers:
    - architecture.policy_layers.operator_surfaces_propagate_current_actor_for_repo_mutations

- kind: source_file
  target: test/jido_code/governance/policy_bridge_test.exs
  covers:
    - architecture.policy_layers.repository_governance_policy_is_repo_control_layer
    - architecture.policy_layers.repo_posture_can_shape_effective_review_policy

- kind: source_file
  target: test/jido_code/projects/project_test.exs
  covers:
    - architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context

- kind: source_file
  target: test/jido_code/control/phase_six_integration_test.exs
  covers:
    - architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context

- kind: source_file
  target: test/jido_code/conversations/phase_seven_integration_test.exs
  covers:
    - architecture.policy_layers.public_turn_materialization_preserves_layered_policy
```
