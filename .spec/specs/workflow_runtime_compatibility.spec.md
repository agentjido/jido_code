# Workflow Runtime Compatibility

This subject defines the local compatibility surface that keeps
`workflow.run.*` tools available when `jido_code_server` expects the legacy
`JidoWorkflow.Workflow.*` runtime modules.

```spec-meta
id: workflow.runtime.compatibility
kind: feature
status: active
summary: jido_code provides a version-controlled local jido_workflow compatibility package that satisfies jido_code_server's legacy loader and engine API without requiring CI access to a private transitive Git dependency, while keeping the root Mix dependency surface responsible for the local override.
surface:
  - mix.exs
  - compat/jido_workflow/mix.exs
  - compat/jido_workflow/lib/**/*.ex
  - test/jido_code/workflow_runtime/jido_workflow_compatibility_test.exs
```

## Requirements

```spec-requirements
- id: workflow.runtime.compatibility.local_override_present
  statement: jido_code shall override the transitive `:jido_workflow` dependency with a version-controlled local compatibility package so repository CI does not depend on private external Git credentials just to resolve dependencies.
  priority: must
  stability: evolving

- id: workflow.runtime.compatibility.legacy_loader_and_engine_surface
  statement: The local compatibility package shall expose the `JidoWorkflow.Workflow.Loader.load_markdown/1` and `JidoWorkflow.Workflow.Engine.execute_definition/3` APIs that jido_code_server expects for workflow asset registration and execution.
  priority: must
  stability: evolving

- id: workflow.runtime.compatibility.action_workflow_execution
  statement: The compatibility runtime shall parse workflow frontmatter inputs from markdown assets and execute action-backed workflow steps that bind `input:` and `result:` references, returning a completed execution envelope for `workflow.run.*` calls.
  priority: must
  stability: evolving
```

## Verification

```spec-verification
- kind: source_file
  target: mix.exs
  covers:
    - workflow.runtime.compatibility.local_override_present

- kind: source_file
  target: compat/jido_workflow/lib/jido_workflow/workflow/loader.ex
  covers:
    - workflow.runtime.compatibility.legacy_loader_and_engine_surface

- kind: source_file
  target: compat/jido_workflow/lib/jido_workflow/workflow/engine.ex
  covers:
    - workflow.runtime.compatibility.legacy_loader_and_engine_surface
    - workflow.runtime.compatibility.action_workflow_execution

- kind: source_file
  target: compat/jido_workflow/lib/jido_workflow/workflow/markdown_parser.ex
  covers:
    - workflow.runtime.compatibility.action_workflow_execution

- kind: source_file
  target: test/jido_code/workflow_runtime/jido_workflow_compatibility_test.exs
  covers:
    - workflow.runtime.compatibility.local_override_present
    - workflow.runtime.compatibility.legacy_loader_and_engine_surface
    - workflow.runtime.compatibility.action_workflow_execution

- kind: command
  target: mix test test/jido_code/workflow_runtime/jido_workflow_compatibility_test.exs
  covers:
    - workflow.runtime.compatibility.local_override_present
    - workflow.runtime.compatibility.legacy_loader_and_engine_surface
    - workflow.runtime.compatibility.action_workflow_execution
```
