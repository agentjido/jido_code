# Phase 77 - Prompt Context Memory Boundary And Namespace Foundation

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary -->
<!-- covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first -->
<!-- covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../specs/package_quality_standards.spec.md`
- `../decisions/jido_code.conversation_history_long_term_capture.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md`
- `../research/jido_memory_prompt_context_integration.md`
- `mix.exs`
- `mix.lock`
- `config/config.exs`
- `config/runtime.exs`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/long_term_provenance.ex`
- `lib/jido_code/agent_workspace.ex`
- `test/jido_code/phase_forty_six_integration_test.exs`
- `test/jido_code/phase_forty_seven_integration_test.exs`
- `test/jido_code/agent_workspace_test.exs`

## Relevant Assumptions / Defaults
- Phases 74 through 76 already established the provenance-first long-term
  recall split, explicit durable-memory adoption, and bounded operator recall
  surfaces for conversation-derived context.
- The new prompt-memory lane should complement those foundations rather than
  replace conversation continuity, workflow provenance, or durable repository
  memory.
- `jido_memory` is not yet a declared dependency or configured runtime surface
  in `jido_code`, so this phase must establish the package, provider, and
  product boundary seams before runtime adoption begins.
- Prompt-context memory should follow managed-repository and governed-work
  scope, not per-agent plugin namespace defaults.

[ ] 77 Phase 77 - Prompt Context Memory Boundary And Namespace Foundation
  Introduce `jido_memory` as a bounded prompt-context layer with a
  product-owned adapter, explicit namespace policy, and provider-safe rollout
  defaults so real conversation runtime can gain memory recall without turning
  prompt memory into product truth.

  [ ] 77.1 Section - Product-Owned Prompt Memory Boundary And Dependency Seam
    Establish the package, config, and product-owned adapter seams that will
    let conversation runtime call prompt memory safely through one canonical
    boundary.

    [ ] 77.1.1 Task - Add the bounded `jido_memory` dependency and rollout seam
      Declare the package and its initial runtime configuration in a way that
      preserves a disabled or degraded product path when prompt memory is not
      ready.

      [ ] 77.1.1.1 Subtask - Add `jido_memory` to `mix.exs` and lock the
        dependency so the repo has one explicit prompt-memory package surface
        instead of ad hoc local experiments.
      [ ] 77.1.1.2 Subtask - Add application and runtime configuration for
        prompt-memory enablement, provider selection, store options, timeouts,
        and bounded defaults without implying that prompt memory is always on.
      [ ] 77.1.1.3 Subtask - Keep the rollout feature-gated and failure-safe so
        missing provider readiness or disabled config does not break
        conversation execution.

    [ ] 77.1.2 Task - Introduce a product-owned `ContextMemory` adapter
      Add one canonical conversation-owned boundary over `Jido.Memory.Runtime`
      so retrieval, writes, and degradation stay out of LiveViews and out of
      arbitrary runtime callers.

      [ ] 77.1.2.1 Subtask - Add a module such as
        `JidoCode.Conversations.ContextMemory` that owns provider resolution,
        namespace resolution, query shaping, and projection shaping.
      [ ] 77.1.2.2 Subtask - Keep `Jido.Memory.BasicPlugin` out of the primary
        product path so managed-repository and work-item scope remain the
        governing namespace model.
      [ ] 77.1.2.3 Subtask - Define one normalized adapter result shape for
        successful retrieval, disabled rollout, and degraded provider behavior
        so runtime callers do not need package-specific branching logic.

  [ ] 77.2 Section - Namespace, Record, And Retention Policy Foundation
    Formalize the scope and data model rules that keep prompt memory bounded,
    useful, and clearly separate from transcript persistence and durable
    repository memory.

    [ ] 77.2.1 Task - Define the canonical prompt-memory namespace model
      Make scope resolution explicit so prompt memory follows the same product
      model as conversation work rather than defaulting to agent identity.

      [ ] 77.2.1.1 Subtask - Define repo-intake namespaces for bounded pre-work
        conversation context and work-item namespaces for governed productive
        conversation context.
      [ ] 77.2.1.2 Subtask - Keep `conversation_id`, `turn_id`, workflow, and
        actor linkage in record metadata instead of making one conversation
        instance the primary long-lived namespace.
      [ ] 77.2.1.3 Subtask - Define how prompt memory transitions from
        repo-intake scope into canonical work-item scope once productive
        conversation attaches to governed work.

    [ ] 77.2.2 Task - Define the prompt-memory record taxonomy and defaults
      Decide which classes, kinds, tags, and retention defaults the prompt
      memory lane should use before runtime code starts writing records.

      [ ] 77.2.2.1 Subtask - Define initial `:working`, `:episodic`,
        `:semantic`, and `:procedural` usage for prompt context along with a
        bounded first-pass kind taxonomy such as active constraints, accepted
        tool results, clarifications, plan summaries, and next steps.
      [ ] 77.2.2.2 Subtask - Define default TTL, expiry, and tagging policy so
        short-term memory stays useful for prompt assembly without becoming an
        ambient long-term transcript store.
      [ ] 77.2.2.3 Subtask - Reject raw transcript dumping, raw tool stdout
        capture, and automatic durable-memory promotion as valid prompt-memory
        record behavior.

  [ ] 77.3 Section - Phase 77 Integration Tests
    Prove the new package and adapter seam can be enabled, disabled, and scoped
    safely before real conversation runtime starts depending on prompt memory.

    [ ] 77.3.1 Task - Add dependency, config, and namespace foundation coverage
      Verify the prompt-memory boundary resolves the right scope and degrades
      safely when the provider is unavailable or disabled.

      [ ] 77.3.1.1 Subtask - Add coverage proving the `ContextMemory` adapter
        can resolve repo-intake and work-item namespaces with stable metadata
        linkage for managed repository, work item, conversation, and turn
        identity.
      [ ] 77.3.1.2 Subtask - Add coverage proving disabled or degraded
        prompt-memory config returns a bounded non-fatal result shape instead of
        crashing runtime callers.
      [ ] 77.3.1.3 Subtask - Add coverage proving prompt-memory record and
        retention defaults stay bounded and do not silently collapse into raw
        transcript or durable-memory semantics.
