# Phase 44 - Managed Repo Conversation Surface Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped -->
<!-- covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state -->
<!-- covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable -->
<!-- covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `lib/jido_code/conversations.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `test/jido_code/phase_forty_four_integration_test.exs`
- `test/jido_code_web/live/project_detail_live_test.exs`

## Relevant Assumptions / Defaults
- Phases 39 through 43 established the canonical conversation scope, interrupt model, event stream, persistence contract, and clarification recovery path.
- The managed-repository detail route already hosts bounded semantic and memory product surfaces, so repo-scoped conversation adoption should follow that same product-owned pattern instead of introducing a raw chat-only page dependency.
- Conversation runtime and persistence remain separate from durable factory truth, but the operator should be able to open, resume, and guide repo-scoped conversation work directly from the managed-repository route.
- When live delivery degrades, the operator still needs the latest durable repository conversation snapshot and explicit continuity messaging instead of a blank or runtime-leaking UI.

[x] 44 Phase 44 - Managed Repo Conversation Surface Adoption
  Adopt the now-durable conversation model into the managed-repository operator surface through a product-owned workspace boundary, bounded repo-detail route, and spec-aligned integration coverage.

  [x] 44.1 Section - Repo Conversation Workspace And Product Boundary
    Add the repo-scoped lookup and opening APIs needed so managed-repository surfaces use a product-owned conversation boundary instead of reaching into raw persistence or runtime topology.

    [x] 44.1.1 Task - Expose repo conversation lookup and opening through bounded product entrypoints
      Make it possible for repo-detail surfaces to find, reuse, or start the right repository conversation without duplicating conversation-domain policy in the UI.

      [x] 44.1.1.1 Subtask - Add latest-repo conversation lookup on the conversation domain for managed-repository surfaces.
      [x] 44.1.1.2 Subtask - Add AgentWorkspace conversation helpers for repo-scoped opening, snapshot lookup, event replay, and command admission.
      [x] 44.1.1.3 Subtask - Introduce a product-owned `ProjectConversation` boundary that decides when repo-detail routes should resume the latest active conversation versus open a fresh one.

  [x] 44.2 Section - Managed Repo Detail Conversation Adoption
    Host a bounded repository conversation panel on the managed-repository detail route so operators can continue repo-scoped conversation work without leaving the canonical product surface.

    [x] 44.2.1 Task - Render the repository conversation panel on repo detail
      Add the managed-repository route panel, transcript, controls, and degraded continuity messaging using the existing event-driven conversation model.

      [x] 44.2.1.1 Subtask - Load the latest repo conversation projection during repo-detail route handling and subscribe to its event stream when LiveView is connected.
      [x] 44.2.1.2 Subtask - Let operators open the repo conversation, submit turns, resume clarification, and pause, resume, or stop active work from the same managed-repository route.
      [x] 44.2.1.3 Subtask - Keep the route bounded and product-readable by rendering recent transcript, execution state, and degraded messaging rather than raw runtime internals.

  [x] 44.3 Section - Phase 44 Integration Tests And Spec Convergence
    Verify the new repo-detail conversation adoption path stays aligned with the conversation spec, product workspace boundary, and LiveView surface behavior.

    [x] 44.3.1 Task - Repo conversation boundary scenarios
      Prove the product-owned repo conversation boundary reuses the right conversation state and exposes snapshots through AgentWorkspace instead of bypassing the conversation contract.

      [x] 44.3.1.1 Subtask - Add integration coverage proving repo-detail conversation opening reuses the latest active repo conversation.
      [x] 44.3.1.2 Subtask - Add integration coverage proving AgentWorkspace repo conversation helpers expose snapshots and command admission for the repo-detail surface.
      [x] 44.3.1.3 Subtask - Keep repo conversation loading durable when the route rehydrates from the latest snapshot.

    [x] 44.3.2 Task - Managed repo route truth scenarios
      Keep the current-truth spec workspace and route-level LiveView behavior aligned after repository conversation adoption lands.

      [x] 44.3.2.1 Subtask - Update repo-detail LiveView coverage to assert the repository conversation panel, transcript, and clarification flow.
      [x] 44.3.2.2 Subtask - Update the conversation spec surface and verification targets to include the managed-repository route adoption files.
      [x] 44.3.2.3 Subtask - Verify the planning index and Phase 44 document remain coherent after repo conversation adoption lands.
