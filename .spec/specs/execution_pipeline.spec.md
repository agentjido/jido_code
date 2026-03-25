# Execution Pipeline

This subject defines the canonical execution model for `Jido.Code` runs, workflow steps,
and sandbox sessions.

```spec-meta
id: architecture.execution_pipeline
kind: policy
status: active
summary: Jido.Code centers execution on Jido.Runic, which drives Runic workflows through the Jido runtime while sprite sessions provide sandbox lifecycle and Ash resources provide durable governance projections.
decisions:
  - jido_code.runic_execution_model
surface:
  - .spec/decisions/jido_code.runic_execution_model.md
  - docs/TECHNICAL_IMPLEMENTATION.md
  - docs/DATA_ONTOLOGY.md
```

## Requirements

```spec-requirements
- id: architecture.execution_pipeline.jido_runic_is_canonical_execution_layer
  statement: Jido.Code shall treat Jido.Runic as the canonical execution integration layer for repository runs and workflow-driven step orchestration.
  priority: must
  stability: evolving

- id: architecture.execution_pipeline.runic_is_underlying_dag_engine
  statement: Jido.Code shall treat Runic as the underlying DAG and runnable substrate beneath Jido.Runic rather than as the primary integration surface.
  priority: must
  stability: evolving

- id: architecture.execution_pipeline.jido_runic_bridges_runtime
  statement: Jido.Code shall use Jido.Runic strategy and directive machinery to connect workflow planning with Jido runtime directives and completion signals.
  priority: must
  stability: evolving

- id: architecture.execution_pipeline.sprite_session_owns_sandbox_lifecycle
  statement: Sprite session resources shall own sandbox provisioning, generic bootstrap, checkpointing, and resume lifecycle.
  priority: must
  stability: evolving

- id: architecture.execution_pipeline.run_is_projection_of_workflow_state
  statement: The durable Run resource shall be a control-plane projection around Jido.Runic-managed workflow state rather than a duplicate step engine.
  priority: must
  stability: stable

- id: architecture.execution_pipeline.repo_prep_and_validation_are_explicit_steps
  statement: Repository-specific prep and validation activities such as sync, dependency install, lint, tests, and spec checks shall be modeled as explicit workflow steps when they affect execution evidence or control decisions.
  priority: must
  stability: evolving

- id: architecture.execution_pipeline.session_bootstrap_distinct_from_repo_prep
  statement: Generic sandbox bootstrap shall remain distinct from repository-specific prep performed inside a workflow run.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: architecture.execution_pipeline.scenario_fresh_sprite_run
  covers:
    - architecture.execution_pipeline.sprite_session_owns_sandbox_lifecycle
    - architecture.execution_pipeline.session_bootstrap_distinct_from_repo_prep
  given:
    - A run starts in a fresh sprite with no active workspace state.
  when:
    - The system prepares execution for repository work.
  then:
    - Session bootstrap handles sandbox setup first, and repository prep remains explicit workflow work inside the run.

- id: architecture.execution_pipeline.scenario_runic_drives_execution
  covers:
    - architecture.execution_pipeline.jido_runic_is_canonical_execution_layer
    - architecture.execution_pipeline.runic_is_underlying_dag_engine
    - architecture.execution_pipeline.jido_runic_bridges_runtime
    - architecture.execution_pipeline.run_is_projection_of_workflow_state
  given:
    - A managed repository launches a new run for a work item.
  when:
    - The run advances through planning and execution.
  then:
    - Jido.Runic drives execution, Runic provides the underlying workflow mechanics, and the Ash Run record reflects the resulting control-plane state.

- id: architecture.execution_pipeline.scenario_validation_fans_out
  covers:
    - architecture.execution_pipeline.repo_prep_and_validation_are_explicit_steps
  given:
    - A run reaches repository validation after implementation or repair work.
  when:
    - Lint, tests, and spec checks can execute independently.
  then:
    - They may be represented as explicit workflow steps that fan out and rejoin before the next approval or landing decision.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.runic_execution_model.md
  covers:
    - architecture.execution_pipeline.jido_runic_is_canonical_execution_layer
    - architecture.execution_pipeline.runic_is_underlying_dag_engine
    - architecture.execution_pipeline.jido_runic_bridges_runtime
    - architecture.execution_pipeline.sprite_session_owns_sandbox_lifecycle
    - architecture.execution_pipeline.run_is_projection_of_workflow_state
    - architecture.execution_pipeline.repo_prep_and_validation_are_explicit_steps
    - architecture.execution_pipeline.session_bootstrap_distinct_from_repo_prep
```
