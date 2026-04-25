# Phase 62 - Managed Repo Workspace Binding Canonicalization

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/runtime_environment_defaults.spec.md`
- `../specs/setup_onboarding.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/conversation_orchestration.spec.md`
- `../decisions/jido_code.runtime_environment_selection_is_persisted_setup_metadata.md`
- `../decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md`
- `lib/jido_code/setup/project_import.ex`
- `lib/jido_code/setup/system_config.ex`
- `lib/jido_code/control/managed_repo.ex`
- `lib/jido_code/control/repo_bridge.ex`
- `lib/jido_code/workbench/project_detail.ex`
- `lib/jido_code/conversations/runtime_readiness.ex`
- `test/jido_code/setup/project_import_test.exs`
- `test/jido_code_web/live/project_detail_live_test.exs`

## Relevant Assumptions / Defaults
- No backward compatibility path is needed for the old shared-parent workspace assumption; this phase can cut directly to the repo-scoped contract.
- Install-wide runtime defaults remain useful as setup-owned seed metadata, but they are not the canonical execution location for already-imported repositories.
- Managed repositories already persist `workspace_settings`; this phase should promote that seam into the single canonical execution-binding contract instead of introducing another layer.
- Cloud-backed imports may remain intentionally unbound to a local workspace path and should read as blocked for local-runtime execution rather than pretending to be partially ready.

[x] 62 Phase 62 - Managed Repo Workspace Binding Canonicalization
  Cut the product over to one canonical rule: each managed repository owns its execution workspace binding, while install-wide runtime defaults only seed initial provisioning.

  [x] 62.1 Section - Canonical Workspace Binding Model
    Promote repo-scoped workspace binding from an implementation detail into the explicit control-plane contract used by runtime and operator surfaces.

    [x] 62.1.1 Task - Make managed-repository workspace settings the single execution-binding seam
      Remove any remaining ambiguity about where runtime surfaces should resolve local execution paths after a repository exists.

      [x] 62.1.1.1 Subtask - Centralize the canonical repo-scoped workspace binding shape around managed-repository `workspace_settings`, including `workspace_environment`, `workspace_root`, and `workspace_path`.
      [x] 62.1.1.2 Subtask - Remove any product-owned runtime read path that treats `SystemConfig.workspace_root` or onboarding state as the canonical execution location for an already-imported repository.
      [x] 62.1.1.3 Subtask - Keep unbound cloud-backed repositories explicit by contract instead of allowing implicit local fallback behavior.

    [x] 62.1.2 Task - Cut runtime and detail helpers over to the canonical seam
      Make repo detail and runtime-readiness helpers consume the same repo-scoped workspace contract instead of reconstructing execution assumptions independently.

      [x] 62.1.2.1 Subtask - Align `ProjectDetail`, conversation runtime readiness, and adjacent repo-scoped helpers on one canonical workspace-binding projection.
      [x] 62.1.2.2 Subtask - Keep blocked readiness typed and actionable when the managed repository has no concrete local workspace binding.
      [x] 62.1.2.3 Subtask - Remove any helper behavior that silently re-derives a local path from install-wide defaults after a managed repository already exists.

  [x] 62.2 Section - Import And Provisioning Cutover
    Keep setup-owned defaults useful at import time while making the resulting managed-repository state authoritative immediately after provisioning.

    [x] 62.2.1 Task - Persist repo-scoped workspace binding directly during import
      Ensure initial repository import writes the execution binding that later runtime surfaces will actually consume.

      [x] 62.2.1.1 Subtask - Keep install-wide runtime defaults limited to seeding initial workspace context for import and provisioning.
      [x] 62.2.1.2 Subtask - Persist the resulting repo-scoped workspace binding onto the managed repository during import instead of requiring later runtime reconstruction.
      [x] 62.2.1.3 Subtask - Keep local provisioning able to materialize a concrete workspace path even when repositories do not share one parent directory.

    [x] 62.2.2 Task - Remove the shared-parent assumption from validation and shaping
      Make the import pipeline accept repo-scoped local execution binding as a first-class concept instead of a special case under one root.

      [x] 62.2.2.1 Subtask - Validate explicit repo-scoped local paths as repository bindings rather than only validating a shared install-wide root.
      [x] 62.2.2.2 Subtask - Keep cloud-backed imports explicit about producing no local workspace binding.
      [x] 62.2.2.3 Subtask - Avoid adding migration or dual-read compatibility helpers for the old shared-root assumption.

  [x] 62.3 Section - Phase Integration Tests
    Prove the control-plane and import cutover works without relying on the retired shared-parent assumption.

    [x] 62.3.1 Task - Add repo-scoped workspace-binding coverage
      Verify the canonical contract at the product seams that matter most for execution readiness.

      [x] 62.3.1.1 Subtask - Add import and provisioning coverage proving managed repositories persist repo-scoped workspace bindings directly from the cutover path.
      [x] 62.3.1.2 Subtask - Add repo-detail or runtime-readiness coverage proving execution reads the managed repository's workspace binding instead of install-wide defaults.
      [x] 62.3.1.3 Subtask - Add coverage proving repositories without a local workspace binding stay explicitly blocked rather than falling back to a shared-root assumption.
