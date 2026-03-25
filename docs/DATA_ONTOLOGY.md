<!-- covers: docs.product_foundation.data_ontology_defined -->

# Jido.Code Data Ontology

## Purpose

This document defines the first durable data model for `Jido.Code`.

The goal is to keep the ontology small, explicit, and aligned with the product thesis:
manage a Git-backed repository through policy, observation, governed work, and
progressive trust.

## Core Framing

From a data perspective, `Jido.Code` is a control system around a source repository.

The ontology must answer six questions:

- what external software system are we managing
- what incoming external deliveries or objects are we reacting to
- what should be true about it
- what do we currently observe to be true
- what work is in motion
- what evidence and decisions justify that work

## Naming Choices

These are the preferred v1 names:

- `SourceRepo`
- `ManagedRepo`
- `PolicySet`
- `Observation`
- `Intake`
- `ExternalObject`
- `Event`
- `Assessment`
- `WorkItem`
- `Run`
- `ChangeRequest`
- `Decision`
- `Evidence`

These names intentionally replace more abstract or overloaded alternatives such as
`RepoCell`, `Signal`, `Snapshot`, `Evaluation`, and `Artifact`.

## Planned Next Layer

The smallest viable ontology is already defined below. The next additions should be
introduced in a narrow order so the model stays coherent.

### `RepoPosture` And `PostureCheck`

`RepoPosture` should become the durable repo-level summary of trust and operating
fitness.

It should be derived from lower-level records such as `Observation`, `Assessment`,
`Run`, `Decision`, and `Evidence`, then used to inform `ManagedRepo.autonomy_mode` and
operator-facing health summaries.

`PostureCheck` should capture one contributing trust or operating dimension behind a
`RepoPosture`.

Likely posture dimensions include:

- policy conformance
- execution readiness
- validation reliability
- review burden
- repo drift
- recovery resilience
- requirements or spec confidence

### `ExecutionProfile`

`ExecutionProfile` should define the repeatable execution shape for a repo or policy
layer.

It should answer:

- what sprite shape to start
- how bootstrap runs
- how repo prep runs in a fresh environment
- which validation nodes are expected by default
- which checkpoints, caches, or resume paths are allowed

`ExecutionProfile` should influence `Run`, but not replace Runic workflow state.

### `Initiative`

`Initiative` should group multiple `WorkItem` records into one higher-order repository
outcome.

It should be used for multi-step feature work, planned maintenance, and broader
conformance efforts that should be tracked as one bounded unit.

### Governance Layering

The policy stack should stay explicit and small:

- `FactoryDefaults`
- `PolicyPack`
- `PolicySet`
- `OperatorOverride`

`ReviewPolicy` should begin as an embedded structure inside `PolicySet` rather than as a
standalone first-class resource.

## Viability Boundary

The ontology is designed to support recursive control without turning every record into
its own system.

By default:

- the factory instance is the top-level viable system
- each `ManagedRepo` is a viable subsystem within that factory
- `WorkItem` and `Run` are operational records within a managed repository

That means the ontology should preserve enough structure for a repository to express:

- operational work loops
- coordination and queue control
- orchestration and dispatch
- audit and reconciliation
- intelligence about external change
- policy and autonomy posture

It should not assume that each unit of work deserves its own full governance stack.
`WorkItem` or `Run` should only be promoted into lower-level viable subsystems when they
have persistent identity, bounded mission, their own coordination needs, their own
control and feedback loop, and distinct policy or autonomy constraints.

## Execution Boundary

The ontology should also keep a clean boundary between control-plane records and the
execution engine.

In `Jido.Code`:

- `Runic` provides the underlying DAG, facts, and runnable mechanics
- `Jido.Runic` owns the strategy-level execution loop that turns workflow state into Jido directives and completion signals
- Sprite sessions own sandbox provisioning, bootstrap, checkpointing, and resume
- `Ash` resources own durable projection, governance state, and operator-facing history

That means the ontology should not try to recreate a second workflow engine in the
database.

`Run` should be the durable control-plane record around a `Jido.Runic`-driven workflow
execution, not a replacement for the underlying Runic DAG state and runnable machinery.

## Core Records

The first ontology has four layers:

- identity and control
- desired and observed state
- external ingress and interpretation
- work and governed execution

### `SourceRepo`

`SourceRepo` is the external repository identity.

It represents one canonical Git repository on one source provider. It is the external
software system that the factory observes and acts against.

Minimum fields:

- `id`
- `provider`
- `external_id`
- `owner`
- `name`
- `full_name`
- `canonical_url`
- `default_branch`
- `visibility`
- `is_archived`
- `last_synced_at`

`SourceRepo` is not a sandbox, not a local clone, and not a policy object.

### `ManagedRepo`

`ManagedRepo` is the factory's managed wrapper around a `SourceRepo`.

It is the unit of control, supervision, and orchestration.

Minimum fields:

- `id`
- `source_repo_id`
- `status`
- `autonomy_mode`
- `backpressure_state`
- `active_policy_set_id`
- `paused_at`
- `enrolled_at`
- `last_assessed_at`

Common cached summaries on `ManagedRepo` may include:

- `confidence_band`
- `queue_depth`
- `health_summary`

Those summaries are useful, but they should not replace the underlying history that
justifies them.

### `PolicySet`

`PolicySet` defines what should be true for a `ManagedRepo`.

It is the declared desired state for repository governance, allowed mutation, approval
boundaries, and conformance expectations.

Minimum fields:

- `id`
- `managed_repo_id`
- `version`
- `status`
- `rules`
- `effective_from`
- `effective_to`
- `changed_by`
- `change_reason`

In the first version, `rules` can remain an embedded structured map.

### `Observation`

`Observation` is the factory's recorded view of repository state at a point in time.

It is raw observed state, not a judgment.

Minimum fields:

- `id`
- `managed_repo_id`
- `observed_at`
- `source_revision`
- `repo_facts`
- `provider_facts`
- `policy_facts`
- `summary`

Typical facts may include branch state, CI state, coverage posture, open work rollups,
or spec verification results.

Specific external issues, pull requests, and similar provider-backed objects should live
in `ExternalObject`, not only inside aggregate observation facts.

### `Intake`

`Intake` is the raw inbound record of something entering the factory boundary.

It may represent a webhook, operator request, scheduled trigger, alert, API call, or
other inbound request for attention.

It is the intake-layer audit and replay record, not the interpreted event and not the
external issue or pull request itself.

Minimum fields:

- `id`
- `managed_repo_id`
- `intake_type`
- `source`
- `external_ref`
- `occurred_at`
- `received_at`
- `transport_data`
- `payload`
- `authenticity_status`
- `processing_status`

Suggested `Intake` types:

- `webhook`
- `operator_request`
- `schedule`
- `alert`
- `api_request`
- `system_follow_up`

### `ExternalObject`

`ExternalObject` is the durable local mirror of a meaningful external object that the
factory may need to track over time.

This allows `Jido.Code` to manage GitHub issues, pull requests, check runs, and similar
provider-backed objects without creating a separate Ash resource for every provider type.

Where `Observation` captures aggregate state, `ExternalObject` captures the durable state
of one specific external object that may generate work over time.

Minimum fields:

- `id`
- `managed_repo_id`
- `provider`
- `object_type`
- `external_id`
- `external_number`
- `title`
- `state`
- `url`
- `author_ref`
- `source_updated_at`
- `last_seen_at`
- `data`

### `Event`

`Event` is a durable record of something that happened or something that was asked.

Events may come from providers, CI, alerts, schedules, operators, or agents.

For provider-driven flows, an `Event` is typically normalized from an `Intake`
and correlated with an `ExternalObject`.

Minimum fields:

- `id`
- `managed_repo_id`
- `intake_id`
- `external_object_id`
- `event_type`
- `source`
- `occurred_at`
- `received_at`
- `severity`
- `payload`
- `correlation_key`
- `status`

### `Assessment`

`Assessment` is the interpreted meaning of policy, observations, and events.

It is where the system decides whether the repository is healthy, drifting, blocked,
waived, or failing in some meaningful way.

Minimum fields:

- `id`
- `managed_repo_id`
- `policy_set_id`
- `observation_id`
- `event_ids`
- `assessment_type`
- `status`
- `severity`
- `summary`
- `recommended_action`
- `assessed_at`

### `WorkItem`

`WorkItem` is the orchestrator-owned unit of actionable responsibility.

It exists when the system decides that something should be investigated, remediated,
implemented, reviewed, or maintained.

This is also the right unit for queueing, prioritization, and kanban-style operator
views. The board is a projection over `WorkItem` state, not a separate root resource.

Minimum fields:

- `id`
- `managed_repo_id`
- `origin_type`
- `origin_id`
- `category`
- `priority`
- `status`
- `summary`
- `scope`
- `created_at`
- `started_at`
- `resolved_at`

Suggested `WorkItem` statuses:

- `inbox`
- `triaged`
- `ready`
- `running`
- `awaiting_approval`
- `blocked`
- `done`
- `dismissed`

Suggested `WorkItem` categories:

- `issue_response`
- `pr_review`
- `pr_repair`
- `feature`
- `maintenance`
- `conformance`
- `incident`
- `investigation`

### `Run`

`Run` is one execution attempt against a `WorkItem`.

It is a governed projection around a `Jido.Runic`-driven workflow execution.

It tracks planning, isolated execution, validation, retries, and terminal outcome while
referencing the underlying workflow state that actually determines which steps are ready
or complete.

A `Run` may coordinate one or more agent sessions inside one or more sandboxes, but the
run remains the durable execution record.

Minimum fields:

- `id`
- `managed_repo_id`
- `work_item_id`
- `workflow_name`
- `workflow_version`
- `policy_set_version`
- `status`
- `trigger`
- `started_at`
- `finished_at`
- `current_step`
- `workflow_state_ref`
- `agent_session_refs`
- `sandbox_refs`
- `result_summary`

`current_step` should be treated as a projected current Runic node or gate, not as proof
that the database owns full step execution semantics.

`workflow_state_ref` should point to the serialized or restorable workflow state used by
`Jido.Runic` and backed by Runic for resume, replay, and inspection.

## Supporting Execution Records

Execution also depends on sandbox lifecycle records that are important, but not part of
the smallest control ontology.

### `SpriteSession`

`SpriteSession` is the execution substrate record for a provisioned or resumable sandbox.

It owns:

- sprite provisioning
- environment injection
- generic bootstrap
- checkpoint creation
- resume context

It should not hide repository-specific prep or validation logic that belongs in a Runic
workflow.

The clean boundary is:

- session bootstrap prepares the execution environment
- workflow prep prepares the repository inside that environment
- validation steps remain explicit workflow nodes

### `ChangeRequest`

`ChangeRequest` is a proposed mutation or governed control action.

It may represent a pull request, a review action, an issue response, a deploy approval,
a policy override, or a temporary permission window.

Minimum fields:

- `id`
- `managed_repo_id`
- `run_id`
- `change_type`
- `status`
- `risk_level`
- `summary`
- `proposed_action`
- `rollback_plan`
- `expires_at`
- `created_at`

### `Decision`

`Decision` is the durable record of approval, rejection, hold, or waiver.

When policy requires governed acceptance, the decision may be made by a human operator or
by an automated policy authority.

Minimum fields:

- `id`
- `change_request_id`
- `decision_type`
- `decided_by`
- `decided_at`
- `rationale`
- `policy_basis`

### `Evidence`

`Evidence` is the durable proof and supporting context produced by the control loop.

It may contain diff summaries, validation results, rollback plans, risk summaries, or
policy variance explanations.

Minimum fields:

- `id`
- `managed_repo_id`
- `run_id`
- `evidence_type`
- `title`
- `summary`
- `body`
- `metadata`
- `created_at`

## Demand, Intake, And Work Creation

Demand should enter the control plane through either `Intake` or `Observation`.

That means the system can respond to:

- provider webhooks
- human/operator requests
- scheduled maintenance triggers
- runtime alerts
- API-driven automation
- internally generated follow-up work
- observed drift discovered during sync or scanning

Once something enters the control plane:

1. `Jido.Code` persists the inbound request or trigger as `Intake`, when one exists.
2. The system upserts the relevant `ExternalObject`, when a specific external object
   exists.
3. The system normalizes one or more actionable `Event` records from intake and current
   observed state.
4. The orchestrator evaluates the new event and repository context into an
   `Assessment`.
5. If action is needed, the assessment creates or updates a `WorkItem`.
6. The `WorkItem` enters the operator queue and can appear on a kanban board.
7. When scheduled, the orchestrator starts a `Run`.
8. The `Run` operates through agent sessions in sandboxes, produces `Evidence`, and may
   emit a `ChangeRequest`.
9. A `Decision` is recorded when policy requires approval or explicit acceptance.

That means:

- intake is the entrypoint
- the issue or pull request is external state
- the event is normalized meaning
- the work item is the queued job
- the run is the execution attempt

## Example Flows

### GitHub Issue Opened

- GitHub sends an `issues.opened` webhook.
- `Jido.Code` stores the raw delivery as `Intake` with `intake_type = webhook`.
- The issue is mirrored as an `ExternalObject` with `object_type = issue`.
- The delivery is normalized into an `Event` such as `issue.opened`.
- Policy and repository context produce an `Assessment`.
- The system creates a `WorkItem` such as `issue_response` or `investigation`.
- The orchestrator starts a sandboxed `Run` when capacity and policy allow.
- The run may produce an issue comment, labels, a follow-up branch, or a pull request as
  governed outcomes.

### External Pull Request Updated

- GitHub sends a `pull_request.synchronize` or `pull_request.opened` webhook.
- The raw delivery is persisted as `Intake` with `intake_type = webhook`.
- The pull request is mirrored as an `ExternalObject` with `object_type = pull_request`.
- A normalized `Event` is created.
- An `Assessment` decides whether the PR needs review, repair, policy escalation, or no
  action.
- A `WorkItem` such as `pr_review` or `pr_repair` is queued.
- A sandboxed `Run` performs analysis, tests, or patch generation.
- The run may produce `Evidence` only, or a governed `ChangeRequest` if mutation or
  approval is required.

### Scheduled Maintenance Trigger

- The factory emits an `Intake` with `intake_type = schedule`.
- There may be no `ExternalObject` at all.
- One or more `Event` records are created, such as `maintenance.window.opened`.
- The system assesses repository state, dependency posture, and policy obligations.
- A `WorkItem` such as `maintenance` or `conformance` is queued.
- A sandboxed `Run` performs the work when capacity and policy allow.

### Human Operator Request

- An operator asks the repository to perform work through chat or UI action.
- The request is persisted as `Intake` with `intake_type = operator_request`.
- The system may normalize an `Event` such as `operator.requested.feature` or
  `operator.requested.remediation`.
- Policy and current repository state produce an `Assessment`.
- A `WorkItem` is created, prioritized, and routed into the normal queue like any other
  unit of work.

## Relationship Model

The control loop should read like this:

```text
SourceRepo
  -> ManagedRepo

ManagedRepo
  -> PolicySet
  -> Observation
  -> Intake
  -> ExternalObject
  -> Event
  -> Assessment
  -> WorkItem

Intake
  -> Event

ExternalObject
  -> Event

WorkItem
  -> Run

Run
  -> ChangeRequest
  -> Evidence

ChangeRequest
  -> Decision
```

The next-layer additions should fit around that base shape like this:

```text
FactoryDefaults
  -> PolicyPack
  -> ExecutionProfile

PolicyPack
  -> PolicySet
  -> ExecutionProfile

ManagedRepo
  -> RepoPosture
  -> Initiative
  -> ExecutionProfile

RepoPosture
  -> PostureCheck

Initiative
  -> WorkItem
```

## Suggested Ash Domain Layout

This ontology maps naturally into four Ash domains.

### `Jido.Code.Repos`

- `SourceRepo`
- `ManagedRepo`

### `Jido.Code.Governance`

- `FactoryDefaults`
- `PolicyPack`
- `PolicySet`
- `OperatorOverride`
- `ChangeRequest`
- `Decision`

### `Jido.Code.Control`

- `Observation`
- `Intake`
- `ExternalObject`
- `Event`
- `Assessment`
- `RepoPosture`
- `PostureCheck`
- `Evidence`

### `Jido.Code.Operations`

- `Initiative`
- `WorkItem`
- `Run`

### `Jido.Code.Execution`

- `ExecutionProfile`

## Derived Summaries, Not Root Truth

The following are important, but they should usually be derived or cached from lower
level records rather than treated as independent roots of truth:

- queue depth
- health summaries
- confidence bands
- policy conformance rollups

That keeps the ontology explainable and reduces duplicated state.

## What Should Not Be First-Class Yet

To keep the ontology tight, the first version should avoid creating standalone resources
for every provider-specific object type.

GitHub issues and pull requests should be represented through the generic
`ExternalObject` resource rather than separate `GitHubIssue` and `GitHubPullRequest`
resources.

These can still begin life as fields inside `Observation`, `Event`, `ExternalObject`, or
`Evidence`:

- check runs
- issue comments
- deployment records
- external alerts
- long chat transcripts

They should only become first-class resources when `Jido.Code` needs to govern them as
independent operational units.

## Mapping To Current Code

This ontology suggests the following direction for the current codebase:

- `JidoCode.GitHub.Repo` is closest to `SourceRepo`
- `JidoCode.Projects.Project` is directionally closer to `ManagedRepo` than to a generic project object
- `JidoCode.GitHub.WebhookDelivery` is the seed of one `Intake` subtype
- `JidoCode.Orchestration.WorkflowRun` is the seed of `Run`

Current implementation still uses `JidoCode.*` module names. The canonical namespace
for new architecture docs is `Jido.Code.*`, and any runtime rename should be treated as
separate implementation work.
