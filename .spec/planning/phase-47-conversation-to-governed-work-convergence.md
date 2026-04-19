# Phase 47 - Conversation To Governed Work Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items -->
<!-- covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage -->
<!-- covers: architecture.work_synthesis.productive_conversations_route_through_work_resolution -->
<!-- covers: architecture.work_synthesis.work_item_origin_can_preserve_conversation_context -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/work_synthesis.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../decisions/jido_code.factory_control_plane.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `lib/jido_code/conversations.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/snapshot.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/operations/work_item.ex`
- `lib/jido_code/operations/work_synthesis.ex`
- `lib/jido_code/operations/synthesis.ex`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code/workbench/project_detail.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `test/jido_code/phase_forty_six_integration_test.exs`
- `test/jido_code_web/live/project_detail_live_test.exs`

## Relevant Assumptions / Defaults
- Phase 46 cut the managed-repository conversation route over to a real LLM-backed runtime, but productive turns can still remain repo-scoped runtime state instead of rejoining the canonical governed `WorkItem` loop.
- The control plane already defines `WorkItem` as the canonical operational record between assessment and execution, so conversation-driven work should reuse that boundary rather than invent a second durable work model.
- AgentOS runtime topology remains one `CodingPod` per `WorkItem`, which means conversation routing should converge on explicit work-item scope before durable specialist execution becomes long-lived governed work.
- The next cut should preserve greenfield clarity: no hidden dual path where some productive conversation work stays conversation-local while some work reenters governed `WorkItem` records.

[x] 47 Phase 47 - Conversation To Governed Work Convergence
  Make productive repository conversations create, attach, steer, and surface canonical `WorkItem` scope so governed work stops living implicitly inside repo-scoped conversation runtime state.

  [x] 47.1 Section - WorkItem Attachment Boundary
    Introduce the product-owned seam that turns productive repository conversation turns into canonical governed work-item attachment instead of leaving durable work implicit in conversation state.

    [x] 47.1.1 Task - Add canonical work-item resolution for productive conversation turns
      Decide when a repo-scoped conversation turn must create, attach, or reuse a `WorkItem` and make that resolution explicit before durable specialist execution continues.

      [x] 47.1.1.1 Subtask - Add a bounded conversation-to-work resolution boundary that can create a new `WorkItem` or reuse an equivalent open work item for productive turns.
      [x] 47.1.1.2 Subtask - Preserve managed-repository scope, initiating actor, turn identity, and conversation linkage as work is attached to canonical governed records.
      [x] 47.1.1.3 Subtask - Keep the conversation-to-work decision explainable so operators can tell why a turn reused existing work, created new work, or halted before execution.

    [x] 47.1.2 Task - Persist work-item linkage in conversation state and APIs
      Make attached governed work visible through snapshots, route helpers, and conversation records instead of hiding it inside transient runtime metadata.

      [x] 47.1.2.1 Subtask - Persist the active `work_item_id` and attachment metadata in conversation snapshots and replayable event state.
      [x] 47.1.2.2 Subtask - Allow later conversation turns to reuse or explicitly steer that governed work-item attachment rather than creating hidden conversation-local work.
      [x] 47.1.2.3 Subtask - Preserve repo-scoped exploratory conversation behavior for non-productive turns while keeping durable work-item promotion explicit once governed work begins.

  [x] 47.2 Section - Runtime And Surface Convergence
    Converge runtime routing and operator surfaces on the canonical `WorkItem` loop so the repo conversation experience stays product-owned and legible after work-item attachment.

    [x] 47.2.1 Task - Route durable specialist execution through explicit work-item scope
      Ensure productive conversation execution uses the same governed work-item substrate the CodingPod and AgentWorkspace already expect.

      [x] 47.2.1.1 Subtask - Ensure productive conversation execution resolves `WorkItem` scope before using long-lived CodingPod specialist paths.
      [x] 47.2.1.2 Subtask - Reuse the per-`WorkItem` CodingPod lifecycle and queue semantics instead of keeping a parallel repo-conversation durable execution model.
      [x] 47.2.1.3 Subtask - Keep pause, resume, clarification, and stop semantics coherent when conversation turns are attached to governed work items.

    [x] 47.2.2 Task - Surface conversation and work-item linkage to operators
      Show the relationship between repo conversations and canonical governed work across the main operator surfaces.

      [x] 47.2.2.1 Subtask - Show attached `WorkItem` identity and status on the managed-repository conversation surface instead of requiring inference from transcript text.
      [x] 47.2.2.2 Subtask - Let operators follow or resume attached work from repo detail, workbench, or adjacent governed surfaces through product-owned links and helpers.
      [x] 47.2.2.3 Subtask - Keep degraded and readiness messaging explicit when work-item resolution or governed work continuation cannot proceed.

  [x] 47.3 Section - Integration Coverage And Current-Truth Convergence
    Prove conversation-to-work convergence end to end and keep the current-truth spec layer aligned with the canonical governed-work model.

    [x] 47.3.1 Task - Add end-to-end coverage for conversation-driven governed work
      Verify productive conversations now create, attach, and steer canonical `WorkItem` scope rather than keeping durable work implicit in conversation runtime state.

      [x] 47.3.1.1 Subtask - Add coverage proving a productive repo conversation turn creates or reuses a canonical `WorkItem` before durable execution continues.
      [x] 47.3.1.2 Subtask - Add coverage proving conversation snapshots and events preserve the attached `work_item_id` plus origin metadata through clarification, resume, and steering.
      [x] 47.3.1.3 Subtask - Add coverage proving equivalent conversation-driven work demand reuses or reprioritizes existing open work instead of spawning uncontrolled duplicate governed work.

    [x] 47.3.2 Task - Converge specs, planning, and operator expectations
      Keep the spec layer and rollout plan coherent once repo conversations stop being a parallel durable work model.

      [x] 47.3.2.1 Subtask - Update current-truth conversation and work-synthesis specs to describe the canonical conversation-to-work-item flow.
      [x] 47.3.2.2 Subtask - Verify the planning index remains coherent after Phase 47 is introduced and that no dual durable-work path remains implied in the product contract.
      [x] 47.3.2.3 Subtask - Keep contributor guidance and operator language aligned so repo conversations are understood as an entrypoint into governed work rather than a separate truth lane.
