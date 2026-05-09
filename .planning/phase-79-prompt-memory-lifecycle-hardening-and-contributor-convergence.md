# Phase 79 - Prompt Memory Lifecycle Hardening And Contributor Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first -->
<!-- covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections -->
<!-- covers: architecture.policy_layers.runtime_entrypoints_seed_explicit_collaboration_context -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-77-prompt-context-memory-boundary-and-namespace-foundation.md`
- `.planning/phase-78-conversation-runtime-prompt-recall-and-bounded-capture-adoption.md`
- `.planning/phase-74-conversation-provenance-long-term-capture-foundation.md`
- `.planning/phase-75-conversation-derived-memory-and-workflow-recall-adoption.md`
- `deps/jido_memory/guides/api_adapter_surface.md`
- `deps/jido_memory/guides/basic_provider.md`
- `deps/jido_memory/docs/provider_contract.md`
- `deps/jido_memory/lib/jido_memory.ex`
- `docs/developer/08-memory-graph-and-workflow-provenance.md`
- `docs/developer/08b-memory-ontology-and-query-examples.md`
- `lib/jido_code/conversations/context_memory.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/long_term_provenance.ex`
- `lib/jido_code/memory_graph/conversation_memory_adoption.ex`
- `mix.exs`
- `config/runtime.exs`
- `test/jido_code/phase_forty_six_integration_test.exs`
- `test/jido_code/memory_graph_workflow_service_test.exs`
- `test/jido_code_web/live/project_detail_live_test.exs`

## Relevant Assumptions / Defaults
- Phases 77 and 78 have already introduced the `ContextMemory` boundary and
  wired bounded prompt-memory retrieval plus writes into the real conversation
  runtime.
- Prompt memory remains a bounded enhancement for turn assembly and should not
  become a second durable-memory or transcript-truth lane.
- The product already has accepted contributor guidance for memory graph and
  workflow provenance, so this phase should explain when prompt memory is the
  right tool and when it is not.
- Provider selection, retention, and cleanup need hardening before prompt
  memory can be treated as a reliable everyday runtime feature.
- Lifecycle work should stay behind `JidoCode.Conversations.ContextMemory` so
  runtime callers ask for bounded retrieval and explicit cleanup rather than
  calling provider lifecycle functions directly.
- Prompt-memory records must remain invisible to operator durable-memory
  surfaces unless a later explicit adoption/classification flow promotes a
  bounded outcome through the existing governed memory path.

[ ] 79 Phase 79 - Prompt Memory Lifecycle Hardening And Contributor Convergence
  Harden provider behavior, retention and cleanup policy, verification
  defaults, and contributor guidance so prompt memory remains bounded,
  explainable, and clearly separate from provenance and durable repository
  memory.

  [x] 79.1 Section - Provider, Retention, And Cleanup Hardening
    Turn the first rollout into a reliable runtime feature by making cleanup,
    expiry, and provider behavior explicit and operationally safe.

    [x] 79.1.1 Task - Add explicit lifecycle management for prompt memory
      Make record expiry and optional consolidation part of the design instead
      of leaving prompt memory to grow indefinitely once runtime writes begin.

      [x] 79.1.1.1 Subtask - Add bounded cleanup helpers over
        `consolidate/2`, `prune_expired/2`, or equivalent lifecycle calls so
        expired or superseded prompt-memory records stop influencing future
        prompts.
      [x] 79.1.1.2 Subtask - Make retrieval expiry-aware so prompt assembly
        ignores stale short-term memory by default without requiring callers to
        hand-code cleanup behavior.
      [x] 79.1.1.3 Subtask - Keep lifecycle operations bounded by timeout,
        limits, and product-owned logging so cleanup work cannot starve active
        conversation execution.
      [x] 79.1.1.4 Subtask - Keep cleanup namespace-scoped so repo-intake and
        work-item prompt memory can be pruned independently without affecting
        transcript persistence, workflow provenance, or durable memory graph
        records.

    [x] 79.1.2 Task - Harden provider selection and degraded runtime behavior
      Make the initial ETS path stable and optional future providers legible
      without turning provider-specific issues into conversation failures.

      [x] 79.1.2.1 Subtask - Keep ETS as the cheap default provider while
        defining the contract for optional Redis or stronger future providers.
      [x] 79.1.2.2 Subtask - Add explicit configuration validation, rollout
        messaging, and structured logging for disabled, degraded, or
        misconfigured prompt-memory providers.
      [x] 79.1.2.3 Subtask - Preserve deterministic fallback to the current
        bounded runtime path whenever provider behavior is unavailable,
        recovering, or not trustworthy.
      [x] 79.1.2.4 Subtask - Validate provider aliases, provider options, store
        options, timeout values, and item limits at the adapter boundary before
        conversation runtime attempts retrieval or writes.

  [x] 79.2 Section - Promotion Boundary, Verification, And Contributor Guidance
    Converge the rest of the product and contributor story around the rule that
    prompt memory helps the next turn while provenance and durable memory own
    long-term explainability and product truth.

    [x] 79.2.1 Task - Preserve the split between prompt memory, provenance, and durable memory
      Make the boundary between short-term prompt context and long-term product
      memory explicit in both code seams and supporting documentation.

      [x] 79.2.1.1 Subtask - Keep prompt-memory records out of operator memory
        surfaces and out of any ambient durable-memory projection unless they
        reenter through explicit adoption or classification.
      [x] 79.2.1.2 Subtask - Preserve provenance back-links and governed record
        truth whenever prompt-memory context helps seed later adoption or
        follow-up work.
      [x] 79.2.1.3 Subtask - Reject any remaining product or contributor path
        that implies prompt memory is an alternate transcript browser or a
        durable semantic source of truth.
      [x] 79.2.1.4 Subtask - Ensure prompt-memory diagnostics are observable as
        runtime health and fallback information without surfacing prompt-memory
        records as operator-facing durable memories.

    [x] 79.2.2 Task - Align verification defaults and contributor docs
      Make the new prompt-memory lane legible enough that future contributors
      use the right boundary and proof strategy for the right problem.

      [x] 79.2.2.1 Subtask - Document when contributors should use prompt
        memory, reopen conversation routes, inspect workflow provenance, or
        adopt durable memory.
      [x] 79.2.2.2 Subtask - Align `mix memory.verify`, conversation runtime
        verification, and prompt-memory-specific coverage with the final rollout
        defaults.
      [x] 79.2.2.3 Subtask - Update contributor or developer guidance so no
        durable-memory or semantic docs imply that bounded prompt context is the
        same thing as repository memory or long-term recall.
      [x] 79.2.2.4 Subtask - Document the adapter contract: use
        `ContextMemory` for short-term prompt help, use conversation routes for
        transcript continuity, use workflow provenance for origin recall, and
        use durable-memory adoption for long-term product truth.

  [ ] 79.3 Section - Phase 79 Integration Tests
    Prove prompt memory stays bounded and operationally safe once lifecycle
    cleanup, provider hardening, and contributor-facing defaults are in place.

    [ ] 79.3.1 Task - Add lifecycle and boundary-hardening coverage
      Verify prompt memory can expire, degrade, and coexist with provenance and
      durable memory without becoming a second truth lane.

      [ ] 79.3.1.1 Subtask - Add coverage proving expired or consolidated
        prompt-memory records stop influencing retrieval while active bounded
        context still remains available for the next turn.
      [ ] 79.3.1.2 Subtask - Add coverage proving provider misconfiguration,
        disablement, or degradation falls back safely and leaves conversation
        execution plus provenance capture intact.
      [ ] 79.3.1.3 Subtask - Add coverage proving prompt memory does not appear
        as durable memory or transcript truth unless later work explicitly
        adopts bounded outcomes through the existing governed memory path.
      [ ] 79.3.1.4 Subtask - Add coverage proving adapter-level config
        validation and lifecycle cleanup failures degrade conversation runtime
        deterministically without dropping provenance capture.
