# Phase 78 - Conversation Runtime Prompt Recall And Bounded Capture Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary -->
<!-- covers: architecture.conversation_orchestration.steering_preserves_short_term_context -->
<!-- covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-77-prompt-context-memory-boundary-and-namespace-foundation.md`
- `.planning/phase-74-conversation-provenance-long-term-capture-foundation.md`
- `.planning/phase-75-conversation-derived-memory-and-workflow-recall-adoption.md`
- `deps/jido_memory/lib/jido_memory.ex`
- `deps/jido_memory/lib/jido_memory/record.ex`
- `deps/jido_memory/lib/jido_memory/retrieve_result.ex`
- `lib/jido_code/conversations/context_memory.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/work_resolution.ex`
- `lib/jido_code/conversations/long_term_provenance.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/agent_workspace.ex`
- `test/jido_code/phase_forty_six_integration_test.exs`
- `test/jido_code/phase_fifty_two_integration_test.exs`
- `test/jido_code_web/live/project_detail_live_test.exs`
- `test/e2e/conversation-ui.spec.ts`

## Relevant Assumptions / Defaults
- Phase 77 has already added the `jido_memory` package, feature-gated config,
  and the `JidoCode.Conversations.ContextMemory` product boundary.
- Runtime code should consume the adapter's normalized projection with
  `:ready`, `:disabled`, and `:degraded` states, not raw `Jido.Memory.Record`
  values or provider option lists.
- The real prompt assembly boundary remains `JidoCode.Conversations.Runtime`
  rather than LiveView code or raw specialist invocation.
- Prompt memory should help with the next turn by recalling bounded context,
  not by replaying raw transcript history or bypassing deterministic workflow
  routing and governed-work attachment.
- Provenance-first long-term capture remains separate and must continue to flow
  through `JidoCode.Conversations.LongTermProvenance`.

[ ] 78 Phase 78 - Conversation Runtime Prompt Recall And Bounded Capture Adoption
  Wire prompt-context retrieval and explicit bounded capture into the real
  conversation runtime so each turn can reuse the right short-term memory
  without replaying raw transcript history or breaking the current provenance
  and governed-work model.

  [x] 78.1 Section - Prompt Retrieval And Instruction Assembly Adoption
    Add prompt-memory retrieval to the real runtime path and shape the returned
    context into the bounded instruction assembly that already drives
    conversation specialists.

    [x] 78.1.1 Task - Retrieve bounded prompt context during request building
      Make runtime ask the new adapter for prompt memory only after workflow,
      managed-repository scope, and work-item scope are resolved.

      [x] 78.1.1.1 Subtask - Resolve the correct repo-intake or work-item
        namespace during `JidoCode.Conversations.Runtime.build_request/2`
        instead of relying on ambient plugin state.
      [x] 78.1.1.2 Subtask - Add workflow-aware bounded retrieval queries for
        active constraints, accepted tool results, clarifications, plan
        summaries, next steps, and stable preferences.
      [x] 78.1.1.3 Subtask - Keep retrieval failure, provider timeouts, or
        disabled rollout non-fatal by falling back to existing shared-context
        assembly instead of failing the whole turn.
      [x] 78.1.1.4 Subtask - Persist the adapter state and diagnostics on the
        runtime request metadata so progress events and tests can explain
        whether prompt memory was ready, disabled, or degraded without exposing
        provider internals.

    [x] 78.1.2 Task - Render prompt memory into the bounded instruction shape
      Fit prompt-memory recall into the existing instruction builder without
      bloating prompts or duplicating already-bounded runtime context.

      [x] 78.1.2.1 Subtask - Add a compact `Prompt memory` section to the
        bounded instruction builder using short summaries instead of raw record
        dumps.
      [x] 78.1.2.2 Subtask - Keep referenced files, accepted tool results,
        clarification context, and prompt-memory summaries legible without
        repeating the same information in multiple sections.
      [x] 78.1.2.3 Subtask - Preserve explicit workflow, repo scope, work-item
        scope, and context-source messaging so operators and logs can still
        explain where the turn context came from.
      [x] 78.1.2.4 Subtask - Render only adapter-provided instruction lines,
        capped by configured item and byte limits, so prompt memory never
        injects arbitrary provider payloads into the specialist prompt.

  [x] 78.2 Section - Bounded Prompt Memory Capture At Product-Significant Seams
    Add explicit write paths for the small set of turn outcomes that truly help
    the next prompt rather than trying to store whole turns by default.

    [x] 78.2.1 Task - Capture short-term context reductions at runtime seams
      Write only bounded working and episodic summaries when the runtime
      reaches points where reusable context becomes clear and stable enough for
      the next turn.

      [x] 78.2.1.1 Subtask - Capture clarification answers, accepted
        constraints, accepted tool results, plan summaries, and next-step
        summaries through explicit adapter helpers rather than ambient
        transcript mirroring.
      [x] 78.2.1.2 Subtask - Attach managed-repository, work-item,
        conversation, turn, workflow, and source metadata plus retention policy
        to those prompt-memory writes.
      [x] 78.2.1.3 Subtask - Keep all other turn content out of prompt memory
        unless it is deliberately reduced into a bounded reusable summary.
      [x] 78.2.1.4 Subtask - Capture from product-significant runtime seams
        only: clarification resume, accepted tool result ingestion, completed
        specialist summary, and explicit next-step handoff.

    [x] 78.2.2 Task - Preserve scope transitions and the long-term memory split
      Make sure prompt-memory writes stay aligned with productive conversation
      scope and do not leak into provenance or durable memory responsibilities.

      [x] 78.2.2.1 Subtask - Handle repo-intake to work-item transitions so
        relevant bounded context can seed productive conversation scope without
        leaving repo-global prompt memory as the canonical long-lived lane.
      [x] 78.2.2.2 Subtask - Keep `JidoCode.Conversations.LongTermProvenance`
        as the long-term lineage capture boundary even when prompt-memory writes
        happen during the same turn lifecycle.
      [x] 78.2.2.3 Subtask - Keep `JidoCode.MemoryGraph.ConversationMemoryAdoption`
        as the explicit durable-memory promotion path instead of auto-promoting
        prompt-memory records into repository memory.

  [ ] 78.3 Section - Phase 78 Integration Tests
    Prove real runtime turns can retrieve and write bounded prompt memory
    without regressing deterministic routing, conversation continuity, or the
    provenance-first long-term recall model.

    [ ] 78.3.1 Task - Add runtime prompt-recall and bounded-capture coverage
      Verify prompt memory appears in real turn assembly only when appropriate
      and that runtime writes stay bounded and product-shaped.

      [ ] 78.3.1.1 Subtask - Add coverage proving runtime request building can
        retrieve bounded prompt memory and append it to the instruction shape
        without breaking workflow routing or explicit scope resolution.
      [ ] 78.3.1.2 Subtask - Add coverage proving clarification answers,
        accepted tool results, and next-step summaries write prompt-memory
        records with the expected scope, metadata, and retention defaults.
      [ ] 78.3.1.3 Subtask - Add coverage proving prompt-memory failure or
        disablement falls back to the current bounded runtime path and does not
        replace provenance capture or transcript continuity.
      [ ] 78.3.1.4 Subtask - Add coverage proving runtime writes use adapter
        helpers with repo, work-item, conversation, turn, workflow, source, TTL,
        and kind metadata instead of raw transcript mirroring.
