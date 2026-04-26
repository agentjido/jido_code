# Setup Onboarding

<!-- current_truth.reconciled_with_branch: `/setup` remains the LiveView-owned signed-in start surface with bounded hybrid follow-up work, runtime-default copy now frames `workspace_root` as seed metadata for new local imports rather than a permanent shared-root rule, ready-state local auth now defaults to dashboard, signed-in `/welcome` behaves as a compact handoff surface instead of a setup surrogate, a settings-owned `/settings/auth` destination now carries durable provider-login and Git integration management without changing setup ownership, setup import can now accept explicit repo-scoped local workspace paths instead of assuming one shared parent root, GitHub-backed repository listing now widens the initial API page to 100 results and continues pagination beyond that so PAT-backed or installation-backed setup follow-up does not truncate linked repository selection at GitHub's default 30-result page, linked repositories now group by account origin and keep the account name visible on each repository card in both the richer widget and the LiveView fallback, and post-import runtime surfaces now keep blocked repo-scoped workspace remediation on the managed-repository route instead of redirecting operators back through setup defaults. -->

This subject defines the first signed-in product entry contract after bootstrap administrator creation. The goal is to keep first-run onboarding simple: create the first admin, enter the app, and defer optional repo and integration setup into signed-in follow-up flows.

<!-- covers: package.jido_code.bootstrap_and_start_surfaces_in_repo -->

```spec-meta
id: setup.onboarding
kind: feature
status: active
summary: jido_code treats bootstrap-admin creation as the only hard first-run gate, auto-detects a global install-flavor hint for start-surface copy, keeps explicit runtime-environment choice separate from that hint and persisted through database-backed setup metadata, presents install-wide workspace-root copy as seed context for new imports rather than as a permanent shared-root rule, uses that setup-owned runtime metadata only as fallback seed context for repository import when repo-scoped binding metadata is absent, persists repo-scoped workspace settings onto each imported managed repository for later execution, allows setup import to accept explicit repo-scoped local workspace paths that do not share one parent directory, keeps `/setup` LiveView-owned while allowing bounded `live_vue` regions for choice-heavy follow-up work, keeps forced hybrid fallback on the real built browser assets so `/setup` stays interactive while Vue regions degrade, requests GitHub-backed repository follow-up with up to 100 repositories per API page and continues pagination beyond the first page so linked repository selection reflects the full accessible set for PAT-backed or installation-backed validation, groups linked repositories by account origin while keeping the account name visible on each repository card in both the richer widget and the fallback, allows optional GitHub repository multi-selection and import progress to resume from persisted onboarding metadata without turning `/setup` back into a blocking wizard, but clears active GitHub selection after completed imports so prior import history does not masquerade as a fresh repo choice, may capture deployment-local GitHub PAT fallback as encrypted onboarding-managed secret storage during that signed-in follow-up while surfacing encryption-key preflight before PAT save, exposes an explicit Mix reset path that can either return onboarding to first-run bootstrap or rewind it to the signed-in `/setup` surface while preserving the bootstrap owner, and defers broader repo/provider/integration setup into signed-in follow-up work where repository import writes canonical control-plane records and later repo detail plus adjacent runtime surfaces can repair one managed repository's workspace binding directly, while post-bootstrap managed-repository and dashboard surfaces may now expose bounded semantic repository inspection, repository memory inspection, recovery, and action-needed memory summaries once those control-plane records exist.
decisions:
  - jido_code.compatibility_era_removal_and_canonical_cutover
  - jido_code.auth_user_system
  - jido_code.internal_domain_and_execution_canonicalization
  - jido_code.internal_cleanup_and_ui_convergence_foundation
  - jido_code.managed_repo_workspace_binding_is_repo_scoped
  - jido_code.operator_surface_managed_repo_and_governed_run_adoption
  - jido_code.runtime_environment_selection_is_persisted_setup_metadata
  - jido_code.setup_onboarding_live_vue_surface_split
surface:
  - .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  - .spec/decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md
  - .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  - .spec/decisions/jido_code.runtime_environment_selection_is_persisted_setup_metadata.md
  - .spec/decisions/jido_code.setup_onboarding_live_vue_surface_split.md
  - .spec/specs/baseline_surface.spec.md
  - .spec/specs/user_administration.spec.md
  - .spec/specs/github_identity_and_integration.spec.md
  - lib/jido_code/setup/deployment_mode.ex
  - lib/jido_code/setup/environment_defaults.ex
  - lib/jido_code/setup/github_repository_listing.ex
  - lib/jido_code/setup/onboarding_reset.ex
  - lib/jido_code/setup/project_import.ex
  - lib/jido_code/mix/onboarding_reset.ex
  - lib/mix/tasks/onboarding.reset.ex
  - lib/jido_code/setup/system_config.ex
  - lib/jido_code/setup/system_config_record.ex
  - lib/jido_code/setup/system_config_persistence.ex
  - lib/jido_code/workbench/project_detail.ex
  - lib/jido_code/workbench/project_workspace_binding.ex
  - lib/jido_code/workbench/project_workspace_binding_notice.ex
  - lib/jido_code/security/encryption.ex
  - lib/jido_code_web/frontend_assets.ex
  - lib/jido_code_web/live/home_live.ex
  - lib/jido_code_web/components/live_vue_components.ex
  - lib/jido_code_web/live/SetupGitHubRepositorySelectorWidget.vue
  - lib/jido_code_web/live/SetupRuntimeDefaultsWidget.vue
  - lib/jido_code_web/live/SetupStartPathSelectorWidget.vue
  - lib/jido_code_web/live/setup_live.ex
  - lib/jido_code_web/live/dashboard_live.ex
  - lib/jido_code_web/components/operator_state_components.ex
  - mix.exs
  - package.json
  - lib/jido_code/control/source_repo.ex
  - lib/jido_code/control/managed_repo.ex
  - test/e2e/
  - test/support/browser_setup.ex
  - test/support/test_browser_scenario_controller.ex
  - test/support/test_browser_session_controller.ex
  - test/support/conn_case.ex
  - test/jido_code/setup/onboarding_reset_test.exs
  - test/jido_code/mix/onboarding_reset_test.exs
  - test/jido_code_web/live/phase_fifty_eight_integration_test.exs
  - test/jido_code_web/live/phase_sixty_integration_test.exs
  - test/jido_code_web/live/phase_sixty_three_integration_test.exs
  - test/jido_code_web/live/phase_sixty_four_integration_test.exs
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

- id: setup.onboarding.explicit_completion_path_to_dashboard
  statement: The signed-in start surface shall expose an explicit completion action that marks onboarding complete and enters the dashboard without requiring deferred integrations such as GitHub connection or repository import.
  priority: must
  stability: evolving

- id: setup.onboarding.runtime_health_transparent_unless_blocking
  statement: Runtime and system health checks shall stay mostly transparent and appear only when they block bootstrap or make the install unsafe to continue.
  priority: must
  stability: evolving

- id: setup.onboarding.deployment_mode_auto_detected
  statement: Deployment mode shall be a global, auto-detected install-flavor hint used for copy and default start-path emphasis rather than an operator-defined runtime-execution choice.
  priority: must
  stability: evolving

- id: setup.onboarding.runtime_environment_selection_distinct_from_install_flavor
  statement: When setup captures local-versus-cloud execution intent, that choice shall describe default runtime environment metadata distinct from the auto-detected install flavor shown for copy and emphasis.
  priority: must
  stability: evolving

- id: setup.onboarding.runtime_environment_selection_persisted_metadata
  statement: When onboarding captures runtime environment choice and optional local workspace root, that choice shall persist through database-backed setup metadata rather than existing only in route-local assigns.
  priority: must
  stability: evolving

- id: setup.onboarding.runtime_defaults_seed_repo_scoped_workspace_binding
  statement: Setup-owned runtime defaults shall seed initial workspace provisioning only when import metadata does not already provide a repo-scoped binding, and each imported managed repository shall persist its own workspace binding so later execution does not require all local repositories to share one parent location.
  priority: must
  stability: evolving

- id: setup.onboarding.deferred_integrations
  statement: Provider credentials, GitHub integration, webhook readiness, and first repository import shall be deferred into signed-in follow-up flows or feature-level prompts instead of blocking initial product entry, and signed-in repository import may normalize durable intake records without turning setup back into a blocking multi-step wizard.
  priority: must
  stability: evolving

- id: setup.onboarding.github_repository_selection_persisted_metadata
  statement: When `/setup` surfaces linked GitHub repositories for optional import, the selected repository list plus the latest repository-listing and import reports shall persist through database-backed onboarding metadata so the operator can resume that follow-up work after reload or restart, while fully successful imports clear the active selection and leave the import report as the durable history.
  priority: must
  stability: evolving

- id: setup.onboarding.github_pat_capture_persisted_secret_ref
  statement: When signed-in GitHub follow-up work needs deployment-local PAT fallback before repository listing can proceed, `/setup` may capture that PAT as encrypted integration secret storage with onboarding provenance and re-run repository readiness without writing plaintext credentials into onboarding state.
  priority: should
  stability: evolving

- id: setup.onboarding.github_pat_capture_requires_encryption_ready_secret_storage
  statement: When `/setup` asks for a deployment-local GitHub PAT, the signed-in follow-up surface shall preflight encrypted secret-storage readiness, warn when `JIDO_CODE_SECRET_REF_ENCRYPTION_KEY` is missing or invalid for the running process, and block PAT save attempts until that prerequisite is satisfied.
  priority: should
  stability: evolving

- id: setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
  statement: `/setup` may prioritize bounded `live_vue` regions for choice-heavy signed-in follow-up work, but route hydration, GitHub PAT capture and encryption preflight, persistence mutations, and explicit completion into the dashboard shall remain LiveView-owned controls.
  priority: should
  stability: evolving

- id: setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback
  statement: When `/setup` surfaces linked GitHub repositories for optional follow-up import, the richer selector should mount as a bounded `live_vue` widget with LiveView-authored props and events plus a server-rendered fallback instead of becoming a client-owned setup sub-application, and both paths shall keep repositories grouped by account origin with the account name visible on each repository card.
  priority: should
  stability: evolving

- id: setup.onboarding.start_path_preference_persisted
  statement: The signed-in start surface shall let the administrator save a preferred first path such as local repo, GitHub, or later without reintroducing blocking step-gated verification.
  priority: must
  stability: evolving

- id: setup.onboarding.reset_mix_task
  statement: The repository shall expose an explicit `mix onboarding.reset` command that can either return onboarding to first-run bootstrap or rewind it to the signed-in `/setup` surface while preserving the bootstrap owner, and that reset shall clear onboarding-managed GitHub PAT fallback state without removing unrelated deployment credentials.
  priority: should
  stability: evolving

- id: setup.onboarding.repo_source_per_project
  statement: Repository source selection shall remain a per-managed-repository concern, with each imported repository writing canonical `SourceRepo` and `ManagedRepo` records that carry their own source identity so local desktop repositories and hosted source-control repositories can coexist without being inferred from the global deployment mode.
  priority: must
  stability: evolving

- id: setup.onboarding.greenfield_import_writes_canonical_repo_records
  statement: Greenfield repository import and setup helpers shall write canonical `SourceRepo` and `ManagedRepo` records directly and shall not require `Project`-era persistence as an internal prerequisite for normal product setup.
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
    - setup.onboarding.explicit_completion_path_to_dashboard
    - setup.onboarding.deployment_mode_auto_detected
    - setup.onboarding.runtime_environment_selection_distinct_from_install_flavor
    - setup.onboarding.repo_source_per_project
  given:
    - A desktop deployment has completed bootstrap-admin creation.
  when:
    - The administrator reaches the signed-in start surface.
  then:
    - The app enters a lightweight start flow that can emphasize attaching a local repository and persist that preference without requiring the admin to finish every optional integration first.
    - Any later local-versus-cloud runtime choice remains distinct from the desktop packaging hint shown for onboarding copy.

- id: setup.onboarding.scenario.local_project_record
  covers:
    - setup.onboarding.repo_source_per_project
    - setup.onboarding.greenfield_import_writes_canonical_repo_records
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
    - setup.onboarding.explicit_completion_path_to_dashboard
    - setup.onboarding.deployment_mode_auto_detected
    - setup.onboarding.runtime_environment_selection_distinct_from_install_flavor
    - setup.onboarding.deferred_integrations
  given:
    - A cloud deployment has completed bootstrap-admin creation.
  when:
    - The administrator reaches the signed-in start surface.
  then:
    - The app may emphasize hosted source-control follow-up work such as GitHub connection, persist that preference, and still defer those integrations out of the blocking onboarding path.
    - Signed-in follow-up repo import may capture durable intake records while remaining a non-blocking onboarding continuation.

- id: setup.onboarding.scenario_github_repository_selection_resumes_from_persisted_metadata
  covers:
    - setup.onboarding.github_repository_selection_persisted_metadata
    - setup.onboarding.deferred_integrations
    - setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback
  given:
    - A signed-in administrator has chosen the GitHub start path and linked repository metadata is available.
  when:
    - The operator selects one or more linked repositories, toggles those selections, or imports them from the optional follow-up surface on `/setup`.
  then:
    - The selected repository list, repository-listing report, and latest import result persist in database-backed onboarding metadata.
    - When the import succeeds completely, the operator returns to an unselected repository picker while the latest import result remains visible as history.
    - The optional follow-up surface can resume that GitHub repository context after route reload without reintroducing a blocking wizard.
    - Linked repositories stay grouped by account origin, and each repository card keeps the account name visible in both richer and fallback delivery.
    - When richer client delivery is available, the repository selector may arrive through a bounded `live_vue` region without moving setup ownership out of LiveView.

- id: setup.onboarding.scenario_github_pat_capture_unblocks_follow_up_listing
  covers:
    - setup.onboarding.deferred_integrations
    - setup.onboarding.github_pat_capture_persisted_secret_ref
  given:
    - A signed-in administrator chooses the GitHub start path.
    - GitHub repository listing is blocked because deployment-local PAT fallback is not configured yet.
  when:
    - The operator saves a GitHub PAT from the signed-in `/setup` follow-up surface.
  then:
    - The PAT is persisted through encrypted integration secret storage with onboarding provenance rather than plaintext onboarding metadata.
    - `/setup` re-runs GitHub repository readiness so linked repository selection can continue without leaving the onboarding follow-up surface.

- id: setup.onboarding.scenario_github_pat_capture_preflights_encryption_key
  covers:
    - setup.onboarding.github_pat_capture_requires_encryption_ready_secret_storage
    - setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
  given:
    - A signed-in administrator chooses the GitHub start path.
    - PAT capture is required, but encrypted secret storage is unavailable in the running process because `JIDO_CODE_SECRET_REF_ENCRYPTION_KEY` is missing or invalid.
  when:
    - The operator opens the PAT capture surface or attempts to submit a PAT anyway.
  then:
    - `/setup` warns that encrypted secret storage is unavailable for the running process.
    - The PAT save path stays blocked until the encryption key is configured correctly and JidoCode is restarted.

- id: setup.onboarding.scenario_reset_mix_task_rewinds_or_restarts_setup
  covers:
    - setup.onboarding.reset_mix_task
  given:
    - A local install has bootstrap or signed-in onboarding state plus an onboarding-managed GitHub PAT fallback.
  when:
    - The operator runs `mix onboarding.reset --keep-owner` or `mix onboarding.reset --full`.
  then:
    - `--keep-owner` preserves the bootstrap owner, clears the onboarding-managed GitHub PAT fallback, and rewinds onboarding to the signed-in `/setup` surface.
    - `--full` clears local bootstrap users, clears the onboarding-managed GitHub PAT fallback, and returns the install to first-run bootstrap.
    - Deployment credentials that are not onboarding-managed PAT fallback remain untouched.

- id: setup.onboarding.scenario_choice_heavy_follow_up_uses_bounded_hybrid_regions
  covers:
    - setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
    - setup.onboarding.deferred_integrations
  given:
    - A signed-in administrator is using `/setup` for optional follow-up work after bootstrap.
  when:
    - The route adds richer UI for choice-heavy setup follow-up such as start-path selection, runtime-default summaries, or repository selection.
  then:
    - The route may introduce bounded `live_vue` regions for that richer composition.
    - PAT capture, server persistence, and completion into the dashboard remain LiveView-owned controls instead of moving into a monolithic client shell.

- id: setup.onboarding.scenario_blocking_runtime_fault
  covers:
    - setup.onboarding.runtime_health_transparent_unless_blocking
  given:
    - A first-run install encounters a runtime failure that prevents safe bootstrap.
  when:
    - The operator opens the public bootstrap entry.
  then:
    - The product surfaces the blocking diagnostic instead of burying the failure in optional setup chrome.

- id: setup.onboarding.scenario_runtime_environment_choice_persists_durably
  covers:
    - setup.onboarding.runtime_environment_selection_persisted_metadata
  given:
    - Setup captures a default runtime environment choice for later repository execution.
  when:
    - The operator saves that validated choice.
  then:
    - The choice is expected to persist through database-backed setup metadata instead of disappearing on route reload or server restart.

- id: setup.onboarding.scenario_import_persists_repo_scoped_workspace_binding
  covers:
    - setup.onboarding.runtime_defaults_seed_repo_scoped_workspace_binding
    - setup.onboarding.greenfield_import_writes_canonical_repo_records
  given:
    - Setup has already persisted runtime-default metadata for later repository execution.
    - A repository import creates canonical source and managed-repository records.
  when:
    - Workspace provisioning metadata is persisted for that imported repository, whether from explicit repo-scoped binding metadata or the setup-owned default runtime metadata.
  then:
    - The managed repository stores repo-scoped workspace settings used by later runtime surfaces.
    - Later execution reads the managed repository's workspace binding instead of re-deriving it from one install-wide workspace root.

- id: setup.onboarding.scenario_start_surface_completes_into_dashboard
  covers:
    - setup.onboarding.explicit_completion_path_to_dashboard
  given:
    - A signed-in administrator has reached `/setup`.
  when:
    - The operator chooses to continue into the app from the lightweight start surface.
  then:
    - Onboarding is marked complete without requiring deferred integrations first.
    - The operator is routed into the dashboard so signed-in product work can continue.

- id: setup.onboarding.scenario_signed_in_surfaces_shift_without_restart
  covers:
    - setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  given:
    - Bootstrap is complete and a signed-in operator has imported a repository into the control plane.
  when:
    - The operator opens dashboard, workbench, or repo detail through the post-bootstrap routes.
  then:
    - Those post-bootstrap surfaces present managed-repository and governed-run concepts as the operator language.
    - They may also adopt bounded hybrid summary widgets, repo-scoped semantic inspection, and repo-scoped memory inspection incrementally as long as those routed surfaces keep onboarding-era auth, loading, and control-plane language in the LiveView host shell.
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
  target: .spec/decisions/jido_code.runtime_environment_selection_is_persisted_setup_metadata.md
  covers:
    - setup.onboarding.runtime_environment_selection_distinct_from_install_flavor
    - setup.onboarding.runtime_environment_selection_persisted_metadata

- kind: source_file
  target: lib/jido_code/setup/environment_defaults.ex
  covers:
    - setup.onboarding.runtime_environment_selection_persisted_metadata

- kind: source_file
  target: lib/jido_code/setup/github_repository_listing.ex
  covers:
    - setup.onboarding.deferred_integrations
    - setup.onboarding.github_repository_selection_persisted_metadata

- kind: source_file
  target: lib/jido_code/security/encryption.ex
  covers:
    - setup.onboarding.github_pat_capture_requires_encryption_ready_secret_storage

- kind: source_file
  target: lib/jido_code/setup/onboarding_reset.ex
  covers:
    - setup.onboarding.reset_mix_task

- kind: source_file
  target: .spec/decisions/jido_code.setup_onboarding_live_vue_surface_split.md
  covers:
    - setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
    - setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback

- kind: source_file
  target: lib/jido_code_web/live/setup_live.ex
  covers:
    - setup.onboarding.post_bootstrap_start_surface
    - setup.onboarding.explicit_completion_path_to_dashboard
    - setup.onboarding.deployment_mode_auto_detected
    - setup.onboarding.deferred_integrations
    - setup.onboarding.github_repository_selection_persisted_metadata
    - setup.onboarding.github_pat_capture_persisted_secret_ref
    - setup.onboarding.github_pat_capture_requires_encryption_ready_secret_storage
    - setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
    - setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback
    - setup.onboarding.start_path_preference_persisted

- kind: source_file
  target: lib/jido_code_web/live/SetupGitHubRepositorySelectorWidget.vue
  covers:
    - setup.onboarding.github_repository_selection_persisted_metadata
    - setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback
    - setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned

- kind: source_file
  target: lib/jido_code_web/live/SetupRuntimeDefaultsWidget.vue
  covers:
    - setup.onboarding.runtime_environment_selection_persisted_metadata
    - setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned

- kind: source_file
  target: lib/jido_code_web/live/SetupStartPathSelectorWidget.vue
  covers:
    - setup.onboarding.start_path_preference_persisted
    - setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned

- kind: source_file
  target: lib/jido_code/setup/system_config.ex
  covers:
    - setup.onboarding.runtime_environment_selection_persisted_metadata
    - setup.onboarding.github_repository_selection_persisted_metadata

- kind: source_file
  target: .spec/decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md
  covers:
    - setup.onboarding.runtime_defaults_seed_repo_scoped_workspace_binding

- kind: source_file
  target: lib/jido_code/setup/system_config_record.ex
  covers:
    - setup.onboarding.runtime_environment_selection_persisted_metadata

- kind: source_file
  target: lib/jido_code/setup/system_config_persistence.ex
  covers:
    - setup.onboarding.runtime_environment_selection_persisted_metadata

- kind: source_file
  target: .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  covers:
    - setup.onboarding.repo_source_per_project

- kind: source_file
  target: .spec/decisions/jido_code.internal_domain_and_execution_canonicalization.md
  covers:
    - setup.onboarding.greenfield_import_writes_canonical_repo_records

- kind: source_file
  target: lib/jido_code/setup/project_import.ex
  covers:
    - setup.onboarding.deferred_integrations
    - setup.onboarding.github_repository_selection_persisted_metadata
    - setup.onboarding.repo_source_per_project

- kind: source_file
  target: test/jido_code/setup/project_import_test.exs
  covers:
    - setup.onboarding.repo_source_per_project

- kind: source_file
  target: test/jido_code/phase_sixty_two_integration_test.exs
  covers:
    - setup.onboarding.runtime_defaults_seed_repo_scoped_workspace_binding

- kind: source_file
  target: test/jido_code/setup/deployment_mode_test.exs
  covers:
    - setup.onboarding.deployment_mode_auto_detected

- kind: source_file
  target: test/jido_code_web/live/phase_fifty_eight_integration_test.exs
  covers:
    - setup.onboarding.post_bootstrap_start_surface

- kind: source_file
  target: test/jido_code_web/live/phase_sixty_integration_test.exs
  covers:
    - setup.onboarding.admin_bootstrap_completion_gate
    - setup.onboarding.post_bootstrap_start_surface
    - setup.onboarding.explicit_completion_path_to_dashboard

- kind: source_file
  target: test/jido_code_web/live/setup_live_test.exs
  covers:
    - setup.onboarding.post_bootstrap_start_surface
    - setup.onboarding.explicit_completion_path_to_dashboard
    - setup.onboarding.deployment_mode_auto_detected
    - setup.onboarding.deferred_integrations
    - setup.onboarding.github_repository_selection_persisted_metadata
    - setup.onboarding.github_pat_capture_persisted_secret_ref
    - setup.onboarding.github_pat_capture_requires_encryption_ready_secret_storage
    - setup.onboarding.start_path_preference_persisted

- kind: source_file
  target: test/e2e/setup-onboarding.spec.ts
  covers:
    - setup.onboarding.post_bootstrap_start_surface
    - setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
    - setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback

- kind: command
  target: mix test test/jido_code_web/live/setup_live_test.exs
  covers:
    - setup.onboarding.github_pat_capture_persisted_secret_ref
    - setup.onboarding.github_pat_capture_requires_encryption_ready_secret_storage

- kind: command
  target: mix test test/jido_code/setup/onboarding_reset_test.exs test/jido_code/mix/onboarding_reset_test.exs
  covers:
    - setup.onboarding.reset_mix_task

- kind: command
  target: mix browser.verify
  covers:
    - setup.onboarding.post_bootstrap_start_surface
    - setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
    - setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback

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

- kind: source_file
  target: test/jido_code_web/live/phase_twenty_five_integration_test.exs
  covers:
    - setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
```
