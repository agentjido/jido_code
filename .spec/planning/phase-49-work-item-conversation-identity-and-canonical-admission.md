# Phase 49 - Work-Item Conversation Identity And Canonical Admission

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item -->
<!-- covers: architecture.conversation_orchestration.repo_scoped_conversations_are_pre_work_intake -->
<!-- covers: architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items -->
<!-- covers: architecture.work_synthesis.active_conversation_identity_rejoins_work_item -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/work_synthesis.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `../decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md`
- `lib/jido_code/conversations.ex`
- `lib/jido_code/conversations/conversation.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/work_resolution.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/operations/work_item.ex`
- `lib/jido_code/operations/work_synthesis.ex`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `test/jido_code/conversations_test.exs`
- `test/jido_code/phase_forty_seven_integration_test.exs`
- `test/jido_code/phase_forty_nine_integration_test.exs`

## Relevant Assumptions / Defaults
- Phase 47 made productive conversations rejoin canonical `WorkItem` scope, but the product still over-indexes on "latest repo conversation" lookup and reuse.
- The intended greenfield model is one active productive conversation per active `WorkItem`, not one active productive conversation per managed repository.
- Managed-repository routes remain the product host surface for conversation entry and oversight, but repo-scoped conversation should stay bounded to pre-work intake or triage.
- AgentOS durable execution already expects explicit `WorkItem` scope, so productive conversation identity and runtime routing should converge on that substrate instead of preserving repo-global productive thread assumptions.

[x] 49 Phase 49 - Work-Item Conversation Identity And Canonical Admission
  Correct the conversation boundary so productive conversation identity is unique per active `WorkItem`, repo-scoped intake stays bounded to pre-work use, and productive work no longer relies on one repo-global current conversation.

  [x] 49.1 Section - Canonical Work-Item Conversation Identity
    Establish the product-owned APIs and invariants that make work-item conversation identity first-class instead of treating it as a side effect of repo-level lookup.

    [x] 49.1.1 Task - Add explicit work-item conversation lookup and resume boundaries
      Introduce product-owned ways to open, list, and resume conversations by canonical `WorkItem` scope so operator surfaces stop depending on "latest repo conversation" for productive work.

      [x] 49.1.1.1 Subtask - Add bounded product APIs to open or resume the active productive conversation for a selected `WorkItem`.
      [x] 49.1.1.2 Subtask - Add product-owned listing or projection helpers for active work-item conversations within one managed repository.
      [x] 49.1.1.3 Subtask - Keep missing, stale, or unavailable work-item conversation state explicit instead of silently falling back to repo-global latest-conversation behavior.

    [x] 49.1.2 Task - Enforce active productive conversation uniqueness per work item
      Make the durable identity contract explicit so one active work item keeps one active productive conversation while different work items in the same repository may run in parallel.

      [x] 49.1.2.1 Subtask - Enforce that reopening productive conversation work for the same active `WorkItem` reuses its active conversation instead of creating a duplicate active thread.
      [x] 49.1.2.2 Subtask - Allow separate active productive conversations for different work items in the same managed repository without treating that as a conflict.
      [x] 49.1.2.3 Subtask - Remove any remaining product-owned assumption that one managed repository has only one canonical active productive conversation.

  [x] 49.2 Section - Repo Intake To Work-Item Handoff
    Keep repo-scoped conversation as bounded intake while making the promotion into canonical work-item conversation identity explicit, explainable, and runtime-safe.

    [x] 49.2.1 Task - Limit repo-scoped conversation to intake and triage
      Preserve a bounded repo-scoped entry path for exploratory or pre-work conversation without letting that path remain the canonical long-lived productive thread after governed work begins.

      [x] 49.2.1.1 Subtask - Keep repo-scoped conversation creation explicit as pre-work intake rather than the default home for long-lived productive work.
      [x] 49.2.1.2 Subtask - Promote productive repo-intake turns onto canonical `WorkItem` conversation scope when governed planning, implementation, review, or follow-up begins.
      [x] 49.2.1.3 Subtask - Preserve handoff metadata so operators can explain how repo intake became a work-item-scoped productive conversation.

    [x] 49.2.2 Task - Route productive execution through the canonical work-item conversation
      Ensure the real runtime path follows the work-item-scoped productive conversation identity instead of continuing durable work on a repo-global thread after handoff.

      [x] 49.2.2.1 Subtask - Route durable specialist execution through the work-item-scoped conversation once governed work is attached.
      [x] 49.2.2.2 Subtask - Reuse the active work-item conversation when later turns or clarifications return to that same governed work.
      [x] 49.2.2.3 Subtask - Keep stop, steer, clarification, and resume semantics coherent across repo-intake to work-item handoff.

  [x] 49.3 Section - Integration Coverage And Current-Truth Convergence
    Prove the corrected identity model end to end and keep the ADR, specs, and planning layers aligned with the intended per-work-item conversation contract.

    [x] 49.3.1 Task - Add end-to-end coverage for parallel work-item conversations
      Verify the system now permits multiple active productive conversations in one repository only when they are attached to different work items.

      [x] 49.3.1.1 Subtask - Add coverage proving one managed repository can keep separate active productive conversations for different canonical work items.
      [x] 49.3.1.2 Subtask - Add coverage proving reopening conversation work for the same active work item resumes the active thread instead of creating a duplicate.
      [x] 49.3.1.3 Subtask - Add coverage proving repo-scoped intake promotes onto work-item-scoped productive conversation identity before durable execution continues.

    [x] 49.3.2 Task - Converge specs, planning, and architectural references
      Keep the current-truth documentation coherent once the product stops treating the latest repo conversation as the canonical productive thread.

      [x] 49.3.2.1 Subtask - Update current-truth conversation, work-synthesis, and control-plane specs to reflect per-work-item conversation identity.
      [x] 49.3.2.2 Subtask - Verify the planning index and ADR references remain coherent after Phase 49 introduces the corrected conversation identity model.
      [x] 49.3.2.3 Subtask - Keep contributor guidance explicit that repo detail hosts intake and oversight while productive conversation identity is canonical per `WorkItem`.
