# Event And Assessment Synthesis

This subject defines how normalized ingress records become durable control-plane
meaning before work synthesis begins.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.event_assessment_synthesis
kind: feature
status: active
summary: Jido.Code derives durable `Event` and `Assessment` records from normalized ingress so verified external demand and trusted operator requests gain typed actionable meaning, repo correlation, and next-action guidance before work-item synthesis begins.
decisions:
  - jido_code.namespace_and_control_naming
  - jido_code.factory_control_plane_and_runtime_overlay
surface:
  - lib/jido_code/conversations/ingress.ex
  - lib/jido_code/operations/event.ex
  - lib/jido_code/operations/assessment.ex
  - lib/jido_code/operations/synthesis.ex
  - lib/jido_code/operations/repo_native_state.ex
  - lib/jido_code/operations/ingress.ex
  - priv/repo/migrations/20260330193000_add_operations_event_and_assessment_resources.exs
  - test/jido_code/operations/event_assessment_synthesis_test.exs
  - test/jido_code/operations/phase_two_integration_test.exs
  - test/jido_code/operations/repo_native_state_test.exs
```

## Requirements

```spec-requirements
- id: architecture.event_assessment_synthesis.event_records_derived_from_ingress
  statement: Jido.Code shall derive durable `Event` records from normalized `Observation` and `Intake` ingress records so actionable occurrences are stored as control-plane state instead of remaining feature-local interpretation.
  priority: must
  stability: evolving

- id: architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
  statement: Derived `Event` records shall preserve typed event categories, managed-repository correlation, and source-record linkage for later work synthesis and deduplication.
  priority: must
  stability: evolving

- id: architecture.event_assessment_synthesis.assessment_records_interpret_events
  statement: Jido.Code shall persist durable `Assessment` records above `Event` so the factory can record what an actionable occurrence means before work is created.
  priority: must
  stability: evolving

- id: architecture.event_assessment_synthesis.assessment_priority_and_next_action
  statement: Each synthesized `Assessment` shall capture priority, urgency, and recommended next action so downstream work creation can use explicit interpretation rather than implicit feature heuristics.
  priority: must
  stability: evolving

- id: architecture.event_assessment_synthesis.assessment_space_for_future_inputs
  statement: `Assessment` synthesis shall preserve structured space for future posture, policy, and repo-native state inputs to influence interpretation outcomes without changing the durable object model.
  priority: must
  stability: evolving

- id: architecture.event_assessment_synthesis.conversation_turn_context_shapes_assessment
  statement: When normalized ingress originates from a coding conversation turn, synthesized event and assessment records shall preserve session or conversation identity and distinguish new demand from explicit steering so downstream work synthesis can remain conversation-aware without becoming chat-local state.
  priority: must
  stability: evolving

- id: architecture.event_assessment_synthesis.repo_native_state_informs_assessment_inputs
  statement: When repo-native `.spec/` or optional Git-native planning observations are available for a managed repository, synthesized assessment inputs shall preserve a compact signal snapshot so later posture and planning decisions can remain explainable without duplicating repo-native state into Ash-backed truth.
  priority: must
  stability: evolving

- id: architecture.event_assessment_synthesis.assessment_preserves_ingress_actor_class_context
  statement: Event and assessment synthesis inputs shall preserve normalized ingress actor class attribution so downstream governance can explain whether demand originated from operator or machine entrypoints without re-reading raw ingress payloads.
  priority: should
  stability: evolving

- id: architecture.event_assessment_synthesis.correlation_prefers_persisted_requested_by_actor_identity
  statement: Event correlation and assessment metadata shall fall back to requested-by actor identity persisted in normalized intake source metadata when the direct requested-by envelope does not retain the original actor identifier.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.event_assessment_synthesis.scenario_verified_issue_signal_becomes_event_and_assessment
  covers:
    - architecture.event_assessment_synthesis.event_records_derived_from_ingress
    - architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
    - architecture.event_assessment_synthesis.assessment_records_interpret_events
    - architecture.event_assessment_synthesis.assessment_priority_and_next_action
  given:
    - A verified GitHub issue webhook has already been normalized into external-object and observation records.
  when:
    - The control plane synthesizes actionable meaning from that ingress.
  then:
    - A durable `Event` and `Assessment` are created with repo correlation, source linkage, and next-action guidance such as issue triage.

- id: architecture.event_assessment_synthesis.scenario_operator_request_becomes_actionable_interpretation
  covers:
    - architecture.event_assessment_synthesis.event_records_derived_from_ingress
    - architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
    - architecture.event_assessment_synthesis.assessment_records_interpret_events
    - architecture.event_assessment_synthesis.assessment_priority_and_next_action
    - architecture.event_assessment_synthesis.assessment_space_for_future_inputs
  given:
    - An operator request has already been normalized into a durable intake record.
  when:
    - The control plane synthesizes the request into actionable meaning.
  then:
    - A durable `Event` and `Assessment` are recorded with typed category, repo correlation, explicit priority and urgency, recommended next action, and preserved assessment inputs for future policy or posture signals.

- id: architecture.event_assessment_synthesis.scenario_conversation_turn_becomes_actionable_interpretation
  covers:
    - architecture.event_assessment_synthesis.event_records_derived_from_ingress
    - architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
    - architecture.event_assessment_synthesis.assessment_records_interpret_events
    - architecture.event_assessment_synthesis.assessment_priority_and_next_action
    - architecture.event_assessment_synthesis.conversation_turn_context_shapes_assessment
  given:
    - A coding-oriented conversation turn has already been normalized into intake.
  when:
    - The control plane synthesizes that turn into event and assessment meaning.
  then:
    - The resulting records preserve conversation identity, managed-repository correlation, and whether the turn created new work demand or steers an existing work item.

- id: architecture.event_assessment_synthesis.scenario_repo_native_state_enriches_assessment_inputs
  covers:
    - architecture.event_assessment_synthesis.assessment_space_for_future_inputs
    - architecture.event_assessment_synthesis.repo_native_state_informs_assessment_inputs
  given:
    - A managed repository has repo-native `.spec/` state and may also have optional Beadwork files already observed by the control plane.
  when:
    - New operator or conversation ingress is synthesized into an assessment.
  then:
    - The assessment inputs preserve a compact repo-native signal snapshot for later posture, planning, and review decisions without replacing the durable repo-native files.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/operations/event.ex
  covers:
    - architecture.event_assessment_synthesis.event_records_derived_from_ingress
    - architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved

- kind: source_file
  target: lib/jido_code/operations/assessment.ex
  covers:
    - architecture.event_assessment_synthesis.assessment_records_interpret_events
    - architecture.event_assessment_synthesis.assessment_priority_and_next_action
    - architecture.event_assessment_synthesis.assessment_space_for_future_inputs

- kind: source_file
  target: lib/jido_code/operations/synthesis.ex
  covers:
    - architecture.event_assessment_synthesis.event_records_derived_from_ingress
    - architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
    - architecture.event_assessment_synthesis.assessment_records_interpret_events
    - architecture.event_assessment_synthesis.assessment_priority_and_next_action
    - architecture.event_assessment_synthesis.assessment_space_for_future_inputs
    - architecture.event_assessment_synthesis.conversation_turn_context_shapes_assessment
    - architecture.event_assessment_synthesis.repo_native_state_informs_assessment_inputs
    - architecture.event_assessment_synthesis.correlation_prefers_persisted_requested_by_actor_identity

- kind: source_file
  target: lib/jido_code/operations/repo_native_state.ex
  covers:
    - architecture.event_assessment_synthesis.repo_native_state_informs_assessment_inputs

- kind: source_file
  target: lib/jido_code/operations/ingress.ex
  covers:
    - architecture.event_assessment_synthesis.assessment_preserves_ingress_actor_class_context

- kind: source_file
  target: test/jido_code/operations/event_assessment_synthesis_test.exs
  covers:
    - architecture.event_assessment_synthesis.event_records_derived_from_ingress
    - architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
    - architecture.event_assessment_synthesis.assessment_records_interpret_events
    - architecture.event_assessment_synthesis.assessment_priority_and_next_action
    - architecture.event_assessment_synthesis.assessment_space_for_future_inputs
    - architecture.event_assessment_synthesis.correlation_prefers_persisted_requested_by_actor_identity

- kind: source_file
  target: test/jido_code/operations/repo_native_state_test.exs
  covers:
    - architecture.event_assessment_synthesis.assessment_space_for_future_inputs
    - architecture.event_assessment_synthesis.repo_native_state_informs_assessment_inputs

- kind: source_file
  target: test/jido_code/operations/phase_two_integration_test.exs
  covers:
    - architecture.event_assessment_synthesis.event_records_derived_from_ingress
    - architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
    - architecture.event_assessment_synthesis.assessment_records_interpret_events
    - architecture.event_assessment_synthesis.assessment_priority_and_next_action

- kind: command
  target: mix test test/jido_code/operations/event_assessment_synthesis_test.exs
  covers:
    - architecture.event_assessment_synthesis.event_records_derived_from_ingress
    - architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
    - architecture.event_assessment_synthesis.assessment_records_interpret_events
    - architecture.event_assessment_synthesis.assessment_priority_and_next_action
    - architecture.event_assessment_synthesis.assessment_space_for_future_inputs
```
