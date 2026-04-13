# Phase 39 - Conversation Coordinator And Command Foundation

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped -->
<!-- covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state -->
<!-- covers: architecture.conversation_orchestration.control_and_work_commands_are_distinct -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/work_synthesis.spec.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `../decisions/jido_code.jido_agent_os_integration.md`
- `../decisions/jido_code.factory_control_plane.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code_web/live/demos/chat_live.ex`
- `lib/jido_code_web/live/forge/show_live.ex`
- `lib/jido_code/operations/work_item.ex`
- `test/jido_code/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- The new conversation model is product-owned and must attach coding conversations to explicit managed-repository scope rather than preserving page-local chat as the durable unit.
- When a conversation becomes actionable factory work, it should steer an existing `WorkItem` or create one through bounded product-owned seams instead of bypassing the control plane.
- AgentWorkspace remains the runtime boundary that hides kernel and pod topology from LiveView or controller callers even if a new conversation driver is introduced beside it.
- The polling-oriented demo chat surface is transitional and may continue to exist temporarily while the canonical conversation foundation is introduced.

[x] 39 Phase 39 - Conversation Coordinator And Command Foundation
  Establish the canonical conversation scope, coordinator boundary, and command-admission model so productive coding conversations become governed runtime objects rather than ad hoc chat turns.

  [x] 39.1 Section - Canonical Conversation Scope And Identity
    Define what a productive coding conversation is in product terms and ensure it binds cleanly to managed repositories and durable work context.

    [x] 39.1.1 Task - Introduce a canonical conversation record and identity model
      Define the identifiers, scope metadata, and lifecycle fields that let the product talk about conversations as first-class bounded objects.

      [x] 39.1.1.1 Subtask - Define canonical conversation identifiers, correlation metadata, actor attribution, and repo/work-item attachment fields.
      [x] 39.1.1.2 Subtask - Decide when a conversation must attach to an existing `WorkItem`, when it may synthesize a new one, and when it remains repo-scoped but pre-work.
      [x] 39.1.1.3 Subtask - Keep the conversation contract product-owned and explicit about repository scope without leaking kernel, pod, or model-session internals.

    [x] 39.1.2 Task - Align conversation entrypoints with the factory control plane
      Ensure operator- or workflow-originated coding conversations enter through bounded product seams that preserve attribution and durable work context.

      [x] 39.1.2.1 Subtask - Add or refine product-owned entrypoints that normalize conversation start and resume requests with managed-repository scope.
      [x] 39.1.2.2 Subtask - Preserve initiating actor, source metadata, and requested objective so conversation history stays explainable alongside work synthesis.
      [x] 39.1.2.3 Subtask - Keep conversation start behavior compatible with steering existing work instead of always creating fresh parallel work objects.

  [x] 39.2 Section - Coordinator Boundary And Command Admission
    Add the coordinator layer that owns turn admission, state transitions, and command normalization before interruption and event streaming are layered on top.

    [x] 39.2.1 Task - Introduce the product-owned conversation coordinator and driver boundary
      Create the runtime-owned boundary that sits beside `AgentWorkspace` and becomes the single owner of turn state for an active conversation.

      [x] 39.2.1.1 Subtask - Introduce a canonical conversation driver or coordinator module that owns admission, snapshots, and turn lifecycle state.
      [x] 39.2.1.2 Subtask - Route the coordinator through AgentWorkspace or adjacent workspace-owned helpers so LiveViews do not address pods directly.
      [x] 39.2.1.3 Subtask - Keep the boundary compatible with one CodingPod per `WorkItem` while making room for pre-work repo-scoped conversations.

    [x] 39.2.2 Task - Split work commands from control commands
      Establish the explicit command vocabulary that later phases will use for interruption, steering, and tool-result handling.

      [x] 39.2.2.1 Subtask - Define canonical work commands such as `turn.submit`, `tool_result.submit`, and `turn.resume`.
      [x] 39.2.2.2 Subtask - Define canonical control commands such as `turn.stop`, `turn.steer`, `tool.cancel`, `session.pause`, and `session.resume`.
      [x] 39.2.2.3 Subtask - Validate and normalize command payloads at the coordinator boundary so callers never depend on raw model- or tool-local shapes.

    [x] 39.2.3 Task - Materialize the baseline turn lifecycle
      Introduce the turn-state model the coordinator will use before more advanced cancellation and eventing semantics arrive.

      [x] 39.2.3.1 Subtask - Define queued, running, awaiting-input, completed, cancelled, superseded, and failed turn states with explicit transitions.
      [x] 39.2.3.2 Subtask - Preserve supersedes and superseded references so later steering behavior can remain explainable and auditable.
      [x] 39.2.3.3 Subtask - Keep turn lifecycle shaping product-readable and detached from any one provider or model runtime.

  [x] 39.3 Section - Phase 39 Integration Tests
    Verify the new conversation foundation produces bounded scope, canonical command handling, and explainable turn lifecycle behavior before interruption semantics build on it.

    [x] 39.3.1 Task - Scope and entrypoint scenarios
      Prove conversations bind to the correct repo and work context through product-owned entrypoints.

      [x] 39.3.1.1 Subtask - Add coverage proving conversation start and resume preserve managed-repository scope and actor attribution.
      [x] 39.3.1.2 Subtask - Add coverage proving actionable conversations can steer existing `WorkItem` context instead of always spawning unrelated work.
      [x] 39.3.1.3 Subtask - Add coverage proving LiveView and workflow callers stay insulated from kernel and pod topology.

    [x] 39.3.2 Task - Command and lifecycle scenarios
      Prove the coordinator recognizes the new command vocabulary and turn-state model cleanly.

      [x] 39.3.2.1 Subtask - Add coverage proving work and control commands are normalized through distinct product-owned shapes.
      [x] 39.3.2.2 Subtask - Add coverage proving baseline turn lifecycle transitions remain explicit and auditable.
      [x] 39.3.2.3 Subtask - Verify the spec workspace remains coherent after Phase 39 introduces the conversation foundation.
