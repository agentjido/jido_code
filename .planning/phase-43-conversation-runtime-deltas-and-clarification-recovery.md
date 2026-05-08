# Phase 43 - Conversation Runtime Deltas And Clarification Recovery

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.control_and_work_commands_are_distinct -->
<!-- covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced -->
<!-- covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable -->
<!-- covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `lib/jido_code/conversations/command.ex`
- `lib/jido_code/conversations/child_work.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/driver.ex`
- `lib/jido_code/conversations/snapshot.ex`
- `lib/jido_code_web/live/demos/chat_live.ex`
- `test/jido_code/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phases 39 through 42 established the canonical conversation scope, control lane, event stream, persistence, and bounded shared context contract.
- The current command model already names `tool_result.submit` and `turn.resume`, but the runtime still needs first-class handling for progressive tool output and clarification loops.
- Progressive tool updates and clarification prompts should stay product-readable and sequenced so reconnect, degraded recovery, and persisted snapshots remain coherent.
- LiveView surfaces should exercise the canonical runtime commands rather than relying on ad hoc test-only settlement shortcuts for normal interactive paths.

[x] 43 Phase 43 - Conversation Runtime Deltas And Clarification Recovery
  Make runtime tool-result updates and clarification loops first-class conversation behavior so productive coding sessions can stream progress, pause for missing input, and resume without losing event or snapshot coherence.

  [x] 43.1 Section - Canonical Tool Result And Resume Commands
    Teach the coordinator to treat `tool_result.submit` and `turn.resume` as real work commands instead of generic queued turns, while preserving durable event and snapshot behavior.

    [x] 43.1.1 Task - Handle progressive tool-result updates through the coordinator
      Add the runtime update path for progress, stdout, delta, needs-input, and terminal tool results without forcing callers to bypass the conversation contract.

      [x] 43.1.1.1 Subtask - Route `tool_result.submit` to the active child work instead of enqueueing a fresh turn.
      [x] 43.1.1.2 Subtask - Emit typed `tool.progress`, `tool.stdout`, `tool.needs_input`, and `turn.delta` events while keeping snapshots bounded and recoverable.
      [x] 43.1.1.3 Subtask - Preserve explicit terminal settlement when `tool_result.submit` carries completed, cancelled, or failed outcomes.

    [x] 43.1.2 Task - Resume clarification turns through the canonical work-command path
      Let awaiting-input turns return to active execution cleanly when the operator answers a clarification prompt.

      [x] 43.1.2.1 Subtask - Route `turn.resume` to the current awaiting-input turn instead of treating it as a new queued request.
      [x] 43.1.2.2 Subtask - Clear pending clarification state from the active child work when a resume payload is accepted.
      [x] 43.1.2.3 Subtask - Keep resumed turn state, actor attribution, and runtime history explainable in snapshots and sequenced events.

  [x] 43.2 Section - LiveView Clarification And Streaming Adoption
    Update the conversation demo surface so it exercises the new canonical runtime commands and shows progressive output plus clarification state clearly.

    [x] 43.2.1 Task - Stream progressive tool and turn updates in the demo surface
      Render live progress, stdout, and delta events as first-class conversation output instead of only showing terminal settlement.

      [x] 43.2.1.1 Subtask - Use `tool_result.submit` from the demo flow for in-flight progress and final settlement simulation.
      [x] 43.2.1.2 Subtask - Render progress, stdout, and delta updates with product-readable event titles and excerpts.
      [x] 43.2.1.3 Subtask - Keep reconnect and degraded recovery legible when the latest state includes in-flight runtime output.

    [x] 43.2.2 Task - Surface clarification prompts and resume actions through the same form
      Let the operator answer an awaiting-input turn without leaving the event-driven conversation surface.

      [x] 43.2.2.1 Subtask - Render pending clarification context from the snapshot when the active turn is waiting on input.
      [x] 43.2.2.2 Subtask - Submit operator clarification through `turn.resume` using the existing bounded input flow.
      [x] 43.2.2.3 Subtask - Keep the UI language product-oriented rather than exposing raw child-worker internals.

  [x] 43.3 Section - Phase 43 Integration Tests And Spec Convergence
    Verify the new runtime update path, clarification recovery, and spec workspace all stay coherent before later conversation surface work builds on them.

    [x] 43.3.1 Task - Runtime delta and clarification scenarios
      Prove the coordinator and driver keep progressive updates, awaiting-input turns, and resumed execution coherent.

      [x] 43.3.1.1 Subtask - Add coverage proving progressive tool updates append sequenced events without breaking the active child-work contract.
      [x] 43.3.1.2 Subtask - Add coverage proving `turn.resume` clears pending clarification and restarts the awaiting turn rather than queueing new work.
      [x] 43.3.1.3 Subtask - Add coverage proving terminal tool-result submission stays aligned with durable snapshots and replay.

    [x] 43.3.2 Task - Surface and workspace truth scenarios
      Keep the planning workspace, specs, and browser-facing surface aligned to the now-complete command vocabulary.

      [x] 43.3.2.1 Subtask - Add coverage proving the conversation demo renders clarification prompts and resumed output through live events.
      [x] 43.3.2.2 Subtask - Update the conversation spec verification targets to include the new runtime-delta and clarification coverage.
      [x] 43.3.2.3 Subtask - Verify the planning index and Phase 43 document remain coherent after the new command behavior lands.
