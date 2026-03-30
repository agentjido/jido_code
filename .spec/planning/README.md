# Jido.Code Factory Control-Plane Migration Plan

This directory contains a phased migration plan for aligning `jido_code` with the
factory-control-plane architecture recorded in the current ADR and subject specs.

The plan aligns to:
- `../specs/factory_control_plane.spec.md`
- `../specs/policy_layers.spec.md`
- `../specs/vsm_recursion.spec.md`
- `../specs/execution_pipeline.spec.md`
- `../specs/conversation_driver.spec.md`
- `../decisions/jido_code.factory_control_plane_and_runtime_overlay.md`
- `../decisions/jido_code.runic_execution_model.md`
- `../decisions/jido_code.vsm_recursion_and_scope.md`

## Phase Files
1. [Phase 1 - Managed Repo Control-Plane Foundation](./phase-01-managed-repo-control-plane-foundation.md): introduce the transitional repo ontology, control-plane domain layout, and initial governance scaffolding without breaking existing project flows.
2. [Phase 2 - Demand Ingress, Observation, and Work Synthesis](./phase-02-demand-ingress-observation-and-work-synthesis.md): normalize repo and operator demand into observation, intake, event, assessment, and work-item records instead of handling it as disconnected feature-specific flows.
3. [Phase 3 - Run, Evidence, Decision, and Execution Governance](./phase-03-run-evidence-decision-and-execution-governance.md): evolve workflow-run execution into the governed run model with evidence, change-request, review, and decision records around explicit execution profiles.
4. [Phase 4 - Conversation Ingress and Runtime Overlay Adoption](./phase-04-conversation-ingress-and-runtime-overlay-adoption.md): move conversations onto the managed-repo control loop while preserving `jido_os` as the runtime overlay and keeping subscriber compatibility stable.
5. [Phase 5 - Repo-Native State, Posture, and Trust Progression](./phase-05-repo-native-state-posture-and-trust-progression.md): make `.spec/` and optional Beadwork state actionable control inputs and introduce repo posture, posture checks, supervision modes, and trust progression logic.
6. [Phase 6 - Compatibility, UI Migration, and Rollout Hardening](./phase-06-compatibility-ui-migration-and-rollout-hardening.md): migrate remaining product surfaces from `Project`/`WorkflowRun` assumptions, harden policy boundaries, and complete rollout with compatibility and backfill safeguards.

## Shared Conventions
- Numbering:
  - Phases: `N`
  - Sections: `N.M`
  - Tasks: `N.M.K`
  - Subtasks: `N.M.K.L`
- Tracking:
  - Every phase, section, task, and subtask uses Markdown checkboxes (`[ ]`).
- Description requirement:
  - Every phase, section, and task starts with a short description paragraph.
- Integration-test requirement:
  - Each phase ends with a final integration-testing section.

## Shared Assumptions and Defaults
- `Jido.Code` remains the product and durable factory control plane.
- `jido_os` remains the runtime overlay for sessions, turns, steering, interruption, and runtime capability gating.
- `Jido.Runic` remains the canonical execution integration layer.
- Current `Project` and `WorkflowRun` surfaces are transitional implementation seams, not the preferred long-term ontology.
- Repo-native `.spec/` state and optional Git-native planning state such as Beadwork remain additive signals that inform the factory without replacing product-owned records.
