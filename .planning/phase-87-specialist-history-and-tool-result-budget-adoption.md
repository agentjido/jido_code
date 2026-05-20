# Phase 87 - Specialist History And Tool Result Budget Adoption

<!-- covers: architecture.agent_os_integration.signal_routing_within_pod -->
<!-- covers: architecture.conversation_orchestration.interruptible_turns_use_single_control_lane -->
<!-- covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-85-context-budget-policy-and-prompt-packing-foundation.md`
- `.planning/phase-86-agent-workspace-semantic-and-memory-context-budget-adoption.md`
- `lib/jido_code/agent_workspace/runtime_specialist_runner.ex`
- `lib/jido_code/agent_workspace/specialist_runner.ex`
- `deps/jido_ai/lib/jido_ai/context.ex`
- `deps/jido_ai/lib/jido_ai/reasoning/react/runner.ex`
- `deps/jido_ai/lib/jido_ai/reasoning/react/strategy.ex`
- `lib/jido_code/actions/read_file.ex`
- `lib/jido_code/actions/search_code.ex`
- `lib/jido_code/actions/git_diff.ex`
- `lib/jido_code/actions/list_files.ex`
- `lib/jido_code/actions/run_tests.ex`
- `docs/developer/05-specialist-prompts-context-and-tool-execution.md`
- `docs/developer/12-user-request-to-llm-message-path.md`
- `test/jido_code/agent_workspace_test.exs`

## Relevant Assumptions / Defaults
- Phase 85 introduces budget policy and prompt packing.
- Phase 86 adopts budgeted semantic and memory prompt sections in `AgentWorkspace`.
- Specialist ReAct context currently persists for a specialist node while its CodingPod is alive.
- `Jido.AI.Context.to_messages/2` supports a message-count limit, but the current ReAct runner request path projects full context without a budget limit.
- Tool output caps are inconsistent and mostly local to individual actions.

[x] 87 Phase 87 - Specialist History And Tool Result Budget Adoption
  Extend context budgeting into specialist ReAct history and tool-result handling so long-lived work-item specialists cannot accumulate unbounded request history or oversized tool outputs.

  [x] 87.1 Section - Specialist History Budget Contract
    Make retained AI context explicitly bounded while preserving useful work-item continuity.

    [x] 87.1.1 Task - Add request-time history packing
      Apply the context budget before the final LLM request is sent from the ReAct runner or through a product-owned request transformer.

      [x] 87.1.1.1 Subtask - Decide whether the first implementation belongs in a `jido_code` request transformer, a `RuntimeSpecialistRunner` adapter, or a small upstream `jido_ai` extension.
      [x] 87.1.1.2 Subtask - Pack projected ReAct messages with current user turn, active tool-call protocol requirements, and recent assistant/tool messages preserved first.
      [x] 87.1.1.3 Subtask - Emit diagnostics for original history size, packed history size, dropped messages, and any protocol-preserving forced inclusions.

    [x] 87.1.2 Task - Define specialist retention and reset policy
      Keep same-work-item specialist continuity useful without assuming every later request belongs to the same subtask.

      [x] 87.1.2.1 Subtask - Add per-specialist defaults for maximum retained turns, maximum packed history budget, and reset conditions.
      [x] 87.1.2.2 Subtask - Support explicit reset or new-topic signals from conversation runtime without guessing from free text alone.
      [x] 87.1.2.3 Subtask - Preserve pod lifetime semantics: different work items still use different CodingPods and different specialists still keep separate histories.

  [x] 87.2 Section - Tool Output Budgeting And Summarization
    Make tool outputs consistently bounded before they are appended into specialist history or reused as accepted conversation context.

    [x] 87.2.1 Task - Normalize tool action output budgets
      Align existing file, search, diff, list, and test actions around shared budget defaults and diagnostics.

      [x] 87.2.1.1 Subtask - Add shared defaults for max lines, max bytes, max results, and truncation messages across workspace tools.
      [x] 87.2.1.2 Subtask - Preserve action-specific parameters such as `max_lines` and `max_results` while validating them against global safety ceilings.
      [x] 87.2.1.3 Subtask - Add diagnostics showing whether tool output was complete, truncated by action options, or truncated by global budget policy.

    [x] 87.2.2 Task - Pack tool results before history append
      Ensure large tool results do not poison later turns by entering ReAct history unbounded.

      [x] 87.2.2.1 Subtask - Route tool-result message content through the context budget layer before appending to `AIContext`.
      [x] 87.2.2.2 Subtask - Preserve enough structured result metadata for the specialist to reason about truncation and request narrower follow-up tools.
      [x] 87.2.2.3 Subtask - Keep raw full tool output out of prompt history unless a future artifact store explicitly supports out-of-band retrieval.

  [x] 87.3 Section - Cross-Turn Context Continuity And Recovery
    Make budget-related trimming visible and recoverable during multi-turn specialist work.

    [x] 87.3.1 Task - Surface budget state in specialist runs
      Preserve operator and developer visibility when a specialist runs with trimmed history or tool context.

      [x] 87.3.1.1 Subtask - Add budget diagnostics to specialist run metadata captured by workflow provenance.
      [x] 87.3.1.2 Subtask - Include concise budget state in conversation progress events when history or tool output was trimmed.
      [x] 87.3.1.3 Subtask - Add clear remediation metadata when the current request exceeds budget even after optional context is dropped.

    [x] 87.3.2 Task - Preserve correctness around tool-call protocols
      Avoid breaking provider message requirements while trimming historical context.

      [x] 87.3.2.1 Subtask - Keep assistant tool-call messages paired with required tool-result messages when either side remains in packed history.
      [x] 87.3.2.2 Subtask - Drop older unrelated message groups only at safe boundaries.
      [x] 87.3.2.3 Subtask - Add tests for multi-tool turns, cancelled turns, superseded turns, and accepted tool-result reuse.

  [x] 87.4 Section - Integration Tests
    Prove long-lived specialists, large tool results, and multi-turn tool protocols remain bounded without losing the active request or corrupting tool-call history.

    [x] 87.4.1 Task - Add specialist history and tool-output regression coverage
      Exercise realistic long-running specialist sessions and oversized tool outputs.

      [x] 87.4.1.1 Subtask - Add coverage proving old specialist history is trimmed while the current request and required scope remain.
      [x] 87.4.1.2 Subtask - Add coverage proving large `git_diff`, file-read, search, list, and test outputs are capped before history append.
      [x] 87.4.1.3 Subtask - Add coverage proving tool-call and tool-result pairs remain valid after history packing.

    [x] 87.4.2 Task - Run specialist and conversation verification gates
      Verify history and tool-result budgeting across direct specialist calls and conversation-routed work.

      [x] 87.4.2.1 Subtask - Run focused `AgentWorkspace` and specialist-runner tests.
      [x] 87.4.2.2 Subtask - Run conversation coordinator and driver tests that cover tool result acceptance, steering, and supersession.
      [x] 87.4.2.3 Subtask - Run Phase 83 refactor routing integration tests to ensure refactor specialists follow the same budget contract.
      [x] 87.4.2.4 Subtask - Run any `jido_ai` focused tests required if upstream request projection behavior changes.
