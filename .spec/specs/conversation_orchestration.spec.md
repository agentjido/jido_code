# Conversation Orchestration

This subject defines how productive coding conversations are coordinated across
durable work scope, interruptible execution, and event-driven UI delivery.

```spec-meta
id: architecture.conversation_orchestration
kind: feature
status: active
summary: Jido.Code treats productive coding conversations as managed-repository hosted, canonically work-item-scoped mixed-initiative sessions coordinated through explicit control and work commands, deterministic product-owned workflow routing, append-only sequenced event streams, durable snapshots, bounded shared context, cancellable tool jobs, real LLM-backed turn execution through product-owned runtime boundaries with explicit repo and conversation LLM provider/model selection, and event-driven LiveView plus PubSub delivery with reconnectable degraded fallbacks, including bounded managed-repository route adoption, repo-scoped pre-work intake, multiple active work-item conversations per repository, and clarification on ambiguous workflow intent rather than snapshot polling, fake timer-driven turn simulation, ad hoc FIFO chat handling, AI-decided specialist self-selection, abstract model-tier routing, or one repo-global productive thread.
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.jido_agent_os_integration
  - jido_code.llm_provider_and_model_selection
  - jido_code.interruptible_conversation_orchestration
  - jido_code.work_item_scoped_conversations_as_canonical_productive_threads
surface:
  - .spec/decisions/jido_code.llm_provider_and_model_selection.md
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
  - lib/jido_code/workbench/inventory.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - lib/jido_code_web/live/workbench_live.ex
  - lib/jido_code_web/live/run_detail_live.ex
  - lib/jido_code/setup/provider_credential_checks.ex
  - .spec/decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md
  - lib/jido_code/forge/pubsub.ex
  - lib/jido_code/orchestration/run_pubsub.ex
  - test/jido_code/phase_thirty_nine_integration_test.exs
  - test/jido_code/phase_forty_four_integration_test.exs
  - test/jido_code/phase_forty_six_integration_test.exs
  - test/jido_code/phase_forty_seven_integration_test.exs
  - test/jido_code/phase_forty_eight_integration_test.exs
  - test/jido_code/phase_fifty_one_integration_test.exs
  - test/jido_code/phase_forty_one_integration_test.exs
  - test/jido_code/phase_forty_two_integration_test.exs
  - test/jido_code_web/live/project_detail_live_test.exs
  - test/jido_code_web/live/workbench_live_test.exs
  - test/jido_code_web/live/run_detail_live_test.exs
```

## Requirements

```spec-requirements
- id: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  statement: Coding conversations shall bind to explicit managed-repository scope and, when they act on durable factory work, shall attach to one existing or newly synthesized `WorkItem` rather than remaining free-floating page-local chat state, allowing one managed repository to host multiple active productive conversations when those threads map to distinct work items.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
  statement: The product shall enforce active productive conversation uniqueness per canonical `WorkItem` rather than per managed repository, so reopening conversation work for the same active work item resumes its active thread while different work items in the same repository may keep separate active conversations.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.repo_scoped_conversations_are_pre_work_intake
  statement: Repo-scoped conversations shall remain a bounded pre-work intake or triage path; once durable planning, implementation, review, or governed follow-up work begins, the canonical long-lived productive conversation shall attach to explicit `WorkItem` scope instead of continuing as a repo-global productive thread.
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
  statement: Managed-repository operator routes should be able to open bounded repo-scoped intake conversations, list active work-item conversations for the repository, and resume the canonical conversation for a selected `WorkItem` through product-owned workspace and service boundaries without forcing the operator onto a separate chat-only surface.
  priority: should
  stability: proposed

- id: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  statement: Managed-repository and adjacent governed-work surfaces should show when a productive conversation is attached to a `WorkItem`, distinguish repo-scoped intake from active work-item conversations, and allow operators to follow or resume the canonical governed work loop from that linkage.
  priority: should
  stability: proposed

- id: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  statement: Workbench and governed run detail should project bounded repo-intake and work-item conversation linkage through product-owned conversation projections so operators can follow active conversation-driven work without reconstructing it from transcript text, raw work metadata, or runtime internals.
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

- id: architecture.conversation_orchestration.repo_and_conversation_llm_selection_is_explicit
  statement: Real conversation execution shall resolve an explicit concrete LLM provider and model through a product-owned selection boundary using repository defaults, optional conversation overrides, and system defaults rather than hardcoded provider enums or abstract model tiers.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.conversation_llm_selection_overrides_repo_default
  statement: When a productive conversation carries an explicit LLM override, that concrete provider/model selection shall take precedence over the repository default for subsequent real runtime turns, and repository default shall take precedence over system default when no override exists.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.selected_llm_provider_readiness_is_validated
  statement: Readiness and failure handling for real conversation execution shall validate the selected provider and its concrete provider-specific requirements rather than only checking global readiness for a fixed provider shortlist.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned
  statement: Conversation workflow and specialist routing shall resolve through one product-owned deterministic routing boundary with explicit precedence, bounded inputs, and inspectable routing metadata rather than duplicated ad hoc heuristics, provider-side self-selection, or letting the active AI agent decide which specialist should handle the turn.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.explicit_workflow_intent_and_continuity_take_precedence
  statement: Explicit workflow intent, clarification or resume continuity, active work-item context, and bounded surface intent shall take precedence over free-text routing heuristics so productive follow-up work continues through the canonical workflow unless the operator explicitly changes it.
  priority: must
  stability: proposed

- id: architecture.conversation_orchestration.ambiguous_workflow_routing_requests_clarification
  statement: When routing signals are weak, conflicting, or otherwise ambiguous, the conversation runtime shall request clarification through bounded conversation control flow instead of silently guessing the workflow or specialist.
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

- id: architecture.conversation_orchestration.work_item_conversation_lifecycle_tracks_governed_work_status
  statement: Active work-item conversations shall remain resumable while governed work stays `open`, `in_progress`, or `blocked`, shall settle into terminal historical lineage when governed work becomes `completed`, `cancelled`, or `suppressed`, and reopening that work later shall create a fresh active productive thread without reviving the historical one as the active default.
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
    - architecture.conversation_orchestration.repo_scoped_conversations_are_pre_work_intake
    - architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items
    - architecture.conversation_orchestration.steering_preserves_short_term_context
  given:
    - A managed-repository conversation has repo scope and no active governed work item yet.
    - The operator submits a productive turn that should become durable planning, implementation, review, or follow-up work.
  when:
    - The product admits that turn into the governed work loop.
  then:
    - A canonical `WorkItem` is created or an equivalent existing work item is reused through a product-owned work-resolution boundary before durable execution continues.
    - The canonical productive conversation attaches to the resolved `WorkItem` instead of remaining a repo-global productive thread.
    - The conversation snapshot records the attached `work_item_id` and later turns reuse or steer that governed work explicitly rather than creating hidden conversation-local work state.
    - The product preserves the turn and actor context needed to explain why the conversation attached to that work item.

- id: architecture.conversation_orchestration.scenario_managed_repo_route_lists_active_work_item_conversations
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
    - architecture.conversation_orchestration.repo_scoped_conversations_are_pre_work_intake
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
  given:
    - A managed repository has multiple active governed `WorkItem`s with productive conversations attached.
    - The repository may also have a bounded repo-scoped intake conversation for pre-work triage.
  when:
    - The operator opens the managed-repository detail route.
  then:
    - The route distinguishes repo-scoped intake from active work-item conversations instead of collapsing all active work onto one latest repo-global productive thread.
    - The route loads active work-item conversation summaries, durable snapshots, and recent events through bounded workspace helpers.
    - Live delivery stays event-driven while degraded continuity still renders the latest durable intake and work-item conversation state.

- id: architecture.conversation_orchestration.scenario_reopening_same_work_item_reuses_active_conversation
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
  given:
    - A managed repository already has an active productive conversation attached to a canonical `WorkItem`.
  when:
    - The operator resumes conversation work for that same work item from repo detail, Workbench, or governed run detail.
  then:
    - The product resumes the active productive conversation for that work item instead of creating a second active conversation for the same governed work.
    - Bounded short-term context, current turn state, and work-item linkage remain attached to the resumed thread.

- id: architecture.conversation_orchestration.scenario_parallel_work_items_keep_separate_conversations
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
    - architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
  given:
    - A managed repository has two distinct governed `WorkItem`s that both require productive LLM-backed supervision.
  when:
    - Operators open or resume conversation work for those work items.
  then:
    - Each work item keeps its own productive conversation thread, bounded context, and runtime routing.
    - The system does not merge those work streams into one repo-global productive conversation.

- id: architecture.conversation_orchestration.scenario_work_item_conversation_settles_and_reopens
  covers:
    - architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
    - architecture.conversation_orchestration.work_item_conversation_lifecycle_tracks_governed_work_status
    - architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  given:
    - A managed repository has a productive work-item conversation and at least one other active work-item conversation.
  when:
    - The first governed work item completes and is later reopened.
  then:
    - The completed conversation settles into historical lineage for that work item instead of competing with active productive conversations.
    - Reopening the work item yields a fresh active productive conversation for that same work item.
    - Governed run detail and adjacent surfaces can explain both the current active thread and the preserved historical lineage.

- id: architecture.conversation_orchestration.scenario_operator_surfaces_expose_conversation_work_item_linkage
  covers:
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
    - architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  given:
    - One or more productive repository conversations are already attached to canonical `WorkItem` scope.
  when:
    - An operator opens the managed-repository route or adjacent governed-work surface for that repository.
  then:
    - The product shows the attached `WorkItem` linkage and current governed work status without requiring the operator to infer it from raw conversation text.
    - The operator can follow or resume each governed work loop from that surfaced linkage rather than reopening a separate ad hoc path.

- id: architecture.conversation_orchestration.scenario_workbench_and_run_detail_project_conversation_linkage
  covers:
    - architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
    - architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  given:
    - A productive repository conversation is attached to canonical governed `WorkItem` scope.
    - Governed execution has begun or completed against that work item.
  when:
    - An operator opens Workbench or governed run detail.
  then:
    - Workbench shows bounded intake and work-item conversation status plus the attached governed work summary on the managed-repository row.
    - Governed run detail shows the bounded relationship between run execution, canonical `WorkItem` scope, and any preserved productive conversation origin or latest linked conversation.
    - Both surfaces route operators back to the managed-repository conversation host surface instead of inventing page-local or run-local chat state.

- id: architecture.conversation_orchestration.scenario_repo_conversation_executes_real_llm_turns
  covers:
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
    - architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
    - architecture.conversation_orchestration.repo_and_conversation_llm_selection_is_explicit
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  given:
    - A managed-repository detail route has an active repository conversation and the required LLM provider plus runtime prerequisites are available.
  when:
    - The operator submits a new repository conversation turn or resumes a clarification.
  then:
    - The coordinator creates child work that routes through a product-owned LLM execution boundary instead of LiveView-local fake progress scheduling.
    - The runtime resolves a concrete provider and model from conversation override, repository default, or system default before specialist execution begins.
    - Progress, stdout, delta, clarification, and completion updates reflect the real conversation runtime outcome.
    - The route continues to consume those updates through the existing event-driven conversation delivery model.

- id: architecture.conversation_orchestration.scenario_conversation_override_supersedes_repo_default
  covers:
    - architecture.conversation_orchestration.repo_and_conversation_llm_selection_is_explicit
    - architecture.conversation_orchestration.conversation_llm_selection_overrides_repo_default
  given:
    - A managed repository has a concrete default provider/model selection for coding conversations.
    - An active productive conversation on that repository carries an explicit concrete provider/model override.
  when:
    - The operator submits or resumes a real runtime turn for that conversation.
  then:
    - The runtime uses the conversation override for the turn instead of the repository default.
    - If the override is absent on a later turn, the runtime falls back to the repository default and then the system default.
    - Abstract model-tier aliases are not consulted as part of the selection path.

- id: architecture.conversation_orchestration.scenario_repo_conversation_surfaces_llm_unavailability
  covers:
    - architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
    - architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
    - architecture.conversation_orchestration.selected_llm_provider_readiness_is_validated
    - architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  given:
    - A managed-repository detail route can open a repository conversation record but the real LLM execution path is unavailable because provider credentials, runtime services, or policy prerequisites are not ready.
  when:
    - The operator submits a repository conversation turn.
  then:
    - The route reports an explicit readiness or recovery state explaining why real execution cannot continue.
    - The system does not fabricate progress, delta, or completion events that imply successful work.
    - Persisted conversation state still remains available for continuity and later recovery.

- id: architecture.conversation_orchestration.scenario_explicit_workflow_intent_beats_ambiguous_text
  covers:
    - architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned
    - architecture.conversation_orchestration.explicit_workflow_intent_and_continuity_take_precedence
  given:
    - A productive conversation turn includes mixed free-text cues such as review and implementation language.
    - The bounded product surface or active conversation state already carries explicit workflow intent or prior continuity for that turn.
  when:
    - The product routes the turn into productive execution.
  then:
    - The canonical routing boundary uses the explicit workflow or continuity signal before considering free-text heuristics.
    - The chosen workflow and routing reason are persisted as bounded routing metadata that downstream runtime helpers can reuse.
    - Specialist selection remains product-owned and deterministic instead of asking the model which specialist to use.

- id: architecture.conversation_orchestration.scenario_ambiguous_routing_requests_clarification
  covers:
    - architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned
    - architecture.conversation_orchestration.ambiguous_workflow_routing_requests_clarification
    - architecture.conversation_orchestration.steering_preserves_short_term_context
  given:
    - A productive conversation turn has no explicit workflow and presents weak or conflicting routing cues.
  when:
    - The product attempts to route that turn into planning, execution, review, or explanation work.
  then:
    - The canonical routing boundary classifies the routing state as ambiguous rather than silently picking a specialist.
    - The coordinator emits a clarification request through the normal conversation control flow.
    - Bounded shared context and work-item continuity remain available so the clarified turn can resume without losing the governed work thread.

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
  target: .spec/decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md
  covers:
    - architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
    - architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
    - architecture.conversation_orchestration.repo_scoped_conversations_are_pre_work_intake

- kind: source_file
  target: .spec/decisions/jido_code.llm_provider_and_model_selection.md
  covers:
    - architecture.conversation_orchestration.repo_and_conversation_llm_selection_is_explicit
    - architecture.conversation_orchestration.conversation_llm_selection_overrides_repo_default
    - architecture.conversation_orchestration.selected_llm_provider_readiness_is_validated

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
  target: .spec/planning/phase-49-work-item-conversation-identity-and-canonical-admission.md
  covers:
    - architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
    - architecture.conversation_orchestration.repo_scoped_conversations_are_pre_work_intake
    - architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items

- kind: source_file
  target: .spec/planning/phase-50-managed-repo-workbench-and-dashboard-multi-conversation-adoption.md
  covers:
    - architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
    - architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage

- kind: source_file
  target: .spec/planning/phase-51-work-item-conversation-runtime-lifecycle-and-convergence.md
  covers:
    - architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
    - architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage

- kind: source_file
  target: .spec/planning/phase-52-deterministic-conversation-workflow-routing-and-clarification.md
  covers:
    - architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned
    - architecture.conversation_orchestration.explicit_workflow_intent_and_continuity_take_precedence
    - architecture.conversation_orchestration.ambiguous_workflow_routing_requests_clarification

- kind: source_file
  target: lib/jido_code/conversations/workflow_router.ex
  covers:
    - architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned
    - architecture.conversation_orchestration.explicit_workflow_intent_and_continuity_take_precedence
    - architecture.conversation_orchestration.ambiguous_workflow_routing_requests_clarification

- kind: source_file
  target: test/jido_code/phase_fifty_two_integration_test.exs
  covers:
    - architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned
    - architecture.conversation_orchestration.explicit_workflow_intent_and_continuity_take_precedence
    - architecture.conversation_orchestration.ambiguous_workflow_routing_requests_clarification

- kind: source_file
  target: test/jido_code/phase_forty_nine_integration_test.exs
  covers:
    - architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
    - architecture.conversation_orchestration.repo_scoped_conversations_are_pre_work_intake
    - architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items

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
    - architecture.conversation_orchestration.work_item_conversation_lifecycle_tracks_governed_work_status

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
    - architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage

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
  target: test/jido_code/phase_forty_eight_integration_test.exs
  covers:
    - architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage

- kind: source_file
  target: test/jido_code/phase_fifty_one_integration_test.exs
  covers:
    - architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
    - architecture.conversation_orchestration.work_item_conversation_lifecycle_tracks_governed_work_status
    - architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage

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
  target: lib/jido_code_web/live/workbench_live.ex
  covers:
    - architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage

- kind: source_file
  target: test/jido_code_web/live/workbench_live_test.exs
  covers:
    - architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage

- kind: source_file
  target: lib/jido_code/forge/pubsub.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable

- kind: source_file
  target: lib/jido_code/orchestration/run_pubsub.ex
  covers:
    - architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
```
