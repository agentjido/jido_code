# Conversation Orchestration

This subject defines how productive coding conversations are coordinated across
durable work scope, interruptible execution, and event-driven UI delivery.

```spec-meta
id: architecture.conversation_orchestration
kind: feature
status: active
summary: Jido.Code treats productive coding conversations as managed-repository and usually work-item-scoped mixed-initiative sessions coordinated through explicit control and work commands, append-only sequenced event streams, durable snapshots, bounded shared context, cancellable tool jobs, real LLM-backed turn execution through product-owned runtime boundaries, and event-driven LiveView plus PubSub delivery with reconnectable degraded fallbacks, including bounded managed-repository route adoption rather than snapshot polling, fake timer-driven turn simulation, or ad hoc FIFO chat handling.
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.jido_agent_os_integration
  - jido_code.interruptible_conversation_orchestration
surface:
  - lib/jido_code/conversations.ex
  - lib/jido_code/conversations/command.ex
  - lib/jido_code/conversations/conversation.ex
  - lib/jido_code/conversations/coordinator.ex
  - lib/jido_code/conversations/driver.ex
  - .spec/decisions/jido_code.interruptible_conversation_orchestration.md
  - lib/jido_code/conversations/event.ex
  - lib/jido_code/conversations/event_record.ex
  - lib/jido_code/conversations/persistence.ex
  - lib/jido_code/conversations/pub_sub.ex
  - lib/jido_code/conversations/snapshot.ex
  - lib/jido_code/conversations/snapshot_record.ex
  - lib/jido_code/conversations/turn.ex
  - lib/jido_code/conversations/runtime.ex
  - lib/jido_code/conversations/work_resolution.ex
  - lib/jido_code/agent_workspace.ex
  - lib/jido_code/operations/work_item.ex
  - lib/jido_code/agent_workspace/runtime_specialist_runner.ex
  - lib/jido_code/operations/synthesis.ex
  - lib/jido_code/pods/coding_pod.ex
  - lib/jido_code/agents/planner.ex
  - lib/jido_code/agents/coder.ex
  - lib/jido_code/agents/reviewer.ex
  - lib/jido_code/agents/refactorer.ex
  - lib/jido_code/agents/explainer.ex
  - lib/jido_code/workbench/project_conversation.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - lib/jido_code/setup/provider_credential_checks.ex
  - lib/jido_code/forge/pubsub.ex
  - lib/jido_code/orchestration/run_pubsub.ex
  - test/jido_code/phase_thirty_nine_integration_test.exs
  - test/jido_code/phase_forty_four_integration_test.exs
  - test/jido_code/phase_forty_six_integration_test.exs
  - test/jido_code/phase_forty_seven_integration_test.exs
  - test/jido_code/phase_forty_one_integration_test.exs
  - test/jido_code/phase_forty_two_integration_test.exs
  - test/jido_code_web/live/project_detail_live_test.exs
```

## Requirements

```spec-requirements
- id: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  statement: Coding conversations shall bind to explicit managed-repository scope and, when they act on durable factory work, shall attach to one existing or newly synthesized WorkItem rather than remaining free-floating page-local chat state.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items
  statement: When a repository conversation turn becomes durable planning, implementation, review, or governed follow-up work, the product shall create, attach, or steer a canonical `WorkItem` through product-owned work-resolution boundaries instead of leaving governed work implicit in repo-scoped conversation state.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
  statement: Each active coding conversation shall have one coordinator responsible for command admission, turn state, cancellation, event sequencing, and snapshots, with AgentWorkspace or an adjacent product-owned boundary hiding runtime topology from LiveViews.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.control_and_work_commands_are_distinct
  statement: Conversation admission shall distinguish control commands from work commands instead of treating all user messages as one FIFO queue.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.control_lane_preempts_work_lane
  statement: Stop, steer, pause, resume, and tool-cancel commands shall be admitted through a single high-priority control lane that drains before queued work turns, while arbitrary multi-level message priorities shall not be part of the product contract.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.active_turns_can_be_superseded
  statement: A newly admitted control command shall be able to supersede an active or queued work turn, preserving explicit supersedes and superseded references plus terminal settlement state instead of silently dropping work.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
  statement: Long-running tool invocations shall execute as child jobs or bounded workers outside the coordinator mailbox and shall support cooperative cancellation plus explicit terminal settlement when cancellation races with completion.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.cancellation_lifecycle_is_evented
  statement: Conversation runtime shall emit distinct cancel-requested, cancellation-acknowledged, cancelled, and cancel-failed outcomes so operator surfaces can reflect interruption progress before underlying tools fully settle.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
  statement: Conversation state shall derive from an append-only event log with monotonic per-conversation sequence numbers, stable turn, tool, and message identifiers, actor attribution, timestamps, and correlation metadata needed for replay and reconnect.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  statement: LiveView and adjacent browser surfaces shall subscribe to conversation events through product-owned PubSub topics and stream incremental updates, using snapshots only for initial load or reconnect recovery rather than steady-state polling.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  statement: When live event delivery or runtime coordination is unavailable, operator surfaces shall degrade to persisted conversation status and event history with explicit continuity messaging rather than exposing raw runtime failures.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.steering_preserves_short_term_context
  statement: Steering or superseding a turn shall preserve bounded shared short-term context such as the active work item, referenced files, accepted tool results, and pending clarification state so users can redirect work without restating the whole task.
  priority: should
  stability: proposed

- id: architecture.conversation_orchestration.expensive_work_announces_intent
  statement: Before expensive tool use or long-running execution, the assistant should emit a concise intent or plan event that tells the user what it is about to inspect or execute and why.
  priority: should
  stability: proposed

- id: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
  statement: Managed-repository operator routes should be able to open, resume, and guide bounded repo-scoped conversations through product-owned workspace and service boundaries without forcing the operator onto a separate chat-only surface.
  priority: should
  stability: proposed

- id: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  statement: Managed-repository and adjacent governed-work surfaces should show when a productive conversation is attached to a `WorkItem` and allow operators to follow or resume the canonical governed work loop from that linkage.
  priority: should
  stability: proposed

- id: architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
  statement: Product-facing repository or work-scoped conversation turns that claim active execution shall run through a real LLM-backed runtime path, specialist agent, or equivalent product-owned execution boundary rather than LiveView-local timer simulation or fake progress events.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  statement: Conversation runtime shall assemble prompts, bounded shared context, tool access, and model execution through AgentWorkspace, CodingPod specialists, or an adjacent product-owned conversation runtime boundary instead of embedding prompt assembly or model orchestration directly in LiveView surfaces.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
  statement: When a repository conversation cannot start or continue real LLM-backed execution because provider credentials, runtime services, or policy prerequisites are unavailable, operator surfaces shall render explicit readiness or recovery states instead of simulating successful work.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.real_runtime_cutover_has_no_compatibility_mode
  statement: The real conversation-runtime cutover shall remove the fake repository-conversation execution path rather than preserving a backward-compatibility shim, feature-flagged legacy mode, or parallel simulated runtime after adoption.
  priority: must
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.conversation_orchestration.scenario_interrupts_supersede_active_tooling
  covers:
    - architecture.conversation_orchestration.control_lane_preempts_work_lane
    - architecture.conversation_orchestration.active_turns_can_be_superseded
    - architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
    - architecture.conversation_orchestration.cancellation_lifecycle_is_evented
  given:
    - A coding conversation is executing a long-running tool call for an active turn.
  when:
    - The user issues a stop or steer command.
  then:
    - The control command is admitted ahead of queued work.
    - The active turn is marked as superseding or cancelling rather than disappearing silently.
    - The tool worker receives cancellation.
    - Event subscribers can observe cancellation progress before final settlement.

- id: architecture.conversation_orchestration.scenario_control_overtakes_queued_work
  covers:
    - architecture.conversation_orchestration.control_and_work_commands_are_distinct
    - architecture.conversation_orchestration.control_lane_preempts_work_lane
  given:
    - A conversation already has one or more queued work turns.
  when:
    - A control command arrives after those work turns were queued.
  then:
    - The control lane drains before the queued work lane.
    - Product behavior remains explainable without exposing arbitrary numeric priority classes to operators.

- id: architecture.conversation_orchestration.scenario_ui_recovers_after_stream_loss
  covers:
    - architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  given:
    - A browser surface has been receiving live conversation events.
  when:
    - The event subscription drops or the page reconnects mid-turn.
  then:
    - The surface reloads the latest snapshot and last accepted sequence.
    - New events continue from the next available sequence.
    - The user sees explicit continuity or degraded-mode messaging when gaps cannot be recovered live.

- id: architecture.conversation_orchestration.scenario_clarification_recovers_through_persistence
  covers:
    - architecture.conversation_orchestration.control_and_work_commands_are_distinct
    - architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.steering_preserves_short_term_context
  given:
    - A conversation has active child work that already emitted progress or stdout updates.
    - That child work requests clarification before the active turn can finish.
  when:
    - The coordinator stops or the browser reconnects before the operator responds, and the operator later answers through `turn.resume`.
  then:
    - Persisted snapshots retain the pending clarification plus bounded runtime context needed to continue.
    - Replayed events preserve progress, stdout, clarification, resume, and settlement ordering.
    - The resumed turn continues from awaiting-input state instead of queueing unrelated new work.

- id: architecture.conversation_orchestration.scenario_steering_keeps_shared_context
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.steering_preserves_short_term_context
  given:
    - A conversation already has explicit repository scope, work context, and accepted tool results.
  when:
    - The user narrows or redirects the task without starting a separate unrelated conversation.
  then:
    - The conversation stays attached to the same managed repository and work context unless the user explicitly changes scope.
    - Bounded short-term context remains available to the next turn.

- id: architecture.conversation_orchestration.scenario_steering_rejoins_canonical_work
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items
    - architecture.conversation_orchestration.steering_preserves_short_term_context
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  given:
    - A conversation already has bounded shared context and managed-repository scope.
  when:
    - The user steers that conversation toward an existing or newly governed work item.
  then:
    - The durable conversation record reflects the updated work-item scope.
    - The governed work loop preserves actor attribution and steering auditability on the canonical `WorkItem`.
    - Persisted conversation snapshots retain the bounded shared context needed for the redirected work.

- id: architecture.conversation_orchestration.scenario_repo_conversation_creates_or_reuses_governed_work
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items
    - architecture.conversation_orchestration.steering_preserves_short_term_context
  given:
    - A managed-repository conversation has repo scope and no active governed work item yet.
    - The operator submits a productive turn that should become durable planning, implementation, review, or follow-up work.
  when:
    - The product admits that turn into the governed work loop.
  then:
    - A canonical `WorkItem` is created or an equivalent existing work item is reused through a product-owned work-resolution boundary before durable execution continues.
    - The conversation snapshot records the attached `work_item_id` and later turns reuse or steer that governed work explicitly rather than creating hidden conversation-local work state.
    - The product preserves the turn and actor context needed to explain why the conversation attached to that work item.

- id: architecture.conversation_orchestration.scenario_managed_repo_route_reuses_repo_conversation
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
  given:
    - A managed-repository detail route needs to show the latest bounded conversation state for that repository.
  when:
    - The operator opens or resumes the repository conversation from that route.
  then:
    - The product-owned route boundary reuses the latest active repo-scoped conversation when one already exists.
    - The route loads the latest durable snapshot and recent events through bounded workspace helpers.
    - Live delivery stays event-driven while degraded continuity still renders the latest durable conversation state.

- id: architecture.conversation_orchestration.scenario_operator_surfaces_expose_conversation_work_item_linkage
  covers:
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
    - architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  given:
    - A productive repository conversation is already attached to a canonical `WorkItem`.
  when:
    - An operator opens the managed-repository route or adjacent governed-work surface for that repository.
  then:
    - The product shows the attached `WorkItem` linkage and current governed work status without requiring the operator to infer it from raw conversation text.
    - The operator can follow or resume the governed work loop from that surfaced linkage rather than reopening a separate ad hoc path.

- id: architecture.conversation_orchestration.scenario_repo_conversation_executes_real_llm_turns
  covers:
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
    - architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  given:
    - A managed-repository detail route has an active repository conversation and the required LLM provider plus runtime prerequisites are available.
  when:
    - The operator submits a new repository conversation turn or resumes a clarification.
  then:
    - The coordinator creates child work that routes through a product-owned LLM execution boundary instead of LiveView-local fake progress scheduling.
    - Progress, stdout, delta, clarification, and completion updates reflect the real conversation runtime outcome.
    - The route continues to consume those updates through the existing event-driven conversation delivery model.

- id: architecture.conversation_orchestration.scenario_repo_conversation_surfaces_llm_unavailability
  covers:
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
    - architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  given:
    - A managed-repository detail route can open a repository conversation record but the real LLM execution path is unavailable because provider credentials, runtime services, or policy prerequisites are not ready.
  when:
    - The operator submits a repository conversation turn.
  then:
    - The route reports an explicit readiness or recovery state explaining why real execution cannot continue.
    - The system does not fabricate progress, delta, or completion events that imply successful work.
    - Persisted conversation state still remains available for continuity and later recovery.

- id: architecture.conversation_orchestration.scenario_real_runtime_cutover_removes_fake_path
  covers:
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
    - architecture.conversation_orchestration.real_runtime_cutover_has_no_compatibility_mode
  given:
    - The repository conversation runtime has been cut over to real LLM-backed execution.
  when:
    - The operator submits or resumes repository conversation work after the cutover.
  then:
    - The system has one canonical runtime path for active conversation execution.
    - The prior fake or timer-driven repository conversation execution path is removed rather than retained behind a compatibility switch.
    - Route behavior stays governed by explicit readiness and degraded-state handling instead of falling back to simulated success.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.interruptible_conversation_orchestration.md
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
    - architecture.conversation_orchestration.control_and_work_commands_are_distinct
    - architecture.conversation_orchestration.control_lane_preempts_work_lane
    - architecture.conversation_orchestration.active_turns_can_be_superseded
    - architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
    - architecture.conversation_orchestration.cancellation_lifecycle_is_evented
    - architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.steering_preserves_short_term_context
    - architecture.conversation_orchestration.expensive_work_announces_intent

- kind: source_file
  target: lib/jido_code/conversations/child_work.ex
  covers:
    - architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
    - architecture.conversation_orchestration.cancellation_lifecycle_is_evented

- kind: source_file
  target: lib/jido_code/conversations/coordinator.ex
  covers:
    - architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
    - architecture.conversation_orchestration.control_lane_preempts_work_lane
    - architecture.conversation_orchestration.active_turns_can_be_superseded
    - architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
    - architecture.conversation_orchestration.cancellation_lifecycle_is_evented
    - architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items

- kind: source_file
  target: lib/jido_code/conversations/driver.ex
  covers:
    - architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
    - architecture.conversation_orchestration.control_and_work_commands_are_distinct

- kind: source_file
  target: .spec/planning/phase-46-real-llm-conversation-runtime-cutover.md
  covers:
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
    - architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
    - architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
    - architecture.conversation_orchestration.real_runtime_cutover_has_no_compatibility_mode

- kind: source_file
  target: .spec/planning/phase-47-conversation-to-governed-work-convergence.md
  covers:
    - architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items
    - architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage

- kind: source_file
  target: lib/jido_code/conversations/event.ex
  covers:
    - architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
    - architecture.conversation_orchestration.expensive_work_announces_intent

- kind: source_file
  target: lib/jido_code/conversations/event_record.ex
  covers:
    - architecture.conversation_orchestration.event_log_is_append_only_and_sequenced

- kind: source_file
  target: lib/jido_code/conversations/pub_sub.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable

- kind: source_file
  target: lib/jido_code/conversations/persistence.ex
  covers:
    - architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.steering_preserves_short_term_context

- kind: source_file
  target: lib/jido_code/conversations/snapshot.ex
  covers:
    - architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state

- kind: source_file
  target: lib/jido_code/conversations/snapshot_record.ex
  covers:
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.steering_preserves_short_term_context

- kind: source_file
  target: lib/jido_code/conversations/runtime.ex
  covers:
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
    - architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
    - architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
    - architecture.conversation_orchestration.real_runtime_cutover_has_no_compatibility_mode

- kind: source_file
  target: lib/jido_code/conversations/work_resolution.ex
  covers:
    - architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items

- kind: source_file
  target: lib/jido_code/conversations.ex
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.steering_preserves_short_term_context

- kind: source_file
  target: lib/jido_code/agent_workspace.ex
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state

- kind: source_file
  target: lib/jido_code/workbench/project_conversation.ex
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
    - architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage

- kind: source_file
  target: test/jido_code/phase_forty_integration_test.exs
  covers:
    - architecture.conversation_orchestration.control_lane_preempts_work_lane
    - architecture.conversation_orchestration.active_turns_can_be_superseded
    - architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
    - architecture.conversation_orchestration.cancellation_lifecycle_is_evented

- kind: source_file
  target: test/jido_code/phase_thirty_nine_integration_test.exs
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
    - architecture.conversation_orchestration.control_and_work_commands_are_distinct

- kind: source_file
  target: test/jido_code/phase_forty_one_integration_test.exs
  covers:
    - architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state

- kind: source_file
  target: test/jido_code/phase_forty_two_integration_test.exs
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.steering_preserves_short_term_context

- kind: source_file
  target: test/jido_code/phase_forty_three_integration_test.exs
  covers:
    - architecture.conversation_orchestration.control_and_work_commands_are_distinct
    - architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.steering_preserves_short_term_context

- kind: source_file
  target: test/jido_code/phase_forty_four_integration_test.exs
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations

- kind: source_file
  target: test/jido_code/phase_forty_six_integration_test.exs
  covers:
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
    - architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
    - architecture.conversation_orchestration.steering_preserves_short_term_context

- kind: source_file
  target: test/jido_code/phase_forty_seven_integration_test.exs
  covers:
    - architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items
    - architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage

- kind: source_file
  target: lib/jido_code_web/live/project_detail_live.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
    - architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation

- kind: source_file
  target: test/jido_code_web/live/project_detail_live_test.exs
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
    - architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
    - architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit

- kind: source_file
  target: lib/jido_code/forge/pubsub.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable

- kind: source_file
  target: lib/jido_code/orchestration/run_pubsub.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
```
