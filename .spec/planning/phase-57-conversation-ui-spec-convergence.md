# Phase 57 - Conversation UI Spec Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations -->
<!-- covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage -->
<!-- covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage -->
<!-- covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable -->
<!-- covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state -->
<!-- covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: architecture.frontend_stack.adoption_is_incremental_per_surface -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/work_synthesis.spec.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `../decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code/workbench/project_detail.ex`
- `lib/jido_code/workbench/inventory.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `lib/jido_code_web/live/run_detail_live.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/components/operator_state_components.ex`
- `test/jido_code_web/live/project_detail_live_test.exs`
- `test/jido_code_web/live/workbench_live_test.exs`
- `test/jido_code_web/live/run_detail_live_test.exs`
- `test/jido_code_web/live/dashboard_live_test.exs`

## Relevant Assumptions / Defaults
- Phases 44 through 52 established the canonical conversation runtime, repo-detail entry surface, cross-surface linkage rules, per-work-item identity, and deterministic routing behavior.
- The current operator UI already has a recognizable visual language: LiveView-owned routed shells, rounded card sections, `operator_state_notice` feedback, compact action buttons, and bounded sidebar or summary panels rather than a full-screen chat application.
- The main remaining gap is not whether conversation exists, but whether the conversation UI fully expresses the current spec model: repo intake versus active work-item conversations, event-driven continuity, degraded recovery, explicit LLM readiness, and coherent projection across repo detail, Workbench, run detail, and dashboard.
- This phase should preserve the existing operator look and feel instead of replacing it with a separate messenger-style product or a client-owned SPA. Any richer client composition should remain bounded and justified by density or scanning needs.

[ ] 57 Phase 57 - Conversation UI Spec Convergence
  Converge the conversation UI with the current specs by evolving the existing operator design into a coherent repo-intake plus work-item conversation experience across repo detail, Workbench, run detail, and dashboard without abandoning the current LiveView-owned product shell.

  [ ] 57.1 Section - Shared Conversation Surface Language
    Standardize the visual and interaction language for conversation surfaces so all routes describe the same product model with the same card hierarchy, status labels, degraded messaging, and route-owned control affordances.

    [ ] 57.1.1 Task - Define the canonical conversation UI vocabulary
      Turn the current repo-detail conversation panel language into a reusable product contract rather than letting each route invent its own conversation wording or state presentation.

      [ ] 57.1.1.1 Subtask - Define shared labels and badges for repo intake, active work-item conversation, historical conversation lineage, clarification required, stream degraded, and runtime not ready states.
      [ ] 57.1.1.2 Subtask - Standardize how conversation identifiers, work-item linkage, latest activity, and governed status appear inside the existing card-and-sidebar operator layout.
      [ ] 57.1.1.3 Subtask - Keep raw event sequence, continuity, and runtime metadata available but visually secondary so the UI stays operator-readable before it becomes runtime-debug-readable.

    [ ] 57.1.2 Task - Introduce reusable conversation presentation helpers
      Reduce route-by-route UI drift by lifting repeated conversation cards, summary rows, and notices into bounded product-owned helpers that preserve the existing design language.

      [ ] 57.1.2.1 Subtask - Extract reusable conversation summary and empty-state helpers that match the current `operator_state_notice` and bordered-panel style.
      [ ] 57.1.2.2 Subtask - Extract reusable transcript-event row shaping for the current operator timeline treatment instead of duplicating render logic across routes.
      [ ] 57.1.2.3 Subtask - Keep any richer client-side interaction bounded to dense rosters or filters only if LiveView becomes unwieldy, leaving route control and persistence LiveView-owned.

  [ ] 57.2 Section - Managed Repo Conversation Host Surface
    Evolve repo detail from a single bounded conversation panel into the canonical host surface that clearly separates repo-scoped intake from active work-item supervision while preserving the current two-column operator layout.

    [ ] 57.2.1 Task - Reshape repo detail around intake plus active work-item conversation roster
      Make the current repo-detail conversation area express the corrected spec model without discarding the existing card-based route structure.

      [ ] 57.2.1.1 Subtask - Split repo-detail conversation projection into bounded repo intake, active work-item conversation roster, and selected conversation detail instead of one generic current-conversation card.
      [ ] 57.2.1.2 Subtask - Show active work-item identity, current status, latest activity, and bounded continuation context for each conversation in the roster while preserving the current sidebar treatment for selected detail.
      [ ] 57.2.1.3 Subtask - Keep empty, historical, stale, snapshot-only, and missing-projection states explicit instead of silently collapsing them into “no conversation.”

    [ ] 57.2.2 Task - Align repo-detail actions with the corrected conversation model
      Make route-level actions readable and intentional so operators know when they are starting intake, resuming a work-item conversation, answering clarification, or reopening governed follow-up.

      [ ] 57.2.2.1 Subtask - Add explicit repo-detail actions for opening repo intake separately from resuming an attached work-item conversation.
      [ ] 57.2.2.2 Subtask - Keep clarification, pause, resume, and stop controls visually grouped around the selected conversation state instead of scattering them across unrelated route chrome.
      [ ] 57.2.2.3 Subtask - Preserve current operator control density and button scale instead of introducing an oversized consumer-chat composer layout.

  [ ] 57.3 Section - Cross-Surface Conversation Projection
    Bring Workbench, run detail, and dashboard up to the same UI standard so conversation-driven work is recognizable across the main operator routes without reconstructing it from transcript text or internal metadata.

    [ ] 57.3.1 Task - Converge Workbench and run detail conversation projection
      Make adjacent operator surfaces show the same conversation model and route operators back to the repo-detail host surface cleanly.

      [ ] 57.3.1.1 Subtask - Expand Workbench row summaries from generic hints into bounded intake-versus-active-conversation projections that fit the current inventory visual style.
      [ ] 57.3.1.2 Subtask - Align governed run detail lineage cards with the same label, badge, and continuation language used on repo detail.
      [ ] 57.3.1.3 Subtask - Keep cross-surface continuation product-owned by routing operators back into canonical repo-detail or governed-work paths instead of inventing run-local or dashboard-local chat state.

    [ ] 57.3.2 Task - Add bounded dashboard conversation supervision
      Make dashboard aware of active conversation-driven work using the same summary-widget language already used for runs, runtime evidence, and memory.

      [ ] 57.3.2.1 Subtask - Add a bounded dashboard summary feed for repositories with active work-item conversations or clarification-needed conversation work.
      [ ] 57.3.2.2 Subtask - Surface enough repository, work-item, and conversation identity to let operators follow active work from dashboard into canonical routes without showing transcript-heavy UI there.
      [ ] 57.3.2.3 Subtask - Keep dashboard conversation supervision aligned to the current widget-and-fallback pattern rather than turning dashboard into a general chat inbox.

  [ ] 57.4 Section - Runtime, Recovery, And Readiness UX
    Make the conversation UI fully satisfy the spec around event-driven continuity, degraded fallback, and explicit runtime readiness while staying inside the current operator-state presentation language.

    [ ] 57.4.1 Task - Make event-driven continuity readable without overwhelming the route
      Present live progress, clarification, interruption, and recovery state in a way that matches the current route design rather than exposing raw runtime feeds as the default view.

      [ ] 57.4.1.1 Subtask - Refine transcript and execution panels so intent, progress, clarification, and tool-output events are easier to scan in the current bordered timeline layout.
      [ ] 57.4.1.2 Subtask - Keep sequence numbers, discontinuity counts, and snapshot continuity visible but secondary, with the main emphasis on operator actionability.
      [ ] 57.4.1.3 Subtask - Add browser-facing coverage proving reconnect, live update, and degraded continuity states remain legible under the evolved UI.

    [ ] 57.4.2 Task - Surface explicit LLM readiness and recovery states
      Ensure the UI clearly explains when real conversation execution cannot proceed and what the operator can do next.

      [ ] 57.4.2.1 Subtask - Add route-level readiness panels or badges for provider, workspace, policy, or runtime prerequisites using the existing operator notice language.
      [ ] 57.4.2.2 Subtask - Keep the selected provider and model, when relevant, visible in a bounded operator-readable way rather than hidden in debug metadata.
      [ ] 57.4.2.3 Subtask - Preserve persisted transcript and work-item linkage during readiness failures so recovery does not feel like lost conversation state.

  [ ] 57.5 Section - Verification And Current-Truth Convergence
    Close the phase by proving the UI now matches the conversation specs and by keeping the planning, spec, and contributor guidance aligned with the converged operator experience.

    [ ] 57.5.1 Task - Add route and browser coverage for the converged conversation UI
      Verify the evolved UI works across the canonical operator surfaces and does not regress under degraded delivery or reconnect scenarios.

      [ ] 57.5.1.1 Subtask - Add repo-detail coverage proving intake, active work-item roster, selected conversation detail, and degraded continuity all render distinctly.
      [ ] 57.5.1.2 Subtask - Add Workbench, run-detail, and dashboard coverage proving conversation projections reuse the same visual and routing language.
      [ ] 57.5.1.3 Subtask - Add browser coverage for conversation controls, clarification flow, readiness failures, and reconnect or degraded continuity where the current test harness can support it.

    [ ] 57.5.2 Task - Converge specs, ADRs, and contributor guidance with the final UI model
      Keep the current-truth and guidance layers synchronized once the conversation UI expresses the actual product contract.

      [ ] 57.5.2.1 Subtask - Update conversation and frontend current-truth specs to describe the final conversation surface model and route ownership boundaries.
      [ ] 57.5.2.2 Subtask - Record any durable UI-boundary decision if a new shared helper or bounded `live_vue` island becomes architecturally important.
      [ ] 57.5.2.3 Subtask - Update the planning index and contributor-facing guidance so future work treats repo detail, Workbench, run detail, and dashboard as one coherent conversation supervision system.
