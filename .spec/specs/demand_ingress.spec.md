# Demand Ingress

This subject defines how `Jido.Code` captures inbound repository and operator
demand into durable control-plane ingress records before downstream planning or
execution begins.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.demand_ingress
kind: feature
status: active
summary: Jido.Code normalizes verified GitHub demand and operator-triggered requests into durable `ExternalObject`, `Observation`, and `Intake` records that preserve repo correlation, actor attribution, and source metadata before downstream work synthesis begins, while letting downstream posture refresh remain tied to that same durable ingress path.
decisions:
  - jido_code.namespace_and_control_naming
  - jido_code.factory_control_plane_and_runtime_overlay
surface:
  - lib/jido_code/operations.ex
  - lib/jido_code/operations/external_object.ex
  - lib/jido_code/operations/observation.ex
  - lib/jido_code/operations/intake.ex
  - lib/jido_code/operations/ingress.ex
  - lib/jido_code/conversations/ingress.ex
  - lib/jido_code/github/webhook_pipeline.ex
  - lib/jido_code/setup/project_import.ex
  - lib/jido_code/workbench/fix_workflow_kickoff.ex
  - lib/jido_code/workbench/issue_triage_workflow_kickoff.ex
  - lib/jido_code/workbench/project_detail_workflow_kickoff.ex
  - priv/repo/migrations/20260330183000_add_operations_ingress_resources.exs
  - test/jido_code/conversations/ingress_test.exs
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

- id: architecture.demand_ingress.normalized_ingress_persists_requested_by_actor_identity
  statement: Normalized intake source metadata shall persist requested-by actor identifiers and stable contact fields so downstream synthesis, posture, and audit flows can correlate the originating actor without depending on transient entrypoint structs.
  priority: must
  stability: evolving

- id: architecture.demand_ingress.entrypoint_policy_metadata_preserved
  statement: Ingress entrypoints that can launch governed runs shall preserve repo-governance approval or review-policy metadata in their normalized source metadata so downstream execution and review behavior remains correlated with the originating intake or webhook.
  priority: should
  stability: evolving

- id: architecture.demand_ingress.conversation_turns_become_durable_intake
  statement: Coding conversation turns shall enter the same managed-repository control loop by normalizing into durable `Intake`, `Event`, `Assessment`, and `WorkItem` records instead of bypassing the ingress layer as transient chat state.
  priority: must
  stability: evolving

- id: architecture.demand_ingress.conversation_turns_preserve_session_and_correlation_context
  statement: Conversation ingress shall preserve actor, conversation or session identity, request, correlation, workspace, and repository context across normalized intake and downstream work records.
  priority: must
  stability: evolving

- id: architecture.demand_ingress.conversation_turns_distinguish_new_work_from_steering
  statement: Conversation ingress shall distinguish brand-new work demand from explicit steering of an existing work item so the control loop can update an existing record when the turn targets one.
  priority: must
  stability: evolving

- id: architecture.demand_ingress.trusted_ingress_uses_explicit_actor_classes
  statement: GitHub webhook, setup import, and other trusted ingress paths shall preserve their normalized correlation through explicit operator or external-ingress actor classes instead of anonymous trusted persistence shortcuts.
  priority: must
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
    - architecture.demand_ingress.trusted_ingress_uses_explicit_actor_classes
  given:
    - An operator triggers project import or a workbench workflow kickoff for a tracked repository.
  when:
    - The request enters the factory through the product surface.
  then:
    - The request is recorded as a durable `Intake` linked to the managed repository before execution-specific launcher behavior continues.
    - Any downstream posture refresh remains coupled to the managed-repository ingress path rather than running as a separate out-of-band feature hook.
    - The persisted ingress path keeps explicit operator or machine actor attribution instead of relying on anonymous trusted writes.

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

- id: architecture.demand_ingress.scenario_conversation_turn_becomes_durable_work_input
  covers:
    - architecture.demand_ingress.conversation_turns_become_durable_intake
    - architecture.demand_ingress.conversation_turns_preserve_session_and_correlation_context
    - architecture.demand_ingress.conversation_turns_distinguish_new_work_from_steering
  given:
    - A managed-repository conversation is active for a coding-oriented operator turn.
  when:
    - The product normalizes that turn into ingress records.
  then:
    - The turn becomes durable intake, preserves conversation and tracing context, and either creates new work or steers the targeted work item instead of remaining isolated chat-only state.
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
    - architecture.demand_ingress.normalized_ingress_persists_requested_by_actor_identity
    - architecture.demand_ingress.trusted_ingress_uses_explicit_actor_classes

- kind: source_file
  target: lib/jido_code/conversations/ingress.ex
  covers:
    - architecture.demand_ingress.conversation_turns_become_durable_intake
    - architecture.demand_ingress.conversation_turns_preserve_session_and_correlation_context
    - architecture.demand_ingress.conversation_turns_distinguish_new_work_from_steering

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

- kind: source_file
  target: test/jido_code/conversations/ingress_test.exs
  covers:
    - architecture.demand_ingress.conversation_turns_become_durable_intake
    - architecture.demand_ingress.conversation_turns_preserve_session_and_correlation_context
    - architecture.demand_ingress.conversation_turns_distinguish_new_work_from_steering

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
    - architecture.demand_ingress.trusted_ingress_uses_explicit_actor_classes

- kind: source_file
  target: lib/jido_code/setup/project_import.ex
  covers:
    - architecture.demand_ingress.trusted_ingress_uses_explicit_actor_classes

- kind: source_file
  target: lib/jido_code/workbench/issue_triage_workflow_kickoff.ex
  covers:
    - architecture.demand_ingress.entrypoint_policy_metadata_preserved

- kind: source_file
  target: test/jido_code_web/controllers/github_webhook_controller_test.exs
  covers:
    - architecture.demand_ingress.trusted_ingress_uses_explicit_actor_classes
```
