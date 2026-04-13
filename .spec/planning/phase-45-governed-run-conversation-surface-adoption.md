# Phase 45 - Governed Run Conversation Surface Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped -->
<!-- covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable -->
<!-- covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state -->
<!-- covers: architecture.conversation_orchestration.governed_run_routes_host_work_conversations -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `lib/jido_code/conversations.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/workbench/run_conversation.ex`
- `lib/jido_code_web/live/run_detail_live.ex`
- `test/jido_code/phase_forty_five_integration_test.exs`
- `test/jido_code_web/live/run_detail_live_test.exs`

## Relevant Assumptions / Defaults
- Phases 39 through 44 established the canonical conversation scope, interrupt model, event stream, persistence contract, clarification recovery path, and managed-repository route adoption.
- The governed run detail route already hosts the canonical `Run`, linked `WorkItem`, governance records, and bounded memory context, so work-item conversation adoption should follow that same product-owned route pattern instead of forcing operators back to repo detail or a chat-only page.
- Run detail should only continue canonical durable work through the existing `WorkItem` link. If a run lacks governed work scope, the route should stay explicit about that gap instead of inventing run-local chat state.
- When live delivery degrades, the operator still needs the latest durable work conversation snapshot and explicit continuity messaging rather than a blank or runtime-leaking UI.

[x] 45 Phase 45 - Governed Run Conversation Surface Adoption
  Adopt the durable conversation model into the governed run operator surface through work-item conversation helpers, bounded run-detail interaction, and spec-aligned integration coverage.

  [x] 45.1 Section - Work Conversation Workspace And Product Boundary
    Add the work-item-scoped lookup and opening APIs needed so governed run surfaces use a product-owned conversation boundary instead of reaching into raw persistence or runtime topology.

    [x] 45.1.1 Task - Expose work conversation lookup and opening through bounded product entrypoints
      Make it possible for run-detail surfaces to find, reuse, or start the right governed work conversation without duplicating conversation-domain policy in the UI.

      [x] 45.1.1.1 Subtask - Add latest-work-item conversation lookup on the conversation domain for governed run surfaces.
      [x] 45.1.1.2 Subtask - Add AgentWorkspace conversation helpers for work-item-scoped opening, snapshot lookup, event replay, and command admission.
      [x] 45.1.1.3 Subtask - Introduce a product-owned `RunConversation` boundary that decides when run-detail routes should resume the latest active work conversation versus open a fresh one.

  [x] 45.2 Section - Governed Run Detail Conversation Adoption
    Host a bounded governed work conversation panel on the run detail route so operators can continue canonical work without leaving the governed surface.

    [x] 45.2.1 Task - Render the governed work conversation panel on run detail
      Add the run-detail route panel, transcript, controls, and degraded continuity messaging using the existing event-driven conversation model.

      [x] 45.2.1.1 Subtask - Load the latest work-item conversation projection during run-detail route handling and subscribe to its event stream when LiveView is connected.
      [x] 45.2.1.2 Subtask - Let operators open the governed work conversation, submit turns, resume clarification, and pause, resume, or stop active work from the same run-detail route.
      [x] 45.2.1.3 Subtask - Keep the route bounded and product-readable by rendering recent transcript, execution state, and degraded messaging rather than raw runtime internals.

  [x] 45.3 Section - Phase 45 Integration Tests And Spec Convergence
    Verify the new run-detail conversation adoption path stays aligned with the conversation spec, product workspace boundary, and LiveView surface behavior.

    [x] 45.3.1 Task - Run conversation boundary scenarios
      Prove the product-owned run conversation boundary reuses the right work-item conversation state and exposes snapshots through AgentWorkspace instead of bypassing the conversation contract.

      [x] 45.3.1.1 Subtask - Add integration coverage proving run-detail conversation opening reuses the latest active work-item conversation.
      [x] 45.3.1.2 Subtask - Add integration coverage proving AgentWorkspace work-item conversation helpers expose snapshots and command admission for the run-detail surface.
      [x] 45.3.1.3 Subtask - Keep run-detail conversation loading durable when the route rehydrates from the latest snapshot.

    [x] 45.3.2 Task - Governed run route truth scenarios
      Keep the current-truth spec workspace and route-level LiveView behavior aligned after governed run conversation adoption lands.

      [x] 45.3.2.1 Subtask - Update run-detail LiveView coverage to assert the governed work conversation panel, transcript, and clarification flow.
      [x] 45.3.2.2 Subtask - Update the conversation spec surface and verification targets to include the run-detail conversation adoption files.
      [x] 45.3.2.3 Subtask - Verify the planning index and Phase 45 document remain coherent after governed run conversation adoption lands.
