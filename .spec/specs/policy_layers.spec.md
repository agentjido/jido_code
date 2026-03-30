# Policy Layers

This subject defines the layered policy model for `Jido.Code`.

```spec-meta
id: architecture.policy_layers
kind: policy
status: active
summary: "Jido.Code uses three interlocking policy layers: repository governance policy in product records, Ash policy as a first-class data-plane authority membrane, and `jido_os` runtime policy for session and turn capability admission."
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
surface:
  - .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  - lib/jido_code/accounts/user.ex
  - lib/jido_code/control/actor.ex
  - lib/jido_code/control/checks/actor_class_in.ex
  - lib/jido_code/control/source_repo.ex
  - lib/jido_code/control/managed_repo.ex
  - lib/jido_code/governance.ex
  - lib/jido_code/governance/review_policy.ex
  - lib/jido_code/governance/policy_set.ex
  - lib/jido_code/governance/policy_bridge.ex
  - lib/jido_code/projects/project.ex
  - lib/jido_code/jido_os_runtime.ex
  - priv/repo/migrations/20260330161500_add_governance_policy_sets.exs
```

## Requirements

```spec-requirements
- id: architecture.policy_layers.repository_governance_policy_is_repo_control_layer
  statement: Repository behavior, approval thresholds, autonomy limits, and review expectations shall be governed through repo-level governance objects such as `PolicySet` and adjacent posture or review rules.
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
  statement: The architecture shall model explicit human and machine actor classes for data-plane authorization, including at least admin, operator, factory-system, managed-repo-orchestrator, run-worker, and external-ingress actors.
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
```
