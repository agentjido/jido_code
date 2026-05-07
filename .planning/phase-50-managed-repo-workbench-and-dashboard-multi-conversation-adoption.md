# Phase 50 - Managed Repo, Workbench, And Dashboard Multi-Conversation Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations -->
<!-- covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_distinguish_repo_intake_from_work_item_conversations -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md`
- `../decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code/workbench/inventory.ex`
- `lib/jido_code/orchestration/run_summary_feed.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/DashboardRunSummaryWidget.vue`
- `test/jido_code_web/live/project_detail_live_test.exs`
- `test/jido_code_web/live/workbench_live_test.exs`
- `test/jido_code_web/live/dashboard_live_test.exs`

## Relevant Assumptions / Defaults
- Phase 49 introduces the canonical identity boundary where productive conversations are unique per active `WorkItem` and repo-scoped conversation is bounded intake only.
- Repo detail remains the host surface for conversation entry and oversight, but the route should stop implying there is only one current productive conversation for the repository.
- Workbench and dashboard are operator-facing control-plane surfaces, so they should project repo intake and active work-item conversation state through canonical records rather than through page-local chat assumptions.
- The product remains greenfield: this adoption should replace repo-global productive conversation language rather than preserve a compatibility-era "latest repo conversation" mental model.

[x] 50 Phase 50 - Managed Repo, Workbench, And Dashboard Multi-Conversation Adoption
  Adopt the corrected repo-intake plus work-item conversation roster model across the main managed-repository operator surfaces so operators can supervise parallel governed conversation work without reconstructing it from transcript history.

  [x] 50.1 Section - Managed Repo Detail Multi-Conversation Projection
    Replace the single-current-conversation repo-detail model with a product-owned surface that distinguishes intake from active work-item conversation supervision.

    [x] 50.1.1 Task - Project repo intake and active work-item conversations separately on repo detail
      Make the managed-repository route show bounded intake state and an explicit roster of active work-item conversations instead of collapsing productive work into one current repo conversation card.

      [x] 50.1.1.1 Subtask - Add a repo-detail projection that distinguishes repo-scoped intake from active work-item-scoped productive conversations.
      [x] 50.1.1.2 Subtask - Show active work-item identity, status, latest activity, and bounded continuation context for each projected conversation.
      [x] 50.1.1.3 Subtask - Keep empty, degraded, and snapshot-unavailable states explicit rather than silently hiding missing conversation projections.

    [x] 50.1.2 Task - Add product-owned repo-detail actions for opening and resuming specific conversations
      Let operators start intake or continue a selected work-item conversation from the managed-repository route without inventing page-local routing semantics.

      [x] 50.1.2.1 Subtask - Add explicit actions to open bounded repo-scoped intake when no governed work item is selected yet.
      [x] 50.1.2.2 Subtask - Add explicit actions to resume the active productive conversation for a selected work item from the repo-detail route.
      [x] 50.1.2.3 Subtask - Preserve route and component behavior through product-owned helpers rather than direct conversation persistence inspection in LiveView code.

  [x] 50.2 Section - Workbench And Dashboard Surface Adoption
    Project the same canonical conversation model through Workbench and dashboard so parallel governed work becomes legible across the main control-plane supervision surfaces.

    [x] 50.2.1 Task - Project multi-conversation state onto Workbench rows
      Show operators when one repository has multiple active governed conversation threads instead of flattening that state into one generic repo-conversation summary.

      [x] 50.2.1.1 Subtask - Extend Workbench conversation projection to surface repo intake plus active work-item conversation counts or summaries per managed-repository row.
      [x] 50.2.1.2 Subtask - Let Workbench route operators back to repo detail or a selected work-item conversation continuation path without inventing a second browser truth lane.
      [x] 50.2.1.3 Subtask - Keep explicit operator messaging when multiple active conversations exist so redundant work launches are easier to avoid.

    [x] 50.2.2 Task - Add bounded dashboard summaries for active work-item conversations
      Make dashboard supervision aware of repositories that have active conversation-driven governed work without turning dashboard into a freeform chat surface.

      [x] 50.2.2.1 Subtask - Add a bounded dashboard summary or widget feed that highlights managed repositories with active work-item conversations.
      [x] 50.2.2.2 Subtask - Surface enough work-item and conversation identity to let operators follow active conversation-driven work from dashboard into canonical routes.
      [x] 50.2.2.3 Subtask - Keep dashboard summaries aligned to canonical managed-repository and governed-work records rather than transcript-derived browser state.

  [x] 50.3 Section - Integration Coverage And Current-Truth Convergence
    Prove the new surface model across repo detail, Workbench, and dashboard and keep the current-truth architecture aligned with the adopted operator experience.

    [x] 50.3.1 Task - Add operator-surface coverage for repo-intake and work-item conversation projection
      Verify the main managed-repository supervision surfaces now expose parallel work-item conversation state instead of a single repo-global productive thread.

      [x] 50.3.1.1 Subtask - Add repo-detail coverage proving active work-item conversations are listed separately from bounded repo intake.
      [x] 50.3.1.2 Subtask - Add Workbench coverage proving repositories with multiple active governed conversation threads surface that state explicitly.
      [x] 50.3.1.3 Subtask - Add dashboard coverage proving active work-item conversation summaries route operators into canonical managed-repository and governed-work surfaces.

    [x] 50.3.2 Task - Converge specs, planning, and operator expectations
      Keep the control-plane and conversation specs coherent once the main operator surfaces adopt the multi-conversation model.

      [x] 50.3.2.1 Subtask - Update current-truth conversation and factory-control-plane specs to describe repo intake plus active work-item conversation projection.
      [x] 50.3.2.2 Subtask - Verify the planning index remains coherent after Phase 50 introduces dashboard and multi-surface conversation adoption.
      [x] 50.3.2.3 Subtask - Keep contributor guidance explicit that dashboard, repo detail, and Workbench all project canonical conversation state through managed repositories and work items.
