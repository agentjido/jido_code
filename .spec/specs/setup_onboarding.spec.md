# Setup Onboarding

This subject defines the first signed-in product entry contract after bootstrap administrator creation. The goal is to keep first-run onboarding simple: create the first admin, enter the app, and defer optional repo and integration setup into signed-in follow-up flows.

<!-- covers: package.jido_code.bootstrap_and_start_surfaces_in_repo -->

```spec-meta
id: setup.onboarding
kind: feature
status: active
summary: jido_code treats bootstrap-admin creation as the only hard first-run gate, auto-detects a global deployment mode for start-surface defaults, keeps the preferred local start path aligned to the current browser architecture, and defers repo/provider/integration setup into signed-in follow-up work where repository import writes canonical control-plane records without reintroducing a blocking wizard.
decisions:
  - jido_code.compatibility_era_removal_and_canonical_cutover
  - jido_code.auth_user_system
  - jido_code.internal_cleanup_and_ui_convergence_foundation
  - jido_code.operator_surface_managed_repo_and_governed_run_adoption
surface:
  - .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  - .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  - .spec/specs/baseline_surface.spec.md
  - .spec/specs/user_administration.spec.md
  - .spec/specs/github_identity_and_integration.spec.md
  - lib/jido_code/setup/deployment_mode.ex
  - lib/jido_code/setup/project_import.ex
  - lib/jido_code_web/live/home_live.ex
  - lib/jido_code_web/live/setup_live.ex
  - lib/jido_code_web/live/dashboard_live.ex
  - lib/jido_code_web/components/operator_state_components.ex
  - lib/jido_code/control/source_repo.ex
  - lib/jido_code/control/managed_repo.ex
  - test/support/conn_case.ex
  - test/jido_code_web/live/setup_live_test.exs
  - test/jido_code_web/live/dashboard_live_test.exs
  - test/jido_code/setup/project_import_test.exs
  - test/jido_code/setup/deployment_mode_test.exs
```

## Requirements

```spec-requirements
- id: setup.onboarding.admin_bootstrap_completion_gate
  statement: First-run onboarding shall require only successful bootstrap administrator creation and authenticated product entry; additional product setup shall be optional follow-up work.
  priority: must
  stability: evolving

- id: setup.onboarding.post_bootstrap_start_surface
  statement: After bootstrap, `/setup` shall serve as a lightweight signed-in start surface rather than a blocking multi-step verification wizard.
  priority: must
  stability: evolving

- id: setup.onboarding.runtime_health_transparent_unless_blocking
  statement: Runtime and system health checks shall stay mostly transparent and appear only when they block bootstrap or make the install unsafe to continue.
  priority: must
  stability: evolving

- id: setup.onboarding.deployment_mode_auto_detected
  statement: Deployment mode shall be a global, auto-detected product hint used for copy and default start-path emphasis rather than an operator-defined setup choice.
  priority: must
  stability: evolving

- id: setup.onboarding.deferred_integrations
  statement: Provider credentials, GitHub integration, webhook readiness, and first repository import shall be deferred into signed-in follow-up flows or feature-level prompts instead of blocking initial product entry, and signed-in repository import may normalize durable intake records without turning setup back into a blocking multi-step wizard.
  priority: must
  stability: evolving

- id: setup.onboarding.start_path_preference_persisted
  statement: The signed-in start surface shall let the administrator save a preferred first path such as local repo, GitHub, or later without reintroducing blocking step-gated verification.
  priority: must
  stability: evolving

- id: setup.onboarding.repo_source_per_project
  statement: Repository source selection shall remain a per-managed-repository concern, with each imported repository writing canonical `SourceRepo` and `ManagedRepo` records that carry their own source identity so local desktop repositories and hosted source-control repositories can coexist without being inferred from the global deployment mode.
  priority: must
  stability: evolving

- id: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  statement: Signed-in post-bootstrap operator surfaces shall use canonical managed-repository and governed-run language once onboarding has created those records.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: setup.onboarding.scenario.desktop_start
  covers:
    - setup.onboarding.admin_bootstrap_completion_gate
    - setup.onboarding.post_bootstrap_start_surface
    - setup.onboarding.deployment_mode_auto_detected
    - setup.onboarding.repo_source_per_project
  given:
    - A desktop deployment has completed bootstrap-admin creation.
  when:
    - The administrator reaches the signed-in start surface.
  then:
    - The app enters a lightweight start flow that can emphasize attaching a local repository and persist that preference without requiring the admin to finish every optional integration first.

- id: setup.onboarding.scenario.local_project_record
  covers:
    - setup.onboarding.repo_source_per_project
  given:
    - A desktop deployment needs to register a local repository into the product control plane.
  when:
    - The repository import record is created for that local repository.
  then:
    - The canonical source and managed-repository records store the local source identity instead of inferring repository behavior from a global mode.

- id: setup.onboarding.scenario_cloud_start
  covers:
    - setup.onboarding.admin_bootstrap_completion_gate
    - setup.onboarding.post_bootstrap_start_surface
    - setup.onboarding.deployment_mode_auto_detected
    - setup.onboarding.deferred_integrations
  given:
    - A cloud deployment has completed bootstrap-admin creation.
  when:
    - The administrator reaches the signed-in start surface.
  then:
    - The app may emphasize hosted source-control follow-up work such as GitHub connection, persist that preference, and still defer those integrations out of the blocking onboarding path.
    - Signed-in follow-up repo import may capture durable intake records while remaining a non-blocking onboarding continuation.

- id: setup.onboarding.scenario_blocking_runtime_fault
  covers:
    - setup.onboarding.runtime_health_transparent_unless_blocking
  given:
    - A first-run install encounters a runtime failure that prevents safe bootstrap.
  when:
    - The operator opens the public bootstrap entry.
  then:
    - The product surfaces the blocking diagnostic instead of burying the failure in optional setup chrome.

- id: setup.onboarding.scenario_signed_in_surfaces_shift_without_restart
  covers:
    - setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  given:
    - Bootstrap is complete and a signed-in operator has imported a repository into the control plane.
  when:
    - The operator opens dashboard, workbench, or repo detail through the post-bootstrap routes.
  then:
    - Those post-bootstrap surfaces present managed-repository and governed-run concepts as the operator language.
    - They may also adopt bounded hybrid summary widgets incrementally as long as those routed surfaces keep onboarding-era auth, loading, and control-plane language in the LiveView host shell.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/specs/user_administration.spec.md
  covers:
    - setup.onboarding.admin_bootstrap_completion_gate

- kind: source_file
  target: .spec/specs/baseline_surface.spec.md
  covers:
    - setup.onboarding.post_bootstrap_start_surface
    - setup.onboarding.runtime_health_transparent_unless_blocking

- kind: source_file
  target: .spec/specs/github_identity_and_integration.spec.md
  covers:
    - setup.onboarding.deferred_integrations

- kind: source_file
  target: lib/jido_code/setup/deployment_mode.ex
  covers:
    - setup.onboarding.deployment_mode_auto_detected

- kind: source_file
  target: lib/jido_code_web/live/setup_live.ex
  covers:
    - setup.onboarding.post_bootstrap_start_surface
    - setup.onboarding.deployment_mode_auto_detected
    - setup.onboarding.deferred_integrations
    - setup.onboarding.start_path_preference_persisted

- kind: source_file
  target: .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  covers:
    - setup.onboarding.repo_source_per_project

- kind: source_file
  target: lib/jido_code/setup/project_import.ex
  covers:
    - setup.onboarding.deferred_integrations
    - setup.onboarding.repo_source_per_project

- kind: source_file
  target: test/jido_code/setup/project_import_test.exs
  covers:
    - setup.onboarding.repo_source_per_project

- kind: source_file
  target: test/jido_code/setup/deployment_mode_test.exs
  covers:
    - setup.onboarding.deployment_mode_auto_detected

- kind: source_file
  target: test/jido_code_web/live/setup_live_test.exs
  covers:
    - setup.onboarding.post_bootstrap_start_surface
    - setup.onboarding.deployment_mode_auto_detected
    - setup.onboarding.deferred_integrations
    - setup.onboarding.start_path_preference_persisted

- kind: source_file
  target: .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  covers:
    - setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language

- kind: source_file
  target: lib/jido_code_web/live/dashboard_live.ex
  covers:
    - setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language

- kind: source_file
  target: test/jido_code_web/live/dashboard_live_test.exs
  covers:
    - setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language

- kind: source_file
  target: lib/jido_code_web/live/workbench_live.ex
  covers:
    - setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language

- kind: source_file
  target: lib/jido_code_web/live/project_detail_live.ex
  covers:
    - setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
```
