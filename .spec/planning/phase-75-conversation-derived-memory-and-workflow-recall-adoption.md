# Phase 75 - Conversation-Derived Memory And Workflow Recall Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections -->
<!-- covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_graph_workflow_and_operator_expansion.spec.md`
- `../specs/work_synthesis.spec.md`
- `../decisions/jido_code.conversation_history_long_term_capture.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.memory_graph_workflow_and_operator_expansion.md`
- `lib/jido_code/memory_graph/product_service.ex`
- `lib/jido_code/memory_graph/workflow_service.ex`
- `lib/jido_code/memory_graph/follow_up_surface.ex`
- `lib/jido_code/memory_graph/materialization.ex`
- `lib/jido_code/memory_graph/governed_adoption.ex`
- `lib/jido_code/agent_workspace.ex`
- `test/jido_code/memory_graph_product_service_test.exs`
- `test/jido_code/memory_graph_workflow_service_test.exs`
- `test/jido_code/memory_graph_governed_adoption_test.exs`

## Relevant Assumptions / Defaults
- Phase 74 has already added bounded conversation-origin provenance capture to
  the semantic stack.
- The product already has bounded memory and workflow-provenance services, but
  it does not yet treat conversation-derived origin context as a first-class
  retrieval and adoption shape.
- Durable conversation-derived takeaways still require explicit adoption or
  classification before they become `memory`.
- Workflows should receive conversation-derived context only through explicit,
  bounded product-owned requests rather than ambient transcript loading.

[ ] 75 Phase 75 - Conversation-Derived Memory And Workflow Recall Adoption
  Add product-owned retrieval, explicit adoption, and workflow request paths so
  conversation-derived provenance can inform later work without exposing raw
  transcripts or bypassing durable-memory rules.

  [ ] 75.1 Section - Product-Owned Conversation Recall And Adoption Boundaries
    Extend the product-owned memory stack so conversation-derived origin context
    becomes retrievable, explainable, and adoptable through the same bounded
    semantic seams as the rest of repository memory.

    [ ] 75.1.1 Task - Add bounded conversation-derived provenance projections
      Expose conversation-origin context through product-owned service helpers
      rather than raw graph queries or transcript scraping.

      [ ] 75.1.1.1 Subtask - Add repository- and work-item-scoped service
        helpers for recalling bounded conversation-origin provenance.
      [ ] 75.1.1.2 Subtask - Shape product-readable origin summaries that keep
        conversation identity, turn lineage, governed links, and freshness
        state explicit without exposing raw graph internals.
      [ ] 75.1.1.3 Subtask - Keep transcript reopening and raw conversation
        continuity outside the product memory service boundary.

    [ ] 75.1.2 Task - Add explicit conversation-derived memory adoption seams
      Turn only intentionally classified conversation outcomes into durable
      memory classes instead of treating all semantic recall as long-term
      memory.

      [ ] 75.1.2.1 Subtask - Add explicit classification or adoption paths for
        conversation-derived decisions, conventions, lessons, known issues,
        open questions, patterns, and similar durable takeaways.
      [ ] 75.1.2.2 Subtask - Preserve provenance back-links from adopted memory
        to the originating conversation lineage and governed records.
      [ ] 75.1.2.3 Subtask - Keep adopted memory reviewable, freshness-aware,
        and separable from the underlying conversation transcript.

  [ ] 75.2 Section - Workflow And Governed Follow-Up Adoption
    Let later workflows and governed product paths request conversation-derived
    recall explicitly and use it safely for follow-up work.

    [ ] 75.2.1 Task - Add explicit workflow recall options for conversation-derived context
      Extend the bounded workflow memory service so planning, execution,
      review, and explanation can request conversation-origin recall when it is
      relevant.

      [ ] 75.2.1.1 Subtask - Add explicit retrieval options for
        conversation-derived provenance alongside existing memory and workflow
        provenance requests.
      [ ] 75.2.1.2 Subtask - Shape workflow-safe selected origin context
        without injecting raw transcript bodies or unbounded turn history.
      [ ] 75.2.1.3 Subtask - Keep degraded, stale, or unavailable
        conversation-derived recall safe and explainable for workflow callers.

    [ ] 75.2.2 Task - Materialize conversation-derived findings back into governed records
      Ensure conversation-derived recall influences factory behavior only when
      it reenters canonical governed records.

      [ ] 75.2.2.1 Subtask - Allow bounded governed follow-up from
        conversation-derived provenance or adopted memory into Observation,
        Assessment, WorkItem, Evidence, or Decision records.
      [ ] 75.2.2.2 Subtask - Preserve origin provenance, freshness, and
        adoption metadata when those conversation-derived findings rejoin the
        control plane.
      [ ] 75.2.2.3 Subtask - Keep the graph as a supporting semantic layer
        rather than an alternate product system of record for conversation work.

  [ ] 75.3 Section - Phase 75 Integration Tests
    Prove product-owned retrieval, workflow recall, and durable-memory adoption
    remain bounded and explainable once conversation-derived semantic recall is
    added.

    [ ] 75.3.1 Task - Add product-service and workflow recall coverage
      Verify the product can retrieve and use bounded conversation-derived
      context without reopening full transcripts or exposing raw graph access.

      [ ] 75.3.1.1 Subtask - Add coverage proving product-owned services return
        bounded conversation-origin projections with explicit freshness and
        governed-link metadata.
      [ ] 75.3.1.2 Subtask - Add coverage proving workflows receive
        conversation-derived recall only when explicitly requested and in a
        bounded, workflow-safe form.
      [ ] 75.3.1.3 Subtask - Add coverage proving classified
        conversation-derived takeaways become durable `memory` only through
        explicit adoption paths.
