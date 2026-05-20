# Phase 88 - Context Budget Observability And Contributor Convergence

<!-- covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit -->
<!-- covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections -->
<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-85-context-budget-policy-and-prompt-packing-foundation.md`
- `.planning/phase-86-agent-workspace-semantic-and-memory-context-budget-adoption.md`
- `.planning/phase-87-specialist-history-and-tool-result-budget-adoption.md`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/driver.ex`
- `lib/jido_code/conversations/snapshot.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/memory_graph/workflow_service.ex`
- `lib/jido_code/source_code_graph/workflow_service.ex`
- `docs/developer/05-specialist-prompts-context-and-tool-execution.md`
- `docs/developer/10-development-workflow-and-quality-gates.md`
- `docs/developer/12-user-request-to-llm-message-path.md`
- `test/jido_code/phase_fifty_two_integration_test.exs`
- `test/jido_code/phase_eighty_three_integration_test.exs`

## Relevant Assumptions / Defaults
- Phases 85 through 87 introduce the context budget policy, workspace prompt adoption, specialist history caps, and tool-result budgeting.
- Operators and contributors need to know when a model ran with complete context, trimmed context, or degraded context.
- Budget diagnostics should be visible as metadata and product records, not as raw prompt dumps.
- Developer guidance should make the difference between prompt budget, prompt memory, durable memory, semantic graph context, and `tool_context` explicit.

[ ] 88 Phase 88 - Context Budget Observability And Contributor Convergence
  Make context budget behavior observable, testable, and documented across conversation runtime, specialist execution, workflow provenance, and contributor quality gates.

  [x] 88.1 Section - Runtime Diagnostics And Product Metadata
    Surface budget outcomes where operators and developers already inspect conversation and run behavior.

    [x] 88.1.1 Task - Add conversation-visible budget diagnostics
      Include concise budget state in events and snapshots without exposing raw prompt contents.

      [x] 88.1.1.1 Subtask - Add budget summary metadata to runtime progress events, including state, model budget, estimated input size, and trimmed section count.
      [x] 88.1.1.2 Subtask - Add budget summary to conversation snapshots and shared context summaries where it helps debug degraded turns.
      [x] 88.1.1.3 Subtask - Keep raw packed prompt text out of operator surfaces unless an explicit debug-only boundary is later accepted.

    [x] 88.1.2 Task - Capture budget diagnostics in provenance
      Preserve enough context-budget evidence for later review without treating prompt text as durable memory.

      [x] 88.1.2.1 Subtask - Record budget policy id, model budget, section diagnostics, and degradation state in specialist run provenance.
      [x] 88.1.2.2 Subtask - Link budget diagnostics to governed work item, conversation id, turn id, and specialist workflow.
      [x] 88.1.2.3 Subtask - Avoid storing raw prompt bodies or raw tool outputs as durable memory through budget diagnostics.

  [x] 88.2 Section - Configuration, Controls, And Degraded Recovery
    Make context budget behavior configurable enough for development and safe enough for production defaults.

    [x] 88.2.1 Task - Add validated runtime configuration
      Expose budget defaults and overrides through the existing product configuration style.

      [x] 88.2.1.1 Subtask - Add config defaults for conservative budget policy, output-token reserve, history budget, tool-output ceilings, and section ratios.
      [x] 88.2.1.2 Subtask - Add environment overrides for local development and provider-specific tuning.
      [x] 88.2.1.3 Subtask - Validate invalid budget config as degraded configuration with clear diagnostics.

    [x] 88.2.2 Task - Define recovery and remediation behavior
      Give operators and contributors clear next steps when context was trimmed or required sections are too large.

      [x] 88.2.2.1 Subtask - Add typed remediation messages for over-budget current requests, oversized tool output, and unavailable model metadata.
      [x] 88.2.2.2 Subtask - Preserve deterministic retry behavior when a user narrows requested files, lowers tool result limits, or changes model selection.
      [x] 88.2.2.3 Subtask - Keep context budget failures non-fatal unless required sections cannot fit after all safe trimming.

  [x] 88.3 Section - Contributor Guidance And Quality Gates
    Converge docs and verification commands so future LLM-context work follows the budgeted architecture.

    [x] 88.3.1 Task - Update prompt and context developer guides
      Make the final context flow easy to trace from user request to provider request.

      [x] 88.3.1.1 Subtask - Update the specialist prompts guide with context sections, packing order, `tool_context` separation, and specialist history limits.
      [x] 88.3.1.2 Subtask - Update the user-request-to-LLM path guide with budget diagnostics and failure modes.
      [x] 88.3.1.3 Subtask - Update memory and semantic docs so prompt projection is not confused with durable graph state.

    [x] 88.3.2 Task - Add quality-gate guidance
      Make the right verification commands discoverable for context budget changes.

      [x] 88.3.2.1 Subtask - Add context-budget focused commands to `docs/developer/10-development-workflow-and-quality-gates.md`.
      [x] 88.3.2.2 Subtask - Explain when to run conversation runtime, AgentWorkspace, source graph, memory graph, and `jido_ai` tests.
      [x] 88.3.2.3 Subtask - Update planning README chronology notes for the Phase 85 through Phase 88 rollout.

  [ ] 88.4 Section - Integration Tests
    End the rollout with cross-boundary tests proving budget behavior is visible, recoverable, and stable across conversation, specialist, memory, and semantic paths.

    [ ] 88.4.1 Task - Add end-to-end context budget observability coverage
      Exercise a real conversation turn that trims optional context and records diagnostics.

      [ ] 88.4.1.1 Subtask - Add coverage proving progress events include budget summaries when context is trimmed.
      [ ] 88.4.1.2 Subtask - Add coverage proving provenance captures section diagnostics without raw prompt dumps.
      [ ] 88.4.1.3 Subtask - Add coverage proving operator-visible degraded states distinguish trimmed optional context from required-context overflow.

    [ ] 88.4.2 Task - Run final context budget rollout verification
      Verify the completed rollout across all touched boundaries.

      [ ] 88.4.2.1 Subtask - Run focused context budget, conversation runtime, and AgentWorkspace tests.
      [ ] 88.4.2.2 Subtask - Run Phase 52 and Phase 83 routing integration tests.
      [ ] 88.4.2.3 Subtask - Run `mix source_graph.verify` and `mix memory.verify` if graph prompt projections or diagnostics are touched.
      [ ] 88.4.2.4 Subtask - Run broader quality gates required by final touched files, documenting any unrelated pre-existing failures.
