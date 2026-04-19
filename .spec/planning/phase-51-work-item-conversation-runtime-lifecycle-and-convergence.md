# Phase 51 - Work-Item Conversation Runtime Lifecycle And Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item -->
<!-- covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/work_synthesis.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md`
- `lib/jido_code/conversations.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/snapshot.ex`
- `lib/jido_code/conversations/work_resolution.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code_web/live/run_detail_live.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `test/jido_code/phase_forty_eight_integration_test.exs`
- `test/jido_code_web/live/run_detail_live_test.exs`
- `docs/developer/06-conversation-orchestration.md`

## Relevant Assumptions / Defaults
- Phase 49 establishes the corrected per-work-item productive conversation identity boundary.
- Phase 50 adopts that boundary across the main managed-repository supervision surfaces, including dashboard summary paths.
- Governed run detail and follow-up routing still need to become fully lifecycle-aware once multiple work-item conversations can coexist within one repository.
- The final convergence cut should remove residual repo-global productive conversation assumptions from runtime helpers, lifecycle rules, and contributor guidance rather than preserving parallel mental models.

[x] 51 Phase 51 - Work-Item Conversation Runtime Lifecycle And Convergence
  Harden governed run routing, runtime lifecycle, and contributor expectations so work-item-scoped productive conversations become the durable default without residual repo-global conversation assumptions.

  [x] 51.1 Section - Governed Run And Follow-Up Conversation Routing
    Make governed execution and operator follow-up actions resolve back to the canonical work-item conversation thread instead of falling through repo-global lookup shortcuts.

    [x] 51.1.1 Task - Route governed run detail back to canonical work-item conversation threads
      Ensure governed run detail can explain and resume the right productive conversation even when one managed repository has several active work-item conversations.

      [x] 51.1.1.1 Subtask - Resolve governed run detail through canonical `WorkItem` conversation linkage before considering any repo-level fallback.
      [x] 51.1.1.2 Subtask - Surface preserved conversation origin and current active work-item conversation identity when governed execution was conversation-driven.
      [x] 51.1.1.3 Subtask - Keep missing, stale, or historical lineage explicit when the originating conversation is no longer the active thread for that work item.

    [x] 51.1.2 Task - Align follow-up actions with work-item conversation identity
      Ensure operator follow-up paths such as clarification, review continuation, and post-run conversation resumption target the canonical conversation for the selected work item.

      [x] 51.1.2.1 Subtask - Route work-item follow-up actions to the active productive conversation for that work item when one exists.
      [x] 51.1.2.2 Subtask - Make follow-up behavior explicit when a work item has only historical conversations and no active productive thread.
      [x] 51.1.2.3 Subtask - Preserve actor attribution and bounded shared context when governed follow-up reopens work-item conversation supervision.

  [x] 51.2 Section - Runtime Lifecycle And Closure Rules
    Remove residual repo-global assumptions from the runtime and define clear closure semantics for productive conversations that follow governed work over time.

    [x] 51.2.1 Task - Retire repo-global productive conversation assumptions from runtime helpers
      Ensure runtime-facing helpers, projections, and continuity logic no longer treat "latest repo conversation" as the productive default after the work-item model lands.

      [x] 51.2.1.1 Subtask - Remove or narrow repo-global productive conversation lookup paths so work-item conversation identity remains canonical.
      [x] 51.2.1.2 Subtask - Keep bounded repo-scoped intake support explicit and separate from productive work-item conversation lifecycle.
      [x] 51.2.1.3 Subtask - Verify restart, reconnect, and recovery paths preserve one-active-conversation-per-work-item semantics across persistence boundaries.

    [x] 51.2.2 Task - Define closure, archival, and reopening behavior for work-item conversations
      Make it explicit how productive conversation threads settle when governed work completes, is cancelled, or is later reopened.

      [x] 51.2.2.1 Subtask - Define when a work-item conversation should complete, pause, cancel, or remain resumable as governed work status changes.
      [x] 51.2.2.2 Subtask - Preserve historical conversation lineage per work item without letting historical threads compete with the active productive conversation.
      [x] 51.2.2.3 Subtask - Keep reopening behavior explicit when closed or historical work-item conversations must yield to a new active productive thread.

  [x] 51.3 Section - Integration Coverage And Contributor Convergence
    Prove the final per-work-item conversation lifecycle end to end and keep specs plus contributor guidance aligned with the corrected product model.

    [x] 51.3.1 Task - Add end-to-end lifecycle coverage for work-item conversations
      Verify governed runs, follow-up actions, completion, reopening, and history all respect the corrected productive conversation identity model.

      [x] 51.3.1.1 Subtask - Add coverage proving governed run detail resolves and resumes the correct work-item conversation when multiple active conversations exist in one repository.
      [x] 51.3.1.2 Subtask - Add coverage proving conversation lifecycle changes stay coherent as governed work completes, cancels, pauses, or reopens.
      [x] 51.3.1.3 Subtask - Add coverage proving historical conversation lineage stays explainable without violating one-active-conversation-per-work-item semantics.

    [x] 51.3.2 Task - Converge specs, planning, and contributor guidance
      Keep the architecture, planning, and developer-facing documentation coherent once the per-work-item conversation model is fully adopted.

      [x] 51.3.2.1 Subtask - Update current-truth conversation, work-synthesis, and factory-control-plane specs to reflect the final lifecycle and run-detail routing model.
      [x] 51.3.2.2 Subtask - Verify the planning index remains coherent after Phase 51 closes out the repo-global productive conversation correction.
      [x] 51.3.2.3 Subtask - Update contributor guidance so future work treats repo intake, active work-item conversations, and historical conversation lineage as distinct concepts.
