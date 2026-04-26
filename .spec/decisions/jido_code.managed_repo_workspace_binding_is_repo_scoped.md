---
id: jido_code.managed_repo_workspace_binding_is_repo_scoped
status: accepted
date: 2026-04-25
affects:
  - package.jido_code
  - architecture.factory_control_plane
  - architecture.conversation_orchestration
  - setup.onboarding
  - setup.runtime_environment_defaults
---

<!-- current_truth.reconciled_with_branch: setup still persists install-wide runtime defaults through SystemConfig, but canonical runtime readiness and repo-detail execution already resolve workspace binding from each managed repository's persisted workspace settings, setup import now accepts explicit repo-scoped local workspace paths without requiring one shared install-wide parent root, the signed-in setup surface now describes `workspace_root` as seed metadata for new imports rather than a permanent topology rule, product-owned repo-scoped workspace-binding updates now let operators repair one managed repository directly from repo detail without rewriting setup defaults or sibling repositories, and blocked conversation, semantic, memory, and workflow surfaces now share that same repo-scoped readiness vocabulary and route-local repair path. -->

<!-- covers: architecture.factory_control_plane.managed_repos_own_repo_scoped_workspace_binding -->
<!-- covers: architecture.conversation_orchestration.runtime_readiness_uses_managed_repo_workspace_binding -->
<!-- covers: setup.onboarding.runtime_defaults_seed_repo_scoped_workspace_binding -->
<!-- covers: setup.runtime_environment_defaults.repo_scoped_workspace_binding_is_canonical -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Managed Repository Workspace Binding Is Repo Scoped

## Context

`Jido.Code` currently persists install-wide runtime defaults through
`SystemConfig.default_environment` and optional `SystemConfig.workspace_root`.
Setup import uses that metadata to seed workspace provisioning for newly
imported repositories when no repo-specific binding was supplied.

At the same time, the product's real execution paths already depend on
repo-scoped workspace metadata:

- managed repositories persist `workspace_settings`, including
  `workspace_environment`, `workspace_root`, and `workspace_path`
- repo detail derives execution readiness from those managed-repository
  workspace settings
- conversation runtime readiness validates the managed repository's persisted
  `workspace_path`

Setup import may also receive explicit repo-scoped workspace metadata such as a
repository-specific local `workspace_path`. That means the canonical execution
binding is already repository-scoped even though some setup copy can still read
as though one install-wide workspace root defines local execution topology for
every repository.

That assumption is too narrow. Managed local repositories may live in unrelated
filesystem locations, may arrive through different import paths, and may need
repo-specific execution bindings that do not share one parent directory.

## Decision

`Jido.Code` shall treat managed-repository workspace binding as repo-scoped
product truth.

The durable rule has five parts:

1. `SystemConfig.default_environment` and optional `SystemConfig.workspace_root`
   are install-wide setup defaults, not the canonical execution location for
   every managed repository.
2. Each managed repository's persisted `workspace_settings`, especially
   `workspace_environment` and `workspace_path`, are the canonical workspace
   binding used by runtime readiness, conversation execution, semantic
   inspection, memory inspection, and other repo-scoped execution surfaces.
3. Setup import may seed initial workspace context from install-wide defaults
   when repository metadata does not already provide a repo-scoped binding, but
   it shall persist the resulting repo-scoped workspace binding onto the managed
   repository so later execution does not depend on re-reading the install-wide
   default root.
4. Local managed repositories are not required to live under a shared parent
   directory, and product contracts must not imply that one install-wide root is
   a permanent topology constraint.
5. Changing install-wide defaults later does not retroactively redefine the
   canonical workspace binding for already-imported managed repositories unless a
   repo-scoped update flow explicitly rewrites that managed-repository state.
6. Product-owned workspace repair and rebinding flows shall update only the
   selected managed repository's persisted `workspace_settings`; those flows are
   not a backdoor for mutating `SystemConfig` defaults or relocating sibling
   repositories.

## Consequences

### Positive

- conversation, semantic, memory, and workflow surfaces all align on the same
  managed-repository execution seam
- the product can support local repositories that live in unrelated filesystem
  locations without inventing shadow runtime rules
- setup-owned runtime defaults remain useful as import-time convenience without
  overstating their authority
- operators have a direct repo-scoped repair seam for blocked runtime readiness
  instead of needing to re-run setup or infer a shared-root convention
- setup copy can stay honest about install-wide defaults without implying later
  repo relocation rules after import

### Constraints

- operator-facing copy should distinguish "default workspace root" from
  "this repository's bound workspace path"
- repo-scoped workspace editing remains a distinct product concern from
  install-wide setup defaults
- repo-scoped workspace mutation boundaries must validate operator-supplied
  absolute local paths and reject ambiguous relative or missing-directory input
- local provisioning must accept and validate explicit absolute repo-scoped
  workspace paths without requiring one shared install-wide parent directory
- imports performed under cloud-backed defaults may remain runtime-blocked on
  repo detail until a concrete repo-scoped workspace binding exists
