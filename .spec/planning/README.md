# Jido.Code Factory Control-Plane Migration Plan

<!-- covers: package.jido_code.spec_led_workspace -->

This directory contains a phased migration plan for aligning `jido_code` with the
factory-control-plane architecture recorded in the current ADR and subject specs.

The plan aligns to:
- `../specs/baseline_surface.spec.md`
- `../specs/operator_auth_settings.spec.md`
- `../specs/provider_login_flow.spec.md`
- `../specs/user_administration.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/setup_onboarding.spec.md`
- `../specs/runtime_environment_defaults.spec.md`
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_graph_surface_rollout_and_governance_actions.spec.md`
- `../specs/memory_graph_workflow_and_operator_expansion.spec.md`
- `../specs/memory_ontology.spec.md`
- `../specs/policy_layers.spec.md`
- `../specs/source_code_graph_pod.spec.md`
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/vsm_recursion.spec.md`
- `../specs/execution_pipeline.spec.md`
- `../specs/conversation_orchestration.spec.md`
- `../specs/repo_posture.spec.md`
- `../specs/run_governance.spec.md`
- `../specs/runtime_service_overlay.spec.md`
- `../decisions/jido_code.factory_control_plane.md`
- `../decisions/jido_code.dashboard_concern_tabs_and_overview_handoff.md`
- `../decisions/jido_code.dashboard_developer_centric_monitoring_sidebar.md`
- `../decisions/jido_code.welcome_bootstrap_entry_with_dashboard_and_settings_handoff.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `../decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.memory_graph_surface_rollout_and_governance_actions.md`
- `../decisions/jido_code.memory_graph_workflow_and_operator_expansion.md`
- `../decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md`
- `../decisions/jido_code.source_code_graph_product_adoption.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `../decisions/jido_code.setup_onboarding_live_vue_surface_split.md`
- `../decisions/jido_code.runtime_environment_selection_is_persisted_setup_metadata.md`
- `../decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md`
- `../decisions/jido_code.runic_execution_model.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `../decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md`
- `../decisions/jido_code.vsm_recursion_and_scope.md`
- `../decisions/jido_code.jido_os_deprecation.md`

## Phase Files
1. [Phase 1 - Managed Repo Control-Plane Foundation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-01-managed-repo-control-plane-foundation.md): introduce the transitional repo ontology, control-plane domain layout, and initial governance scaffolding without breaking existing project flows.
2. [Phase 2 - Demand Ingress, Observation, and Work Synthesis](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-02-demand-ingress-observation-and-work-synthesis.md): normalize repo and operator demand into observation, intake, event, assessment, and work-item records instead of handling it as disconnected feature-specific flows.
3. [Phase 3 - Run, Evidence, Decision, and Execution Governance](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-03-run-evidence-decision-and-execution-governance.md): evolve workflow-run execution into the governed run model with evidence, change-request, review, and decision records around explicit execution profiles.
4. [Phase 5 - Repo-Native State, Posture, and Trust Progression](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-05-repo-native-state-posture-and-trust-progression.md): make `.spec/` and optional Beadwork state actionable control inputs and introduce repo posture, posture checks, supervision modes, and trust progression logic.
5. [Phase 6 - Compatibility, UI Migration, and Rollout Hardening](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-06-compatibility-ui-migration-and-rollout-hardening.md): migrate remaining product surfaces from `Project`/`WorkflowRun` assumptions, harden policy boundaries, and complete rollout with compatibility and backfill safeguards.
6. [Phase 12 - Live Vue Toolchain and Host Shell Foundation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-12-live-vue-toolchain-and-host-shell-foundation.md): add the `live_vue` dependency, Vite and SSR-capable asset baseline, and Phoenix host-shell integration while preserving LiveView as the routed product shell.
7. [Phase 13 - Live Vue Product Boundary and Testing Conventions](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-13-live-vue-product-boundary-and-testing-conventions.md): standardize how `jido_code` mounts Vue through product-owned helpers, event conventions, and LiveVue-aware tests instead of ad hoc component islands.
8. [Phase 14 - Incremental Operator Surface Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-14-incremental-operator-surface-adoption.md): migrate the highest-value operator surfaces to the LiveView-plus-`live_vue` composition model in an incremental, surface-by-surface rollout.
9. [Phase 15 - Frontend Rollout Hardening and Contributor Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-15-frontend-rollout-hardening-and-contributor-convergence.md): harden SSR, fallback behavior, observability, and docs so the new frontend stack becomes the durable contributor and operator default without regressing simpler LiveView routes.
10. [Phase 16 - Internal Cleanup and UI Convergence Foundation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-16-internal-cleanup-and-ui-convergence-foundation.md): consolidate product-owned helpers, retire transitional seams, align start-oriented Mix entrypoints with the current frontend architecture, and standardize operator-facing UI states before the next feature wave.
11. [Phase 17 - Compatibility Era Removal and Canonical Cutover](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-17-compatibility-era-removal-and-canonical-cutover.md): remove previous-era compatibility routes, bridges, rollout seams, and mixed-mode record shaping so this greenfield repo keeps only the canonical control-plane, runtime, and UI surfaces after specs are updated.
12. [Phase 18 - Internal Domain and Execution Canonicalization](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-18-internal-domain-and-execution-canonicalization.md): remove the remaining `Project`- and `WorkflowRun`-era implementation seams so product internals, persistence helpers, and test fixtures create and consume only the canonical managed-repo and governed-run model.
13. [Phase 19 - AgentOS Integration](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-19-agent-os-integration.md): integrate `jido_agent_os` to provide durable, multi-repository coding operations with one kernel per ManagedRepo, one RepoPod singleton for repository monitoring, and one CodingPod per WorkItem containing multiple collaborating AI agents.
14. [Phase 20 - Source Code Graph Pod Foundation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-20-source-code-graph-pod-foundation.md): establish the repository-scoped SourceCodeGraphPod contract, local graph-store boundaries, and explicit action surfaces for full-mode ontology analysis and named-graph ingestion.
15. [Phase 21 - Full Ontology Analysis and Named Graph Load](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-21-full-ontology-analysis-and-named-graph-load.md): implement the ElixirOntologies full-profile analysis pipeline and coherent loading into the canonical `source_code` named graph of the local TripleStore database.
16. [Phase 22 - Source Code Graph Query Agents and Workflow Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-22-source-code-graph-query-agents-and-workflow-adoption.md): add SPARQL-backed query tools and specialist agents to the SourceCodeGraphPod, then expose repository-scoped query and refresh behavior through product-owned workspace entrypoints.
17. [Phase 23 - Source Code Graph Hardening and Operational Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-23-source-code-graph-hardening-and-operational-convergence.md): harden refresh semantics, revision tracking, failure reporting, contributor guidance, and end-to-end pod scenarios so the source-code graph capability becomes a durable AgentOS-native repository service.
18. [Phase 24 - Source Code Graph Product Service Foundation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-24-source-code-graph-product-service-foundation.md): add the bounded product-owned semantic service and governed finding materialization layer that turns the source-code graph from a runtime capability into a reusable product boundary.
19. [Phase 25 - Semantic Operator Surface Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-25-semantic-operator-surface-adoption.md): adopt semantic inspection into canonical managed-repository operator surfaces, including bounded hybrid regions where richer graph exploration is useful.
20. [Phase 26 - Semantic Workflow And Governed Finding Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-26-semantic-workflow-and-governed-finding-adoption.md): let planning, review, and explanation workflows request semantic context explicitly and adopt semantic findings into governed product records.
21. [Phase 27 - Semantic Product Hardening And Contributor Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-27-semantic-product-hardening-and-contributor-convergence.md): harden the product-facing semantic experience, align contributor guidance, and converge verification around the final semantic product architecture.
22. [Phase 28 - Memory Graph Pod And Store Foundation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-28-memory-graph-pod-and-store-foundation.md): establish the repository-scoped MemoryGraphPod, shared semantic-store boundaries, ontology assets, and explicit memory graph action surfaces.
23. [Phase 29 - Workflow Provenance Capture Plane](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-29-workflow-provenance-capture-plane.md): add the bounded capture seam that records work-session, agent, tool, prompt, review, plan, and patch provenance into `workflow_provenance` through runtime and workflow boundaries.
24. [Phase 30 - Durable Coding Memory Adoption And Validation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-30-durable-coding-memory-adoption-and-validation.md): classify and adopt durable memories into the `memory` graph, then add freshness, validation, and invalidation behavior driven by revision and test evidence.
25. [Phase 31 - Memory Graph Product Hardening And Contributor Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-31-memory-graph-product-hardening-and-contributor-convergence.md): harden memory-graph behavior, recovery, docs, and verification so the capture plane and memory graph become durable product capabilities.
26. [Phase 32 - Memory Graph Product Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-32-memory-graph-product-adoption.md): adopt repository memory and workflow provenance into canonical managed-repository product services and operator surfaces so durable memory becomes explorable, actionable, and cross-linked through product-owned boundaries.
27. [Phase 33 - Memory Graph Workflow And Operator Expansion](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-33-memory-graph-workflow-and-operator-expansion.md): expand bounded memory and workflow-provenance adoption into governed workflow surfaces, operator memory actions, and intent-specific workflow retrieval so memory becomes actionable across the canonical product.
28. [Phase 34 - Memory Graph Surface Rollout And Governance Actions](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-34-memory-graph-surface-rollout-and-governance-actions.md): roll out bounded memory context, operator memory actions, and consistent cross-graph navigation across dashboard summaries and the remaining canonical governed product surfaces.
29. [Phase 35 - Governed Control-Plane Ontology And Typed Reference Foundation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-35-governed-control-plane-ontology-and-typed-reference-foundation.md): add the companion governed control-plane ontology, canonical typed governed IRIs, and the stronger semantic contract that lets memory and provenance link to governed product records directly.
30. [Phase 36 - Memory Capture And Writer Semantic Cutover](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-36-memory-capture-and-writer-semantic-cutover.md): cut the capture plane, durable memory writers, and provenance writers over from generic artifact semantics to typed governed references while preserving the existing graph layout.
31. [Phase 37 - Query, Navigation, And Product Service Semantic Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-37-query-navigation-and-product-service-semantic-adoption.md): adopt typed governed semantics across SPARQL helpers, cross-graph navigation, product services, operator actions, and memory-aware workflow boundaries.
32. [Phase 38 - Semantic Surface Hardening And Contributor Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-38-semantic-surface-hardening-and-contributor-convergence.md): harden existing memory-aware surfaces, verification and rebuild flows, and contributor guidance so the stronger semantic model becomes the durable repo default.
33. [Phase 39 - Conversation Coordinator And Command Foundation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-39-conversation-coordinator-and-command-foundation.md): introduce the canonical conversation scope, coordinator boundary, and command-admission model that attaches productive coding conversations to managed-repository and work-item context.
34. [Phase 40 - Interruptible Turns And Cancellable Tool Execution](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-40-interruptible-turns-and-cancellable-tool-execution.md): implement the single control lane, turn supersession, and cancellable child-tool execution model needed for stop, steer, pause, and resume semantics.
35. [Phase 41 - Evented Conversation UI And Stream Recovery](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-41-evented-conversation-ui-and-stream-recovery.md): replace polling-oriented conversation updates with sequenced conversation events, PubSub delivery, LiveView streams, and reconnect or degraded recovery behavior.
36. [Phase 42 - Conversation Persistence And Product Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-42-conversation-persistence-and-product-convergence.md): persist append-only conversation history and snapshots, preserve bounded short-term context across steering, and converge the conversation model with factory work, docs, and rollout defaults.
37. [Phase 43 - Conversation Runtime Deltas And Clarification Recovery](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-43-conversation-runtime-deltas-and-clarification-recovery.md): make `tool_result.submit` and `turn.resume` first-class coordinator behaviors, surface progressive tool and turn updates, and keep clarification loops recoverable through the event-driven conversation model.
38. [Phase 44 - Managed Repo Conversation Surface Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-44-managed-repo-conversation-surface-adoption.md): adopt the durable conversation model into the managed-repository detail route through product-owned workspace helpers, bounded repo-detail interaction, and current-truth coverage.
39. [Phase 45 - Memory-Aware Execute Workflow Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-45-memory-aware-execute-workflow-adoption.md): add a product-owned memory-aware execute workflow so coder paths can request bounded, freshness-aware durable memory and provenance context through the canonical workspace boundary.
40. [Phase 46 - Real LLM Conversation Runtime Cutover](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-46-real-llm-conversation-runtime-cutover.md): replace the remaining fake managed-repository conversation runtime with a real LLM-backed execution path routed through product-owned conversation, workspace, and specialist boundaries.
41. [Phase 47 - Conversation To Governed Work Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-47-conversation-to-governed-work-convergence.md): make productive repository conversations create, attach, and surface canonical WorkItem scope so governed work stops living implicitly inside repo-scoped conversation runtime state.
42. [Phase 48 - Operator Conversation Surface Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-48-operator-conversation-surface-adoption.md): project canonical repo-conversation and governed-work linkage across Workbench and governed run detail so operators can follow active work without reconstructing it from transcript or metadata internals.
43. [Phase 49 - Work-Item Conversation Identity And Canonical Admission](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-49-work-item-conversation-identity-and-canonical-admission.md): correct the conversation model so active productive threads are unique per WorkItem, parallel across different work items in the same repository, and no longer treated as one repo-global productive conversation.
44. [Phase 50 - Managed Repo, Workbench, And Dashboard Multi-Conversation Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-50-managed-repo-workbench-and-dashboard-multi-conversation-adoption.md): adopt the new repo-intake plus work-item conversation roster model across the main managed-repository operator surfaces.
45. [Phase 51 - Work-Item Conversation Runtime Lifecycle And Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-51-work-item-conversation-runtime-lifecycle-and-convergence.md): harden governed run routing, runtime lifecycle, and contributor guidance so per-work-item productive conversations become the durable default without residual repo-global assumptions.
46. [Phase 52 - Deterministic Conversation Workflow Routing And Clarification](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-52-deterministic-conversation-workflow-routing-and-clarification.md): centralize productive conversation workflow routing into one deterministic product-owned boundary, preserve explicit intent and continuity ahead of text heuristics, and clarify ambiguous routing instead of silently guessing the specialist.
47. [Phase 53 - Source Code Graph Enablement and Hardening](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-53-source-code-graph-enablement-and-hardening.md): enable the source code graph feature for development use and add production-hardening including timeouts, retries, resource limits, health monitoring, and graceful degradation.
48. [Phase 54 - Drift Closure And Current-Truth Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-54-drift-closure-and-current-truth-convergence.md): close the remaining spec-to-implementation drift by finishing canonical repo and run cutovers, converging greenfield fixtures and helpers, promoting shipped semantic and AgentOS subjects out of proposal-only status, and repairing planning plus contributor guidance where chronology or terminology has diverged.
49. [Phase 55 - Memory Rollout And Governed Surfaces](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-55-memory-rollout-and-governed-surfaces.md): finish the remaining memory rollout by adding canonical work-item, evidence, and decision memory surfaces, reusing product-owned memory actions on those routes, promoting the last proposed memory subjects to active current truth, and aligning the existing `55.6.*` integration coverage with the completed governed-surface narrative.
50. [Phase 56 - Setup Onboarding Hybrid Surface Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-56-setup-onboarding-hybrid-surface-adoption.md): implement the accepted `/setup` LiveView-plus-`live_vue` split by adding bounded hybrid setup widgets, preserving LiveView-owned sensitive controls and fallbacks, and closing the current browser-test gap for onboarding interactions.
51. [Phase 57 - Conversation UI Spec Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-57-conversation-ui-spec-convergence.md): evolve the current repo-detail conversation panel language into a coherent intake, active work-item conversation, route-owned runtime readiness plus recovery, browser-verified clarification and degraded continuity, and cross-surface operator UI that fully matches the conversation specs without abandoning the current LiveView-owned product shell.
52. [Phase 58 - Welcome Bootstrap And Ready-State Routing Foundation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-58-welcome-bootstrap-and-ready-state-routing-foundation.md): cut over the authenticated ready-state handoff so `/welcome` remains the public/bootstrap entry route while ready users default into dashboard instead of reopening the welcome-page operator console.
53. [Phase 59 - Operator Auth Settings Settings-Surface Adoption](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-59-operator-auth-settings-settings-surface-adoption.md): move Provider Login and Git Provider Integrations from the ready-state welcome view onto a durable settings-owned authenticated surface.
54. [Phase 60 - Welcome Dashboard And Settings Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-60-welcome-dashboard-and-settings-convergence.md): finish the route, settings, copy, and spec cutover so dashboard is the durable authenticated landing, settings owns operator configuration, and welcome stays focused on bootstrap and sign-in handoff.
55. [Phase 61 - Managed Repo Detail Sidebar Information Architecture](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-61-managed-repo-detail-sidebar-information-architecture.md): reorganize the managed-repository detail route around sidebar-selected families for overview, conversations, semantic inspection, memory/provenance, and workflow controls without breaking the current LiveView-owned host shell.
56. [Phase 62 - Managed Repo Workspace Binding Canonicalization](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-62-managed-repo-workspace-binding-canonicalization.md): cut the product over to repo-scoped workspace binding as the canonical execution seam while keeping install-wide runtime defaults limited to import-time seed metadata.
57. [Phase 63 - Repo-Scoped Workspace Configuration Surfaces](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-63-repo-scoped-workspace-configuration-surfaces.md): add the repo-level mutation and operator UI needed to inspect and repair each managed repository's local workspace binding directly.
58. [Phase 64 - Runtime Surface Workspace Convergence](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-64-runtime-surface-workspace-convergence.md): align conversation, semantic, memory, and workflow readiness surfaces on the final repo-scoped workspace model and remove the last shared-root assumptions from product copy and current truth.
59. [Phase 65 - Dashboard Concern Tab Information Architecture](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-65-dashboard-concern-tab-information-architecture.md): reorganize the authenticated dashboard around route-owned concern tabs for overview, runs, conversations, memory, runtime posture, and conditional next actions while keeping the dashboard a single LiveView-owned landing route.
60. [Phase 66 - Dashboard Sidebar And Repository Monitoring Foundation](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-66-dashboard-sidebar-and-repository-monitoring-foundation.md): replace the dashboard’s top concern rail with a left-sidebar shell and convert overview into a repository-first monitoring list ordered by recent meaningful work activity.
61. [Phase 67 - Dashboard Repository Panels And Accordion Monitoring](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/phase-67-dashboard-repository-panels-and-accordion-monitoring.md): turn the repository-first overview scaffold into the final simple monitoring-card surface with a summary region and a bounded lower inline-detail region.

Chronology note: Phase 55 now owns the previously landed `55.6.*` memory
ontology and governed-reference verification so the planning sequence once
again matches the shipped coverage instead of treating that integration work as
an orphaned planning gap.

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
- Remaining `Project` and `WorkflowRun` compatibility seams are bounded internal, migration, or audit exceptions rather than the preferred contributor path or long-term ontology.
- Repo-native `.spec/` state and optional Git-native planning state such as Beadwork remain additive signals that inform the factory without replacing product-owned records.
- Repository-scoped AgentOS kernels remain the bounded runtime host for specialist pods such as CodingPod, RepoPod, SourceCodeGraphPod, and MemoryGraphPod.
