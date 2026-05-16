# Phase 82 - Conversation Runtime Supervisor Stability

<!-- covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state -->
<!-- covers: architecture.conversation_orchestration.interruptible_turns_use_single_control_lane -->
<!-- covers: architecture.conversation_orchestration.child_work_lifecycle_is_recoverable -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/child_supervisor.ex`
- `lib/jido_code/conversations/child_worker.ex`
- `lib/jido_code/conversations/driver.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/persistence.ex`
- `test/jido_code/conversations_coordinator_test.exs`
- `test/jido_code/conversations_driver_test.exs`
- `test/jido_code/conversations_test.exs`
- `test/jido_code/conversations_pubsub_test.exs`
- `test/jido_code/conversations/context_memory_test.exs`

## Relevant Assumptions / Defaults
- The conversation files currently pass when run individually.
- The combined conversation-runtime batch can fail around `test/jido_code/conversations_coordinator_test.exs:448` because queued child-work activation can call `JidoCode.Conversations.ChildSupervisor` after it is stopped, missing, or otherwise unavailable.
- The fix should preserve existing coordinator semantics for stop, steer, resume, queued child work, and turn supersession.
- The conversation runtime should not depend on test file ordering, global process leakage, or implicit supervisor lifetime assumptions.

## Implementation Notes
- Reproduced the historical batch failure with:
  `mix test test/jido_code/conversations_driver_test.exs test/jido_code/conversations_coordinator_test.exs test/jido_code/conversations_test.exs test/jido_code/conversations_pubsub_test.exs test/jido_code/conversations/context_memory_test.exs --seed 871949 --max-cases 1 --max-failures 1`
- The same combined batch can pass with other seeds, and `test/jido_code/conversations_coordinator_test.exs:448` passes in isolation, so this is an order-sensitive supervisor lifecycle issue.
- The crash occurs while `Coordinator.settle_child_work/5` settles a superseded active turn and immediately activates the queued replacement turn. That path calls `ChildWorker.start/1`, which directly calls the named `JidoCode.Conversations.ChildSupervisor`.
- The failing stack shows `DynamicSupervisor.start_child/2` exiting with `:shutdown`, which means the coordinator currently lets child-supervisor unavailability escape as a coordinator crash instead of preserving the settled state and leaving queued work recoverable.
- Phase 82.2 now routes child-work startup through `ChildWorker.start/1` and `Coordinator.start_child_worker/1`, normalizing supervisor unavailability and preserving coordinator state with a `turn.activation_failed` event if startup cannot begin.
- Phase 82.3 records the shared application-supervisor contract in `docs/developer/06-conversation-orchestration.md` and adds the historical seeded batch to `docs/developer/10-development-workflow-and-quality-gates.md`.
- Phase 82.4 adds focused coordinator coverage for supervisor-backed child-worker startup, normal queued child-work activation, and the steer/supersession activation path while the child-supervisor name is temporarily unavailable.
- Verified with `mix test test/jido_code/conversations_coordinator_test.exs --max-cases 1 --max-failures 1` and the historical seeded combined conversation batch.

[x] 82 Phase 82 - Conversation Runtime Supervisor Stability
  Stabilize the conversation runtime child-work supervision contract so combined conversation suites are deterministic, queued work activation is resilient, and supervisor lifecycle assumptions are explicit in both runtime code and tests.

  [x] 82.1 Section - Failure Reproduction And Lifecycle Diagnosis
    Capture the existing combined-suite failure as a bounded runtime problem before changing coordinator behavior.

    [x] 82.1.1 Task - Reproduce the combined conversation batch failure
      Lock down the failing command and identify the minimal cross-file ordering or shared process state that makes the coordinator test fail.

      [x] 82.1.1.1 Subtask - Record the failing combined conversation command, seed behavior, and exact failure shape for `Conversations.ChildSupervisor`.
      [x] 82.1.1.2 Subtask - Confirm the same coordinator test passes in isolation so the regression target is suite-order stability rather than the test's core assertions.
      [x] 82.1.1.3 Subtask - Identify whether the failure comes from application supervision, test setup teardown, named process shutdown, or queued child-work activation timing.

    [x] 82.1.2 Task - Trace child-work activation ownership
      Make the runtime ownership model clear enough that the fix lands at the correct boundary.

      [x] 82.1.2.1 Subtask - Trace where `Coordinator` starts queued `ChildWork` and where it assumes `ChildSupervisor` is globally available.
      [x] 82.1.2.2 Subtask - Trace how tests start, stop, or replace conversation supervisors across async and sync files.
      [x] 82.1.2.3 Subtask - Document the intended supervisor ownership in the phase implementation notes or developer guidance before broadening behavior.

  [x] 82.2 Section - Supervisor Availability Contract
    Make child-work startup fail closed or recover through a product-owned path instead of crashing the coordinator when the child supervisor is unavailable.

    [x] 82.2.1 Task - Harden coordinator child-work startup
      Ensure queued work activation handles unavailable supervision in a typed, recoverable way.

      [x] 82.2.1.1 Subtask - Replace raw `GenServer.call/3` assumptions to `Conversations.ChildSupervisor` with a bounded helper that normalizes `:noproc`, `:shutdown`, timeout, and start-child errors.
      [x] 82.2.1.2 Subtask - Keep coordinator state consistent when child-work activation cannot start, including active turn, active child work, lifecycle events, and operator-visible error state.
      [x] 82.2.1.3 Subtask - Preserve successful activation semantics for normal queued tool calls and runtime child work.

    [x] 82.2.2 Task - Normalize test supervision setup
      Remove hidden order dependence from the conversation tests so each file can run alone or as part of the batch.

      [x] 82.2.2.1 Subtask - Ensure conversation tests that require `ChildSupervisor` start from a known supervised application state.
      [x] 82.2.2.2 Subtask - Remove or isolate test cleanup that shuts down shared conversation runtime processes needed by later files.
      [x] 82.2.2.3 Subtask - Keep forced failure tests scoped to their fixture process rather than leaking global supervisor state.

  [x] 82.3 Section - Runtime State And Contributor Convergence
    Preserve the conversation runtime mental model while making supervisor failure modes explicit for future work.

    [x] 82.3.1 Task - Keep turn supersession and queued work semantics stable
      Verify the stability fix does not change the core stop, steer, and queued child-work behavior that Phase 40 introduced.

      [x] 82.3.1.1 Subtask - Preserve supersession links when steering overtakes queued work.
      [x] 82.3.1.2 Subtask - Preserve cancellation and settlement behavior for active and queued child work.
      [x] 82.3.1.3 Subtask - Preserve event publication and persistence side effects around child-work state changes.

    [x] 82.3.2 Task - Update contributor guidance for conversation supervisor lifecycle
      Make the stable test and runtime contract discoverable for future conversation-runtime changes.

      [x] 82.3.2.1 Subtask - Document which supervisor processes are shared application infrastructure versus per-test fixtures.
      [x] 82.3.2.2 Subtask - Document the expected behavior when child-work startup cannot begin.
      [x] 82.3.2.3 Subtask - Update planning or developer notes with the combined-suite command that protects this boundary.

  [x] 82.4 Section - Integration Tests
    End the phase with regression coverage that proves the full conversation-runtime batch is stable, not only the individual failing test.

    [x] 82.4.1 Task - Add focused regression coverage for child-supervisor availability
      Exercise the unavailable-supervisor path and the normal queued-child-work path without relying on cross-file ordering.

      [x] 82.4.1.1 Subtask - Add coverage for typed coordinator behavior when `ChildSupervisor` is unavailable during queued child-work activation.
      [x] 82.4.1.2 Subtask - Add coverage proving the steer-overtakes-queued-work scenario still preserves supersession links.
      [x] 82.4.1.3 Subtask - Add coverage proving normal queued child work still starts under the expected supervisor.

    [x] 82.4.2 Task - Run the relevant conversation-runtime suites
      Verify the historical failure is closed across individual and combined execution modes.

      [x] 82.4.2.1 Subtask - Run `mix test test/jido_code/conversations_coordinator_test.exs --max-cases 1 --max-failures 1`.
      [x] 82.4.2.2 Subtask - Run the combined conversation batch covering coordinator, driver, persistence, PubSub, and context-memory tests.
      [x] 82.4.2.3 Subtask - Run any affected broader verification command required by touched conversation, memory, or workflow-provenance boundaries.
