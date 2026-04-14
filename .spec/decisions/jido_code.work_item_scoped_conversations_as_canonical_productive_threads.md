---
id: jido_code.work_item_scoped_conversations_as_canonical_productive_threads
status: accepted
date: 2026-04-14
affects:
  - architecture.conversation_orchestration
  - architecture.work_synthesis
  - architecture.factory_control_plane
---

<!-- covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped -->
<!-- covers: architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item -->
<!-- covers: architecture.conversation_orchestration.repo_scoped_conversations_are_pre_work_intake -->
<!-- covers: architecture.work_synthesis.active_conversation_identity_rejoins_work_item -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_distinguish_repo_intake_from_work_item_conversations -->
<!-- covers: package.jido_code.spec_led_workspace -->

# Work-Item Scoped Conversations As Canonical Productive Threads

## Context

The original intent for productive coding conversations in `jido_code` was to
support multiple governed work streams inside the same managed repository, with
each durable thread staying attached to explicit `WorkItem` scope once real
planning, implementation, review, or governed follow-up begins.

Recent conversation phases landed the durable coordinator, real LLM runtime,
work-item attachment, and operator-surface projection work, but they also let
the repo-detail experience drift toward a "latest repo conversation" default.
That route-hosting convenience was useful during early rollout, yet it obscured
the stronger architectural boundary: AgentOS durable execution, CodingPod
lifecycle, and governed work records are all already scoped per `WorkItem`, not
per repository-global chat thread.

If left uncorrected, that drift would make parallel governed work awkward. A
single managed repository could have many open work items, but the product would
still teach operators to think in terms of one current conversation per repo.
That is the wrong long-term model for a governed software factory.

## Decision

Managed-repository routes remain the host surfaces for conversation entry and
oversight, but canonical productive conversations are work-item scoped.

Repo-scoped conversation is allowed only as bounded pre-work intake or triage.
Once a conversation becomes durable planning, implementation, review, or
governed follow-up work, the product shall create, attach, or reuse canonical
`WorkItem` scope and treat the resulting productive thread as the canonical
conversation for that work item.

A managed repository may therefore have multiple active productive conversations
at the same time, provided they are attached to distinct active `WorkItem`
records. The product shall not treat "one active conversation per repo" as the
canonical invariant.

To preserve clarity and avoid thread duplication, each active `WorkItem` shall
have at most one active canonical productive conversation at a time. Reopening
conversation work for the same active work item should resume that active thread
rather than creating a second competing productive conversation for the same
governed work.

Operator surfaces shall distinguish bounded repo-scoped intake from active
work-item conversations. Repo detail, Workbench, dashboard summaries, and
governed run detail should project work-item conversation linkage through
canonical `ManagedRepo`, `WorkItem`, and governed `Run` records rather than
collapsing active work onto one repo-global chat lane.

## Consequences

- Multiple active work-item conversations may coexist inside one managed
  repository without violating the product model.
- Repo-scoped intake remains available, but it is no longer the canonical home
  for long-lived governed work.
- Work-item conversation lookup, reuse, and runtime routing become first-class
  product boundaries instead of incidental persistence details.
- Operator surfaces must move from "latest repo conversation" projection toward
  "repo intake plus active work-item conversation roster" projection.
- Runtime helpers and surface APIs should enforce uniqueness per active work
  item, not per repository.
