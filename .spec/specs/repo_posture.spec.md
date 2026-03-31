# Repo Posture

This subject defines how repo-native state becomes explainable posture and trust
records for managed repositories.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.repo_posture
kind: feature
status: active
summary: Jido.Code observes repo-native `.spec/` and optional Git-native planning state as durable signals, then projects explainable `RepoPosture` and `PostureCheck` records that stay linked to observations, assessments, and evidence instead of hiding trust state inside opaque service logic.
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
surface:
  - lib/jido_code/operations/repo_native_state.ex
  - lib/jido_code/governance/repo_posture.ex
  - lib/jido_code/governance/posture_check.ex
  - lib/jido_code/governance/posture_bridge.ex
  - lib/jido_code/governance/policy_bridge.ex
  - lib/jido_code/control/repo_bridge.ex
  - lib/jido_code/operations/ingress.ex
  - lib/jido_code/governance/run_governance_bridge.ex
  - priv/repo/migrations/20260331143000_add_repo_posture_records.exs
  - priv/repo/migrations/20260331153000_add_repo_posture_supervision_fields.exs
  - test/jido_code/operations/repo_native_state_test.exs
  - test/jido_code/governance/posture_bridge_test.exs
  - test/jido_code/governance/policy_bridge_test.exs
  - test/jido_code/governance/phase_five_integration_test.exs
```

## Requirements

```spec-requirements
- id: architecture.repo_posture.repo_native_observations_capture_current_truth_signals
  statement: When a managed repository has repo-native `.spec/` state and optional Git-native planning files available, Jido.Code shall observe those signals durably without re-storing the full repo-native files as product truth.
  priority: must
  stability: evolving

- id: architecture.repo_posture.repo_posture_summarizes_trust_dimensions
  statement: Jido.Code shall project a durable `RepoPosture` record per managed repository that summarizes trust and readiness dimensions including execution readiness, validation reliability, review burden, drift rate, recovery resilience, and requirements confidence.
  priority: must
  stability: evolving

- id: architecture.repo_posture.posture_checks_preserve_explainable_links
  statement: Jido.Code shall preserve explicit `PostureCheck` records for each contributing posture dimension, including stable links back to relevant `Observation`, `Assessment`, and `Evidence` records when those signals contributed to the posture value.
  priority: must
  stability: evolving

- id: architecture.repo_posture.supervision_modes_are_explicit_and_reversible
  statement: Jido.Code shall translate posture into explicit managed-repository supervision modes of `directed`, `guided`, `delegated`, and `autonomous`, with downgrade behavior remaining explicit when confidence drops.
  priority: must
  stability: evolving

- id: architecture.repo_posture.algedonic_escalation_is_typed_and_evidence_rich
  statement: Viability-threatening posture conditions shall create typed escalation state and explainable posture checks that show why normal flow was bypassed, rather than relying on implicit or ad hoc escalation rules.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.repo_posture.scenario_repo_native_signals_become_observed_inputs
  covers:
    - architecture.repo_posture.repo_native_observations_capture_current_truth_signals
  given:
    - A managed repository has authored `.spec/` state and may also keep optional Beadwork files.
  when:
    - The control plane synchronizes repo-native state.
  then:
    - Durable repo-native observations are recorded for the available signal layers while the Git-traveling files remain the source of truth.

- id: architecture.repo_posture.scenario_posture_updates_stay_explainable
  covers:
    - architecture.repo_posture.repo_posture_summarizes_trust_dimensions
    - architecture.repo_posture.posture_checks_preserve_explainable_links
  given:
    - Repo-native observations, recent assessments, and governed run evidence exist for a managed repository.
  when:
    - The control plane refreshes posture.
  then:
    - The repository receives an updated posture summary and explicit dimension checks whose links explain which observations, assessments, and evidence shaped the posture.

- id: architecture.repo_posture.scenario_supervision_progression_and_escalation
  covers:
    - architecture.repo_posture.supervision_modes_are_explicit_and_reversible
    - architecture.repo_posture.algedonic_escalation_is_typed_and_evidence_rich
  given:
    - Repo posture has enough signal to classify the managed repository as either stable or viability-threatening.
  when:
    - Effective repo governance policy is derived from posture.
  then:
    - Stable repositories may progress to delegated or autonomous supervision while viability threats downgrade to directed supervision with typed algedonic escalation evidence.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/operations/repo_native_state.ex
  covers:
    - architecture.repo_posture.repo_native_observations_capture_current_truth_signals

- kind: source_file
  target: lib/jido_code/governance/repo_posture.ex
  covers:
    - architecture.repo_posture.repo_posture_summarizes_trust_dimensions

- kind: source_file
  target: lib/jido_code/governance/posture_check.ex
  covers:
    - architecture.repo_posture.posture_checks_preserve_explainable_links

- kind: source_file
  target: lib/jido_code/governance/posture_bridge.ex
  covers:
    - architecture.repo_posture.repo_posture_summarizes_trust_dimensions
    - architecture.repo_posture.posture_checks_preserve_explainable_links
    - architecture.repo_posture.supervision_modes_are_explicit_and_reversible
    - architecture.repo_posture.algedonic_escalation_is_typed_and_evidence_rich

- kind: source_file
  target: lib/jido_code/governance/policy_bridge.ex
  covers:
    - architecture.repo_posture.supervision_modes_are_explicit_and_reversible
    - architecture.repo_posture.algedonic_escalation_is_typed_and_evidence_rich

- kind: source_file
  target: test/jido_code/operations/repo_native_state_test.exs
  covers:
    - architecture.repo_posture.repo_native_observations_capture_current_truth_signals

- kind: source_file
  target: test/jido_code/governance/posture_bridge_test.exs
  covers:
    - architecture.repo_posture.repo_posture_summarizes_trust_dimensions
    - architecture.repo_posture.posture_checks_preserve_explainable_links

- kind: source_file
  target: test/jido_code/governance/policy_bridge_test.exs
  covers:
    - architecture.repo_posture.supervision_modes_are_explicit_and_reversible
    - architecture.repo_posture.algedonic_escalation_is_typed_and_evidence_rich

- kind: source_file
  target: test/jido_code/governance/phase_five_integration_test.exs
  covers:
    - architecture.repo_posture.repo_native_observations_capture_current_truth_signals
    - architecture.repo_posture.repo_posture_summarizes_trust_dimensions
    - architecture.repo_posture.posture_checks_preserve_explainable_links
    - architecture.repo_posture.supervision_modes_are_explicit_and_reversible
    - architecture.repo_posture.algedonic_escalation_is_typed_and_evidence_rich
```
