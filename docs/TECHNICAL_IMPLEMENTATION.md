<!-- covers: docs.product_foundation.technical_approach_defined -->

# Jido.Code Technical Implementation

## Purpose

This document captures the current technical stance behind `Jido.Code`.

It is intentionally terse. The goal is to define the implementation approach that
supports the vision and the data ontology.

## System Shape

`Jido.Code` is a control center for managed repositories.

The system has five technical parts:

- a web control surface for operators
- a durable control-plane data model
- repository-scoped orchestration
- isolated execution environments for work and verification
- provider integrations, starting with GitHub

## Technical Stance

- `Ash` is the source of truth for durable control-plane state
- `Jido` is the orchestration runtime for repository agents and worker agents
- `Jido.Runic` is the canonical execution integration layer for repository runs
- `Runic` provides the underlying workflow DAG and runnable execution substrate
- Phoenix and LiveView provide the operator control surface
- Sprite sessions provide the sandbox lifecycle for isolated execution, checkpointing, and resume
- Git remains the mutation boundary and audit trail

## Canonical Namespace

The canonical namespace for new architecture docs is `Jido.Code`.

Current implementation modules may still use `JidoCode.*`, but new domain layouts and
conceptual naming should prefer `Jido.Code.*`.

## Control Loop

The system should follow one durable control loop:

1. synchronize the `SourceRepo`
2. load the active `PolicySet`
3. capture inbound `Intake` and `Observation` records
4. upsert relevant `ExternalObject` records when one exists
5. normalize actionable `Event` records
6. derive `Assessment` records
7. create or reprioritize `WorkItem` records
8. execute a `Run` in an isolated environment
9. produce `Evidence` and a `ChangeRequest` when mutation or governance action is needed
10. persist `Decision` when policy requires acceptance or rejection
11. update the `ManagedRepo` operating posture

## Near-Term Implementation Priorities

The current plan should now concentrate on six additions that close the most important
product gaps without widening the scope too early.

### `RepoPosture` And `PostureCheck`

`RepoPosture` should become the primary control summary for a managed repository.

It should answer:

- how trustworthy the repository is for greater autonomy
- what is currently blocking confidence
- what the operator should improve next

`PostureCheck` should capture the contributing checks or gates behind that summary.
These checks should be derived from policy, observations, assessments, run history, and
recovery evidence rather than hand-maintained scores.

### `ExecutionProfile`

`ExecutionProfile` should make execution environment behavior explicit.

It should describe:

- which sprite shape to start
- how sandbox bootstrap works
- how repo prep runs in a fresh environment
- which validation nodes are expected by default
- what can be cached, checkpointed, or resumed

The profile should be attachable to a `ManagedRepo` directly or inherited through a
`PolicyPack`.

### `Initiative`

`Initiative` should sit above `WorkItem` for multi-step repository outcomes.

It should group related work items, runs, approvals, and evidence into one bounded unit
for feature delivery, maintenance programs, or broader conformance efforts.

### `ReviewPolicy`

`ReviewPolicy` should begin as an embedded structure inside `PolicySet`, not as a
standalone platform.

It should define:

- when human review is required
- what evidence must be assembled
- what path-scoped or repo-scoped review rules apply
- what happens after approval, rejection, or hold

### Headless Control Surface

CLI and API entry points should route into the same durable control loop as the web UI.

They should create the same `Intake`, `Event`, `Assessment`, `WorkItem`, `Run`, and
`Evidence` records rather than creating a detached automation path.

### Simplified Control Layers

The first control hierarchy should stay simple:

- `FactoryDefaults`
- `PolicyPack`
- `PolicySet`
- `OperatorOverride`

This layering is enough to support a personal factory without prematurely importing
enterprise configuration complexity.

## VSM Recursion

`Jido.Code` should apply Stafford Beer's recursive Viable System Model at two default
levels:

- the factory instance as the overall viable system
- each `ManagedRepo` as a viable subsystem inside that factory

At the factory level, the primary operational units are managed repositories. At the
repository level, the primary operational units are the work loops that create and
complete `WorkItem` and `Run` records.

This is intentionally bounded. `WorkItem` and `Run` are durable operational records, not
full viable systems by default. They should only be promoted into lower-level viable
subsystems when they develop persistent identity, bounded mission, their own
coordination needs, their own control and feedback loop, and distinct policy or
autonomy constraints.

This keeps the architecture recursive without becoming noisy or over-modeled.

## Execution Stack

`Jido.Code` should not invent a separate run engine beside `Jido.Runic`.

The execution stack should be understood as five layers:

- `Runic` defines the workflow graph, node dependencies, and runnable mechanics
- `Jido.Runic` turns those workflows into a Jido-native strategy, directives, and signals
- `Jido` hosts the runtime loop that dispatches directives and routes completion signals
- Sprite sessions provide the provisioned execution environment where runnable work happens
- `Ash` stores durable projections, approvals, evidence, and operator-facing state

This means `Jido.Code` should primarily integrate against `Jido.Runic`, not against bare
Runic internals, while still treating the underlying Runic workflow state as the source
of truth for topology and step progression.

## Jido.Runic Execution Model

`Jido.Runic` already packages the Runic execution model in the form `Jido.Code` actually
needs: a strategy-driven loop that accepts signals, prepares runnables, emits execution
directives, and applies completion signals back into workflow state.

Underneath that, the execution model remains explicitly three-phase:

1. `prepare` the next runnable units from the workflow graph
2. `execute` those runnables in isolation, potentially in parallel
3. `apply` the completed results back into the workflow so downstream steps can unlock

`Jido.Code` should adopt that model through `Jido.Runic.Strategy` and
`Jido.Runic.Directive.ExecuteRunnable`, not by recreating it in local runner logic.

The durable `Run` record in the control plane should be a governed projection around a
`Jido.Runic`-driven workflow execution. It should track:

- which workflow definition is being executed
- which repository and work item it belongs to
- which sandbox session or sessions are attached
- the current projected step or gate
- high-level status, evidence, and approval state

It should not duplicate the full Runic step engine as a second execution system.

`Jido.Runic` also gives `Jido.Code` a natural supervision control point through
`execution_mode: :auto | :step`. That is a strong fit for the trust model because step
mode can support directed or guided supervision, while auto mode supports delegated or
autonomous operation.

## Session And Run Boundary

Fresh sandbox startup has two distinct layers that should not be collapsed together.

Session-level setup is generic sandbox lifecycle work:

- provision or restore a sprite
- inject environment and secrets
- run generic bootstrap commands
- initialize the runner and checkpoint/resume hooks

Run-level prep is repository-specific work that should be explicit inside the Runic DAG:

- attach or hydrate the workspace
- checkout or create the target branch
- detect the stack and toolchain
- install dependencies
- restore caches if available
- run preflight validation

That distinction matters. Generic sprite bootstrap belongs to the session substrate.
Repository prep belongs in the workflow so it is visible, retryable, explainable, and
eligible for evidence capture.

## Suggested Session And Run Shape

For a fresh repository run, the implementation should look like this:

1. Start or resume a sprite session
2. Complete generic sprite bootstrap
3. Create or restore the Runic workflow state for the run
4. Feed run inputs into the workflow
5. Let `Jido.Runic` prepare and dispatch runnables
6. Execute runnable work inside the attached sprite session
7. Apply completion signals back through `Jido.Runic`
8. Repeat until the workflow reaches approval, failure, or completion

Within that workflow, the default step family should be:

- `policy_gate`
- `workspace_attach`
- `repo_sync`
- `repo_prep`
- `implement_or_repair`
- `validate_lint`
- `validate_tests`
- `validate_specs`
- `assemble_evidence`
- `approval_gate`
- `publish_or_land`
- `checkpoint_or_cleanup`

Validation steps such as lint, tests, and spec checks should usually be explicit Runic
nodes so they can fan out and then join before the next control decision.

## Ash Modeling Approach

- model durable control objects first
- keep the first resource set small
- prefer embedded structures for unstable policy details and provider payloads
- promote stable substructures to first-class resources only when governance requires it
- keep cached summaries separate from root truth

## Suggested Ash Domain Layout

### `Jido.Code.Repos`

Core repository identity and managed control objects.

- `SourceRepo`
- `ManagedRepo`

### `Jido.Code.Governance`

Desired state and governed acceptance of change.

- `FactoryDefaults`
- `PolicyPack`
- `PolicySet`
- `OperatorOverride`
- `ChangeRequest`
- `Decision`

`ReviewPolicy` should begin embedded inside `PolicySet`.

### `Jido.Code.Control`

Observed state, incoming events, interpreted meaning, and durable proof.

- `Observation`
- `Intake`
- `ExternalObject`
- `Event`
- `Assessment`
- `RepoPosture`
- `PostureCheck`
- `Evidence`

### `Jido.Code.Operations`

Actionable work and execution lifecycle.

- `Initiative`
- `WorkItem`
- `Run`

### `Jido.Code.Execution`

Reusable execution environment definitions.

- `ExecutionProfile`

## Modeling Boundaries

In the first version, `Jido.Code` should not model every GitHub concept as a
first-class resource.

GitHub issues, pull requests, check runs, alerts, and deployment events can begin as
generic external-state records rather than provider-specific Ash resources.

The first version should prefer:

- one `Intake` resource for raw inbound deliveries and requests
- one `ExternalObject` resource for mirrored issues, pull requests, and similar objects
- one `Event` resource for normalized actionable meaning

That keeps the model small while still supporting general demand creation.

## General Demand Flow

When demand enters `Jido.Code`, it should flow like this:

1. an inbound request or trigger is captured as `Intake`, when one exists
2. any related issue, pull request, or other external record is mirrored as an `ExternalObject`
3. one or more normalized `Event` records are created
4. policy and current repository context produce an `Assessment`
5. the assessment creates or updates a `WorkItem`
6. the `WorkItem` enters the queue and may be shown on a kanban board
7. the orchestrator launches a sandboxed `Run` when policy and capacity allow
8. the run produces `Evidence` and, when needed, a governed `ChangeRequest`

This should work for:

- provider webhooks
- human/operator requests
- scheduled maintenance windows
- runtime alerts
- API-driven automation
- internally generated follow-up work
- drift discovered through observation

## Work System

`WorkItem` is the durable job-system unit in `Jido.Code`.

The operator queue, kanban views, backlog views, and run launch decisions should all be
projections over `WorkItem` records and their status, priority, and scope.

## Operational Implications

- autonomy is a property of the `ManagedRepo`, not of individual runs
- external provider state should be mirrored separately from raw intake transport
- policy determines when work may proceed and when decisions must be escalated
- the work queue should be represented through `WorkItem`, not through ad hoc run lists
- runs own execution attempts, not the long-term identity of the repository
- evidence must survive beyond any one agent session or prompt window
- the UI should read from the same control-plane records that the orchestrator uses
