# Phase 40 - Interruptible Turns And Cancellable Tool Execution

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.control_lane_preempts_work_lane -->
<!-- covers: architecture.conversation_orchestration.active_turns_can_be_superseded -->
<!-- covers: architecture.conversation_orchestration.tool_execution_is_cancellable_child_work -->
<!-- covers: architecture.conversation_orchestration.cancellation_lifecycle_is_evented -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `../decisions/jido_code.jido_agent_os_integration.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/forge/operations.ex`
- `lib/jido_code/forge/manager.ex`
- `lib/jido_code/forge/sprite_session.ex`
- `lib/jido_code/forge/workers/streaming_exec_session_worker.ex`
- `test/jido_code/forge/`
- `test/jido_code/`

## Relevant Assumptions / Defaults
- Phase 39 introduced the canonical coordinator, command model, and baseline turn lifecycle.
- Long-running tool and runtime operations should not block the coordinator mailbox if we want reliable stop, steer, and pause semantics.
- The product contract prefers one explicit control lane over a general numeric-priority message model.
- Cancellation outcomes must stay observable and product-shaped even when underlying tools race with completion or fail to stop cleanly.

[x] 40 Phase 40 - Interruptible Turns And Cancellable Tool Execution
  Implement the interruption layer that lets users stop, steer, pause, and resume productive coding turns while long-running tool work is still in flight.

  [x] 40.1 Section - Cancellable Child Execution Model
    Move long-running tool work into bounded child execution paths so the coordinator can remain responsive to control commands.

    [x] 40.1.1 Task - Refactor long-running tool work into child jobs or workers
      Separate coordination from execution so the system can interrupt in-flight tooling without wedging turn admission.

      [x] 40.1.1.1 Subtask - Introduce a canonical child-work contract for long-running tool invocations, shell sessions, and similar extended runtime steps.
      [x] 40.1.1.2 Subtask - Preserve ownership metadata linking each child job to conversation, turn, tool-call, and work-item identifiers.
      [x] 40.1.1.3 Subtask - Keep result delivery bounded and explicit so coordinator state is updated through settled outcomes rather than hidden mailbox side effects.

    [x] 40.1.2 Task - Add cooperative cancellation and race-safe settlement
      Ensure child execution can be asked to stop, can acknowledge that request, and still settle deterministically if completion wins the race.

      [x] 40.1.2.1 Subtask - Introduce cancellation requests, acknowledgements, and final settlement behavior for child tool jobs.
      [x] 40.1.2.2 Subtask - Handle completion-before-cancel, cancel-before-start, and cancel-failed races without leaving turns in ambiguous intermediate state.
      [x] 40.1.2.3 Subtask - Keep cancellation behavior provider- and tool-agnostic so later adapters reuse one product contract.

  [x] 40.2 Section - Control Lane And Turn Supersession
    Add the admission and lifecycle behavior that gives interruption commands precedence over stale queued or active work.

    [x] 40.2.1 Task - Implement the single control lane
      Make control commands drain ahead of queued work while keeping the runtime model explainable and bounded.

      [x] 40.2.1.1 Subtask - Admit `turn.stop`, `turn.steer`, `tool.cancel`, `session.pause`, and `session.resume` through one explicit control lane.
      [x] 40.2.1.2 Subtask - Keep queued work turns in a separate normal lane rather than introducing arbitrary multi-level message priorities.
      [x] 40.2.1.3 Subtask - Add fairness and guardrails so repeated control traffic does not create hidden starvation or orphaned work state.

    [x] 40.2.2 Task - Wire interruption and supersession behavior into turn lifecycle
      Turn stop and steer into explicit, user-visible product behavior instead of runtime-local cancellation tricks.

      [x] 40.2.2.1 Subtask - Mark active turns as cancelling or superseding immediately when a control command is admitted.
      [x] 40.2.2.2 Subtask - Preserve links between replacement turns and the turns they supersede so steering remains auditable.
      [x] 40.2.2.3 Subtask - Keep pause and resume semantics explicit about whether work admission, tool execution, or both are currently halted.

  [x] 40.3 Section - Phase 40 Integration Tests
    Verify interruption, cancellation, and supersession work end to end before the UI begins to depend on them as the canonical conversation model.

    [x] 40.3.1 Task - Child execution and cancellation scenarios
      Prove long-running tool work can be cancelled cleanly and race-safe settlement remains explicit.

      [x] 40.3.1.1 Subtask - Add coverage proving in-flight tool work receives and honors cancellation requests through the new child-work contract.
      [x] 40.3.1.2 Subtask - Add coverage proving completion-before-cancel and cancel-failed races settle with explicit terminal outcomes.
      [x] 40.3.1.3 Subtask - Add coverage proving child-work ownership metadata stays aligned to conversation, turn, and tool-call identifiers.

    [x] 40.3.2 Task - Control-lane and supersession scenarios
      Prove stop, steer, pause, and resume semantics overtake queued work and stay understandable to product callers.

      [x] 40.3.2.1 Subtask - Add coverage proving control commands overtake queued work turns without introducing arbitrary numeric priority semantics.
      [x] 40.3.2.2 Subtask - Add coverage proving active turns become cancelled or superseded explicitly when replacement turns are admitted.
      [x] 40.3.2.3 Subtask - Verify the spec workspace remains coherent after Phase 40 establishes interruptible turn execution.
