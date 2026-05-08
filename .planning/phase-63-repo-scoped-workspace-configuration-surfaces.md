# Phase 63 - Repo-Scoped Workspace Configuration Surfaces

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/runtime_environment_defaults.spec.md`
- `../specs/setup_onboarding.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/conversation_orchestration.spec.md`
- `../decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md`
- `lib/jido_code/control/managed_repo.ex`
- `lib/jido_code/control/repo_bridge.ex`
- `lib/jido_code_web/live/setup_live.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/settings_live.ex`
- `lib/jido_code_web/components/operator_state_components.ex`
- `test/jido_code_web/live/setup_live_test.exs`
- `test/jido_code_web/live/project_detail_live_test.exs`
- `test/jido_code_web/live/settings_live_test.exs`

## Relevant Assumptions / Defaults
- No backward compatibility path is needed for repo configuration UX; new repo-scoped controls can replace wording and flows that imply one shared local root.
- Install-wide runtime defaults still belong to setup and remain useful for seeding imports, but operators need a direct repo-scoped way to inspect and update execution binding after import.
- Repo detail is already the canonical runtime-readiness host for managed repositories, so repo-scoped workspace remediation should remain close to that route unless a settings-owned control surface is clearly better.
- Local repositories may live in unrelated filesystem locations, so repo-scoped configuration must accept arbitrary valid absolute paths instead of forcing a derived subdirectory under one root.

[x] 63 Phase 63 - Repo-Scoped Workspace Configuration Surfaces
  Add the product-owned mutation and operator UI needed to inspect, set, and repair each managed repository's workspace binding directly, without relying on one install-wide local-root assumption.

[x] 63.1 Section - Repo-Scoped Workspace Mutation Boundaries
    Introduce an explicit managed-repository write surface for workspace binding so repo-level remediation is no longer an indirect side effect of setup import.

    [x] 63.1.1 Task - Add canonical repo-scoped workspace-binding updates
      Make managed repositories writable at the right seam for workspace environment and local path updates.

      [x] 63.1.1.1 Subtask - Add a product-owned repo-scoped mutation path for setting or replacing workspace environment, workspace root, and workspace path on one managed repository.
      [x] 63.1.1.2 Subtask - Validate repo-scoped local workspace paths as absolute and operator-intentional instead of deriving them from install-wide defaults.
      [x] 63.1.1.3 Subtask - Keep repo-scoped updates isolated to the selected managed repository instead of rewriting install-wide setup defaults as a side effect.

    [x] 63.1.2 Task - Keep setup defaults and repo-scoped edits clearly distinct
      Avoid reintroducing the old ambiguity in either mutation behavior or copy.

      [x] 63.1.2.1 Subtask - Preserve install-wide runtime defaults as import-time seed metadata rather than a hidden repo-edit channel.
      [x] 63.1.2.2 Subtask - Keep repo-scoped workspace edits from implicitly changing other managed repositories.
      [x] 63.1.2.3 Subtask - Remove UI or copy paths that imply changing setup defaults will retroactively relocate already-imported repositories.

  [x] 63.2 Section - Operator And Setup Surface Adoption
    Surface the repo-scoped binding model to operators in the places where they actually discover blocked runtime state.

    [x] 63.2.1 Task - Add repo-level workspace inspection and repair UI
      Give operators a direct place to see the bound workspace path and repair blocked local runtime readiness for one repository.

      [x] 63.2.1.1 Subtask - Expose the current repo-scoped workspace binding and readiness state on a canonical managed-repository operator surface.
      [x] 63.2.1.2 Subtask - Add explicit repo-level repair controls that let an operator bind or rebind a local workspace path for one managed repository.
      [x] 63.2.1.3 Subtask - Keep blocked runtime remediation language focused on the selected repository rather than on one install-wide root.

    [x] 63.2.2 Task - Update setup and import copy to describe defaults honestly
      Keep setup useful without overstating what the install-wide root means after import.

      [x] 63.2.2.1 Subtask - Rewrite setup runtime-environment copy so `workspace_root` is clearly described as a default seed, not a permanent topology rule.
      [x] 63.2.2.2 Subtask - Update local-repository and GitHub import follow-up copy so operators understand that each managed repository owns its later workspace binding.
      [x] 63.2.2.3 Subtask - Remove product wording that implies all managed local repositories must sit under one shared parent directory.

  [x] 63.3 Section - Phase Integration Tests
    Verify the new repo-scoped mutation and UI surfaces the way an operator will actually use them.

    [x] 63.3.1 Task - Add repo-scoped configuration interaction coverage
      Cover both the mutation boundary and the user-facing repair flow that depends on it.

      [x] 63.3.1.1 Subtask - Add coverage proving one managed repository can be rebound to an arbitrary valid absolute local path without changing another repository.
      [x] 63.3.1.2 Subtask - Add repo-detail or settings coverage proving blocked runtime remediation can set a repo-scoped workspace binding directly.
      [x] 63.3.1.3 Subtask - Add setup coverage proving install-wide runtime defaults remain seed-only metadata after the copy and control-surface cutover.
