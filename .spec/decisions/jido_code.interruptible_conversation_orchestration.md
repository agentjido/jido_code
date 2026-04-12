---
id: jido_code.interruptible_conversation_orchestration
status: accepted
date: 2026-04-12
affects:
  - package.jido_code
  - architecture.conversation_orchestration
  - architecture.agent_os_integration
  - architecture.factory_control_plane
  - architecture.frontend_stack
---

<!-- covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped -->
<!-- covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state -->
<!-- covers: architecture.conversation_orchestration.control_and_work_commands_are_distinct -->
<!-- covers: architecture.conversation_orchestration.control_lane_preempts_work_lane -->
<!-- covers: architecture.conversation_orchestration.active_turns_can_be_superseded -->
<!-- covers: architecture.conversation_orchestration.tool_execution_is_cancellable_child_work -->
<!-- covers: architecture.conversation_orchestration.cancellation_lifecycle_is_evented -->
<!-- covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced -->
<!-- covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable -->
<!-- covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state -->
<!-- covers: architecture.conversation_orchestration.steering_preserves_short_term_context -->
<!-- covers: architecture.conversation_orchestration.expensive_work_announces_intent -->

# Interruptible Conversation Orchestration

## Context

Productive coding conversations are not ordinary chat.

They mix:

- explicit human steering
- model planning and partial output
- long-running tool execution
- interruption, redirection, and clarification mid-turn
- a UI that must stay legible while work is still in flight

`jido_code` already has several relevant foundations:

- the factory control plane prefers durable managed-repository and work-item scope
- AgentWorkspace and CodingPods provide repo- and work-scoped execution boundaries
- Forge already demonstrates event-driven PubSub delivery, reconnect handling, and degraded-mode fallback

At the same time, the demo chat surface still relies on polling snapshots, and the
current AgentOS conversation-driver sketches stop short of a durable interrupt and
event model. A naive FIFO queue of messages is not enough for coding work because
the user often needs to stop, redirect, or narrow a turn while tool calls are still
running.

The product therefore needs a conversation contract that:

- fits the factory control plane instead of creating a second chat-native truth lane
- allows interruption and steering without waiting behind stale queued turns
- gives the UI immediate evented visibility into tool and turn lifecycle
- supports recovery, replay, and degraded continuity after dropped live delivery

## Decision

`Jido.Code` shall treat coding conversations as mixed-initiative, repo-scoped
control-plane interactions rather than as unstructured FIFO chat sessions.

Each active coding conversation shall bind to a `ManagedRepo` and, when it acts on
durable factory work, to one canonical `WorkItem`. Conversation handling should
therefore steer existing work context or synthesize new work context explicitly
rather than leaving taskful coding exchanges as page-local ephemeral chat state.

Each active conversation shall have one coordinator boundary, expected to live in a
product-owned conversation driver adjacent to `AgentWorkspace`. That coordinator is
responsible for:

- admitting commands
- sequencing turn lifecycle
- maintaining current snapshots derived from events
- requesting cancellation of active child work
- emitting product-owned events for UI and persistence

The product command model is split into two classes:

- work commands such as `turn.submit`, `tool_result.submit`, and `turn.resume`
- control commands such as `turn.steer`, `turn.stop`, `session.pause`,
  `session.resume`, and `tool.cancel`

Only the control class has priority semantics.

The product contract shall not define arbitrary multi-level message priorities.
Instead, the coordinator shall expose one explicit control lane that drains before
queued work turns. This keeps interruption semantics legible for operators while
preserving a simpler and more durable product model than a general numeric-priority
chat queue.

When a control command arrives during active work, the coordinator shall:

1. admit the control command ahead of queued work commands
2. emit an immediate conversation event showing that supersession or cancellation is
   underway
3. request cancellation of any active tool worker or child job
4. settle the superseded turn explicitly as cancelled, superseded, completed before
   cancel landed, or failed to cancel

Long-running tool execution shall not stay trapped inside the coordinator mailbox.
Instead, tools shall execute as cancellable child jobs or bounded workers with
explicit lifecycle ownership. Cancellation should be cooperative first and must
still emit a final settlement event if completion wins the race.

Conversation state shall be represented as an append-only event log plus a
materialized current snapshot. The event model shall carry, at minimum:

- monotonic per-conversation sequence number
- conversation identifier
- turn identifier
- message identifier when relevant
- tool call identifier when relevant
- actor attribution
- timestamp
- correlation metadata such as parent turn or supersedes reference
- typed event name

The canonical conversation event taxonomy should include product-oriented lifecycle
events such as:

- `conversation.message_added`
- `turn.queued`
- `turn.started`
- `turn.intent_announced`
- `turn.delta`
- `tool.started`
- `tool.progress`
- `tool.stdout`
- `tool.needs_input`
- `tool.cancel_requested`
- `tool.cancel_acknowledged`
- `tool.cancelled`
- `tool.cancel_failed`
- `turn.superseded`
- `turn.completed`
- `turn.failed`

LiveView and adjacent browser surfaces shall subscribe to product-owned PubSub
topics and render incremental updates from these events. Snapshots are for cold
load, reconnect, or degraded recovery, not for steady-state polling during healthy
runtime operation.

When live delivery is interrupted, the browser should recover by:

1. reloading the latest durable conversation snapshot
2. restoring the last accepted event sequence
3. resuming from the next available sequence when continuity is possible
4. showing explicit continuity or degraded-mode messaging when only persisted state
   is available

Steering and interruption shall preserve bounded short-term collaboration context,
including active repo scope, work-item attachment, accepted tool results, file
references, and pending clarification state. Superseded partial output should not be
presented as a final answer, but the coordinator may keep it as traceable runtime
history.

Before expensive tool use or long-running execution, the assistant should emit a
short intent or plan event describing what it is about to inspect or execute and
why. The purpose is to keep the human partner oriented without forcing them to wait
for opaque background work.

## Rejected Alternative

The product explicitly rejects a general numeric-priority conversation queue as the
primary contract.

Numeric priorities across all messages make operator-visible ordering harder to
reason about, encourage feature-local queue policy, and couple the product model too
tightly to runtime scheduler details. If lower-level runtime primitives such as BEAM
priority messaging are introduced later, they should remain an opt-in transport
optimization for control and cancellation signals only, not the user-facing
conversation model.

## Consequences

- Conversation handling aligns with the factory control plane by attaching coding
  exchanges to explicit repo and work scope.
- Forge-style PubSub delivery, reconnect handling, and degraded continuity become
  the preferred model for conversation UI.
- Polling-only conversation surfaces are transitional and should migrate toward
  event-driven delivery.
- Tool adapters and workers need a uniform cancellation and settlement contract.
- Persistence must support append-only event history plus current snapshots before
  richer multi-user conversation surfaces can land safely.
