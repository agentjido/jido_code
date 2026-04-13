# Jido.Code Factory Control-Plane Migration Plan

<!-- covers: package.jido_code.spec_led_workspace -->

This directory contains a phased migration plan for aligning `jido_code` with the
factory-control-plane architecture recorded in the current ADR and subject specs.

The plan aligns to:
- `../specs/agent_os_integration.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
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
- `../specs/run_governance.spec.md`
- `../decisions/jido_code.factory_control_plane.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `../decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.memory_graph_surface_rollout_and_governance_actions.md`
- `../decisions/jido_code.memory_graph_workflow_and_operator_expansion.md`
- `../decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md`
- `../decisions/jido_code.source_code_graph_product_adoption.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `../decisions/jido_code.runic_execution_model.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
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
18. [Phase 24 - Source Code Graph Product Service Foundation](./phase-24-source-code-graph-product-service-foundation.md): add the bounded product-owned semantic service and governed finding materialization layer that turns the source-code graph from a runtime capability into a reusable product boundary.
19. [Phase 25 - Semantic Operator Surface Adoption](./phase-25-semantic-operator-surface-adoption.md): adopt semantic inspection into canonical managed-repository operator surfaces, including bounded hybrid regions where richer graph exploration is useful.
20. [Phase 26 - Semantic Workflow And Governed Finding Adoption](./phase-26-semantic-workflow-and-governed-finding-adoption.md): let planning, review, and explanation workflows request semantic context explicitly and adopt semantic findings into governed product records.
21. [Phase 27 - Semantic Product Hardening And Contributor Convergence](./phase-27-semantic-product-hardening-and-contributor-convergence.md): harden the product-facing semantic experience, align contributor guidance, and converge verification around the final semantic product architecture.
22. [Phase 28 - Memory Graph Pod And Store Foundation](./phase-28-memory-graph-pod-and-store-foundation.md): establish the repository-scoped MemoryGraphPod, shared semantic-store boundaries, ontology assets, and explicit memory graph action surfaces.
23. [Phase 29 - Workflow Provenance Capture Plane](./phase-29-workflow-provenance-capture-plane.md): add the bounded capture seam that records work-session, agent, tool, prompt, review, plan, and patch provenance into `workflow_provenance` through runtime and workflow boundaries.
24. [Phase 30 - Durable Coding Memory Adoption And Validation](./phase-30-durable-coding-memory-adoption-and-validation.md): classify and adopt durable memories into the `memory` graph, then add freshness, validation, and invalidation behavior driven by revision and test evidence.
25. [Phase 31 - Memory Graph Product Hardening And Contributor Convergence](./phase-31-memory-graph-product-hardening-and-contributor-convergence.md): harden memory-graph behavior, recovery, docs, and verification so the capture plane and memory graph become durable product capabilities.
26. [Phase 32 - Memory Graph Product Adoption](./phase-32-memory-graph-product-adoption.md): adopt repository memory and workflow provenance into canonical managed-repository product services and operator surfaces so durable memory becomes explorable, actionable, and cross-linked through product-owned boundaries.
27. [Phase 33 - Memory Graph Workflow And Operator Expansion](./phase-33-memory-graph-workflow-and-operator-expansion.md): expand bounded memory and workflow-provenance adoption into governed workflow surfaces, operator memory actions, and intent-specific workflow retrieval so memory becomes actionable across the canonical product.
28. [Phase 34 - Memory Graph Surface Rollout And Governance Actions](./phase-34-memory-graph-surface-rollout-and-governance-actions.md): roll out bounded memory context, operator memory actions, and consistent cross-graph navigation across dashboard summaries and the remaining canonical governed product surfaces.
29. [Phase 35 - Governed Control-Plane Ontology And Typed Reference Foundation](./phase-35-governed-control-plane-ontology-and-typed-reference-foundation.md): add the companion governed control-plane ontology, canonical typed governed IRIs, and the stronger semantic contract that lets memory and provenance link to governed product records directly.
30. [Phase 36 - Memory Capture And Writer Semantic Cutover](./phase-36-memory-capture-and-writer-semantic-cutover.md): cut the capture plane, durable memory writers, and provenance writers over from generic artifact semantics to typed governed references while preserving the existing graph layout.
31. [Phase 37 - Query, Navigation, And Product Service Semantic Adoption](./phase-37-query-navigation-and-product-service-semantic-adoption.md): adopt typed governed semantics across SPARQL helpers, cross-graph navigation, product services, operator actions, and memory-aware workflow boundaries.
32. [Phase 38 - Semantic Surface Hardening And Contributor Convergence](./phase-38-semantic-surface-hardening-and-contributor-convergence.md): harden existing memory-aware surfaces, verification and rebuild flows, and contributor guidance so the stronger semantic model becomes the durable repo default.
33. [Phase 39 - Conversation Coordinator And Command Foundation](./phase-39-conversation-coordinator-and-command-foundation.md): introduce the canonical conversation scope, coordinator boundary, and command-admission model that attaches productive coding conversations to managed-repository and work-item context.
34. [Phase 40 - Interruptible Turns And Cancellable Tool Execution](./phase-40-interruptible-turns-and-cancellable-tool-execution.md): implement the single control lane, turn supersession, and cancellable child-tool execution model needed for stop, steer, pause, and resume semantics.
35. [Phase 41 - Evented Conversation UI And Stream Recovery](./phase-41-evented-conversation-ui-and-stream-recovery.md): replace polling-oriented conversation updates with sequenced conversation events, PubSub delivery, LiveView streams, and reconnect or degraded recovery behavior.
36. [Phase 42 - Conversation Persistence And Product Convergence](./phase-42-conversation-persistence-and-product-convergence.md): persist append-only conversation history and snapshots, preserve bounded short-term context across steering, and converge the conversation model with factory work, docs, and rollout defaults.
37. [Phase 43 - Conversation Runtime Deltas And Clarification Recovery](./phase-43-conversation-runtime-deltas-and-clarification-recovery.md): make `tool_result.submit` and `turn.resume` first-class coordinator behaviors, surface progressive tool and turn updates, and keep clarification loops recoverable through the event-driven conversation model.

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
