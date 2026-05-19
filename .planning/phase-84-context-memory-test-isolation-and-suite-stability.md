# Phase 84 - Context Memory Test Isolation And Suite Stability

<!-- covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary -->
<!-- covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first -->
<!-- covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `lib/jido_code/conversations/context_memory.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/driver.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `test/jido_code/conversations/context_memory_test.exs`
- `test/jido_code/phase_fifty_two_integration_test.exs`
- `test/jido_code/phase_eighty_three_integration_test.exs`
- `test/jido_code/conversations_driver_test.exs`
- `test/jido_code/conversations_coordinator_test.exs`
- `test/jido_code/conversations_test.exs`
- `test/jido_code/conversations_pubsub_test.exs`
- `docs/developer/06-conversation-orchestration.md`
- `docs/developer/10-development-workflow-and-quality-gates.md`

## Relevant Assumptions / Defaults
- The intended Phase 82 historical conversation batch passes after the supervisor hardening work.
- Phase 52 and Phase 83 routing integration tests pass as their own verification group.
- An exploratory over-broad mixed command that combines context-memory tests with later routing integration tests can still expose an ETS cleanup race in `test/jido_code/conversations/context_memory_test.exs`.
- The observed failure shape is `ArgumentError` from `:ets.delete/1` when the configured test table identifier no longer refers to an existing ETS table during `on_exit` cleanup.
- Prompt memory remains short-term prompt context only; this phase should improve test isolation and suite reliability without changing prompt-memory product semantics.
- The fix should not rely on test file ordering, sleeps, or ambient process lifetime assumptions.

## Implementation Notes
- Reproduced the current context-memory cleanup race with the historical Phase 82 conversation batch:
  `mix test test/jido_code/conversations_driver_test.exs test/jido_code/conversations_coordinator_test.exs test/jido_code/conversations_test.exs test/jido_code/conversations_pubsub_test.exs test/jido_code/conversations/context_memory_test.exs --seed 871949 --max-cases 1 --max-failures 1`
- Confirmed the isolated context-memory suite passes with:
  `mix test test/jido_code/conversations/context_memory_test.exs --max-cases 1 --max-failures 1`
- Confirmed the Phase 52 and Phase 83 routing integration tests can run with context-memory tests in the same command:
  `mix test test/jido_code/conversations/context_memory_test.exs test/jido_code/phase_fifty_two_integration_test.exs test/jido_code/phase_eighty_three_integration_test.exs --max-cases 1 --max-failures 1`
- The failing stack is in `ContextMemoryTest.reset_store!/0` during `on_exit`, where cleanup checks a fixed named ETS table and then calls `:ets.delete/1`; the table can disappear between those operations.
- `ContextMemoryTest` owns global application config for `:conversation_context_memory` and points every test at the same fixed ETS base table, while `Jido.Memory.Store.ETS` derives four named public tables from that base table.
- The prompt-memory production adapter behavior is not the failure boundary. The unstable boundary is the test fixture lifecycle around global app config restoration and named ETS table cleanup.

[ ] 84 Phase 84 - Context Memory Test Isolation And Suite Stability
  Make prompt-context memory tests hermetic enough that conversation runtime, workflow routing, and context-memory suites can run together without ETS cleanup races, while preserving the product boundary between short-term prompt memory, conversation provenance, and durable memory.

  [x] 84.1 Section - Failure Reproduction And Test-Lifecycle Diagnosis
    Capture the mixed-suite failure as a bounded test isolation problem before changing memory runtime behavior.

    [x] 84.1.1 Task - Reproduce and minimize the context-memory cleanup race
      Identify the smallest deterministic command that proves the ETS table lifecycle can be invalidated by mixed conversation and routing test execution.

      [x] 84.1.1.1 Subtask - Record the over-broad mixed test command, seed behavior, failure stack, and involved test modules.
      [x] 84.1.1.2 Subtask - Confirm `test/jido_code/conversations/context_memory_test.exs` passes alone and the historical Phase 82 conversation batch still exposes the context-memory cleanup race.
      [x] 84.1.1.3 Subtask - Determine whether the failure comes from shared ETS table names, repeated `on_exit` cleanup, application env restoration, provider startup, or cross-test process ownership.

    [x] 84.1.2 Task - Trace prompt-memory test ownership boundaries
      Make test lifecycle ownership explicit enough that the fix lands in the test harness or adapter boundary instead of masking a product behavior.

      [x] 84.1.2.1 Subtask - Trace how `ContextMemoryTest` configures `:conversation_context_memory`, store table names, store options, and provider state.
      [x] 84.1.2.2 Subtask - Trace how runtime and routing integration tests retrieve or write prompt memory during asynchronous child-work execution.
      [x] 84.1.2.3 Subtask - Document which resources are global application config, which are per-test fixtures, and which are runtime-owned state.

  [ ] 84.2 Section - Hermetic Context-Memory Test Store Contract
    Replace shared test-store assumptions with an explicit per-test lifecycle that survives mixed suite execution.

    [ ] 84.2.1 Task - Isolate context-memory store resources per test
      Ensure every prompt-memory test owns its configured store without colliding with later or earlier test cleanup.

      [ ] 84.2.1.1 Subtask - Use unique ETS table identifiers or a supervised fixture-owned store for each context-memory test.
      [ ] 84.2.1.2 Subtask - Restore `:conversation_context_memory` application config in a way that cannot point later tests at a deleted table.
      [ ] 84.2.1.3 Subtask - Make cleanup idempotent when a table was already removed, never created, or replaced by another fixture.

    [ ] 84.2.2 Task - Keep prompt-memory adapter behavior unchanged for production callers
      Fix the test lifecycle without widening product semantics or making prompt memory ambient product truth.

      [ ] 84.2.2.1 Subtask - Keep `ContextMemory.retrieve/2`, `remember/2`, and namespace behavior unchanged for disabled, degraded, and ready states.
      [ ] 84.2.2.2 Subtask - Avoid adding test-only branches to runtime prompt assembly or durable-memory adoption paths.
      [ ] 84.2.2.3 Subtask - Preserve prompt-memory fallback behavior when provider configuration is missing, disabled, invalid, or unavailable.

  [ ] 84.3 Section - Contributor Guidance And Quality-Gate Convergence
    Make the stable mixed-suite contract discoverable so future conversation-memory changes do not reintroduce order dependence.

    [ ] 84.3.1 Task - Update prompt-memory verification guidance
      Align developer docs with the new stable verification boundary for context-memory tests and conversation routing tests.

      [ ] 84.3.1.1 Subtask - Add the minimized mixed-suite command to `docs/developer/10-development-workflow-and-quality-gates.md`.
      [ ] 84.3.1.2 Subtask - Explain when contributors should run context-memory-only tests, the historical conversation batch, and mixed routing/runtime tests.
      [ ] 84.3.1.3 Subtask - Keep guidance clear that prompt memory is a bounded runtime enhancement, not durable repository memory or transcript storage.

    [ ] 84.3.2 Task - Update planning and implementation notes
      Preserve the diagnosis and final verification commands as current truth for later prompt-memory work.

      [ ] 84.3.2.1 Subtask - Record the root cause and final fixture contract in this phase document.
      [ ] 84.3.2.2 Subtask - Update `.planning/README.md` with the Phase 84 entry and chronology note.
      [ ] 84.3.2.3 Subtask - Cross-reference Phase 79, Phase 82, and Phase 83 where their verification boundaries overlap this suite-stability work.

  [ ] 84.4 Section - Integration Tests
    End the phase with regression coverage that proves context-memory tests can run with conversation runtime and refactor-routing suites without order-sensitive ETS failures.

    [ ] 84.4.1 Task - Add focused context-memory isolation coverage
      Exercise the exact fixture behavior that failed so the test harness remains safe under repeated setup and cleanup.

      [ ] 84.4.1.1 Subtask - Add coverage proving repeated context-memory setup and teardown does not raise when the ETS table is missing or already removed.
      [ ] 84.4.1.2 Subtask - Add coverage proving two context-memory fixtures cannot accidentally share and delete each other's active store.
      [ ] 84.4.1.3 Subtask - Add coverage proving disabled and degraded prompt-memory projections still return bounded non-fatal results after fixture cleanup.

    [ ] 84.4.2 Task - Run mixed conversation and routing verification
      Verify the original over-broad command and the narrower intended gates are both stable after the isolation fix.

      [ ] 84.4.2.1 Subtask - Run `mix test test/jido_code/conversations/context_memory_test.exs --max-cases 1 --max-failures 1`.
      [ ] 84.4.2.2 Subtask - Run the historical Phase 82 conversation batch with seed `871949`.
      [ ] 84.4.2.3 Subtask - Run the Phase 52 and Phase 83 routing integration tests with context-memory tests in the same command.
      [ ] 84.4.2.4 Subtask - Run `mix memory.verify` or any narrower prompt-memory verification command required by the final touched boundaries.
