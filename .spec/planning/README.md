# Jido.Code Factory Control-Plane Migration Plan

<!-- covers: package.jido_code.spec_led_workspace -->

This directory contains a phased migration plan for aligning `jido_code` with the
factory-control-plane architecture recorded in the current ADR and subject specs.

The plan aligns to:
- `../specs/agent_os_integration.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/policy_layers.spec.md`
- `../specs/source_code_graph_pod.spec.md`
- `../specs/vsm_recursion.spec.md`
- `../specs/execution_pipeline.spec.md`
- `../specs/run_governance.spec.md`
- `../decisions/jido_code.factory_control_plane.md`
- `../decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `../decisions/jido_code.runic_execution_model.md`
- `../decisions/jido_code.vsm_recursion_and_scope.md`
- `../decisions/jido_code.jido_os_deprecation.md`

## Phase Files
1. [Phase 1 - Managed Repo Control-Plane Foundation](./phase-01-managed-repo-control-plane-foundation.md): introduce the transitional repo ontology, control-plane domain layout, and initial governance scaffolding without breaking existing project flows.
2. [Phase 2 - Demand Ingress, Observation, and Work Synthesis](./phase-02-demand-ingress-observation-and-work-synthesis.md): normalize repo and operator demand into observation, intake, event, assessment, and work-item records instead of handling it as disconnected feature-specific flows.
3. [Phase 3 - Run, Evidence, Decision, and Execution Governance](./phase-03-run-evidence-decision-and-execution-governance.md): evolve workflow-run execution into the governed run model with evidence, change-request, review, and decision records around explicit execution profiles.
4. [Phase 5 - Repo-Native State, Posture, and Trust Progression](./phase-05-repo-native-state-posture-and-trust-progression.md): make `.spec/` and optional Beadwork state actionable control inputs and introduce repo posture, posture checks, supervision modes, and trust progression logic.
5. [Phase 6 - Compatibility, UI Migration, and Rollout Hardening](./phase-06-compatibility-ui-migration-and-rollout-hardening.md): migrate remaining product surfaces from `Project`/`WorkflowRun` assumptions, harden policy boundaries, and complete rollout with compatibility and backfill safeguards.
6. [Phase 12 - Live Vue Toolchain and Host Shell Foundation](./phase-12-live-vue-toolchain-and-host-shell-foundation.md): add the `live_vue` dependency, Vite and SSR-capable asset baseline, and Phoenix host-shell integration while preserving LiveView as the routed product shell.
7. [Phase 13 - Live Vue Product Boundary and Testing Conventions](./phase-13-live-vue-product-boundary-and-testing-conventions.md): standardize how `jido_code` mounts Vue through product-owned helpers, event conventions, and LiveVue-aware tests instead of ad hoc component islands.
8. [Phase 14 - Incremental Operator Surface Adoption](./phase-14-incremental-operator-surface-adoption.md): migrate the highest-value operator surfaces to the LiveView-plus-`live_vue` composition model in an incremental, surface-by-surface rollout.
9. [Phase 15 - Frontend Rollout Hardening and Contributor Convergence](./phase-15-frontend-rollout-hardening-and-contributor-convergence.md): harden SSR, fallback behavior, observability, and docs so the new frontend stack becomes the durable contributor and operator default without regressing simpler LiveView routes.
10. [Phase 16 - Internal Cleanup and UI Convergence Foundation](./phase-16-internal-cleanup-and-ui-convergence-foundation.md): consolidate product-owned helpers, retire transitional seams, align start-oriented Mix entrypoints with the current frontend architecture, and standardize operator-facing UI states before the next feature wave.
11. [Phase 17 - Compatibility Era Removal and Canonical Cutover](./phase-17-compatibility-era-removal-and-canonical-cutover.md): remove previous-era compatibility routes, bridges, rollout seams, and mixed-mode record shaping so this greenfield repo keeps only the canonical control-plane, runtime, and UI surfaces after specs are updated.
12. [Phase 18 - Internal Domain and Execution Canonicalization](./phase-18-internal-domain-and-execution-canonicalization.md): remove the remaining `Project`- and `WorkflowRun`-era implementation seams so product internals, persistence helpers, and test fixtures create and consume only the canonical managed-repo and governed-run model.
13. [Phase 19 - AgentOS Integration](./phase-19-agent-os-integration.md): integrate `jido_agent_os` to provide durable, multi-repository coding operations with one kernel per ManagedRepo, one RepoPod singleton for repository monitoring, and one CodingPod per WorkItem containing multiple collaborating AI agents.
14. [Phase 20 - Source Code Graph Pod Foundation](./phase-20-source-code-graph-pod-foundation.md): establish the repository-scoped SourceCodeGraphPod contract, local graph-store boundaries, and explicit action surfaces for full-mode ontology analysis and named-graph ingestion.
15. [Phase 21 - Full Ontology Analysis and Named Graph Load](./phase-21-full-ontology-analysis-and-named-graph-load.md): implement the ElixirOntologies full-profile analysis pipeline and coherent loading into the canonical `source_code` named graph of the local TripleStore database.
16. [Phase 22 - Source Code Graph Query Agents and Workflow Adoption](./phase-22-source-code-graph-query-agents-and-workflow-adoption.md): add SPARQL-backed query tools and specialist agents to the SourceCodeGraphPod, then expose repository-scoped query and refresh behavior through product-owned workspace entrypoints.
17. [Phase 23 - Source Code Graph Hardening and Operational Convergence](./phase-23-source-code-graph-hardening-and-operational-convergence.md): harden refresh semantics, revision tracking, failure reporting, contributor guidance, and end-to-end pod scenarios so the source-code graph capability becomes a durable AgentOS-native repository service.

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
- `Jido.Code` is the product and durable factory control plane.
- `Jido.Runic` is the canonical execution integration layer.
- Current `Project` and `WorkflowRun` surfaces are transitional implementation seams, not the preferred long-term ontology.
- Repo-native `.spec/` state and optional Git-native planning state such as Beadwork remain additive signals that inform the factory without replacing product-owned records.
- Repository-scoped AgentOS kernels remain the bounded runtime host for specialist pods such as CodingPod, RepoPod, and future semantic-analysis pods.
