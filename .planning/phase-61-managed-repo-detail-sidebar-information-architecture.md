# Phase 61 - Managed Repo Detail Sidebar Information Architecture

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records -->
<!-- covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations -->
<!-- covers: architecture.conversation_orchestration.route_level_runtime_readiness_and_continuity_are_operator_readable -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: architecture.frontend_stack.adoption_is_incremental_per_surface -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/factory_control_plane.spec.md`
- `../specs/conversation_orchestration.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_graph_surface_rollout_and_governance_actions.spec.md`
- `../specs/source_code_graph_product_adoption.spec.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `../decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md`
- `lib/jido_code/workbench/project_detail.ex`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code/workbench/project_memory_inspection.ex`
- `lib/jido_code/workbench/project_semantic_inspection.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/ProjectDetailOverviewWidget.vue`
- `lib/jido_code_web/live/ProjectDetailSemanticExplorerWidget.vue`
- `lib/jido_code_web/components/conversation_surface_components.ex`
- `test/jido_code_web/live/project_detail_live_test.exs`
- `test/jido_code_web/live/workbench_live_test.exs`
- `test/e2e/conversation-ui.spec.ts`

## Relevant Assumptions / Defaults
- The managed-repository detail route already cohosts five distinct information families: overview, conversations, semantic inspection, memory/provenance inspection, and workflow launch controls.
- Repo detail remains the canonical productive-conversation host route; a sidebar split should clarify that ownership, not demote conversation into one peer widget among many unrelated cards.
- The current visual language is already established: LiveView-owned routed shells, rounded bordered sections, `operator_state_notice` feedback, compact action controls, and bounded Vue regions only where density justifies them.
- The first implementation should stay on the existing repo-detail route with route-local tab selection rather than exploding these families into separate routes or a client-owned sub-application.
- Desktop can use a true left sidebar, but narrower viewports need a compact fallback such as a stacked section-nav or horizontal tab rail so the redesign does not become a mobile regression.

[x] 61 Phase 61 - Managed Repo Detail Sidebar Information Architecture
  Reorganize the managed-repository detail surface around a left-sidebar information architecture so operators can move between overview, conversations, semantic inspection, memory/provenance, and workflow controls without scanning one long mixed-context page.

  [x] 61.1 Section - Canonical Tab Families And Route Ownership
    Define the sidebar families, their order, and their route-owned selection model so the information split is durable instead of becoming another page-local arrangement.

    [x] 61.1.1 Task - Establish the canonical repo-detail tab set
      Turn the current mixed page sections into a stable product contract before moving any layout chrome.

      [x] 61.1.1.1 Subtask - Adopt `Overview`, `Conversations`, `Semantic`, `Memory`, and `Workflows` as the initial top-level families for the managed-repository detail route.
      [x] 61.1.1.2 Subtask - Keep repo intake, active governed conversation roster, selected conversation detail, runtime readiness, and execution controls together under `Conversations` instead of fragmenting them across multiple top-level tabs.
      [x] 61.1.1.3 Subtask - Keep semantic inspection and memory/provenance as separate top-level families even though both are repository knowledge surfaces, so each retains clear recovery and freshness messaging.

    [x] 61.1.2 Task - Keep tab selection and navigation route-owned
      Make the sidebar feel like product navigation instead of browser-local widget state.

      [x] 61.1.2.1 Subtask - Represent the selected family in LiveView-owned route state such as query params or patchable state so direct links and back-button behavior stay stable.
      [x] 61.1.2.2 Subtask - Keep the routed page shell, access control, and persistence boundaries in LiveView instead of moving repo-detail state into a client-owned tab application.
      [x] 61.1.2.3 Subtask - Provide a responsive fallback navigation treatment for smaller screens that preserves the same family ordering and selected-state semantics without requiring a left column.

  [x] 61.2 Section - Sidebar Shell And Shared Navigation Language
    Introduce the desktop sidebar and shared tab affordances in a way that fits the current operator design language rather than reading like imported dashboard chrome.

    [x] 61.2.1 Task - Add a reusable repo-detail section navigation shell
      Create the left sidebar as a bounded route-owned navigation helper that can reflect status without overwhelming the route.

      [x] 61.2.1.1 Subtask - Add sidebar items with concise labels, short helper text where needed, and selection styling that matches existing card and notice treatments.
      [x] 61.2.1.2 Subtask - Allow sidebar items to expose bounded status badges such as active conversation count, semantic stale/degraded state, memory state, or workflow blocked/ready posture.
      [x] 61.2.1.3 Subtask - Preserve the current repo identity and back-navigation cues outside or above the sidebar so page orientation does not depend on which tab is selected.

    [x] 61.2.2 Task - Standardize visible versus secondary information
      Use the new family boundaries to reduce scan load instead of just hiding sections behind tabs.

      [x] 61.2.2.1 Subtask - Keep family-level summary signals visible in the sidebar or tab chrome while leaving detailed cards inside the selected panel.
      [x] 61.2.2.2 Subtask - Avoid duplicating launch posture, repo identity, or readiness detail across multiple tabs unless the duplication is necessary for actionability.
      [x] 61.2.2.3 Subtask - Keep raw runtime, graph, and sequence metadata secondary to operator-readable summaries in the selected panel.

  [x] 61.3 Section - Overview And Workflow Separation
    Clarify the difference between orientation and action so the route can open on a concise overview while still keeping workflow launch controls first-class.

    [x] 61.3.1 Task - Keep `Overview` lightweight and summary-first
      Make overview the entry tab that explains the repo and its current posture without becoming another mixed-action dump.

      [x] 61.3.1.1 Subtask - Keep the existing overview widget focused on repository identity, launch posture, and high-level workflow card summary.
      [x] 61.3.1.2 Subtask - Remove deep launch remediation and button-heavy workflow controls from the overview family once a dedicated `Workflows` family exists.
      [x] 61.3.1.3 Subtask - Preserve enough overview context to help operators decide which deeper family to open next.

    [x] 61.3.2 Task - Move launch defaults and workflow actions into `Workflows`
      Consolidate execution-specific controls into one action-oriented family.

      [x] 61.3.2.1 Subtask - Place launch defaults, launch-disabled guidance, workflow cards, and kickoff feedback together under `Workflows`.
      [x] 61.3.2.2 Subtask - Keep workflow launch readiness and remediation explicit without repeating the same blocked messaging in both overview and workflows.
      [x] 61.3.2.3 Subtask - Preserve the current governed-launch traceability language so workflow kickoff still reads like control-plane action rather than generic repo tooling.

  [x] 61.4 Section - Conversation And Knowledge Surface Compartmentalization
    Use the sidebar split to reduce context mixing while preserving the repo-detail route as the canonical host for conversations and bounded knowledge views.

    [x] 61.4.1 Task - Keep `Conversations` as the canonical hosted work surface
      Make the conversation family feel like the route’s primary productive workspace rather than one more informational tab.

      [x] 61.4.1.1 Subtask - Keep repo intake, active governed roster, selected conversation detail, transcript, clarification controls, runtime readiness, and execution controls on the same conversation tab.
      [x] 61.4.1.2 Subtask - Preserve explicit empty, historical, snapshot-only, degraded, and not-ready states inside the conversation tab instead of flattening them into generic empty-state messaging.
      [x] 61.4.1.3 Subtask - Make sure the sidebar can signal conversation urgency through counts or warning state without forcing operators to open the tab to discover blocked or clarification-needed work.

    [x] 61.4.2 Task - Split `Semantic` and `Memory` into distinct knowledge tabs
      Separate the two graph-backed families so each can carry its own recovery and bounded projection language.

      [x] 61.4.2.1 Subtask - Keep semantic graph status, recovery, and bounded explorer/fallback content entirely within `Semantic`.
      [x] 61.4.2.2 Subtask - Keep memory graph status, memory summary, durable memory list, and provenance list entirely within `Memory`.
      [x] 61.4.2.3 Subtask - Preserve product-owned cross-links and recovery affordances between these knowledge families without collapsing them back into one mixed graph tab.

  [x] 61.5 Section - Current-Truth And Helper Convergence
    Align the supporting helpers and current-truth language once the sidebar model is real so the repo-detail route remains coherent across implementation and specs.

    [x] 61.5.1 Task - Reconcile repo-detail helpers and specs with the new information architecture
      Keep the route-owned split explicit in both code boundaries and current-truth subjects.

      [x] 61.5.1.1 Subtask - Update repo-detail helper boundaries and any bounded Vue widgets so their responsibilities map cleanly to the new families instead of the old long-form page order.
      [x] 61.5.1.2 Subtask - Update factory-control-plane, conversation, frontend, semantic, and memory current-truth subjects to describe the sidebar-selected family model once implemented.
      [x] 61.5.1.3 Subtask - Record a new ADR only if implementation reveals a durable UI-boundary rule that goes beyond the existing LiveView-host-shell and conversation-host decisions.

  [x] 61.6 Section - Phase Integration Tests
    Prove the sidebar layout clarifies repo detail without breaking route ownership, productive conversation control, or bounded knowledge surfaces.

    [x] 61.6.1 Task - Add repo-detail route and browser coverage for the sidebar model
      Verify the tab families and their most important states as an operator would actually use them.

      [x] 61.6.1.1 Subtask - Add LiveView coverage proving `Overview`, `Conversations`, `Semantic`, `Memory`, and `Workflows` each expose the intended family of information and do not leak the other families by default.
      [x] 61.6.1.2 Subtask - Add coverage proving conversation controls, degraded continuity, and runtime readiness still function correctly after the conversation family moves behind sidebar selection.
      [x] 61.6.1.3 Subtask - Add browser coverage for desktop sidebar behavior and narrow-screen fallback navigation so the new information architecture is usable across the supported viewport range.
