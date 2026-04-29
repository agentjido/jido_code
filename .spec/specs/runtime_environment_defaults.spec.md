<!-- covers: package.jido_code.spec_led_workspace -->

# Runtime Environment Defaults

<!-- current_truth.reconciled_with_branch: persisted setup runtime defaults and related onboarding metadata remain governed by this subject, while setup import now treats explicit repo-scoped local workspace paths as higher-priority binding input than the shared install default root, repo detail plus adjacent runtime-readiness surfaces now read and repair workspace binding from each managed repository's own persisted binding instead of pointing operators back to setup defaults, blocked repo-detail conversation runtime now exposes that repair jump inline from the readiness notice, and dashboard `Work > Overview` plus `/workbench` now project those same repo-scoped readiness and repair cues through the shared managed-repository inventory model under the shared signed-in operator navigation layer, with `/workbench` now carrying those cues inside the proportional shared shell. -->

This subject defines how `Jido.Code` captures default runtime execution intent
during setup and persists that choice as durable product metadata.

```spec-meta
id: setup.runtime_environment_defaults
kind: feature
status: active
summary: Jido.Code treats runtime environment choice as setup-owned metadata distinct from install flavor, persists default execution environment and optional local workspace root through the database-backed system-config singleton, keeps that singleton writable through the shared `SystemConfig` boundary so setup reset flows can safely restore canonical defaults, maps cloud defaults to Sprite-backed execution and local defaults to local workspace execution, uses that install-wide metadata only as fallback seed context for repository import and provisioning when repo-scoped binding metadata is absent, allows explicit repo-scoped local workspace paths at import time, and treats each managed repository's persisted workspace settings as the canonical execution binding once repo-scoped state exists, including for conversation, semantic, memory, and workflow readiness plus repo-scoped repair with inline repo-detail conversation repair affordances when that binding is missing, while dashboard `Work > Overview` plus `/workbench` now reuse the same repo-scoped readiness and repair cues through the shared managed-repository inventory helpers and `/workbench` now presents them inside the proportional shared shell.
decisions:
  - jido_code.managed_repo_workspace_binding_is_repo_scoped
  - jido_code.runtime_environment_selection_is_persisted_setup_metadata
  - jido_code.runic_execution_model
surface:
  - .spec/decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md
  - .spec/decisions/jido_code.runtime_environment_selection_is_persisted_setup_metadata.md
  - .spec/decisions/jido_code.runic_execution_model.md
  - lib/jido_code/setup/environment_defaults.ex
  - lib/jido_code/setup/system_config.ex
  - lib/jido_code/setup/system_config_record.ex
  - lib/jido_code/setup/system_config_persistence.ex
  - lib/jido_code/setup/project_import.ex
  - lib/jido_code/conversations/runtime_readiness.ex
  - lib/jido_code/workbench/project_detail.ex
  - lib/jido_code/workbench/inventory_surface.ex
  - lib/jido_code/workbench/inventory_action_state.ex
  - lib/jido_code/workbench/project_memory_inspection.ex
  - lib/jido_code/workbench/project_semantic_inspection.ex
  - lib/jido_code/workbench/project_workspace_binding.ex
  - lib/jido_code/workbench/project_workspace_binding_notice.ex
  - lib/jido_code_web/components/managed_repo_inventory_components.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - lib/jido_code_web/live/workbench_live.ex
  - config/config.exs
  - test/jido_code_web/live/phase_sixty_four_integration_test.exs
```

## Requirements

```spec-requirements
- id: setup.runtime_environment_defaults.selection_is_distinct_from_install_flavor
  statement: Runtime environment choice shall remain distinct from auto-detected install flavor so operator intent about local versus cloud-backed execution is not inferred only from packaging context.
  priority: must
  stability: evolving

- id: setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config
  statement: Default runtime environment and optional local workspace root shall persist through the database-backed system-config singleton rather than existing only as transient onboarding UI state.
  priority: must
  stability: evolving

- id: setup.runtime_environment_defaults.cloud_selection_maps_to_sprite_default
  statement: A cloud-style runtime selection shall persist a Sprite-backed default environment with no required workspace root.
  priority: must
  stability: evolving

- id: setup.runtime_environment_defaults.local_selection_requires_valid_workspace_root
  statement: A local runtime selection shall require a validated absolute workspace root that exists on disk before setup treats the selection as ready.
  priority: must
  stability: evolving

- id: setup.runtime_environment_defaults.repo_scoped_workspace_binding_is_canonical
  statement: Managed repositories shall carry repo-scoped workspace environment and workspace path as the canonical execution binding, so local repositories are not required to share one install-wide parent location.
  priority: must
  stability: evolving

- id: setup.runtime_environment_defaults.import_uses_persisted_runtime_defaults
  statement: Setup repository import shall resolve initial workspace environment from explicit repo-scoped binding metadata when present and otherwise fall back to persisted setup runtime-default metadata, then persist repo-scoped workspace settings on the managed repository so later execution does not depend on one install-wide parent location.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: setup.runtime_environment_defaults.scenario_cloud_selection_persists_sprite_default
  covers:
    - setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config
    - setup.runtime_environment_defaults.cloud_selection_maps_to_sprite_default
  given:
    - Setup captures a cloud-style runtime choice.
  when:
    - The validated environment-default state is persisted.
  then:
    - "The system-config singleton stores `default_environment: :sprite`."
    - The persisted metadata does not require a workspace root for that default.

- id: setup.runtime_environment_defaults.scenario_local_selection_requires_workspace_root
  covers:
    - setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config
    - setup.runtime_environment_defaults.local_selection_requires_valid_workspace_root
  given:
    - Setup captures a local runtime choice.
  when:
    - The choice is validated before persistence.
  then:
    - The local workspace root must be absolute and present on disk.
    - "The persisted system-config singleton stores `default_environment: :local` plus that workspace root."

- id: setup.runtime_environment_defaults.scenario_project_import_uses_persisted_runtime_defaults
  covers:
    - setup.runtime_environment_defaults.import_uses_persisted_runtime_defaults
  given:
    - Setup has already persisted runtime default metadata.
  when:
    - First repository import or workspace provisioning resolves its initial workspace context without explicit repo-scoped local binding metadata.
  then:
    - The import path derives workspace environment and workspace root from the persisted setup metadata instead of inferring those defaults from install flavor alone.
    - The resulting managed repository persists repo-scoped workspace settings used by later execution surfaces.

- id: setup.runtime_environment_defaults.scenario_repo_scoped_workspace_binding_can_diverge_from_install_default_root
  covers:
    - setup.runtime_environment_defaults.repo_scoped_workspace_binding_is_canonical
    - setup.runtime_environment_defaults.import_uses_persisted_runtime_defaults
  given:
    - Install-wide runtime defaults have already been persisted.
    - One or more managed repositories later carry explicit repo-scoped workspace settings, including an explicit local `workspace_path` that may live outside the shared default root.
  when:
    - Runtime readiness or another repo-scoped execution surface resolves workspace binding for a managed repository.
  then:
    - The product uses that managed repository's persisted workspace settings as the canonical execution binding.
    - The product does not assume every local managed repository lives under one shared install-wide parent root.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.runtime_environment_selection_is_persisted_setup_metadata.md
  covers:
    - setup.runtime_environment_defaults.selection_is_distinct_from_install_flavor
    - setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config

- kind: source_file
  target: lib/jido_code/setup/environment_defaults.ex
  covers:
    - setup.runtime_environment_defaults.cloud_selection_maps_to_sprite_default
    - setup.runtime_environment_defaults.local_selection_requires_valid_workspace_root

- kind: source_file
  target: lib/jido_code/setup/system_config.ex
  covers:
    - setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config

- kind: source_file
  target: lib/jido_code/setup/system_config_record.ex
  covers:
    - setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config

- kind: source_file
  target: lib/jido_code/setup/system_config_persistence.ex
  covers:
    - setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config

- kind: source_file
  target: config/config.exs
  covers:
    - setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config

- kind: source_file
  target: lib/jido_code/setup/project_import.ex
  covers:
    - setup.runtime_environment_defaults.import_uses_persisted_runtime_defaults

- kind: source_file
  target: .spec/decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md
  covers:
    - setup.runtime_environment_defaults.repo_scoped_workspace_binding_is_canonical

- kind: source_file
  target: test/jido_code/phase_sixty_two_integration_test.exs
  covers:
    - setup.runtime_environment_defaults.import_uses_persisted_runtime_defaults
    - setup.runtime_environment_defaults.repo_scoped_workspace_binding_is_canonical
```
