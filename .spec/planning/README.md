# Jido.Code Factory Control-Plane Migration Plan

<!-- covers: package.jido_code.spec_led_workspace -->

This directory contains a phased migration plan for aligning `jido_code` with the
factory-control-plane architecture recorded in the current ADR and subject specs,
plus follow-on runtime adoption phases that deepen the public `jido_os` runtime
service integration after the initial control-plane migration.

The plan aligns to:
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/policy_layers.spec.md`
- `../specs/vsm_recursion.spec.md`
- `../specs/execution_pipeline.spec.md`
- `../specs/conversation_driver.spec.md`
- `../specs/coding_assistance_boundary.spec.md`
- `../specs/runtime_service_overlay.spec.md`
- `../specs/run_governance.spec.md`
- `../decisions/jido_code.factory_control_plane_and_runtime_overlay.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `../decisions/jido_code.jido_os_runtime_service_overlay_adoption.md`
- `../decisions/jido_code.runic_execution_model.md`
- `../decisions/jido_code.vsm_recursion_and_scope.md`
- `../decisions/jido_code.jido_os_public_turn_runtime_adoption.md`

## Phase Files
1. [Phase 1 - Managed Repo Control-Plane Foundation](./phase-01-managed-repo-control-plane-foundation.md): introduce the transitional repo ontology, control-plane domain layout, and initial governance scaffolding without breaking existing project flows.
2. [Phase 2 - Demand Ingress, Observation, and Work Synthesis](./phase-02-demand-ingress-observation-and-work-synthesis.md): normalize repo and operator demand into observation, intake, event, assessment, and work-item records instead of handling it as disconnected feature-specific flows.
3. [Phase 3 - Run, Evidence, Decision, and Execution Governance](./phase-03-run-evidence-decision-and-execution-governance.md): evolve workflow-run execution into the governed run model with evidence, change-request, review, and decision records around explicit execution profiles.
4. [Phase 4 - Conversation Ingress and Runtime Overlay Adoption](./phase-04-conversation-ingress-and-runtime-overlay-adoption.md): move conversations onto the managed-repo control loop while preserving `jido_os` as the runtime overlay and keeping subscriber compatibility stable.
5. [Phase 5 - Repo-Native State, Posture, and Trust Progression](./phase-05-repo-native-state-posture-and-trust-progression.md): make `.spec/` and optional Beadwork state actionable control inputs and introduce repo posture, posture checks, supervision modes, and trust progression logic.
6. [Phase 6 - Compatibility, UI Migration, and Rollout Hardening](./phase-06-compatibility-ui-migration-and-rollout-hardening.md): migrate remaining product surfaces from `Project`/`WorkflowRun` assumptions, harden policy boundaries, and complete rollout with compatibility and backfill safeguards.
7. [Phase 7 - Public Turn Runtime Bridge and Governed Projection Adoption](./phase-07-public-turn-runtime-bridge-and-governed-projection-adoption.md): adopt the newer public `jido_os` turn runtime in product-owned wrappers, route conversations through non-blocking turn start, bridge replay-driven subscriber updates, and materialize terminal turn outputs into governed run/evidence records.
8. [Phase 8 - Runtime Gateway Foundation and Capability Posture](./phase-08-runtime-gateway-foundation-and-capability-posture.md): reframe product integration around public `jido_os` runtime-service gateways, expose typed capability posture, and keep runtime admission and degraded-path evidence legible to product governance.
9. [Phase 9 - Live Runtime Delivery and Conversation Bridge Hardening](./phase-09-live-runtime-delivery-and-conversation-bridge-hardening.md): replace polling-first coding progress delivery with public live turn subscription plus replay fallback while preserving subscriber compatibility and governed terminal projection.
10. [Phase 10 - External Runtime Integration Service Adoption](./phase-10-external-runtime-integration-service-adoption.md): introduce a product-owned boundary over `Jido.Os.Integration.Service` and normalize external SaaS runtime outcomes back into the managed-repo control loop.
11. [Phase 11 - Runtime Evidence, Posture, and Rollout Convergence](./phase-11-runtime-evidence-posture-and-rollout-convergence.md): converge coding and integration runtime evidence into product posture, evidence, and operator surfaces so admitted-service rollout and degraded-path behavior become governed factory inputs.
12. [Phase 12 - Live Vue Toolchain and Host Shell Foundation](./phase-12-live-vue-toolchain-and-host-shell-foundation.md): add the `live_vue` dependency, Vite and SSR-capable asset baseline, and Phoenix host-shell integration while preserving LiveView as the routed product shell.
13. [Phase 13 - Live Vue Product Boundary and Testing Conventions](./phase-13-live-vue-product-boundary-and-testing-conventions.md): standardize how `jido_code` mounts Vue through product-owned helpers, event conventions, and LiveVue-aware tests instead of ad hoc component islands.
14. [Phase 14 - Incremental Operator Surface Adoption](./phase-14-incremental-operator-surface-adoption.md): migrate the highest-value operator surfaces to the LiveView-plus-`live_vue` composition model in an incremental, surface-by-surface rollout.
15. [Phase 15 - Frontend Rollout Hardening and Contributor Convergence](./phase-15-frontend-rollout-hardening-and-contributor-convergence.md): harden SSR, fallback behavior, observability, and docs so the new frontend stack becomes the durable contributor and operator default without regressing simpler LiveView routes.
16. [Phase 16 - Internal Cleanup and UI Convergence Foundation](./phase-16-internal-cleanup-and-ui-convergence-foundation.md): consolidate product-owned helpers, retire transitional seams, align start-oriented Mix entrypoints with the current frontend architecture, and standardize operator-facing UI states before the next feature wave.
17. [Phase 17 - Compatibility Era Removal and Canonical Cutover](./phase-17-compatibility-era-removal-and-canonical-cutover.md): remove previous-era compatibility routes, bridges, rollout seams, and mixed-mode record shaping so this greenfield repo keeps only the canonical control-plane, runtime, and UI surfaces after specs are updated.

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
- `jido_os` remains the authority-backed runtime-services overlay for sessions, turns, steering, interruption, runtime capability gating, and admitted optional services.
- `Jido.Runic` remains the canonical execution integration layer.
- Current `Project` and `WorkflowRun` surfaces are transitional implementation seams, not the preferred long-term ontology.
- Repo-native `.spec/` state and optional Git-native planning state such as Beadwork remain additive signals that inform the factory without replacing product-owned records.
