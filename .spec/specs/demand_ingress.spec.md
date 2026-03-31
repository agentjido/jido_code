# Demand Ingress

This subject defines how `Jido.Code` captures inbound repository and operator
demand into durable control-plane ingress records before downstream planning or
execution begins.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.demand_ingress
kind: feature
status: active
summary: Jido.Code normalizes verified GitHub demand and operator-triggered requests into durable `ExternalObject`, `Observation`, and `Intake` records that preserve repo correlation, actor attribution, and source metadata before downstream work synthesis begins.
decisions:
  - jido_code.namespace_and_control_naming
  - jido_code.factory_control_plane_and_runtime_overlay
surface:
  - lib/jido_code/operations.ex
  - lib/jido_code/operations/external_object.ex
  - lib/jido_code/operations/observation.ex
  - lib/jido_code/operations/intake.ex
  - lib/jido_code/operations/ingress.ex
  - lib/jido_code/github/webhook_pipeline.ex
  - lib/jido_code/setup/project_import.ex
  - lib/jido_code/workbench/fix_workflow_kickoff.ex
  - lib/jido_code/workbench/issue_triage_workflow_kickoff.ex
  - lib/jido_code/workbench/project_detail_workflow_kickoff.ex
  - priv/repo/migrations/20260330183000_add_operations_ingress_resources.exs
  - test/jido_code/operations/demand_ingress_test.exs
  - test/jido_code/operations/phase_two_integration_test.exs
```

## Requirements

```spec-requirements
- id: architecture.demand_ingress.external_object_tracks_repo_external_entities
  statement: Jido.Code shall persist durable `ExternalObject` records for tracked GitHub repository entities such as issues, pull requests, and repository references so later control-plane layers can reason about stable external identities instead of transient webhook payloads.
  priority: must
  stability: evolving

- id: architecture.demand_ingress.observation_captures_repo_and_system_facts
  statement: Jido.Code shall capture verified external or system-derived facts as durable `Observation` records tied to managed-repository context before downstream planning or execution logic interprets them.
  priority: must
  stability: evolving

- id: architecture.demand_ingress.intake_captures_operator_and_trusted_requests
  statement: Jido.Code shall normalize operator-originated and trusted-ingress requests into durable `Intake` records instead of letting setup or workbench actions bypass the factory control loop.
  priority: must
  stability: evolving

- id: architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation
  statement: Normalized ingress records shall preserve source metadata, actor attribution, and managed-repository or project correlation continuity across webhook, setup, and workbench entrypoints.
  priority: must
  stability: evolving

- id: architecture.demand_ingress.entrypoint_policy_metadata_preserved
  statement: Ingress entrypoints that can launch governed runs shall preserve repo-governance approval or review-policy metadata in their normalized source metadata so downstream execution and review behavior remains correlated with the originating intake or webhook.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.demand_ingress.scenario_github_issue_webhook_becomes_external_object_and_observation
  covers:
    - architecture.demand_ingress.external_object_tracks_repo_external_entities
    - architecture.demand_ingress.observation_captures_repo_and_system_facts
    - architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation
  given:
    - A verified GitHub webhook delivery references a tracked repository and issue.
  when:
    - The webhook pipeline normalizes the delivery into the control plane.
  then:
    - A durable `ExternalObject` and `Observation` are recorded with managed-repository correlation and ingress attribution before downstream workflow dispatch continues.

- id: architecture.demand_ingress.scenario_operator_setup_or_workbench_action_becomes_intake
  covers:
    - architecture.demand_ingress.intake_captures_operator_and_trusted_requests
    - architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation
    - architecture.demand_ingress.entrypoint_policy_metadata_preserved
  given:
    - An operator triggers project import or a workbench workflow kickoff for a tracked repository.
  when:
    - The request enters the factory through the product surface.
  then:
    - The request is recorded as a durable `Intake` linked to the managed repository before execution-specific launcher behavior continues.

- id: architecture.demand_ingress.scenario_repo_governance_policy_flows_through_launch_entrypoints
  covers:
    - architecture.demand_ingress.entrypoint_policy_metadata_preserved
    - architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation
  given:
    - A managed repository has repo-governance review policy that affects issue-triage approval behavior.
  when:
    - A webhook or workbench entrypoint prepares downstream workflow launch metadata.
  then:
    - The normalized launch metadata preserves the effective approval or review policy alongside the ingress correlation context.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/operations/external_object.ex
  covers:
    - architecture.demand_ingress.external_object_tracks_repo_external_entities

- kind: source_file
  target: lib/jido_code/operations/observation.ex
  covers:
    - architecture.demand_ingress.observation_captures_repo_and_system_facts

- kind: source_file
  target: lib/jido_code/operations/intake.ex
  covers:
    - architecture.demand_ingress.intake_captures_operator_and_trusted_requests

- kind: source_file
  target: lib/jido_code/operations/ingress.ex
  covers:
    - architecture.demand_ingress.external_object_tracks_repo_external_entities
    - architecture.demand_ingress.observation_captures_repo_and_system_facts
    - architecture.demand_ingress.intake_captures_operator_and_trusted_requests
    - architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation

- kind: source_file
  target: test/jido_code/operations/demand_ingress_test.exs
  covers:
    - architecture.demand_ingress.external_object_tracks_repo_external_entities
    - architecture.demand_ingress.observation_captures_repo_and_system_facts
    - architecture.demand_ingress.intake_captures_operator_and_trusted_requests
    - architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation

- kind: source_file
  target: test/jido_code/operations/phase_two_integration_test.exs
  covers:
    - architecture.demand_ingress.external_object_tracks_repo_external_entities
    - architecture.demand_ingress.observation_captures_repo_and_system_facts
    - architecture.demand_ingress.intake_captures_operator_and_trusted_requests
    - architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation

- kind: command
  target: mix test test/jido_code/operations/demand_ingress_test.exs
  covers:
    - architecture.demand_ingress.external_object_tracks_repo_external_entities
    - architecture.demand_ingress.observation_captures_repo_and_system_facts
    - architecture.demand_ingress.intake_captures_operator_and_trusted_requests
    - architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation

- kind: source_file
  target: lib/jido_code/github/webhook_pipeline.ex
  covers:
    - architecture.demand_ingress.entrypoint_policy_metadata_preserved

- kind: source_file
  target: lib/jido_code/workbench/issue_triage_workflow_kickoff.ex
  covers:
    - architecture.demand_ingress.entrypoint_policy_metadata_preserved
```
