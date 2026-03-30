# Setup Onboarding

This subject defines the first signed-in product entry contract after bootstrap administrator creation. The goal is to keep first-run onboarding simple: create the first admin, enter the app, and defer optional repo and integration setup into signed-in follow-up flows.

<!-- covers: package.jido_code.bootstrap_and_start_surfaces_in_repo -->

```spec-meta
id: setup.onboarding
kind: feature
status: active
summary: jido_code treats bootstrap-admin creation as the only hard first-run gate, presents that path through a refined welcome surface, auto-detects a global deployment mode for start-surface defaults, and defers repo/provider/integration setup into signed-in follow-up work.
decisions:
  - jido_code.auth_user_system
surface:
  - .spec/specs/baseline_surface.spec.md
  - .spec/specs/user_administration.spec.md
  - .spec/specs/github_identity_and_integration.spec.md
  - lib/jido_code/setup/deployment_mode.ex
  - lib/jido_code/setup/project_import.ex
  - lib/jido_code_web/live/home_live.ex
  - lib/jido_code_web/live/setup_live.ex
  - lib/jido_code_web/live/dashboard_live.ex
  - lib/jido_code/projects/project.ex
  - priv/repo/migrations/20260326122740_add_project_source_identity.exs
  - priv/resource_snapshots/repo/projects/20260326122740.json
  - test/jido_code_web/live/setup_live_test.exs
  - test/jido_code/setup/project_import_test.exs
  - test/jido_code/projects/project_test.exs
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
  statement: Provider credentials, GitHub integration, webhook readiness, and first-project import shall be deferred into signed-in follow-up flows or feature-level prompts instead of blocking initial product entry.
  priority: must
  stability: evolving

- id: setup.onboarding.start_path_preference_persisted
  statement: The signed-in start surface shall let the administrator save a preferred first path such as local repo, GitHub, or later without reintroducing blocking step-gated verification.
  priority: must
  stability: evolving

- id: setup.onboarding.repo_source_per_project
  statement: Repository source selection shall remain a per-project concern, with each project carrying its own source kind and source identity so local desktop repositories and hosted source-control repositories can coexist without being inferred from the global deployment mode.
  priority: must
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
    - A desktop deployment needs to register a local repository as a project.
  when:
    - The project record is created for that local repository.
  then:
    - The record stores its local source kind and source identity on the project itself instead of inferring repository behavior from a global mode.

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

- id: setup.onboarding.scenario_blocking_runtime_fault
  covers:
    - setup.onboarding.runtime_health_transparent_unless_blocking
  given:
    - A first-run install encounters a runtime failure that prevents safe bootstrap.
  when:
    - The operator opens the public bootstrap entry.
  then:
    - The product surfaces the blocking diagnostic instead of burying the failure in optional setup chrome.
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
  target: .spec/specs/setup_onboarding.spec.md
  covers:
    - setup.onboarding.repo_source_per_project

- kind: source_file
  target: lib/jido_code/projects/project.ex
  covers:
    - setup.onboarding.repo_source_per_project

- kind: source_file
  target: lib/jido_code/setup/project_import.ex
  covers:
    - setup.onboarding.repo_source_per_project

- kind: source_file
  target: test/jido_code/projects/project_test.exs
  covers:
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
```
