# Conversation Orchestration

This subject defines how productive coding conversations are coordinated across
durable work scope, interruptible execution, and event-driven UI delivery.

```spec-meta
id: architecture.conversation_orchestration
kind: feature
status: active
summary: Jido.Code treats productive coding conversations as managed-repository and usually work-item-scoped mixed-initiative sessions coordinated through explicit control and work commands, append-only sequenced event streams, durable snapshots, bounded shared context, cancellable tool jobs, and event-driven LiveView plus PubSub delivery with reconnectable degraded fallbacks, including bounded managed-repository and governed-run route adoption rather than snapshot polling or ad hoc FIFO chat handling.
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.jido_agent_os_integration
  - jido_code.interruptible_conversation_orchestration
surface:
  - lib/jido_code/conversations.ex
  - .spec/decisions/jido_code.interruptible_conversation_orchestration.md
  - lib/jido_code/conversations/event.ex
  - lib/jido_code/conversations/event_record.ex
  - lib/jido_code/conversations/persistence.ex
  - lib/jido_code/conversations/pub_sub.ex
  - lib/jido_code/conversations/snapshot.ex
  - lib/jido_code/conversations/snapshot_record.ex
  - lib/jido_code/agent_workspace.ex
  - lib/jido_code/operations/synthesis.ex
  - lib/jido_code/workbench/project_conversation.ex
  - lib/jido_code/workbench/run_conversation.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - lib/jido_code_web/live/run_detail_live.ex
  - lib/jido_code_web/live/demos/chat_live.ex
  - lib/jido_code_web/live/forge/show_live.ex
  - lib/jido_code/forge/pubsub.ex
  - lib/jido_code/orchestration/run_pubsub.ex
  - test/jido_code/phase_forty_five_integration_test.exs
  - test/jido_code/phase_forty_four_integration_test.exs
  - test/jido_code/phase_forty_one_integration_test.exs
  - test/jido_code/phase_forty_two_integration_test.exs
  - test/jido_code_web/live/demos/chat_live_test.exs
  - test/jido_code_web/live/project_detail_live_test.exs
  - test/jido_code_web/live/run_detail_live_test.exs
```

## Requirements

```spec-requirements
- id: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  statement: Coding conversations shall bind to explicit managed-repository scope and, when they act on durable factory work, shall attach to one existing or newly synthesized WorkItem rather than remaining free-floating page-local chat state.
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

- id: architecture.conversation_orchestration.governed_run_routes_host_work_conversations
  statement: Governed run routes should be able to open, resume, and guide bounded work-item-scoped conversations through product-owned workspace and service boundaries when the run already carries canonical governed work, without forcing the operator back to repo detail or onto a separate chat-only surface.
  priority: should
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

- id: architecture.conversation_orchestration.scenario_run_detail_route_reuses_work_item_conversation
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.governed_run_routes_host_work_conversations
  given:
    - A governed run detail route needs to show the latest bounded conversation state for the run's canonical work item.
  when:
    - The operator opens or resumes the governed work conversation from that route.
  then:
    - The product-owned route boundary reuses the latest active work-item-scoped conversation when one already exists.
    - The route loads the latest durable snapshot and recent events through bounded workspace helpers.
    - Live delivery stays event-driven while degraded continuity still renders the latest durable conversation state.
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

- kind: source_file
  target: lib/jido_code/conversations/driver.ex
  covers:
    - architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
    - architecture.conversation_orchestration.control_and_work_commands_are_distinct

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

- kind: source_file
  target: lib/jido_code/workbench/run_conversation.ex
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.governed_run_routes_host_work_conversations

- kind: source_file
  target: test/jido_code/phase_forty_integration_test.exs
  covers:
    - architecture.conversation_orchestration.control_lane_preempts_work_lane
    - architecture.conversation_orchestration.active_turns_can_be_superseded
    - architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
    - architecture.conversation_orchestration.cancellation_lifecycle_is_evented

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
  target: test/jido_code/phase_forty_five_integration_test.exs
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
    - architecture.conversation_orchestration.governed_run_routes_host_work_conversations

- kind: source_file
  target: lib/jido_code_web/live/forge/show_live.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state

- kind: source_file
  target: lib/jido_code_web/live/demos/chat_live.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state

- kind: source_file
  target: lib/jido_code_web/live/project_detail_live.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.governed_run_routes_host_work_conversations

- kind: source_file
  target: test/jido_code_web/live/demos/chat_live_test.exs
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state

- kind: source_file
  target: test/jido_code_web/live/project_detail_live_test.exs
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.governed_run_routes_host_work_conversations

- kind: source_file
  target: lib/jido_code/forge/pubsub.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable

- kind: source_file
  target: lib/jido_code/orchestration/run_pubsub.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
```
