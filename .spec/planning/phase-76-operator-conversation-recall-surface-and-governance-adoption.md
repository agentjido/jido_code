# Phase 76 - Operator Conversation Recall Surface And Governance Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections -->
<!-- covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_graph_surface_rollout_and_governance_actions.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../decisions/jido_code.conversation_history_long_term_capture.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.memory_graph_surface_rollout_and_governance_actions.md`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code/workbench/project_memory_inspection.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `lib/jido_code_web/live/run_detail_live.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/components/conversation_surface_components.ex`
- `lib/jido_code_web/components/memory_surface_components.ex`
- `test/jido_code_web/live/project_detail_live_test.exs`
- `test/jido_code_web/live/workbench_live_test.exs`
- `test/jido_code_web/live/run_detail_live_test.exs`
- `test/e2e/conversation-ui.spec.ts`
- `test/e2e/operator-navigation.spec.ts`

## Relevant Assumptions / Defaults
- Phase 75 has already introduced bounded conversation-derived provenance
  projections, explicit adoption seams, and workflow-safe recall options.
- Repo detail remains the canonical host for both active conversation
  continuity and repository memory/provenance inspection, but the two surfaces
  should not collapse into one transcript-plus-memory hybrid pane.
- Workbench, dashboard inventory, and governed follow-up surfaces may project
  bounded conversation-derived recall when it helps operators understand origin
  and next action.
- Operator surfaces should cross-link back to canonical conversation routes for
  full continuity and transcript review rather than reimplementing a transcript
  browser inside memory or governed surfaces.

[ ] 76 Phase 76 - Operator Conversation Recall Surface And Governance Adoption
  Roll bounded conversation-derived recall into canonical operator and governed
  surfaces so conversation-driven origin context becomes explorable and
  actionable without replacing the conversation UI or the control plane.

  [ ] 76.1 Section - Canonical Operator Surface Recall Adoption
    Add conversation-derived provenance and adopted-memory projections to the
    operator routes where origin and follow-up context are most useful.

    [ ] 76.1.1 Task - Project bounded conversation-origin context on canonical routes
      Show the origin of governed work and adopted memory through product-owned
      summaries and cross-links instead of requiring transcript reconstruction.

      [ ] 76.1.1.1 Subtask - Add bounded conversation-origin projections to
        managed-repository detail where memory, provenance, and conversation
        surfaces already coexist.
      [ ] 76.1.1.2 Subtask - Add bounded conversation-origin hints to
        Workbench, dashboard inventory, or governed-run follow-up surfaces when
        they improve triage and operator orientation.
      [ ] 76.1.1.3 Subtask - Cross-link from those bounded projections back to
        the canonical conversation route when full transcript continuity or
        active supervision is needed.

    [ ] 76.1.2 Task - Keep the UI bounded and product-shaped
      Make sure operator recall surfaces improve explainability without
      becoming graph tooling or alternate transcript shells.

      [ ] 76.1.2.1 Subtask - Keep raw transcript bodies, raw SPARQL, and raw
        graph internals out of memory and governed surfaces.
      [ ] 76.1.2.2 Subtask - Preserve the route-owned split where conversation
        routes own continuity and transcript detail while memory or governed
        surfaces own bounded semantic origin summaries.
      [ ] 76.1.2.3 Subtask - Keep freshness, degradation, recovery, and
        unavailability explicit when conversation-derived recall cannot be
        trusted or loaded.

  [ ] 76.2 Section - Governed Follow-Up And Contributor Convergence
    Converge governed follow-up behavior and contributor expectations around
    the new conversation-derived recall model.

    [ ] 76.2.1 Task - Adopt conversation-derived recall into governed actions
      Let governed product paths use bounded conversation-derived origin context
      for follow-up work, evidence review, and decision reconsideration.

      [ ] 76.2.1.1 Subtask - Add bounded follow-up affordances that can create
        or refine governed work from conversation-derived provenance and adopted
        memory.
      [ ] 76.2.1.2 Subtask - Preserve canonical repo, work-item, evidence, and
        decision linkage when operators act on those conversation-derived
        findings.
      [ ] 76.2.1.3 Subtask - Keep governed records, not semantic recall, as the
        durable product truth once action is taken.

    [ ] 76.2.2 Task - Align contributor guidance and verification defaults
      Make the new long-term conversation recall model legible to future
      contributors so they use the right boundary for the right question.

      [ ] 76.2.2.1 Subtask - Document when contributors should reopen the
        conversation route, query bounded provenance, or adopt durable memory.
      [ ] 76.2.2.2 Subtask - Keep `mix memory.verify`, `mix semantic.verify`,
        and route-level proof aligned with the new conversation-derived recall
        behavior.
      [ ] 76.2.2.3 Subtask - Ensure no remaining planning or contributor docs
        imply that full transcript history should become ambient durable memory.

  [ ] 76.3 Section - Phase 76 Integration Tests
    Prove operator and governed surfaces can use conversation-derived recall
    safely, clearly, and without regressing the canonical conversation route
    model.

    [ ] 76.3.1 Task - Add operator-surface and governed-follow-up coverage
      Verify the final rollout keeps recall bounded, cross-linked, and
      contributor-friendly across the product.

      [ ] 76.3.1.1 Subtask - Add route coverage proving bounded
        conversation-origin projections render on managed-repository, workbench,
        dashboard, or governed-run surfaces without exposing raw transcript or
        graph internals.
      [ ] 76.3.1.2 Subtask - Add coverage proving operator follow-up from
        conversation-derived provenance or adopted memory preserves governed
        linkage and canonical product truth.
      [ ] 76.3.1.3 Subtask - Add browser and route coverage proving operators
        can move from bounded origin summaries back to the canonical
        conversation route when full continuity or transcript detail is needed.
