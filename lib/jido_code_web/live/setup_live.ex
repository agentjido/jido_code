defmodule JidoCodeWeb.SetupLive do
  use JidoCodeWeb, :live_view

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Setup.EnvironmentDefaults
  alias JidoCode.Setup.GitHubCredentialChecks
  alias JidoCode.Setup.GitHubRepositoryListing
  alias JidoCode.Setup.OwnerBootstrap
  alias JidoCode.Setup.OwnerRecovery
  alias JidoCode.Setup.ProjectImport
  alias JidoCode.Setup.ProviderCredentialChecks
  alias JidoCode.Setup.PrerequisiteChecks
  alias JidoCode.Setup.RuntimeMode
  alias JidoCode.Setup.SystemConfig
  alias JidoCode.Setup.WebhookSimulationChecks

  @wizard_steps %{
    1 => "Welcome and system check",
    2 => "Owner account bootstrap",
    3 => "Provider and secret setup",
    4 => "GitHub app and webhook validation",
    5 => "Environment defaults",
    6 => "Issue bot MVP checks",
    7 => "Import first project",
    8 => "Complete onboarding"
  }

  @default_diagnostic "Setup is required before protected routes are available."
  @validation_error "Add validation notes before continuing."
  @owner_step_validation_error "Complete owner account bootstrap before continuing."
  @owner_recovery_validation_error "Complete owner recovery verification before attempting credential reset."

  @impl true
  def mount(params, _session, socket) do
    # params["step"] may be a form data map (POST) or a string (GET query param)
    # For form data, we'll use the step from SystemConfig, not params
    parsed_step = if is_map(params["step"]), do: nil, else: parse_step(params["step"])

    {onboarding_step, onboarding_state, default_environment, workspace_root, diagnostic} =
      case SystemConfig.load() do
        {:ok, %SystemConfig{} = config} ->
          {config.onboarding_step, config.onboarding_state, config.default_environment, config.workspace_root,
           params["diagnostic"] || @default_diagnostic}

        {:error, %{diagnostic: load_diagnostic}} ->
          {parsed_step || 1, %{}, :sprite, nil, params["diagnostic"] || load_diagnostic}
      end

    prerequisite_report = resolve_prerequisite_report(onboarding_step, onboarding_state)

    provider_credential_report =
      resolve_provider_credential_report(onboarding_step, onboarding_state)

    github_credential_report =
      resolve_github_credential_report(onboarding_step, onboarding_state)

    webhook_simulation_report =
      resolve_webhook_simulation_report(onboarding_step, onboarding_state)

    environment_defaults_report =
      resolve_environment_defaults_report(
        onboarding_step,
        onboarding_state,
        default_environment,
        workspace_root
      )

    project_import_report = resolve_project_import_report(onboarding_step, onboarding_state)

    repository_listing_report =
      resolve_repository_listing_report(onboarding_step, onboarding_state)

    available_repositories =
      resolve_available_repositories(repository_listing_report, onboarding_state)

    owner_bootstrap = resolve_owner_bootstrap(onboarding_step)

    {:ok,
     socket
     |> assign(:onboarding_step, onboarding_step)
     |> assign(:onboarding_state, onboarding_state)
     |> assign(:default_environment, default_environment)
     |> assign(:workspace_root, workspace_root)
     |> assign(:prerequisite_report, prerequisite_report)
     |> assign(:provider_credential_report, provider_credential_report)
     |> assign(:github_credential_report, github_credential_report)
     |> assign(:webhook_simulation_report, webhook_simulation_report)
     |> assign(:environment_defaults_report, environment_defaults_report)
     |> assign(:project_import_report, project_import_report)
     |> assign(:repository_listing_report, repository_listing_report)
     |> assign(:available_repositories, available_repositories)
     |> assign(:owner_bootstrap, owner_bootstrap)
     |> assign(:save_error, owner_bootstrap_error(owner_bootstrap))
     |> assign(:redirect_reason, params["reason"] || "onboarding_incomplete")
     |> assign(:diagnostic, diagnostic)
     |> assign_step_form(onboarding_step, onboarding_state, default_environment, workspace_root)
     |> assign_owner_form(onboarding_step, onboarding_state, owner_bootstrap)
     |> assign_recovery_form(onboarding_step, onboarding_state, owner_bootstrap)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section id="setup-gate" class="mx-auto w-full max-w-3xl space-y-4">
        <h1 class="text-2xl font-semibold">Setup required</h1>
        <p class="text-base-content/80">
          Complete onboarding before accessing protected routes.
        </p>

        <dl class="space-y-3 rounded-lg border border-base-300 bg-base-100 p-4">
          <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <dt class="font-medium">Resolved onboarding step</dt>
            <dd id="resolved-onboarding-step" class="font-mono">Step {@onboarding_step}</dd>
          </div>
          <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <dt class="font-medium">Current wizard step</dt>
            <dd id="current-wizard-step" class="font-mono">{step_title(@onboarding_step)}</dd>
          </div>
          <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <dt class="font-medium">Redirect reason</dt>
            <dd id="setup-redirect-reason" class="font-mono">{@redirect_reason}</dd>
          </div>
        </dl>

        <div id="setup-diagnostic" class="alert alert-warning">
          <.icon name="hero-exclamation-triangle-mini" class="size-5" />
          <span>{@diagnostic}</span>
        </div>

        <div :if={@save_error} id="setup-save-error" class="alert alert-error">
          <.icon name="hero-x-circle-mini" class="size-5" />
          <span>{@save_error}</span>
        </div>

        <section :if={@prerequisite_report} id="setup-prerequisite-status" class="space-y-3">
          <h2 class="text-lg font-semibold">System prerequisite checks</h2>
          <p id="setup-prerequisite-checked-at" class="text-sm text-base-content/70">
            Last checked: {format_checked_at(@prerequisite_report.checked_at)}
          </p>

          <ul class="space-y-2">
            <li
              :for={check <- @prerequisite_report.checks}
              id={"setup-prerequisite-#{check.id}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="font-medium">{check.name}</p>
                <span
                  id={"setup-prerequisite-#{check.id}-status"}
                  class={["badge", prerequisite_status_class(check.status)]}
                >
                  {prerequisite_status_label(check.status)}
                </span>
              </div>
              <p class="text-sm text-base-content/80">{check.detail}</p>
              <p
                :if={check.status != :pass}
                id={"setup-prerequisite-remediation-#{check.id}"}
                class="text-sm text-warning"
              >
                {check.remediation}
              </p>
            </li>
          </ul>
        </section>

        <section
          :if={@provider_credential_report}
          id="setup-provider-credentials"
          class="space-y-3"
        >
          <h2 class="text-lg font-semibold">LLM provider credential verification</h2>
          <p id="setup-provider-checked-at" class="text-sm text-base-content/70">
            Last checked: {format_checked_at(@provider_credential_report.checked_at)}
          </p>

          <ul class="space-y-2">
            <li
              :for={credential <- @provider_credential_report.credentials}
              id={"setup-provider-#{provider_dom_id(credential.provider)}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="font-medium">{credential.name}</p>
                <span
                  id={"setup-provider-#{provider_dom_id(credential.provider)}-status"}
                  class={["badge", provider_status_class(credential.status)]}
                >
                  {provider_status_label(credential.status)}
                </span>
              </div>
              <p
                id={"setup-provider-transition-#{provider_dom_id(credential.provider)}"}
                class="text-sm text-base-content/80"
              >
                Status transition: {credential.transition}
              </p>
              <p class="text-sm text-base-content/80">{credential.detail}</p>
              <p
                :if={credential.error_type}
                id={"setup-provider-error-type-#{provider_dom_id(credential.provider)}"}
                class="font-mono text-xs text-base-content/70"
              >
                Error type: {credential.error_type}
              </p>
              <p
                :if={credential.verified_at}
                id={"setup-provider-verified-at-#{provider_dom_id(credential.provider)}"}
                class="text-xs text-base-content/70"
              >
                Verified at: {format_checked_at(credential.verified_at)}
              </p>
              <p
                :if={credential.status != :active}
                id={"setup-provider-remediation-#{provider_dom_id(credential.provider)}"}
                class="text-sm text-warning"
              >
                {credential.remediation}
              </p>
            </li>
          </ul>
        </section>

        <section :if={@github_credential_report} id="setup-github-integration" class="space-y-3">
          <h2 class="text-lg font-semibold">GitHub integration credential validation</h2>
          <p id="setup-github-checked-at" class="text-sm text-base-content/70">
            Last validated: {format_checked_at(@github_credential_report.checked_at)}
          </p>
          <p
            :if={@github_credential_report.owner_context}
            id="setup-github-owner-context"
            class="font-mono text-sm text-base-content/80"
          >
            Owner context: {@github_credential_report.owner_context}
          </p>
          <div id="setup-github-integration-health" class="flex flex-wrap items-center gap-3 text-sm">
            <p id="setup-github-readiness-status" class="text-base-content/80">
              Integration readiness:
              <span class={[
                "badge ml-1",
                github_readiness_status_class(github_integration_health(@github_credential_report).readiness_status)
              ]}>
                {github_readiness_status_label(github_integration_health(@github_credential_report).readiness_status)}
              </span>
            </p>
            <p id="setup-github-app-readiness-status" class="text-base-content/80">
              GitHub App readiness:
              <span class={[
                "badge ml-1",
                github_status_class(github_integration_health(@github_credential_report).github_app_status)
              ]}>
                {github_status_label(github_integration_health(@github_credential_report).github_app_status)}
              </span>
            </p>
            <p id="setup-github-auth-mode" class="text-base-content/80">
              Active auth mode:
              <span class={[
                "badge ml-1",
                github_auth_mode_badge_class(github_auth_mode_feedback(@github_credential_report).mode)
              ]}>
                {github_auth_mode_feedback(@github_credential_report).label}
              </span>
            </p>
          </div>
          <p
            :if={github_auth_mode_feedback(@github_credential_report).detail}
            id="setup-github-auth-mode-feedback"
            class="text-sm text-warning"
          >
            {github_auth_mode_feedback(@github_credential_report).detail}
          </p>
          <p
            :if={github_integration_health(@github_credential_report).expected_repositories != []}
            id="setup-github-expected-repositories"
            class="text-sm text-base-content/80"
          >
            Expected repositories: {github_repositories_text(
              github_integration_health(@github_credential_report).expected_repositories
            )}
          </p>
          <p
            :if={github_integration_health(@github_credential_report).missing_repositories != []}
            id="setup-github-missing-repositories"
            class="text-sm text-error"
          >
            Missing expected repositories: {github_repositories_text(
              github_integration_health(@github_credential_report).missing_repositories
            )}
          </p>

          <ul class="space-y-2">
            <li
              :for={path <- @github_credential_report.paths}
              id={"setup-github-#{github_path_dom_id(path.path)}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="font-medium">{path.name}</p>
                <span
                  id={"setup-github-#{github_path_dom_id(path.path)}-status"}
                  class={["badge", github_status_class(path.status)]}
                >
                  {github_status_label(path.status)}
                </span>
              </div>
              <p
                id={"setup-github-transition-#{github_path_dom_id(path.path)}"}
                class="text-sm text-base-content/80"
              >
                Status transition: {path.transition}
              </p>
              <p
                id={"setup-github-repository-access-#{github_path_dom_id(path.path)}"}
                class="text-sm text-base-content/80"
              >
                Repository access: {github_repository_access_label(path.repository_access)}
              </p>
              <p
                id={"setup-github-repositories-#{github_path_dom_id(path.path)}"}
                class="text-sm text-base-content/80"
              >
                Accessible repositories: {github_repositories_text(path.repositories)}
              </p>
              <p class="text-sm text-base-content/80">{path.detail}</p>
              <p
                :if={path.validated_at}
                id={"setup-github-validated-at-#{github_path_dom_id(path.path)}"}
                class="text-xs text-base-content/70"
              >
                Validated at: {format_checked_at(path.validated_at)}
              </p>
              <p
                :if={path.error_type}
                id={"setup-github-error-type-#{github_path_dom_id(path.path)}"}
                class="text-sm text-error"
              >
                Typed integration error: {path.error_type}
              </p>
              <p
                :if={path.status != :ready}
                id={"setup-github-remediation-#{github_path_dom_id(path.path)}"}
                class="text-sm text-warning"
              >
                {path.remediation}
              </p>
            </li>
          </ul>
        </section>

        <section :if={@environment_defaults_report} id="setup-environment-defaults" class="space-y-3">
          <h2 class="text-lg font-semibold">Execution environment defaults</h2>
          <p id="setup-environment-checked-at" class="text-sm text-base-content/70">
            Last validated: {format_checked_at(@environment_defaults_report.checked_at)}
          </p>

          <div class="rounded-lg border border-base-300 bg-base-100 p-3">
            <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <p class="font-medium">Selected mode</p>
              <span id="setup-environment-mode" class="badge badge-info">
                {environment_mode_label(@environment_defaults_report.mode)}
              </span>
            </div>
            <p id="setup-default-environment" class="text-sm text-base-content/80">
              Default environment: {environment_default_label(@environment_defaults_report.default_environment)}
            </p>
            <p
              :if={@environment_defaults_report.workspace_root}
              id="setup-workspace-root"
              class="text-sm text-base-content/80 font-mono"
            >
              Workspace root: {@environment_defaults_report.workspace_root}
            </p>
          </div>

          <ul class="space-y-2">
            <li
              :for={check <- @environment_defaults_report.checks}
              id={"setup-environment-#{check.id}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="font-medium">{check.name}</p>
                <span
                  id={"setup-environment-#{check.id}-status"}
                  class={["badge", environment_check_status_class(check.status)]}
                >
                  {environment_check_status_label(check.status)}
                </span>
              </div>
              <p class="text-sm text-base-content/80">{check.detail}</p>
              <p
                :if={check.status != :ready}
                id={"setup-environment-#{check.id}-remediation"}
                class="text-sm text-warning"
              >
                {check.remediation}
              </p>
            </li>
          </ul>
        </section>

        <section :if={@webhook_simulation_report} id="setup-webhook-simulation" class="space-y-3">
          <h2 class="text-lg font-semibold">Issue Bot webhook simulation readiness</h2>
          <p id="setup-webhook-simulated-at" class="text-sm text-base-content/70">
            Last simulated: {format_checked_at(@webhook_simulation_report.checked_at)}
          </p>

          <div class="rounded-lg border border-base-300 bg-base-100 p-3">
            <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <p class="font-medium">Simulation status</p>
              <span
                id="setup-webhook-simulation-status"
                class={["badge", webhook_simulation_status_class(@webhook_simulation_report.status)]}
              >
                {webhook_simulation_status_label(@webhook_simulation_report.status)}
              </span>
            </div>
            <p
              :if={@webhook_simulation_report.failure_reason}
              id="setup-webhook-failure-reason"
              class="text-sm text-error"
            >
              {@webhook_simulation_report.failure_reason}
            </p>
          </div>

          <div
            id="setup-webhook-signature"
            class="rounded-lg border border-base-300 bg-base-100 p-3"
          >
            <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <p class="font-medium">Signature verification readiness</p>
              <span
                id="setup-webhook-signature-status"
                class={[
                  "badge",
                  webhook_check_status_class(@webhook_simulation_report.signature.status)
                ]}
              >
                {webhook_check_status_label(@webhook_simulation_report.signature.status)}
              </span>
            </div>
            <p class="text-sm text-base-content/80">{@webhook_simulation_report.signature.detail}</p>
            <p
              :if={@webhook_simulation_report.signature.status != :ready}
              id="setup-webhook-signature-remediation"
              class="text-sm text-warning"
            >
              {@webhook_simulation_report.signature.remediation}
            </p>
          </div>

          <ul class="space-y-2">
            <li
              :for={event <- @webhook_simulation_report.events}
              id={"setup-webhook-event-#{webhook_event_dom_id(event.event)}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="font-medium">{event.event}</p>
                <span
                  id={"setup-webhook-event-#{webhook_event_dom_id(event.event)}-status"}
                  class={["badge", webhook_check_status_class(event.status)]}
                >
                  {webhook_check_status_label(event.status)}
                </span>
              </div>
              <p
                id={"setup-webhook-event-#{webhook_event_dom_id(event.event)}-route"}
                class="text-sm text-base-content/80"
              >
                Route readiness: {event.route}
              </p>
              <p class="text-sm text-base-content/80">{event.detail}</p>
              <p
                :if={event.status != :ready}
                id={"setup-webhook-event-#{webhook_event_dom_id(event.event)}-remediation"}
                class="text-sm text-warning"
              >
                {event.remediation}
              </p>
            </li>
          </ul>

          <div
            :if={@webhook_simulation_report.status == :ready}
            id="setup-issue-bot-defaults"
            class="rounded-lg border border-base-300 bg-base-100 p-3"
          >
            <p class="font-medium">Issue Bot defaults ready for enablement</p>
            <p id="setup-issue-bot-default-enabled" class="text-sm text-base-content/80">
              Enabled: {issue_bot_default_enabled(@webhook_simulation_report.issue_bot_defaults)}
            </p>
            <p id="setup-issue-bot-default-approval-mode" class="text-sm text-base-content/80">
              Approval mode: {issue_bot_default_approval_mode(@webhook_simulation_report.issue_bot_defaults)}
            </p>
          </div>
        </section>

        <section :if={@onboarding_step in [7, 8]} id="setup-project-import" class="space-y-3">
          <h2 class="text-lg font-semibold">First project import readiness</h2>
          <p id="setup-project-import-step-note" class="text-sm text-base-content/80">
            Select one repository and complete clone provisioning plus baseline sync before onboarding can complete.
          </p>

          <div
            :if={@onboarding_step == 7}
            id="setup-project-repository-listing"
            class="rounded-lg border border-base-300 bg-base-100 p-3"
          >
            <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
              <p class="font-medium">Accessible repositories for import</p>
              <button
                id="setup-project-repository-refresh"
                type="button"
                phx-click="refresh_repository_listing"
                class="btn btn-sm btn-outline"
              >
                Refresh repositories
              </button>
            </div>
            <p
              :if={@repository_listing_report}
              id="setup-project-repository-listing-checked-at"
              class="mt-2 text-sm text-base-content/70"
            >
              Last fetched: {format_checked_at(@repository_listing_report.checked_at)}
            </p>
            <p
              :if={@repository_listing_report}
              id="setup-project-repository-listing-status"
              class="mt-1 text-sm text-base-content/80"
            >
              Listing status:
              <span class={[
                "badge ml-1",
                repository_listing_status_class(@repository_listing_report.status)
              ]}>
                {repository_listing_status_label(@repository_listing_report.status)}
              </span>
            </p>
            <p
              :if={@repository_listing_report && @repository_listing_report.error_type}
              id="setup-project-repository-listing-error-type"
              class="mt-1 text-sm text-error"
            >
              GitHub fetch error type: {@repository_listing_report.error_type}
            </p>
            <p
              :if={@repository_listing_report}
              id="setup-project-repository-listing-detail"
              class="mt-1 text-sm text-base-content/80"
            >
              {@repository_listing_report.detail}
            </p>
            <p
              :if={@repository_listing_report && @repository_listing_report.status != :ready}
              id="setup-project-repository-listing-remediation"
              class="mt-1 text-sm text-warning"
            >
              {@repository_listing_report.remediation}
            </p>
          </div>

          <div
            :if={@onboarding_step == 7 and !Enum.empty?(@available_repositories)}
            id="setup-project-repository-options"
            class="rounded-lg border border-base-300 bg-base-100 p-3"
          >
            <p class="font-medium">Validated repository access</p>
            <ul class="mt-2 space-y-1 text-sm text-base-content/80">
              <li
                :for={repository <- repository_listing_entries(@repository_listing_report, @available_repositories)}
                id={"setup-project-repository-option-#{repository_dom_id(repository.full_name)}"}
              >
                <p>{repository.full_name}</p>
                <p
                  id={"setup-project-repository-stable-id-#{repository_dom_id(repository.full_name)}"}
                  class="font-mono text-xs text-base-content/70"
                >
                  Stable ID: {repository.id}
                </p>
              </li>
            </ul>
          </div>

          <div
            :if={@project_import_report}
            id="setup-project-import-report"
            class="rounded-lg border border-base-300 bg-base-100 p-3"
          >
            <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <p class="font-medium">Project import status</p>
              <span
                id="setup-project-import-status"
                class={["badge", project_import_status_class(@project_import_report.status)]}
              >
                {project_import_status_label(@project_import_report.status)}
              </span>
            </div>
            <p id="setup-project-import-checked-at" class="text-sm text-base-content/70">
              Last import attempt: {format_checked_at(@project_import_report.checked_at)}
            </p>
            <p
              :if={@project_import_report.selected_repository}
              id="setup-project-import-repository"
              class="font-mono text-sm text-base-content/80"
            >
              Selected repository: {@project_import_report.selected_repository}
            </p>
            <p
              :if={project_import_clone_status(@project_import_report)}
              id="setup-project-import-clone-status"
              class="text-sm text-base-content/80"
            >
              Clone status:
              <span class={[
                "badge ml-1",
                project_clone_status_class(project_import_clone_status(@project_import_report))
              ]}>
                {project_clone_status_label(project_import_clone_status(@project_import_report))}
              </span>
            </p>
            <p
              :if={project_import_clone_transition(@project_import_report)}
              id="setup-project-import-clone-transition"
              class="text-sm text-base-content/80"
            >
              Clone transitions: {project_import_clone_transition(@project_import_report)}
            </p>
            <p
              :if={project_import_baseline_branch(@project_import_report)}
              id="setup-project-import-baseline-branch"
              class="font-mono text-sm text-base-content/80"
            >
              Baseline branch: {project_import_baseline_branch(@project_import_report)}
            </p>
            <p
              :if={project_import_last_synced_at(@project_import_report)}
              id="setup-project-import-last-sync-at"
              class="text-sm text-base-content/80"
            >
              Last baseline sync: {format_checked_at(project_import_last_synced_at(@project_import_report))}
            </p>
            <p id="setup-project-import-detail" class="text-sm text-base-content/80">
              {@project_import_report.detail}
            </p>
            <p
              :if={@project_import_report.error_type}
              id="setup-project-import-error-type"
              class="text-sm text-error"
            >
              Import error type: {@project_import_report.error_type}
            </p>
            <p
              :if={@project_import_report.status != :ready}
              id="setup-project-import-remediation"
              class="text-sm text-warning"
            >
              {@project_import_report.remediation}
            </p>
          </div>
        </section>

        <section
          :if={@onboarding_step == 8}
          id="setup-onboarding-complete-next-actions"
          class="space-y-3 rounded-lg border border-base-300 bg-base-100 p-3"
        >
          <h2 class="text-lg font-semibold">Next actions after completion</h2>
          <ul class="space-y-1 text-sm text-base-content/80">
            <li id="setup-next-action-run-workflow">Run your first workflow</li>
            <li id="setup-next-action-review-security">Review the security playbook</li>
            <li id="setup-next-action-test-rpc">Test the RPC client</li>
          </ul>
        </section>

        <section :if={@onboarding_step == 2} id="setup-owner-bootstrap" class="space-y-3">
          <h2 class="text-lg font-semibold">Owner account bootstrap</h2>
          <p id="setup-owner-bootstrap-mode" class="text-sm text-base-content/80">
            {owner_bootstrap_mode_message(@owner_bootstrap.mode)}
          </p>
          <p
            :if={@owner_bootstrap.mode == :confirm and @owner_bootstrap.owner_email}
            id="setup-owner-bootstrap-owner-email"
            class="font-mono text-sm"
          >
            Existing owner: {@owner_bootstrap.owner_email}
          </p>

          <.form for={@owner_form} id="setup-owner-bootstrap-form" phx-submit="bootstrap_owner" class="space-y-4">
            <.input
              field={@owner_form[:email]}
              id="setup-owner-email"
              type="email"
              label="Owner email"
              required
            />
            <.input
              field={@owner_form[:password]}
              id="setup-owner-password"
              type="password"
              label={owner_password_label(@owner_bootstrap.mode)}
              minlength={if @owner_bootstrap.mode == :create, do: 8, else: nil}
              required
            />
            <.input
              :if={@owner_bootstrap.mode == :create}
              field={@owner_form[:password_confirmation]}
              id="setup-owner-password-confirmation"
              type="password"
              label="Confirm owner password"
              minlength="8"
              required
            />
            <button id="setup-owner-bootstrap-submit" type="submit" class="btn btn-primary">
              {owner_submit_label(@owner_bootstrap.mode)}
            </button>
          </.form>

          <section
            :if={@owner_bootstrap.mode == :confirm}
            id="setup-owner-recovery"
            class="space-y-3 rounded-lg border border-base-300 bg-base-100 p-3"
          >
            <h3 class="text-base font-semibold">Owner recovery bootstrap path</h3>
            <p id="setup-owner-recovery-summary" class="text-sm text-base-content/80">
              Use this path only if owner credentials are lost. Recovery verification must pass before reset.
            </p>
            <ol id="setup-owner-recovery-steps" class="list-decimal space-y-1 pl-5 text-sm text-base-content/80">
              <li id="setup-owner-recovery-step-email">Confirm the existing owner email.</li>
              <li id="setup-owner-recovery-step-phrase">
                Type the recovery verification phrase exactly.
              </li>
              <li id="setup-owner-recovery-step-ack">
                Acknowledge the credential reset action.
              </li>
            </ol>
            <p id="setup-owner-recovery-verification-target" class="font-mono text-sm">
              Verification phrase: {OwnerRecovery.verification_phrase()}
            </p>

            <.form
              for={@owner_recovery_form}
              id="setup-owner-recovery-form"
              phx-submit="recover_owner"
              class="space-y-4"
            >
              <.input
                field={@owner_recovery_form[:email]}
                id="setup-owner-recovery-email"
                type="email"
                label="Owner email verification"
                required
              />
              <.input
                field={@owner_recovery_form[:password]}
                id="setup-owner-recovery-password"
                type="password"
                label="New owner password"
                minlength="8"
                required
              />
              <.input
                field={@owner_recovery_form[:password_confirmation]}
                id="setup-owner-recovery-password-confirmation"
                type="password"
                label="Confirm new owner password"
                minlength="8"
                required
              />
              <.input
                field={@owner_recovery_form[:verification_phrase]}
                id="setup-owner-recovery-verification-phrase"
                type="text"
                label="Recovery verification phrase"
                required
              />
              <.input
                field={@owner_recovery_form[:verification_ack]}
                id="setup-owner-recovery-verification-ack"
                type="checkbox"
                label="I verified owner identity and approve credential reset."
                required
              />
              <button id="setup-owner-recovery-submit" type="submit" class="btn btn-warning">
                Recover owner credentials
              </button>
            </.form>
          </section>
        </section>

        <.form
          :if={@onboarding_step != 2}
          for={@step_form}
          id="onboarding-step-form"
          phx-submit="save_step"
          class="space-y-4"
        >
          <.input
            :if={@onboarding_step == 5}
            field={@step_form[:execution_mode]}
            id="setup-execution-mode"
            type="select"
            label="Default execution mode"
            options={[{"Cloud (Sprite default)", "cloud"}, {"Local workspace", "local"}]}
            required
          />
          <.input
            :if={@onboarding_step == 5}
            field={@step_form[:workspace_root]}
            id="setup-workspace-root-input"
            type="text"
            label="Local workspace root"
            placeholder="/absolute/path/to/workspaces"
          />
          <.input
            :if={@onboarding_step == 7 and !Enum.empty?(@available_repositories)}
            field={@step_form[:repository_full_name]}
            id="setup-project-repository-select"
            type="select"
            label="Repository to import"
            options={repository_select_options(@available_repositories)}
            required
          />
          <.input
            :if={@onboarding_step == 7 and Enum.empty?(@available_repositories)}
            field={@step_form[:repository_full_name]}
            id="setup-project-repository-input"
            type="text"
            label="Repository to import"
            placeholder="owner/repository"
            required
          />
          <.input
            field={@step_form[:validated_note]}
            id="onboarding-validated-note"
            type="text"
            label="Validation notes for this step"
            required
          />
          <button id="onboarding-save-step" type="submit" class="btn btn-primary">
            Save step and continue
          </button>
        </.form>

        <section id="validated-state" class="space-y-2">
          <h2 class="text-lg font-semibold">Persisted validated state</h2>
          <p :if={Enum.empty?(validated_step_entries(@onboarding_state))} class="text-sm text-base-content/70">
            No step state has been validated yet.
          </p>
          <ul :if={!Enum.empty?(validated_step_entries(@onboarding_state))} class="space-y-2">
            <li
              :for={{step_key, step_state} <- validated_step_entries(@onboarding_state)}
              id={"validated-state-step-#{step_number(step_key)}"}
              class="rounded-lg border border-base-300 bg-base-100 p-3"
            >
              <p class="font-medium">Step {step_number(step_key)}</p>
              <p class="text-sm text-base-content/80">{Map.get(step_state, "validated_note", "Validated")}</p>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save_step", _params, %{assigns: %{onboarding_step: 2}} = socket) do
    {:noreply, assign(socket, :save_error, @owner_step_validation_error)}
  end

  def handle_event(
        "bootstrap_owner",
        %{"owner" => owner_params},
        %{assigns: %{onboarding_step: 2}} = socket
      ) do
    case OwnerBootstrap.bootstrap(owner_params) do
      {:ok, owner_bootstrap_result} ->
        step_state =
          %{
            "validated_note" => owner_bootstrap_result.validated_note,
            "owner_email" => to_string(owner_bootstrap_result.owner.email),
            "owner_mode" => Atom.to_string(owner_bootstrap_result.owner_mode)
          }
          |> maybe_mark_registration_lockout()

        case SystemConfig.save_step_progress(step_state) do
          {:ok, %SystemConfig{} = config} ->
            {:noreply,
             socket
             |> assign_config_state(config)
             |> assign(:save_error, nil)
             |> redirect(to: owner_sign_in_with_token_path(owner_bootstrap_result.token))}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply, assign(socket, :save_error, diagnostic)}
        end

      {:error, {_error_type, diagnostic}} ->
        owner_bootstrap = resolve_owner_bootstrap(socket.assigns.onboarding_step)

        {:noreply,
         socket
         |> assign(:owner_bootstrap, owner_bootstrap)
         |> assign(:save_error, diagnostic)
         |> assign_owner_form(
           socket.assigns.onboarding_step,
           socket.assigns.onboarding_state,
           owner_bootstrap,
           owner_params
         )}
    end
  end

  def handle_event("bootstrap_owner", _params, socket) do
    {:noreply, assign(socket, :save_error, @owner_step_validation_error)}
  end

  def handle_event(
        "recover_owner",
        %{"owner_recovery" => recovery_params},
        %{assigns: %{onboarding_step: 2, owner_bootstrap: %{mode: :confirm}}} = socket
      ) do
    case OwnerRecovery.recover(recovery_params) do
      {:ok, owner_recovery_result} ->
        step_state =
          %{
            "validated_note" => owner_recovery_result.validated_note,
            "owner_email" => to_string(owner_recovery_result.owner.email),
            "owner_mode" => Atom.to_string(owner_recovery_result.owner_mode),
            "owner_recovery_audit" => OwnerRecovery.serialize_audit_for_state(owner_recovery_result.audit)
          }
          |> maybe_mark_registration_lockout()

        case SystemConfig.save_step_progress(step_state) do
          {:ok, %SystemConfig{} = config} ->
            {:noreply,
             socket
             |> assign_config_state(config)
             |> assign(:save_error, nil)
             |> redirect(to: owner_sign_in_with_token_path(owner_recovery_result.token))}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply, assign(socket, :save_error, diagnostic)}
        end

      {:error, {_error_type, diagnostic}} ->
        owner_bootstrap = resolve_owner_bootstrap(socket.assigns.onboarding_step)

        {:noreply,
         socket
         |> assign(:owner_bootstrap, owner_bootstrap)
         |> assign(:save_error, diagnostic)
         |> assign_owner_form(
           socket.assigns.onboarding_step,
           socket.assigns.onboarding_state,
           owner_bootstrap
         )
         |> assign_recovery_form(
           socket.assigns.onboarding_step,
           socket.assigns.onboarding_state,
           owner_bootstrap,
           recovery_params
         )}
    end
  end

  def handle_event("recover_owner", _params, socket) do
    {:noreply, assign(socket, :save_error, @owner_recovery_validation_error)}
  end

  def handle_event(
        "refresh_repository_listing",
        _params,
        %{assigns: %{onboarding_step: 7}} = socket
      ) do
    repository_listing_report =
      GitHubRepositoryListing.run(
        socket.assigns.repository_listing_report,
        socket.assigns.onboarding_state
      )

    available_repositories =
      resolve_available_repositories(repository_listing_report, socket.assigns.onboarding_state)

    save_error =
      if GitHubRepositoryListing.blocked?(repository_listing_report) do
        repository_listing_block_message(repository_listing_report)
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:repository_listing_report, repository_listing_report)
     |> assign(:available_repositories, available_repositories)
     |> assign(:save_error, save_error)}
  end

  def handle_event("refresh_repository_listing", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save_step", %{"step" => step_params}, socket) when is_map(step_params) do
    case normalize_validated_note(Map.get(step_params, "validated_note")) do
      {:ok, normalized_note} ->
        save_step_progress(socket, normalized_note, step_params)

      {:error, diagnostic} ->
        {:noreply, assign(socket, :save_error, diagnostic)}
    end
  end

  def handle_event("save_step", _params, socket) do
    {:noreply, assign(socket, :save_error, @validation_error)}
  end

  defp parse_step(step) when is_integer(step) and step > 0, do: step

  defp parse_step(step) when is_binary(step) do
    case Integer.parse(step) do
      {parsed_step, ""} when parsed_step > 0 -> parsed_step
      _ -> 1
    end
  end

  defp parse_step(_), do: 1

  defp assign_step_form(
         socket,
         onboarding_step,
         onboarding_state,
         default_environment,
         workspace_root,
         step_params \\ %{}
       ) do
    step_state = fetch_step_state(onboarding_state, onboarding_step)
    available_repositories = ProjectImport.available_repositories(onboarding_state)

    persisted_note = Map.get(step_state, "validated_note", "")

    persisted_environment_state =
      step_state
      |> Map.get("environment_defaults", %{})
      |> normalize_environment_state()

    persisted_project_import_report =
      step_state
      |> Map.get("project_import")
      |> ProjectImport.from_state()

    default_mode = default_environment_mode(default_environment)

    execution_mode =
      step_params
      |> Map.get("execution_mode")
      |> normalize_execution_mode(Map.get(persisted_environment_state, :mode, default_mode))

    workspace_root_value =
      step_params
      |> Map.get("workspace_root")
      |> normalize_workspace_root_input(Map.get(persisted_environment_state, :workspace_root, workspace_root || ""))

    repository_full_name =
      step_params
      |> Map.get("repository_full_name")
      |> normalize_repository_full_name_input(
        ProjectImport.selected_repository(persisted_project_import_report) ||
          List.first(available_repositories) ||
          ""
      )

    assign(
      socket,
      :step_form,
      to_form(
        %{
          "validated_note" => persisted_note,
          "execution_mode" => execution_mode,
          "workspace_root" => workspace_root_value,
          "repository_full_name" => repository_full_name
        },
        as: :step
      )
    )
  end

  defp assign_owner_form(
         socket,
         onboarding_step,
         onboarding_state,
         owner_bootstrap,
         owner_params \\ %{}
       ) do
    if onboarding_step == 2 do
      persisted_owner_email =
        onboarding_state
        |> fetch_step_state(2)
        |> Map.get("owner_email", "")

      owner_email =
        owner_params["email"] ||
          owner_bootstrap.owner_email ||
          persisted_owner_email

      assign(
        socket,
        :owner_form,
        to_form(
          %{
            "email" => owner_email,
            "password" => "",
            "password_confirmation" => ""
          },
          as: :owner
        )
      )
    else
      assign(
        socket,
        :owner_form,
        to_form(%{"email" => "", "password" => "", "password_confirmation" => ""}, as: :owner)
      )
    end
  end

  defp assign_recovery_form(
         socket,
         onboarding_step,
         onboarding_state,
         owner_bootstrap,
         recovery_params \\ %{}
       ) do
    if onboarding_step == 2 and owner_bootstrap.mode == :confirm do
      persisted_owner_email =
        onboarding_state
        |> fetch_step_state(2)
        |> Map.get("owner_email", "")

      recovery_email =
        recovery_params["email"] ||
          owner_bootstrap.owner_email ||
          persisted_owner_email

      recovery_phrase =
        recovery_params
        |> Map.get("verification_phrase", "")
        |> normalize_recovery_phrase_input()

      recovery_ack =
        recovery_params
        |> Map.get("verification_ack")
        |> normalize_recovery_ack_input(false)

      assign(
        socket,
        :owner_recovery_form,
        to_form(
          %{
            "email" => recovery_email,
            "password" => "",
            "password_confirmation" => "",
            "verification_phrase" => recovery_phrase,
            "verification_ack" => recovery_ack
          },
          as: :owner_recovery
        )
      )
    else
      assign(
        socket,
        :owner_recovery_form,
        to_form(
          %{
            "email" => "",
            "password" => "",
            "password_confirmation" => "",
            "verification_phrase" => "",
            "verification_ack" => false
          },
          as: :owner_recovery
        )
      )
    end
  end

  defp normalize_recovery_phrase_input(verification_phrase) when is_binary(verification_phrase) do
    String.trim(verification_phrase)
  end

  defp normalize_recovery_phrase_input(_verification_phrase), do: ""

  defp normalize_recovery_ack_input(true, _fallback), do: true
  defp normalize_recovery_ack_input("true", _fallback), do: true
  defp normalize_recovery_ack_input("1", _fallback), do: true
  defp normalize_recovery_ack_input(1, _fallback), do: true
  defp normalize_recovery_ack_input("on", _fallback), do: true
  defp normalize_recovery_ack_input(false, _fallback), do: false
  defp normalize_recovery_ack_input("false", _fallback), do: false
  defp normalize_recovery_ack_input("0", _fallback), do: false
  defp normalize_recovery_ack_input(0, _fallback), do: false
  defp normalize_recovery_ack_input(_verification_ack, fallback), do: fallback

  defp normalize_validated_note(validated_note) when is_binary(validated_note) do
    normalized_note = String.trim(validated_note)

    if normalized_note == "" do
      {:error, @validation_error}
    else
      {:ok, normalized_note}
    end
  end

  defp normalize_validated_note(_), do: {:error, @validation_error}

  defp environment_selection(step_params, default_environment, workspace_root)
       when is_map(step_params) do
    %{
      "mode" =>
        step_params
        |> Map.get("execution_mode")
        |> normalize_execution_mode(default_environment_mode(default_environment)),
      "workspace_root" =>
        step_params
        |> Map.get("workspace_root")
        |> normalize_workspace_root_input(workspace_root)
    }
  end

  defp environment_selection(_step_params, default_environment, workspace_root) do
    %{
      "mode" => default_environment_mode(default_environment),
      "workspace_root" => normalize_workspace_root_input(nil, workspace_root)
    }
  end

  defp normalize_environment_state(environment_state) when is_map(environment_state) do
    %{}
    |> maybe_put_environment_field(
      :mode,
      environment_state
      |> Map.get("mode")
      |> normalize_execution_mode(nil)
    )
    |> maybe_put_environment_field(
      :workspace_root,
      environment_state
      |> Map.get("workspace_root")
      |> normalize_optional_workspace_root()
    )
  end

  defp normalize_environment_state(_environment_state), do: %{}

  defp default_environment_mode(:local), do: "local"
  defp default_environment_mode(_default_environment), do: "cloud"

  defp mode_param(:local), do: "local"
  defp mode_param(:cloud), do: "cloud"

  defp normalize_execution_mode("local", _default_mode), do: "local"
  defp normalize_execution_mode(:local, _default_mode), do: "local"
  defp normalize_execution_mode("cloud", _default_mode), do: "cloud"
  defp normalize_execution_mode(:cloud, _default_mode), do: "cloud"
  defp normalize_execution_mode(_mode, nil), do: nil
  defp normalize_execution_mode(_mode, default_mode), do: default_mode

  defp normalize_workspace_root_input(workspace_root, fallback) when is_binary(workspace_root) do
    workspace_root
    |> String.trim()
    |> case do
      "" -> normalize_workspace_root_fallback(fallback)
      normalized_workspace_root -> normalized_workspace_root
    end
  end

  defp normalize_workspace_root_input(_workspace_root, fallback),
    do: normalize_workspace_root_fallback(fallback)

  defp normalize_workspace_root_fallback(fallback) when is_binary(fallback) do
    fallback
    |> String.trim()
    |> case do
      "" -> ""
      normalized_workspace_root -> normalized_workspace_root
    end
  end

  defp normalize_workspace_root_fallback(_fallback), do: ""

  defp normalize_optional_workspace_root(workspace_root) when is_binary(workspace_root) do
    workspace_root
    |> String.trim()
    |> case do
      "" -> nil
      normalized_workspace_root -> normalized_workspace_root
    end
  end

  defp normalize_optional_workspace_root(_workspace_root), do: nil

  defp normalize_repository_full_name_input(repository_full_name, fallback)
       when is_binary(repository_full_name) do
    repository_full_name
    |> String.trim()
    |> case do
      "" -> normalize_repository_fallback(fallback)
      normalized_repository_full_name -> normalized_repository_full_name
    end
  end

  defp normalize_repository_full_name_input(_repository_full_name, fallback),
    do: normalize_repository_fallback(fallback)

  defp normalize_repository_fallback(fallback) when is_binary(fallback) do
    fallback
    |> String.trim()
    |> case do
      "" -> ""
      normalized_repository_full_name -> normalized_repository_full_name
    end
  end

  defp normalize_repository_fallback(_fallback), do: ""

  defp maybe_put_environment_field(environment_state, _key, nil), do: environment_state

  defp maybe_put_environment_field(environment_state, key, value),
    do: Map.put(environment_state, key, value)

  defp validated_step_entries(onboarding_state) do
    onboarding_state
    |> Enum.filter(fn {_step_key, step_state} -> is_map(step_state) end)
    |> Enum.sort_by(fn {step_key, _step_state} -> step_number(step_key) end)
  end

  defp resolve_prerequisite_report(onboarding_step, onboarding_state) do
    if onboarding_step == 1 do
      PrerequisiteChecks.run()
    else
      onboarding_state
      |> fetch_step_state(1)
      |> Map.get("prerequisite_checks")
      |> PrerequisiteChecks.from_state()
    end
  end

  defp resolve_provider_credential_report(onboarding_step, onboarding_state) do
    if onboarding_step == 3 do
      onboarding_state
      |> fetch_step_state(3)
      |> Map.get("provider_credentials")
      |> ProviderCredentialChecks.run()
    else
      nil
    end
  end

  defp resolve_github_credential_report(onboarding_step, onboarding_state) do
    if onboarding_step == 4 do
      owner_context = resolve_owner_context(onboarding_state)

      onboarding_state
      |> fetch_step_state(4)
      |> Map.get("github_credentials")
      |> GitHubCredentialChecks.run(owner_context)
    else
      nil
    end
  end

  defp resolve_webhook_simulation_report(onboarding_step, onboarding_state) do
    if onboarding_step == 6 do
      onboarding_state
      |> fetch_step_state(6)
      |> Map.get("webhook_simulation")
      |> WebhookSimulationChecks.run()
    else
      nil
    end
  end

  defp resolve_project_import_report(onboarding_step, onboarding_state) do
    if onboarding_step in [7, 8] do
      onboarding_state
      |> fetch_step_state(7)
      |> Map.get("project_import")
      |> ProjectImport.from_state()
    else
      nil
    end
  end

  defp resolve_repository_listing_report(onboarding_step, onboarding_state) do
    if onboarding_step == 7 do
      previous_repository_listing_report =
        onboarding_state
        |> fetch_step_state(7)
        |> Map.get("repository_listing")
        |> GitHubRepositoryListing.from_state()

      GitHubRepositoryListing.run(previous_repository_listing_report, onboarding_state)
    else
      nil
    end
  end

  defp resolve_available_repositories(repository_listing_report, onboarding_state) do
    case GitHubRepositoryListing.repository_full_names(repository_listing_report) do
      [] -> ProjectImport.available_repositories(onboarding_state)
      repository_full_names -> repository_full_names
    end
  end

  defp resolve_environment_defaults_report(
         onboarding_step,
         onboarding_state,
         default_environment,
         workspace_root
       ) do
    if onboarding_step == 5 do
      persisted_environment_state =
        onboarding_state
        |> fetch_step_state(5)
        |> Map.get("environment_defaults", %{})
        |> normalize_environment_state()

      EnvironmentDefaults.run(
        environment_selection(
          %{
            "execution_mode" =>
              Map.get(
                persisted_environment_state,
                :mode,
                default_environment_mode(default_environment)
              ),
            "workspace_root" => Map.get(persisted_environment_state, :workspace_root, workspace_root || "")
          },
          default_environment,
          workspace_root
        )
      )
    else
      nil
    end
  end

  defp resolve_owner_context(onboarding_state) do
    onboarding_state
    |> fetch_step_state(2)
    |> Map.get("owner_email")
    |> normalize_owner_context()
  end

  defp normalize_owner_context(owner_context) when is_binary(owner_context) do
    owner_context
    |> String.trim()
    |> case do
      "" -> nil
      normalized_owner_context -> normalized_owner_context
    end
  end

  defp normalize_owner_context(_owner_context), do: nil

  defp save_step_progress(socket, validated_note, step_params) do
    case socket.assigns.onboarding_step do
      1 ->
        prerequisite_report = PrerequisiteChecks.run()

        socket = assign(socket, :prerequisite_report, prerequisite_report)

        if PrerequisiteChecks.blocked?(prerequisite_report) do
          {:noreply, assign(socket, :save_error, prerequisite_block_message(prerequisite_report))}
        else
          persist_step_progress(socket, %{
            "validated_note" => validated_note,
            "prerequisite_checks" => PrerequisiteChecks.serialize_for_state(prerequisite_report)
          })
        end

      3 ->
        provider_credential_report =
          socket.assigns.onboarding_state
          |> fetch_step_state(3)
          |> Map.get("provider_credentials")
          |> ProviderCredentialChecks.run()

        socket = assign(socket, :provider_credential_report, provider_credential_report)

        if ProviderCredentialChecks.blocked?(provider_credential_report) do
          {:noreply, assign(socket, :save_error, provider_block_message(provider_credential_report))}
        else
          persist_step_progress(socket, %{
            "validated_note" => validated_note,
            "provider_credentials" => ProviderCredentialChecks.serialize_for_state(provider_credential_report)
          })
        end

      4 ->
        github_credential_report =
          socket.assigns.onboarding_state
          |> fetch_step_state(4)
          |> Map.get("github_credentials")
          |> GitHubCredentialChecks.run(resolve_owner_context(socket.assigns.onboarding_state))

        socket = assign(socket, :github_credential_report, github_credential_report)

        if GitHubCredentialChecks.blocked?(github_credential_report) do
          {:noreply, assign(socket, :save_error, github_block_message(github_credential_report))}
        else
          persist_step_progress(socket, %{
            "validated_note" => validated_note,
            "github_credentials" => GitHubCredentialChecks.serialize_for_state(github_credential_report)
          })
        end

      5 ->
        environment_defaults_report =
          step_params
          |> environment_selection(
            socket.assigns.default_environment,
            socket.assigns.workspace_root
          )
          |> EnvironmentDefaults.run()

        socket =
          socket
          |> assign(:environment_defaults_report, environment_defaults_report)
          |> assign_step_form(
            socket.assigns.onboarding_step,
            socket.assigns.onboarding_state,
            socket.assigns.default_environment,
            socket.assigns.workspace_root,
            %{
              "validated_note" => validated_note,
              "execution_mode" => mode_param(environment_defaults_report.mode),
              "workspace_root" => environment_defaults_report.workspace_root || ""
            }
          )

        if EnvironmentDefaults.blocked?(environment_defaults_report) do
          {:noreply, assign(socket, :save_error, environment_block_message(environment_defaults_report))}
        else
          persist_step_progress(
            socket,
            %{
              "validated_note" => validated_note,
              "environment_defaults" => EnvironmentDefaults.serialize_for_state(environment_defaults_report)
            },
            EnvironmentDefaults.system_config_updates(environment_defaults_report)
          )
        end

      6 ->
        webhook_simulation_report =
          socket.assigns.onboarding_state
          |> fetch_step_state(6)
          |> Map.get("webhook_simulation")
          |> WebhookSimulationChecks.run()

        socket = assign(socket, :webhook_simulation_report, webhook_simulation_report)

        if WebhookSimulationChecks.blocked?(webhook_simulation_report) do
          {:noreply,
           assign(
             socket,
             :save_error,
             webhook_simulation_block_message(webhook_simulation_report)
           )}
        else
          persist_step_progress(socket, %{
            "validated_note" => validated_note,
            "webhook_simulation" => WebhookSimulationChecks.serialize_for_state(webhook_simulation_report),
            "issue_bot_defaults" => WebhookSimulationChecks.issue_bot_defaults(webhook_simulation_report)
          })
        end

      7 ->
        project_import_report =
          socket.assigns.onboarding_state
          |> fetch_step_state(7)
          |> Map.get("project_import")
          |> ProjectImport.run(
            Map.get(step_params, "repository_full_name"),
            socket.assigns.onboarding_state
          )

        selected_repository = ProjectImport.selected_repository(project_import_report) || ""

        socket =
          socket
          |> assign(:project_import_report, project_import_report)
          |> assign_step_form(
            socket.assigns.onboarding_step,
            socket.assigns.onboarding_state,
            socket.assigns.default_environment,
            socket.assigns.workspace_root,
            %{
              "validated_note" => validated_note,
              "repository_full_name" => selected_repository
            }
          )

        if ProjectImport.blocked?(project_import_report) do
          {:noreply, assign(socket, :save_error, project_import_block_message(project_import_report))}
        else
          persist_step_progress(socket, %{
            "validated_note" => validated_note,
            "project_import" => ProjectImport.serialize_for_state(project_import_report)
          })
        end

      8 ->
        project_import_report =
          socket.assigns.onboarding_state
          |> fetch_step_state(7)
          |> Map.get("project_import")
          |> ProjectImport.from_state()

        if ProjectImport.blocked?(project_import_report) do
          {:noreply, assign(socket, :save_error, onboarding_completion_block_message(project_import_report))}
        else
          complete_onboarding(socket, validated_note, project_import_report)
        end

      _step ->
        persist_step_progress(socket, %{"validated_note" => validated_note})
    end
  end

  defp complete_onboarding(socket, validated_note, project_import_report) do
    next_actions = onboarding_next_actions()

    completion_step_state = %{
      "validated_note" => validated_note,
      "imported_repository" => ProjectImport.selected_repository(project_import_report),
      "next_actions" => next_actions,
      "completed_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    case SystemConfig.save_step_progress(completion_step_state, %{onboarding_completed: true}) do
      {:ok, %SystemConfig{} = config} ->
        {:noreply,
         socket
         |> assign_config_state(config)
         |> assign(:save_error, nil)
         |> put_flash(:info, onboarding_completion_message(next_actions))
         |> push_navigate(to: ~p"/dashboard?onboarding=completed")}

      {:error, %{diagnostic: diagnostic}} ->
        {:noreply, assign(socket, :save_error, diagnostic)}
    end
  end

  defp persist_step_progress(socket, step_state, config_updates \\ %{}) do
    case SystemConfig.save_step_progress(step_state, config_updates) do
      {:ok, %SystemConfig{} = config} ->
        {:noreply,
         socket
         |> assign_config_state(config)
         |> assign(:save_error, nil)
         |> assign_step_form(
           config.onboarding_step,
           config.onboarding_state,
           config.default_environment,
           config.workspace_root
         )}

      {:error, %{diagnostic: diagnostic}} ->
        {:noreply, assign(socket, :save_error, diagnostic)}
    end
  end

  defp prerequisite_block_message(report) do
    blocked_checks = PrerequisiteChecks.blocked_checks(report)

    remediation =
      blocked_checks
      |> Enum.map(fn check -> "#{check.name}: #{check.remediation}" end)
      |> Enum.join(" ")

    timeout_blocked? = Enum.any?(blocked_checks, fn check -> check.status == :timeout end)

    prefix =
      if timeout_blocked? do
        "One or more prerequisite checks timed out. Onboarding remains blocked and no setup progress was saved."
      else
        "System prerequisite checks failed. Resolve the reported prerequisites before continuing."
      end

    String.trim("#{prefix} #{remediation}")
  end

  defp provider_block_message(report) do
    remediation =
      report
      |> ProviderCredentialChecks.blocked_credentials()
      |> Enum.map(fn credential ->
        typed_error = credential.error_type || "provider_credential_unknown_error"
        "#{credential.name} [#{typed_error}]: #{credential.remediation}"
      end)
      |> Enum.join(" ")

    String.trim(
      "At least one provider credential must verify as Active before continuing to GitHub setup. No setup progress was saved. #{remediation}"
    )
  end

  defp github_block_message(report) do
    remediation =
      report
      |> GitHubCredentialChecks.blocked_paths()
      |> Enum.map(fn path ->
        typed_error = path.error_type || "github_integration_unknown_error"
        "#{path.name} [#{typed_error}]: #{path.remediation}"
      end)
      |> Enum.join(" ")

    String.trim(
      "GitHub integration validation failed for both GitHub App and PAT fallback. Step 4 remains blocked with typed integration errors. No setup progress was saved. #{remediation}"
    )
  end

  defp environment_block_message(report) do
    remediation =
      report
      |> EnvironmentDefaults.blocked_checks()
      |> Enum.map(fn check -> "#{check.name}: #{check.remediation}" end)
      |> Enum.join(" ")

    String.trim(
      "Environment defaults validation failed. Step 5 remains blocked and no environment defaults were changed. #{remediation}"
    )
  end

  defp webhook_simulation_block_message(report) do
    failure_reason =
      report
      |> WebhookSimulationChecks.failure_reason()
      |> case do
        nil -> "Unknown simulation failure."
        reason -> reason
      end

    String.trim(
      "Webhook simulation failed. Issue Bot defaults remain blocked until signature and routing readiness checks pass. The last failure reason is retained for retry: #{failure_reason}"
    )
  end

  defp repository_listing_block_message(report) do
    typed_error = report.error_type || "github_repository_fetch_failed"

    String.trim(
      "GitHub repository listing failed with typed error #{typed_error}. Step 7 state was preserved for retry. #{report.detail} #{report.remediation}"
    )
  end

  defp project_import_block_message(report) do
    typed_error = report.error_type || "project_import_unknown_error"

    String.trim(
      "Project import failed with typed error #{typed_error}. Onboarding completion is blocked and no completion flag was persisted. #{report.detail} #{report.remediation}"
    )
  end

  defp onboarding_completion_block_message(report) do
    typed_error = (report && report.error_type) || "project_import_missing"

    String.trim(
      "Onboarding completion is blocked until Step 7 imports a project with ready baseline metadata. Last import status: #{typed_error}."
    )
  end

  defp onboarding_next_actions do
    [
      "Run your first workflow",
      "Review the security playbook",
      "Test the RPC client"
    ]
  end

  defp onboarding_completion_message(next_actions) do
    "Onboarding complete. Next actions: #{Enum.join(next_actions, ", ")}."
  end

  defp prerequisite_status_label(:pass), do: "Pass"
  defp prerequisite_status_label(:timeout), do: "Timeout"
  defp prerequisite_status_label(:fail), do: "Fail"

  defp prerequisite_status_class(:pass), do: "badge-success"
  defp prerequisite_status_class(:timeout), do: "badge-warning"
  defp prerequisite_status_class(:fail), do: "badge-error"

  defp provider_status_label(:active), do: "Active"
  defp provider_status_label(:invalid), do: "Invalid"
  defp provider_status_label(:not_set), do: "Not set"
  defp provider_status_label(:rotating), do: "Rotating"

  defp provider_status_class(:active), do: "badge-success"
  defp provider_status_class(:invalid), do: "badge-error"
  defp provider_status_class(:not_set), do: "badge-warning"
  defp provider_status_class(:rotating), do: "badge-info"

  defp github_status_label(:ready), do: "Ready"
  defp github_status_label(:invalid), do: "Invalid"
  defp github_status_label(:not_configured), do: "Not configured"

  defp github_readiness_status_label(:ready), do: "Ready"
  defp github_readiness_status_label(:blocked), do: "Blocked"

  defp github_status_class(:ready), do: "badge-success"
  defp github_status_class(:invalid), do: "badge-error"
  defp github_status_class(:not_configured), do: "badge-warning"

  defp github_readiness_status_class(:ready), do: "badge-success"
  defp github_readiness_status_class(:blocked), do: "badge-error"

  defp github_auth_mode_feedback(report) do
    github_app_path = github_path_result(report, :github_app)
    pat_path = github_path_result(report, :pat)

    cond do
      github_path_ready?(github_app_path) ->
        %{
          mode: :github_app,
          label: "GitHub App",
          detail: nil
        }

      github_path_ready?(pat_path) ->
        %{
          mode: :pat_fallback,
          label: "PAT fallback",
          detail: "PAT fallback has reduced granularity relative to GitHub App mode. Webhook automation may be limited."
        }

      true ->
        %{
          mode: :not_ready,
          label: "Not ready",
          detail: nil
        }
    end
  end

  defp github_auth_mode_badge_class(:github_app), do: "badge-success"
  defp github_auth_mode_badge_class(:pat_fallback), do: "badge-warning"
  defp github_auth_mode_badge_class(:not_ready), do: "badge-error"

  defp github_path_result(%{paths: paths}, path) when is_list(paths) do
    Enum.find(paths, fn path_result ->
      path_value = Map.get(path_result, :path, Map.get(path_result, "path"))
      path_value == path or path_value == Atom.to_string(path)
    end) || %{}
  end

  defp github_path_result(_report, _path), do: %{}

  defp github_path_ready?(path_result) when is_map(path_result) do
    status = Map.get(path_result, :status, Map.get(path_result, "status"))

    repository_access =
      Map.get(path_result, :repository_access, Map.get(path_result, "repository_access"))

    status in [:ready, "ready"] and repository_access in [:confirmed, "confirmed"]
  end

  defp github_path_ready?(_path_result), do: false

  defp environment_check_status_label(:ready), do: "Ready"
  defp environment_check_status_label(:failed), do: "Failed"

  defp environment_check_status_class(:ready), do: "badge-success"
  defp environment_check_status_class(:failed), do: "badge-error"

  defp environment_mode_label(:cloud), do: "Cloud"
  defp environment_mode_label(:local), do: "Local"

  defp environment_default_label(:sprite), do: "sprite"
  defp environment_default_label(:local), do: "local"

  defp webhook_simulation_status_label(:ready), do: "Ready"
  defp webhook_simulation_status_label(:blocked), do: "Blocked"

  defp webhook_simulation_status_class(:ready), do: "badge-success"
  defp webhook_simulation_status_class(:blocked), do: "badge-error"

  defp webhook_check_status_label(:ready), do: "Ready"
  defp webhook_check_status_label(:failed), do: "Failed"

  defp webhook_check_status_class(:ready), do: "badge-success"
  defp webhook_check_status_class(:failed), do: "badge-error"

  defp repository_listing_status_label(:ready), do: "Ready"
  defp repository_listing_status_label(:blocked), do: "Blocked"
  defp repository_listing_status_label(_status), do: "Unknown"

  defp repository_listing_status_class(:ready), do: "badge-success"
  defp repository_listing_status_class(:blocked), do: "badge-error"
  defp repository_listing_status_class(_status), do: "badge-warning"

  defp project_import_status_label(:ready), do: "Ready"
  defp project_import_status_label(:blocked), do: "Blocked"
  defp project_import_status_label(_status), do: "Unknown"

  defp project_import_status_class(:ready), do: "badge-success"
  defp project_import_status_class(:blocked), do: "badge-error"
  defp project_import_status_class(_status), do: "badge-warning"

  defp project_import_clone_status(%{} = report) do
    report
    |> Map.get(:project_record, Map.get(report, "project_record", %{}))
    |> case do
      %{} = project_record ->
        project_record
        |> Map.get(:clone_status, Map.get(project_record, "clone_status"))
        |> normalize_project_clone_status()

      _other ->
        nil
    end
  end

  defp project_import_clone_status(_report), do: nil

  defp project_import_clone_transition(%{} = report) do
    statuses =
      report
      |> project_import_clone_history()
      |> Enum.map(&Map.get(&1, :status))
      |> Enum.uniq()

    case statuses do
      [] ->
        nil

      clone_statuses ->
        clone_statuses
        |> Enum.map(&project_clone_status_label/1)
        |> Enum.join(" -> ")
    end
  end

  defp project_import_clone_transition(_report), do: nil

  defp project_import_baseline_branch(%{} = report) do
    report
    |> Map.get(:baseline_metadata, Map.get(report, "baseline_metadata", %{}))
    |> case do
      %{} = baseline_metadata ->
        baseline_metadata
        |> Map.get(:synced_branch, Map.get(baseline_metadata, "synced_branch"))
        |> case do
          branch when is_binary(branch) and branch != "" -> branch
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp project_import_baseline_branch(_report), do: nil

  defp project_import_last_synced_at(%{} = report) do
    project_record =
      Map.get(report, :project_record) || Map.get(report, "project_record") || %{}

    baseline_metadata =
      Map.get(report, :baseline_metadata) || Map.get(report, "baseline_metadata") || %{}

    project_record
    |> Map.get(:last_synced_at, Map.get(project_record, "last_synced_at"))
    |> case do
      nil ->
        baseline_metadata
        |> Map.get(:last_synced_at, Map.get(baseline_metadata, "last_synced_at"))

      datetime ->
        datetime
    end
    |> normalize_live_datetime()
  end

  defp project_import_last_synced_at(_report), do: nil

  defp project_import_clone_history(%{} = report) do
    project_record =
      Map.get(report, :project_record) || Map.get(report, "project_record") || %{}

    project_record
    |> Map.get(:clone_status_history, Map.get(project_record, "clone_status_history", []))
    |> Enum.flat_map(fn
      %{} = entry ->
        status =
          entry
          |> Map.get(:status, Map.get(entry, "status"))
          |> normalize_project_clone_status()

        transitioned_at =
          entry
          |> Map.get(:transitioned_at, Map.get(entry, "transitioned_at"))
          |> normalize_live_datetime()

        if is_nil(status) or is_nil(transitioned_at) do
          []
        else
          [%{status: status, transitioned_at: transitioned_at}]
        end

      _other ->
        []
    end)
  end

  defp project_import_clone_history(_report), do: []

  defp normalize_project_clone_status(:pending), do: :pending
  defp normalize_project_clone_status(:cloning), do: :cloning
  defp normalize_project_clone_status(:ready), do: :ready
  defp normalize_project_clone_status(:error), do: :error
  defp normalize_project_clone_status("pending"), do: :pending
  defp normalize_project_clone_status("cloning"), do: :cloning
  defp normalize_project_clone_status("ready"), do: :ready
  defp normalize_project_clone_status("error"), do: :error
  defp normalize_project_clone_status(_status), do: nil

  defp project_clone_status_label(:pending), do: "Pending"
  defp project_clone_status_label(:cloning), do: "Cloning"
  defp project_clone_status_label(:ready), do: "Ready"
  defp project_clone_status_label(:error), do: "Error"
  defp project_clone_status_label(_status), do: "Unknown"

  defp project_clone_status_class(:pending), do: "badge-warning"
  defp project_clone_status_class(:cloning), do: "badge-info"
  defp project_clone_status_class(:ready), do: "badge-success"
  defp project_clone_status_class(:error), do: "badge-error"
  defp project_clone_status_class(_status), do: "badge-warning"

  defp issue_bot_default_enabled(issue_bot_defaults) when is_map(issue_bot_defaults) do
    issue_bot_defaults
    |> Map.get("enabled")
    |> case do
      true -> "true"
      false -> "false"
      _other -> "unknown"
    end
  end

  defp issue_bot_default_enabled(_issue_bot_defaults), do: "unknown"

  defp issue_bot_default_approval_mode(issue_bot_defaults) when is_map(issue_bot_defaults) do
    issue_bot_defaults
    |> Map.get("approval_mode")
    |> case do
      value when is_binary(value) and value != "" -> value
      _other -> "unknown"
    end
  end

  defp issue_bot_default_approval_mode(_issue_bot_defaults), do: "unknown"

  defp github_repository_access_label(:confirmed), do: "Confirmed"
  defp github_repository_access_label(:unconfirmed), do: "Unconfirmed"

  defp github_repositories_text(repositories) when is_list(repositories) do
    case repositories do
      [] -> "none reported"
      _repositories -> Enum.join(repositories, ", ")
    end
  end

  defp github_repositories_text(_repositories), do: "none reported"

  defp format_checked_at(%DateTime{} = checked_at), do: DateTime.to_iso8601(checked_at)
  defp format_checked_at(_), do: "unknown"

  defp normalize_live_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_live_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, parsed_datetime, _offset} -> parsed_datetime
      _other -> nil
    end
  end

  defp normalize_live_datetime(_datetime), do: nil

  defp fetch_step_state(onboarding_state, onboarding_step) when is_map(onboarding_state) do
    step_key = Integer.to_string(onboarding_step)
    Map.get(onboarding_state, step_key) || Map.get(onboarding_state, onboarding_step) || %{}
  end

  defp fetch_step_state(_onboarding_state, _onboarding_step), do: %{}

  defp step_title(step) do
    Map.get(@wizard_steps, step, "Onboarding step #{step}")
  end

  defp assign_config_state(socket, %SystemConfig{} = config) do
    owner_bootstrap = resolve_owner_bootstrap(config.onboarding_step)

    repository_listing_report =
      resolve_repository_listing_report(config.onboarding_step, config.onboarding_state)

    available_repositories =
      resolve_available_repositories(repository_listing_report, config.onboarding_state)

    socket
    |> assign(:onboarding_step, config.onboarding_step)
    |> assign(:onboarding_state, config.onboarding_state)
    |> assign(:default_environment, config.default_environment)
    |> assign(:workspace_root, config.workspace_root)
    |> assign(
      :prerequisite_report,
      resolve_prerequisite_report(config.onboarding_step, config.onboarding_state)
    )
    |> assign(
      :provider_credential_report,
      resolve_provider_credential_report(config.onboarding_step, config.onboarding_state)
    )
    |> assign(
      :github_credential_report,
      resolve_github_credential_report(config.onboarding_step, config.onboarding_state)
    )
    |> assign(
      :webhook_simulation_report,
      resolve_webhook_simulation_report(config.onboarding_step, config.onboarding_state)
    )
    |> assign(
      :environment_defaults_report,
      resolve_environment_defaults_report(
        config.onboarding_step,
        config.onboarding_state,
        config.default_environment,
        config.workspace_root
      )
    )
    |> assign(
      :project_import_report,
      resolve_project_import_report(config.onboarding_step, config.onboarding_state)
    )
    |> assign(:repository_listing_report, repository_listing_report)
    |> assign(:available_repositories, available_repositories)
    |> assign(:owner_bootstrap, owner_bootstrap)
    |> assign_owner_form(config.onboarding_step, config.onboarding_state, owner_bootstrap)
    |> assign_recovery_form(config.onboarding_step, config.onboarding_state, owner_bootstrap)
  end

  defp resolve_owner_bootstrap(2) do
    case OwnerBootstrap.status() do
      {:ok, %{mode: :create}} ->
        %{mode: :create, owner_email: nil, error: nil}

      {:ok, %{mode: :confirm, owner: owner}} ->
        %{mode: :confirm, owner_email: to_string(owner.email), error: nil}

      {:error, {_error_type, diagnostic}} ->
        %{mode: :error, owner_email: nil, error: diagnostic}
    end
  end

  defp resolve_owner_bootstrap(_step), do: %{mode: :inactive, owner_email: nil, error: nil}

  defp owner_bootstrap_error(%{error: diagnostic})
       when is_binary(diagnostic) and diagnostic != "",
       do: diagnostic

  defp owner_bootstrap_error(_owner_bootstrap), do: nil

  defp owner_bootstrap_mode_message(:create),
    do: "No owner account exists yet. Create one owner to continue."

  defp owner_bootstrap_mode_message(:confirm),
    do: "An owner account already exists. Confirm owner credentials to continue."

  defp owner_bootstrap_mode_message(:error),
    do: "Owner bootstrap is currently blocked by a single-user policy issue."

  defp owner_bootstrap_mode_message(:inactive), do: ""

  defp owner_password_label(:create), do: "Owner password"
  defp owner_password_label(:confirm), do: "Owner password for confirmation"
  defp owner_password_label(_mode), do: "Owner password"

  defp owner_submit_label(:create), do: "Create owner account"
  defp owner_submit_label(:confirm), do: "Confirm owner account"
  defp owner_submit_label(_mode), do: "Continue"

  defp maybe_mark_registration_lockout(step_state) do
    if RuntimeMode.production?() do
      Map.put(step_state, "registration_actions_disabled", true)
    else
      step_state
    end
  end

  defp owner_sign_in_with_token_path(token) do
    strategy = Info.strategy!(User, :password)

    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _ -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})

    "#{path}?#{query}"
  end

  defp repository_listing_entries(repository_listing_report, available_repositories) do
    repository_options =
      case GitHubRepositoryListing.repository_options(repository_listing_report) do
        [] ->
          Enum.map(available_repositories || [], fn repository ->
            %{
              full_name: repository,
              id: repository_fallback_stable_id(repository)
            }
          end)

        repositories ->
          Enum.map(repositories, fn repository ->
            full_name = Map.get(repository, :full_name, Map.get(repository, "full_name"))

            %{
              full_name: full_name,
              id:
                Map.get(repository, :id, Map.get(repository, "id")) ||
                  repository_fallback_stable_id(full_name)
            }
          end)
      end

    repository_options
    |> Enum.filter(fn repository ->
      is_binary(repository.full_name) and String.trim(repository.full_name) != ""
    end)
    |> Enum.sort_by(fn repository -> {repository.full_name, repository.id} end)
  end

  defp repository_fallback_stable_id(repository) when is_binary(repository) do
    repository
    |> String.trim()
    |> case do
      "" -> "repo:unknown"
      normalized_repository -> "repo:#{normalized_repository}"
    end
  end

  defp repository_fallback_stable_id(_repository), do: "repo:unknown"

  defp repository_select_options(repositories) when is_list(repositories) do
    repositories
    |> Enum.sort()
    |> Enum.map(fn repository -> {repository, repository} end)
  end

  defp repository_select_options(_repositories), do: []

  defp step_number(step_key), do: parse_step(step_key)

  defp provider_dom_id(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider_dom_id(provider) when is_binary(provider), do: provider
  defp provider_dom_id(_provider), do: "unknown"

  defp repository_dom_id(repository) when is_binary(repository) do
    repository
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "unknown"
      dom_id -> dom_id
    end
  end

  defp repository_dom_id(_repository), do: "unknown"

  defp webhook_event_dom_id(event) when is_binary(event) do
    event
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "unknown"
      dom_id -> dom_id
    end
  end

  defp webhook_event_dom_id(event) when is_atom(event) do
    event
    |> Atom.to_string()
    |> webhook_event_dom_id()
  end

  defp webhook_event_dom_id(_event), do: "unknown"

  defp github_integration_health(%{integration_health: integration_health})
       when is_map(integration_health),
       do: integration_health

  defp github_integration_health(%{status: status, paths: paths}) when is_list(paths) do
    github_app_path =
      Enum.find(paths, fn path_result -> path_result.path == :github_app end) || %{}

    %{
      readiness_status: status,
      github_app_status: Map.get(github_app_path, :status, :not_configured),
      expected_repositories: Map.get(github_app_path, :expected_repositories, []),
      missing_repositories: Map.get(github_app_path, :missing_repositories, [])
    }
  end

  defp github_integration_health(_report) do
    %{
      readiness_status: :blocked,
      github_app_status: :not_configured,
      expected_repositories: [],
      missing_repositories: []
    }
  end

  defp github_path_dom_id(path) when is_atom(path), do: Atom.to_string(path)
  defp github_path_dom_id(path) when is_binary(path), do: path
  defp github_path_dom_id(_path), do: "unknown"
end
