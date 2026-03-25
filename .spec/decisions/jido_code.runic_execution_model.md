---
id: jido_code.runic_execution_model
status: accepted
date: 2026-03-23
affects:
  - package.jido_code
  - architecture.execution_pipeline
  - docs.product_foundation
---

<!-- covers: architecture.execution_pipeline.jido_runic_is_canonical_execution_layer -->
<!-- covers: architecture.execution_pipeline.runic_is_underlying_dag_engine -->
<!-- covers: architecture.execution_pipeline.jido_runic_bridges_runtime -->
<!-- covers: architecture.execution_pipeline.sprite_session_owns_sandbox_lifecycle -->
<!-- covers: architecture.execution_pipeline.run_is_projection_of_workflow_state -->
<!-- covers: architecture.execution_pipeline.repo_prep_and_validation_are_explicit_steps -->
<!-- covers: architecture.execution_pipeline.session_bootstrap_distinct_from_repo_prep -->

# Runic Execution Model

## Context

`Jido.Code` needs a durable execution model for repository work that supports branching,
parallel validation, resumability, sandbox execution, and governed approval flows.

The architecture already depends on `jido_runic`, which bridges `Runic` workflows into
the `Jido` runtime, and the codebase already contains sprite session lifecycle support
for sandbox provisioning and bootstrap. The risk is drifting into a second ad hoc run
engine in database records or runner-specific state machines instead of adopting the
canonical workflow machinery that is already present.

## Decision

`Jido.Code` shall use `Jido.Runic` as the canonical execution integration layer for
repository runs and workflow-driven step orchestration.

`Runic` shall remain the underlying DAG and runnable substrate beneath `Jido.Runic`.

`Jido.Runic` shall be the canonical bridge that turns workflow planning into `Jido`
runtime directives and completion signals.

Sprite sessions shall remain the sandbox lifecycle owner. They provision or restore the
execution environment, inject environment and secrets, run generic bootstrap, and manage
checkpoint/resume concerns.

The durable `Run` resource in `Jido.Code` shall be treated as a projection around
`Jido.Runic`-managed workflow state rather than as a duplicate step engine. It may store
status, current projected step, evidence links, session references, approval state, and
workflow state references, but the underlying workflow graph and runnable progression
remain `Runic` concerns mediated through `Jido.Runic`.

Repository-specific prep and validation work shall be modeled as explicit workflow steps.
This includes repository attach/sync, dependency install, lint, tests, spec checks, and
other gates that should be visible, retryable, and evidence-producing.

Generic sandbox bootstrap shall remain distinct from repository prep. Session bootstrap
prepares the sandbox. Workflow prep prepares the repository inside that sandbox.

## Consequences

- `Jido.Runic` becomes the authoritative execution modality for `Run` and step planning.
- `Runic` remains essential, but as the substrate beneath the primary integration layer.
- `Run` remains a durable Ash record without becoming a parallel workflow engine.
- Fresh sandbox startup can be modeled cleanly through sprite session lifecycle plus
  explicit repo-prep steps.
- Linting, tests, and other quality gates can fan out as Runic nodes and join before the
  next control decision.
- Resume and replay can be grounded in stored workflow state references and sprite
  checkpoints instead of reconstructed ad hoc state.
