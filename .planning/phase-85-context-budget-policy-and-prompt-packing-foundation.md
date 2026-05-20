# Phase 85 - Context Budget Policy And Prompt Packing Foundation

<!-- covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary -->
<!-- covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit -->
<!-- covers: architecture.policy_layers.runtime_entrypoints_seed_explicit_collaboration_context -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/context_memory.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/llm_selection.ex`
- `deps/jido_ai/lib/jido_ai/context.ex`
- `deps/jido_ai/lib/jido_ai/reasoning/react/runner.ex`
- `config/config.exs`
- `config/runtime.exs`
- `docs/developer/05-specialist-prompts-context-and-tool-execution.md`
- `docs/developer/12-user-request-to-llm-message-path.md`
- `test/jido_code/conversations/context_memory_test.exs`
- `test/jido_code/phase_seventy_eight_integration_test.exs`

## Relevant Assumptions / Defaults
- Prompt memory, selected conversation context, and some tool outputs already have local caps, but there is no single model-aware context budget.
- The current user request, repository scope, workflow, and governed work-item identity are non-droppable.
- Context budgeting should be section-aware before it becomes token-perfect; byte and approximate-token estimation are acceptable for the first foundation if diagnostics make the approximation explicit.
- The budget layer should degrade context selection before failing a conversation turn.
- Prompt memory remains short-term prompt context, not durable repository memory or transcript truth.

[ ] 85 Phase 85 - Context Budget Policy And Prompt Packing Foundation
  Establish the product-owned policy and prompt-packing boundary that turns scattered local caps into a coherent model-aware budget contract for conversation runtime and specialist requests.

  [x] 85.1 Section - Context Budget Policy Model
    Define the durable vocabulary for context sections, priority, budget ownership, and model defaults before changing prompt assembly.

    [x] 85.1.1 Task - Introduce section and priority contracts
      Model prompt context as typed sections so packers can preserve required material and trim optional context predictably.

      [x] 85.1.1.1 Subtask - Define canonical section kinds for system prompt, current request, repository scope, conversation history, prompt memory, semantic context, memory context, accepted tool results, referenced files, and tool output.
      [x] 85.1.1.2 Subtask - Define retention classes such as required, important, useful, and optional, with current request and governed scope always required.
      [x] 85.1.1.3 Subtask - Define section diagnostics for original size, packed size, dropped entries, truncation reason, and degradation state.

    [x] 85.1.2 Task - Resolve model and provider budget defaults
      Connect context budget policy to the existing LLM selection boundary without hard-coding one provider's context window into runtime code.

      [x] 85.1.2.1 Subtask - Add product-owned defaults for known provider/model context windows, output-token reserves, and conservative fallback budgets.
      [x] 85.1.2.2 Subtask - Let managed-repo or request options override input budget, output reserve, and per-section budget ratios through a validated policy shape.
      [x] 85.1.2.3 Subtask - Keep missing model metadata safe by using conservative defaults and explicit diagnostics instead of disabling the turn.

  [ ] 85.2 Section - Prompt Packing Service Foundation
    Add one bounded service that accepts structured sections and returns packed prompt text plus diagnostics.

    [ ] 85.2.1 Task - Implement size estimation and section packing
      Provide a deterministic budget algorithm that can be used before provider-specific token counting is available.

      [ ] 85.2.1.1 Subtask - Add approximate token and byte estimators with tests documenting the approximation.
      [ ] 85.2.1.2 Subtask - Pack required sections first, then trim optional sections according to policy order and per-section caps.
      [ ] 85.2.1.3 Subtask - Return a stable packed structure that keeps section labels, packed text, and diagnostics separate until final rendering.

    [ ] 85.2.2 Task - Define degradation and overflow behavior
      Make oversized context recoverable and explainable instead of silently sending an over-large request.

      [ ] 85.2.2.1 Subtask - Preserve current request and repository/work-item scope even when all optional context must be dropped.
      [ ] 85.2.2.2 Subtask - Emit typed diagnostics when required sections exceed budget and the packer must enter degraded mode.
      [ ] 85.2.2.3 Subtask - Avoid lossy changes to durable memory, provenance, or conversation records; packing affects only prompt assembly.

  [ ] 85.3 Section - Conversation Runtime Prompt Boundary Adoption
    Route the conversation runtime's bounded instruction through the new packer while preserving existing prompt-memory semantics.

    [ ] 85.3.1 Task - Convert runtime instruction assembly to structured sections
      Replace ad hoc string assembly with section construction at the final runtime instruction boundary.

      [ ] 85.3.1.1 Subtask - Express objective, workflow, current request, repository scope, referenced files, accepted tool results, clarification context, prompt memory, and guidance as budgeted sections.
      [ ] 85.3.1.2 Subtask - Keep existing prompt-memory item, line, byte, and capture caps as upstream section limits.
      [ ] 85.3.1.3 Subtask - Include prompt-packing diagnostics in runtime progress metadata without exposing raw prompt text unnecessarily.

    [ ] 85.3.2 Task - Preserve conversation fallback behavior
      Ensure disabled, degraded, or over-budget context does not break deterministic workflow routing or child-work execution.

      [ ] 85.3.2.1 Subtask - Keep ambiguous workflow clarification independent from optional context availability.
      [ ] 85.3.2.2 Subtask - Preserve disabled and degraded prompt-memory projections as non-fatal packed sections.
      [ ] 85.3.2.3 Subtask - Keep existing Phase 52, Phase 78, Phase 83, and Phase 84 verification commands stable.

  [ ] 85.4 Section - Integration Tests
    Prove the new budget layer protects conversation runtime prompts without changing workflow routing, prompt-memory boundaries, or current-request fidelity.

    [ ] 85.4.1 Task - Add context budget unit and runtime coverage
      Exercise the policy model, packer, and runtime integration with realistic oversized inputs.

      [ ] 85.4.1.1 Subtask - Add tests proving required sections survive when optional prompt memory, tool results, and referenced files exceed budget.
      [ ] 85.4.1.2 Subtask - Add tests proving per-section diagnostics report original size, packed size, dropped entries, and degraded state.
      [ ] 85.4.1.3 Subtask - Add runtime tests proving a huge accepted-tool-result list is trimmed before reaching the specialist instruction.

    [ ] 85.4.2 Task - Run context-budget verification gates
      Verify the foundation with focused and existing conversation-memory commands.

      [ ] 85.4.2.1 Subtask - Run focused context budget tests once introduced.
      [ ] 85.4.2.2 Subtask - Run `mix test test/jido_code/conversations/context_memory_test.exs test/jido_code/phase_seventy_eight_integration_test.exs --max-cases 1 --max-failures 1`.
      [ ] 85.4.2.3 Subtask - Run the Phase 52 and Phase 83 routing integration tests with context-memory tests in the same command.
      [ ] 85.4.2.4 Subtask - Run any broader `mix memory.verify` or conversation-runtime verification required by touched boundaries.
