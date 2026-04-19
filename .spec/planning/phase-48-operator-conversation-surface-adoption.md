# Phase 48 - Operator Conversation Surface Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/work_synthesis.spec.md`
- `lib/jido_code/conversations.ex`
- `lib/jido_code/conversations/conversation.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/operations/work_item.ex`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code/workbench/inventory.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `lib/jido_code_web/live/run_detail_live.ex`
- `test/jido_code/phase_forty_seven_integration_test.exs`
- `test/jido_code_web/live/workbench_live_test.exs`
- `test/jido_code_web/live/run_detail_live_test.exs`

## Relevant Assumptions / Defaults
- Phase 47 made productive repo conversations attach to canonical `WorkItem` scope, but the strongest operator projection still lives on repo detail.
- Workbench remains the main managed-repository inventory surface, so it should show whether a repo already has active governed conversation work before operators launch redundant flows.
- Governed run detail already projects work-item, evidence, decision, and memory context, so it should also make conversation lineage legible when a run is executing work that originated from or remains attached to productive conversation scope.
- The project remains greenfield: operator surfaces should adopt the canonical conversation and work model directly instead of preserving a separate compatibility-era “chat metadata” interpretation layer.

[x] 48 Phase 48 - Operator Conversation Surface Adoption
  Project canonical repo-conversation, governed-work, and governed-run linkage across the remaining operator surfaces so operators can follow active conversation-driven work without reconstructing it from transcript text or raw work metadata.

  [x] 48.1 Section - Workbench Conversation Projection
    Extend the product-owned conversation projection boundary to Workbench so managed-repository inventory rows show active repo conversation and attached governed work status.

    [x] 48.1.1 Task - Add reusable managed-repository conversation projections
      Reuse the canonical repo-conversation projection boundary rather than teaching Workbench to query conversation persistence or runtime details directly.

      [x] 48.1.1.1 Subtask - Expose a product-owned managed-repository conversation projection that Workbench can consume without reimplementing snapshot or work-item lookup logic.
      [x] 48.1.1.2 Subtask - Keep projection behavior explicit when no repo conversation exists or when the latest snapshot is temporarily unavailable.
      [x] 48.1.1.3 Subtask - Preserve attached governed work-item identity, resolution detail, and route-level action labels in the shared projection.

    [x] 48.1.2 Task - Surface repo conversation state on Workbench rows
      Show operators when a managed repository already has active productive conversation work and how to continue it from the canonical route.

      [x] 48.1.2.1 Subtask - Add bounded repo-conversation status, resolution detail, and attached work-item summary to managed-repository inventory rows.
      [x] 48.1.2.2 Subtask - Keep Workbench routing product-owned by linking operators back to repo detail for continued conversation work.
      [x] 48.1.2.3 Subtask - Preserve explicit degraded messaging when conversation projection data is unavailable instead of silently hiding that state.

  [x] 48.2 Section - Governed Run Conversation Lineage
    Project conversation lineage onto governed run detail so operators can tell when governed execution came from productive repo conversation work and where to continue it.

    [x] 48.2.1 Task - Resolve conversation lineage from canonical governed work
      Load the relevant conversation projection from `WorkItem` scope and preserved conversation-origin metadata instead of inventing a run-local conversation model.

      [x] 48.2.1.1 Subtask - Add a product-owned way to resolve the latest or originating conversation for a canonical `WorkItem`.
      [x] 48.2.1.2 Subtask - Reuse preserved work-item conversation-origin metadata so governed run detail can explain where the work came from even when the runtime is idle.
      [x] 48.2.1.3 Subtask - Keep missing or stale conversation lineage explicit instead of implying the run has no conversation relationship.

    [x] 48.2.2 Task - Surface conversation lineage on governed run detail
      Show the bounded relationship between governed run execution, the attached `WorkItem`, and any productive repo conversation that created or continues that work.

      [x] 48.2.2.1 Subtask - Add a governed-run panel that shows conversation identity, status, route-level action, and preserved origin metadata when available.
      [x] 48.2.2.2 Subtask - Let operators follow governed run conversation lineage back to the managed-repository detail surface instead of inventing a separate run-chat route.
      [x] 48.2.2.3 Subtask - Preserve clear empty-state messaging when a governed run has no linked work item or no productive conversation origin.

  [x] 48.3 Section - Integration Coverage And Current-Truth Convergence
    Prove the new operator projections end to end and keep the current-truth spec and contributor guidance aligned with the adopted surface model.

    [x] 48.3.1 Task - Add operator-surface coverage for conversation projections
      Verify Workbench and governed run detail now project canonical conversation linkage rather than leaving operators to infer it from internal metadata.

      [x] 48.3.1.1 Subtask - Add Workbench coverage proving a managed-repository row shows active repo conversation status and attached governed work after productive conversation execution.
      [x] 48.3.1.2 Subtask - Add run-detail coverage proving preserved conversation origin and current conversation linkage appear when a governed run executes conversation-driven work.
      [x] 48.3.1.3 Subtask - Add integration coverage proving work-item-scoped conversation lineage remains product-owned and explainable across repo detail, Workbench, and governed run surfaces.

    [x] 48.3.2 Task - Converge specs, planning, and contributor guidance
      Keep the spec and documentation layers coherent once Workbench and governed run detail adopt the canonical conversation projection model.

      [x] 48.3.2.1 Subtask - Update current-truth conversation and factory-control-plane specs to describe Workbench and governed run conversation projections.
      [x] 48.3.2.2 Subtask - Mark Phase 48 complete in planning once all operator-surface adoption work lands without leaving implied compatibility lanes.
      [x] 48.3.2.3 Subtask - Update contributor-facing developer guidance so conversation linkage expectations across repo detail, Workbench, and run detail stay clear.
