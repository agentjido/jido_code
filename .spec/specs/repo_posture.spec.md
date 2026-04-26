# Repo Posture

<!-- current_truth.reconciled_with_branch: run-detail posture coverage continues to coexist with bounded memory context on canonical operator surfaces, and dashboard now keeps runtime and posture summaries inside a dedicated route-owned concern tab on the authenticated landing route. -->

This subject defines how repo-native state becomes explainable posture and trust
records for managed repositories.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.repo_posture
kind: feature
status: active
summary: Jido.Code observes repo-native `.spec/` and optional Git-native planning state as durable signals, then projects explainable `RepoPosture` and `PostureCheck` records that stay linked to observations, assessments, evidence, bounded dashboard and run-detail memory context, canonical managed-repository scope, and the authenticated dashboard's dedicated runtime and posture concern tab instead of hiding trust state inside opaque service logic.
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.internal_cleanup_and_ui_convergence_foundation
  - jido_code.runtime_evidence_posture_and_rollout_convergence
  - jido_code.dashboard_concern_tabs_and_overview_handoff
  - jido_code.operator_surface_managed_repo_and_governed_run_adoption
surface:
  - .spec/decisions/jido_code.dashboard_concern_tabs_and_overview_handoff.md
  - .spec/decisions/jido_code.runtime_evidence_posture_and_rollout_convergence.md
  - .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  - lib/jido_code/operations/repo_native_state.ex
  - lib/jido_code/governance/repo_posture.ex
  - lib/jido_code/governance/posture_check.ex
  - lib/jido_code/governance/posture_bridge.ex
  - lib/jido_code/governance/runtime_evidence_feed.ex
  - lib/jido_code/governance/policy_bridge.ex
  - lib/jido_code/control/repo_bridge.ex
  - lib/jido_code/orchestration/run_summary_feed.ex
  - lib/jido_code_web/components/operator_state_components.ex
  - lib/jido_code_web/live/dashboard_live.ex
  - lib/jido_code_web/live/DashboardRuntimePostureWidget.vue
  - lib/jido_code_web/live/run_detail_live.ex
  - lib/jido_code/operations/ingress.ex
  - lib/jido_code/governance/run_governance_bridge.ex
  - priv/repo/migrations/20260331143000_add_repo_posture_records.exs
  - priv/repo/migrations/20260331153000_add_repo_posture_supervision_fields.exs
  - test/jido_code/operations/repo_native_state_test.exs
  - test/jido_code/governance/posture_bridge_test.exs
  - test/jido_code/governance/runtime_capability_bridge_test.exs
  - test/jido_code/governance/runtime_evidence_feed_test.exs
  - test/jido_code/governance/policy_bridge_test.exs
  - test/jido_code/governance/phase_five_integration_test.exs
  - test/jido_code_web/live/dashboard_live_test.exs
  - test/jido_code_web/live/phase_sixteen_integration_test.exs
  - test/jido_code_web/live/run_detail_live_test.exs
  - test/jido_code_web/live/phase_eleven_integration_test.exs
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

- id: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  statement: Operator-facing dashboard and run-detail surfaces shall expose governed evidence, review, and decision state through canonical governed-run feeds so repo posture and escalation drivers remain explainable without workflow-history fallback loaders.
  priority: should
  stability: evolving

- id: architecture.repo_posture.governed_run_memory_context_does_not_displace_posture_state
  statement: When run-detail surfaces co-host bounded memory and provenance context, posture and escalation narratives shall remain grounded in governed run, evidence, and decision records rather than being replaced by graph-local memory state.
  priority: should
  stability: evolving

- id: architecture.repo_posture.ingress_actor_identity_remains_explainable_for_posture_inputs
  statement: When posture-relevant operator demand enters through normalized ingress, requested-by actor identity shall remain explainable through persisted source metadata so posture and review-burden explanations do not depend on raw transient entrypoint payloads.
  priority: should
  stability: evolving

- id: architecture.repo_posture.canonical_repo_scope_remains_explainable_for_posture_inputs
  statement: When posture-relevant demand or runtime outcomes enter through canonical repo provisioning and repo-scope resolution, posture refresh shall keep managed-repository identity explainable without requiring fallback project-record repair.
  priority: should
  stability: evolving

- id: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  statement: When product-owned runtime gateways observe capability availability, denial, withholding, or degraded-path state that changes repo readiness or review burden, Jido.Code shall materialize that state as governed observations and let posture consume those observations without collapsing product governance into runtime policy.
  priority: should
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

- id: architecture.repo_posture.scenario_operator_views_show_governance_evidence
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  given:
    - Governed run evidence, review requests, or decisions exist for a managed repository.
  when:
    - An operator opens dashboard or run detail.
  then:
    - The product surfaces enough governed review state to explain why posture or escalation-relevant review burden exists.

- id: architecture.repo_posture.scenario_runtime_capability_posture_stays_explainable
  covers:
    - architecture.repo_posture.runtime_capability_observations_can_inform_posture
    - architecture.repo_posture.posture_checks_preserve_explainable_links
    - architecture.repo_posture.supervision_modes_are_explicit_and_reversible
  given:
    - Product-owned runtime gateways observe admitted-service availability or degraded-path state for a managed repository.
  when:
    - Repo posture refreshes and that runtime capability state affects execution readiness or review burden.
  then:
    - The posture flow records governed runtime-capability observations, links the affected posture checks back to those observations, and keeps the resulting review or supervision change explainable as product-owned governance state.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/operations/repo_native_state.ex
  covers:
    - architecture.repo_posture.repo_native_observations_capture_current_truth_signals

- kind: source_file
  target: lib/jido_code/operations/ingress.ex
  covers:
    - architecture.repo_posture.ingress_actor_identity_remains_explainable_for_posture_inputs
    - architecture.repo_posture.canonical_repo_scope_remains_explainable_for_posture_inputs

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
    - architecture.repo_posture.runtime_capability_observations_can_inform_posture

- kind: source_file
  target: lib/jido_code/governance/runtime_evidence_feed.ex
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
    - architecture.repo_posture.runtime_capability_observations_can_inform_posture

- kind: source_file
  target: lib/jido_code/orchestration/run_summary_feed.ex
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state

- kind: source_file
  target: lib/jido_code_web/live/DashboardRuntimePostureWidget.vue
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state

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
    - architecture.repo_posture.runtime_capability_observations_can_inform_posture

- kind: source_file
  target: test/jido_code/governance/runtime_capability_bridge_test.exs
  covers:
    - architecture.repo_posture.runtime_capability_observations_can_inform_posture

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
    - architecture.repo_posture.governed_run_memory_context_does_not_displace_posture_state

- kind: source_file
  target: test/jido_code/governance/runtime_evidence_feed_test.exs
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
    - architecture.repo_posture.runtime_capability_observations_can_inform_posture

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

- kind: source_file
  target: test/jido_code_web/live/dashboard_live_test.exs
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state

- kind: source_file
  target: test/jido_code_web/live/phase_sixty_five_integration_test.exs
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state

- kind: source_file
  target: test/jido_code_web/live/phase_eleven_integration_test.exs
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state

- kind: source_file
  target: .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state

- kind: source_file
  target: lib/jido_code/orchestration/run_summary_feed.ex
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state

- kind: source_file
  target: lib/jido_code_web/live/dashboard_live.ex
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
    - architecture.repo_posture.governed_run_memory_context_does_not_displace_posture_state

```
