# VSM Recursion

This subject defines how `Jido.Code` applies Stafford Beer's recursive Viable System
Model to the software factory and to managed repositories.

```spec-meta
id: architecture.vsm_recursion
kind: policy
status: active
summary: Jido.Code models the factory instance and each ManagedRepo as recursive viable systems, while treating WorkItem and Run as operational records unless explicitly promoted to lower-level viable subsystems.
decisions:
  - jido_code.vsm_recursion_and_scope
surface:
  - .spec/decisions/jido_code.vsm_recursion_and_scope.md
```

## Requirements

```spec-requirements
- id: architecture.vsm_recursion.factory_is_viable_system
  statement: Jido.Code shall model the factory instance as a viable system whose primary operational units are ManagedRepo records.
  priority: must
  stability: evolving

- id: architecture.vsm_recursion.managed_repo_is_viable_system
  statement: Each ManagedRepo shall be treated as a recursive viable system with explicit operational, coordination, control, intelligence, and policy responsibilities.
  priority: must
  stability: evolving

- id: architecture.vsm_recursion.repo_system1_scope
  statement: ManagedRepo System 1 shall be expressed through operational work loops represented by WorkItem categories and executed through Run records.
  priority: must
  stability: evolving

- id: architecture.vsm_recursion.work_items_not_default_vsm
  statement: WorkItem and Run shall be treated as operational records rather than full viable systems unless they are explicitly promoted through a lower-level viability rule.
  priority: must
  stability: stable

- id: architecture.vsm_recursion.promotion_rule_defined
  statement: The architecture shall define the conditions under which a lower-level work unit may be promoted into its own recursive viable subsystem.
  priority: must
  stability: evolving

- id: architecture.vsm_recursion.algedonic_escalation
  statement: Viability-threatening conditions shall support direct escalation from lower levels to higher policy levels without waiting for normal queue progression.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.vsm_recursion.scenario.factory_supervises_repos
  covers:
    - architecture.vsm_recursion.factory_is_viable_system
    - architecture.vsm_recursion.managed_repo_is_viable_system
  given:
    - The factory is supervising multiple managed repositories.
  when:
    - Operators reason about capacity, policy, and cross-repo demand.
  then:
    - ManagedRepo units are treated as the factory's operational subsystems rather than as unrelated records.

- id: architecture.vsm_recursion.scenario_repo_turns_demand_into_work
  covers:
    - architecture.vsm_recursion.managed_repo_is_viable_system
    - architecture.vsm_recursion.repo_system1_scope
  given:
    - A managed repository receives new demand from intake or observation.
  when:
    - The repository orchestrator assesses that demand and creates work.
  then:
    - WorkItem and Run operate inside the repo's System 1 scope while coordination, control, and policy remain explicit at the repo level.

- id: architecture.vsm_recursion.scenario_work_packet_not_overmodeled
  covers:
    - architecture.vsm_recursion.work_items_not_default_vsm
    - architecture.vsm_recursion.promotion_rule_defined
  given:
    - A single work item or run is created for routine repository work.
  when:
    - The architecture classifies its control scope.
  then:
    - The work packet remains an operational record unless it has persistent identity, bounded mission, its own coordination needs, its own feedback loop, and distinct policy constraints.

- id: architecture.vsm_recursion.scenario_viability_threat_bypasses_normal_flow
  covers:
    - architecture.vsm_recursion.algedonic_escalation
  given:
    - A viability-threatening condition appears inside a managed repository, whether from repo-native posture, governed evidence, or another managed signal entering the repo's control loop.
  when:
    - Normal queue processing would be too slow or too noisy to preserve control.
  then:
    - The condition can bypass the normal queue and escalate directly to higher policy authority.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.vsm_recursion_and_scope.md
  covers:
    - architecture.vsm_recursion.factory_is_viable_system
    - architecture.vsm_recursion.managed_repo_is_viable_system
    - architecture.vsm_recursion.repo_system1_scope
    - architecture.vsm_recursion.work_items_not_default_vsm
    - architecture.vsm_recursion.promotion_rule_defined
    - architecture.vsm_recursion.algedonic_escalation

- kind: source_file
  target: lib/jido_code/governance/posture_bridge.ex
  covers:
    - architecture.vsm_recursion.algedonic_escalation

- kind: source_file
  target: test/jido_code/governance/policy_bridge_test.exs
  covers:
    - architecture.vsm_recursion.algedonic_escalation

- kind: source_file
  target: test/jido_code/governance/phase_five_integration_test.exs
  covers:
    - architecture.vsm_recursion.algedonic_escalation
```
