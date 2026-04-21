---
id: jido_code.runtime_environment_selection_is_persisted_setup_metadata
status: accepted
date: 2026-04-21
affects:
  - package.jido_code
  - setup.onboarding
  - setup.runtime_environment_defaults
  - architecture.execution_pipeline
  - architecture.run_governance
---

<!-- covers: setup.onboarding.runtime_environment_selection_distinct_from_install_flavor -->
<!-- covers: setup.onboarding.runtime_environment_selection_persisted_metadata -->
<!-- covers: setup.runtime_environment_defaults.selection_is_distinct_from_install_flavor -->
<!-- covers: setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config -->
<!-- covers: setup.runtime_environment_defaults.cloud_selection_maps_to_sprite_default -->
<!-- covers: setup.runtime_environment_defaults.local_selection_requires_valid_workspace_root -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Runtime Environment Selection Is Persisted Setup Metadata

## Context

`Jido.Code` currently carries two different ideas that are easy to blur in the
browser:

- an auto-detected install flavor used for copy and start-surface emphasis
- a runtime execution default that determines whether repository work should run
  through local workspaces or cloud-backed runtime services such as the current
  Sprite execution path

The codebase already has durable runtime-environment metadata surfaces:
`SystemConfig.default_environment`, `SystemConfig.workspace_root`,
database-backed `SystemConfigRecord` persistence, and setup helpers that map a
cloud-style selection to `:sprite` and a local-style selection to `:local`.

What is missing is an explicit durable rule that this runtime selection is
product metadata, not a cosmetic UI hint and not something to infer from the
install flavor alone.

## Decision

`Jido.Code` shall treat onboarding runtime-environment selection as real,
durable setup metadata.

The durable rule has five parts:

1. Auto-detected install flavor and runtime environment selection are separate
   concepts. Install flavor explains product packaging context. Runtime
   environment selection explains where governed repository work should run by
   default.
2. Runtime environment selection shall persist through the database-backed
   system-config singleton instead of living only in route-local assigns, flash
   state, or non-durable browser choices.
3. The durable product metadata for this choice is `default_environment` plus
   optional `workspace_root`, with onboarding step-state metadata allowed to
   preserve the validated selection details that produced those fields.
4. A cloud-style runtime choice maps to `default_environment: :sprite`; runtime
   provider details such as the current Sprites-backed path stay behind product
   runtime boundaries instead of becoming the onboarding contract itself.
5. A local runtime choice maps to `default_environment: :local` and requires a
   validated absolute workspace root before setup can treat the choice as ready.

Repo import, workspace preparation, and later execution-default resolution shall
use this persisted metadata as the setup-owned seed until repo-level governed
settings or execution profiles override it explicitly.

## Consequences

### Positive

- onboarding can present a real local-versus-cloud runtime choice without
  overloading install-flavor copy
- runtime defaults survive server restarts because they are persisted in the
  database-backed setup record
- later repo import and execution setup can rely on one durable metadata seam
  instead of reconstructing intent from packaging context

### Constraints

- the onboarding contract should describe runtime-environment classes such as
  local or cloud-backed execution, not vendor names like Sprites or future
  providers
- setup UI must not label install flavor as though it were the operator's
  runtime execution choice
- repo-level execution settings may still override the setup-owned default once
  canonical managed-repository governance exists
