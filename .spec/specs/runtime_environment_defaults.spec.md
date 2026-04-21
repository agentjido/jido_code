<!-- covers: package.jido_code.spec_led_workspace -->

# Runtime Environment Defaults

This subject defines how `Jido.Code` captures default runtime execution intent
during setup and persists that choice as durable product metadata.

```spec-meta
id: setup.runtime_environment_defaults
kind: feature
status: active
summary: Jido.Code treats runtime environment choice as setup-owned metadata distinct from install flavor, persists default execution environment and optional local workspace root through the database-backed system-config singleton, maps cloud defaults to Sprite-backed execution and local defaults to local workspace execution, and lets later setup helpers resolve workspace context from that durable metadata until repo-level overrides take over.
decisions:
  - jido_code.runtime_environment_selection_is_persisted_setup_metadata
  - jido_code.runic_execution_model
surface:
  - .spec/decisions/jido_code.runtime_environment_selection_is_persisted_setup_metadata.md
  - .spec/decisions/jido_code.runic_execution_model.md
  - lib/jido_code/setup/environment_defaults.ex
  - lib/jido_code/setup/system_config.ex
  - lib/jido_code/setup/system_config_record.ex
  - lib/jido_code/setup/system_config_persistence.ex
  - lib/jido_code/setup/project_import.ex
  - config/config.exs
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

- id: setup.runtime_environment_defaults.import_uses_persisted_runtime_defaults
  statement: Setup repository import shall resolve workspace environment and workspace root from persisted setup runtime-default metadata until more specific per-repository settings are available.
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
    - First repository import or workspace provisioning resolves its initial workspace context.
  then:
    - The import path derives workspace environment and workspace root from the persisted setup metadata instead of inferring those defaults from install flavor alone.
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
```
