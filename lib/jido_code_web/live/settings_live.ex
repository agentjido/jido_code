defmodule JidoCodeWeb.SettingsLive do
  # covers: architecture.policy_layers.operator_surfaces_propagate_current_actor_for_repo_mutations
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.frontend_stack.settings_routes_keep_repo_import_liveview_owned
  # covers: auth.operator_settings.sections_separated
  # covers: auth.operator_settings.broker_trust_configuration_ui
  # covers: auth.operator_settings.github_service_validation_feedback
  # covers: auth.operator_settings.integration_boundary_visible
  # covers: auth.operator_settings.hidden_during_bootstrap_entry
  # covers: architecture.factory_control_plane.settings_github_add_uses_canonical_repo_import
  use JidoCodeWeb, :live_view

  alias JidoCode.Accounts.SecurityTokens
  alias JidoCode.Control.Actor
  alias JidoCode.GitHub.RepoStore
  alias JidoCode.Security.SecretRefs
  alias JidoCode.Setup.ProjectImport
  alias JidoCodeWeb.OperatorAuthSettings
  alias JidoCodeWeb.OperatorShell
  alias JidoCodeWeb.Security.UiRedaction

  @secret_scope_options [
    {"Instance", "instance"},
    {"Repository", "project"},
    {"Integration", "integration"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:show_add_modal, false)
      |> assign(:form, nil)
      |> assign(:repo_save_error, nil)
      |> assign(:repo_count, 0)
      |> assign(:enabled_repo_count, 0)
      |> assign(:operator_auth_allowlist_options, OperatorAuthSettings.allowlist_options())
      |> assign(:provider_login_cards, [])
      |> assign(:github_service_report, %{checked_at: nil, status: :not_configured, paths: []})
      |> assign(:github_service_secret_refs, [])
      |> assign(:security_tokens, [])
      |> assign(:security_api_keys, [])
      |> assign(:security_audit_events, [])
      |> assign(:security_revocation_error, nil)
      |> assign(:security_status_error, nil)
      |> assign(:security_secret_refs, [])
      |> assign(:security_secret_error, nil)
      |> assign(:security_secret_form, empty_security_secret_form())
      |> assign(:security_secret_lifecycle_audits, [])
      |> assign(:security_secret_audit_error, nil)
      |> assign(:security_provider_rotation_error, nil)
      |> assign(:security_provider_rotation_report, nil)
      |> assign(:security_provider_rotation_form, empty_security_provider_rotation_form())
      |> assign(:secret_scope_options, @secret_scope_options)
      |> assign(:provider_rotation_options, SecretRefs.provider_rotation_options())
      |> stream(:repos, [], reset: true)
      |> load_repos()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = Map.get(params, "tab", "github")

    socket =
      socket
      |> assign(:active_tab, tab)
      |> maybe_load_settings_tab(tab)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      active_area={:settings}
      area_panel={if @active_tab == "github", do: JidoCodeWeb.AreaPanels.panel_for(:settings), else: nil}
    >
      <.subject_tree_shell
        id="settings-shell"
        breadcrumbs={settings_breadcrumbs(assigns)}
        parent_subjects={[]}
        child_subjects={settings_nav_items(assigns)}
        child_nav_id="settings-nav"
        child_nav_label="Settings sections"
        child_nav_heading="Settings"
        child_nav_summary="Choose the operator setting you want to inspect or update."
        sidebar_id="settings-sidebar"
        content_id="settings-content"
      >
        <.subject_pane pane={settings_selected_pane(assigns)}>
          <section class="space-y-6">
            <.vue_surface
              id="settings-overview-widget"
              component="SettingsOverviewWidget"
              socket={@socket}
              props={
                %{
                  activeTab: @active_tab,
                  cards: settings_overview_cards(assigns),
                  activeTabSummary: settings_active_tab_summary(assigns),
                  openAddRepoVisible: @active_tab == "github"
                }
              }
              events={%{"openAddRepo" => "open_add_modal"}}
            />

            <%= case @active_tab do %>
              <% "github" -> %>
                <.github_tab repos={@streams.repos} show_add_modal={@show_add_modal} form={@form} />
              <% "agents" -> %>
                <.agents_tab />
              <% "account" -> %>
                <.account_tab />
              <% "auth" -> %>
                <.auth_integrations_tab
                  provider_login_cards={@provider_login_cards}
                  github_service_report={@github_service_report}
                  github_service_secret_refs={@github_service_secret_refs}
                  operator_auth_allowlist_options={@operator_auth_allowlist_options}
                />
              <% "security" -> %>
                <.security_tab
                  security_tokens={@security_tokens}
                  security_api_keys={@security_api_keys}
                  security_audit_events={@security_audit_events}
                  security_revocation_error={@security_revocation_error}
                  security_status_error={@security_status_error}
                  security_secret_refs={@security_secret_refs}
                  security_secret_error={@security_secret_error}
                  security_secret_form={@security_secret_form}
                  security_secret_lifecycle_audits={@security_secret_lifecycle_audits}
                  security_secret_audit_error={@security_secret_audit_error}
                  secret_scope_options={@secret_scope_options}
                  security_provider_rotation_error={@security_provider_rotation_error}
                  security_provider_rotation_report={@security_provider_rotation_report}
                  security_provider_rotation_form={@security_provider_rotation_form}
                  provider_rotation_options={@provider_rotation_options}
                />
              <% _ -> %>
                <.github_tab repos={@streams.repos} show_add_modal={@show_add_modal} form={@form} />
            <% end %>
          </section>

          <:footer_actions :if={@active_tab == "github"}>
            <button
              id="settings-github-open-add-modal"
              type="button"
              phx-click="open_add_modal"
              class="btn btn-primary"
            >
              <.icon name="hero-plus" class="mr-1 size-4" /> Add Repository
            </button>
          </:footer_actions>

          <:footer_actions :if={@active_tab == "auth"}>
            <button
              id="settings-auth-refresh-github-service-checks"
              type="button"
              phx-click="refresh_github_service_checks"
              class="btn btn-outline btn-sm"
            >
              Refresh GitHub Validation
            </button>
          </:footer_actions>
        </.subject_pane>
      </.subject_tree_shell>

      <div
        :if={@show_add_modal}
        id="add-repo-modal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-base-content/40 p-4"
      >
        <div class="w-full max-w-lg rounded-lg border border-base-300 bg-base-100 p-6 shadow-xl">
          <div class="flex items-center justify-between gap-4">
            <h2 class="text-lg font-semibold">Add GitHub Repository</h2>
            <button type="button" class="btn btn-sm btn-ghost" phx-click="close_add_modal">
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
          <.form for={@form} phx-change="validate" phx-submit="save_repo" class="mt-4 space-y-4">
            <div
              :if={@repo_save_error}
              id="settings-github-repo-save-error"
              class="rounded-lg border border-warning/50 bg-warning/10 p-4 text-sm"
            >
              {@repo_save_error}
            </div>
            <.input
              field={@form[:owner]}
              type="text"
              label="Owner"
              placeholder="e.g., agentjido"
            />
            <.input
              field={@form[:name]}
              type="text"
              label="Repository Name"
              placeholder="e.g., jido"
            />
            <p class="text-sm text-base-content/60">
              This imports the repository into the managed-repository control plane. Webhook
              secrets remain managed in Security settings via encrypted SecretRef entries.
            </p>
            <div class="mt-6 flex justify-end gap-3">
              <button type="button" class="btn btn-outline" phx-click="close_add_modal">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary">
                Add Repository
              </button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp github_tab(assigns) do
    ~H"""
    <div>
      <div class="mb-6">
        <h2 class="text-xl font-semibold">GitHub Repositories</h2>
        <p class="mt-1 text-sm text-base-content/70">
          Manage repositories connected to your agent workflows.
        </p>
      </div>

      <div class="space-y-4" id="repos-list" phx-update="stream">
        <div
          :for={{dom_id, repo} <- @repos}
          id={dom_id}
          class="rounded-lg border border-base-300 bg-base-100 p-4"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-folder" class="w-6 h-6 text-base-content/50" />
              <div>
                <p class="font-medium">{repo.full_name}</p>
                <% settings_summary = repo_settings_summary(repo.settings) %>
                <p id={"settings-github-repo-settings-#{repo.id}"} class="text-sm text-base-content/60">
                  {settings_summary.text}
                </p>
                <p
                  :if={settings_summary.security_alert?}
                  id={"settings-github-repo-security-alert-#{repo.id}"}
                  class="text-xs text-warning mt-1"
                >
                  {settings_summary.alert_message}
                </p>
              </div>
            </div>

            <div class="flex items-center gap-4">
              <button
                id={"repo-toggle-#{repo.id}"}
                type="button"
                phx-click="toggle_repo"
                phx-value-id={repo.id}
                class={[
                  "btn btn-sm min-w-24",
                  repo.enabled && "btn-success",
                  !repo.enabled && "btn-outline"
                ]}
              >
                {if repo.enabled, do: "Enabled", else: "Disabled"}
              </button>
              <button
                type="button"
                class="btn btn-outline btn-error btn-sm"
                phx-click="delete_repo"
                phx-value-id={repo.id}
                data-confirm="Are you sure you want to remove this repository?"
              >
                <.icon name="hero-trash" class="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>

        <div
          :if={Enum.empty?(Map.values(@repos))}
          class="rounded-lg border border-base-300 bg-base-100 p-6 text-center"
        >
          <.icon name="hero-inbox" class="w-12 h-12 mx-auto text-base-content/30 mb-3" />
          <p class="text-base-content/70">No repositories configured yet.</p>
          <p class="text-sm text-base-content/50 mt-1">
            Click "Add Repository" to import your first GitHub repository into the managed
            control plane.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp agents_tab(assigns) do
    ~H"""
    <div>
      <div class="mb-6">
        <h2 class="text-xl font-semibold">Agent Configuration</h2>
        <p class="text-sm text-base-content/70 mt-1">
          Configure AI agents and their behaviors
        </p>
      </div>

      <div class="rounded-lg border border-base-300 bg-base-100 p-6 text-center">
        <.icon name="hero-cpu-chip" class="w-12 h-12 mx-auto text-base-content/30 mb-3" />
        <p class="text-base-content/70">Agent settings coming soon.</p>
        <p class="text-sm text-base-content/50 mt-1">
          This section will allow you to configure agent behaviors and preferences.
        </p>
      </div>
    </div>
    """
  end

  defp account_tab(assigns) do
    ~H"""
    <div>
      <div class="mb-6">
        <h2 class="text-xl font-semibold">Account Settings</h2>
        <p class="text-sm text-base-content/70 mt-1">
          Manage your account and preferences
        </p>
      </div>

      <div class="rounded-lg border border-base-300 bg-base-100 p-6 text-center">
        <.icon name="hero-user-circle" class="w-12 h-12 mx-auto text-base-content/30 mb-3" />
        <p class="text-base-content/70">Account settings coming soon.</p>
        <p class="text-sm text-base-content/50 mt-1">
          This section will allow you to manage your profile and account preferences.
        </p>
      </div>
    </div>
    """
  end

  defp auth_integrations_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h2 class="text-xl font-semibold">Auth & Integrations</h2>
        <p class="text-sm text-base-content/70 mt-1">
          Manage hosted provider login broker trust separately from deployment-local Git automation credentials.
        </p>
      </div>

      <section
        id="settings-auth-provider-login-settings"
        class="rounded-3xl border border-base-300 bg-base-100 p-8 shadow-xl"
      >
        <div class="mb-6 flex items-start justify-between gap-6">
          <div class="space-y-2">
            <p class="text-xs font-bold uppercase tracking-[0.22em] text-base-content/45">
              Operator Settings
            </p>
            <h3 class="text-2xl font-semibold text-base-content">Provider Login</h3>
            <p class="max-w-3xl text-sm leading-6 text-base-content/70">
              Configure broker trust and allowlist policy separately from deployment-local Git automation credentials.
            </p>
          </div>
          <div class="rounded-2xl border border-base-300 bg-base-200/70 px-4 py-3 text-sm text-base-content/70">
            Local email sign-in stays available even if every provider card below is disabled.
          </div>
        </div>

        <div class="grid gap-6 xl:grid-cols-3">
          <article
            :for={card <- @provider_login_cards}
            id={"settings-auth-provider-login-card-#{card.provider}"}
            class="rounded-2xl border border-base-300 bg-base-200/40 p-5"
          >
            <div class="flex items-start justify-between gap-4">
              <div>
                <h4 class="text-lg font-semibold text-base-content">{card.display_name}</h4>
                <p class="text-sm text-base-content/60">{card.provider_host}</p>
              </div>
              <span class={OperatorAuthSettings.provider_status_badge_class(card.status.tone)}>
                {card.status.label}
              </span>
            </div>

            <p class="mt-4 text-sm leading-6 text-base-content/70">{card.status.detail}</p>

            <p
              :if={card.status.missing_fields != []}
              class="mt-3 text-xs font-medium uppercase tracking-[0.18em] text-warning"
            >
              Missing: {Enum.join(card.status.missing_fields, ", ")}
            </p>

            <p class="mt-3 text-xs leading-5 text-base-content/55">{card.entrypoint_note}</p>

            <.form
              for={%{}}
              as={:provider_login}
              id={"settings-auth-provider-login-form-#{card.provider}"}
              phx-submit="save_provider_login"
              class="mt-5 space-y-3"
            >
              <input type="hidden" name="provider_login[provider]" value={card.provider} />

              <div class="grid gap-3 sm:grid-cols-2">
                <.input
                  type="checkbox"
                  name="provider_login[enabled]"
                  checked={card.enabled}
                  label="Enable provider host"
                />
                <.input
                  type="checkbox"
                  name="provider_login[login_enabled]"
                  checked={card.login_enabled}
                  label="Allow browser sign-in"
                />
              </div>

              <.input
                type="select"
                name="provider_login[allowlist_mode]"
                label="Allowlist Mode"
                value={card.allowlist_mode}
                options={@operator_auth_allowlist_options}
              />

              <.input
                type="textarea"
                name="provider_login[allowlist_values]"
                label="Allowlist Values"
                value={card.allowlist_values_text}
                rows="4"
                placeholder="One value per line or comma separated"
              />

              <div class="rounded-2xl border border-base-300 bg-base-100/70 p-4">
                <p class="text-xs font-bold uppercase tracking-[0.18em] text-base-content/45">
                  Broker Trust
                </p>
                <div class="mt-3 space-y-3">
                  <.input
                    type="url"
                    name="provider_login[broker_base_url]"
                    label="Broker Base URL"
                    value={card.broker_base_url}
                    placeholder="https://broker.example.com"
                  />
                  <.input
                    type="text"
                    name="provider_login[broker_issuer]"
                    label="Broker Issuer"
                    value={card.broker_issuer}
                    placeholder="https://broker.example.com"
                  />
                  <.input
                    type="text"
                    name="provider_login[broker_audience]"
                    label="Broker Audience"
                    value={card.broker_audience}
                    placeholder="jido-code"
                  />
                </div>
              </div>

              <button type="submit" class="btn btn-primary btn-block">
                Save {card.display_name} Login Settings
              </button>
            </.form>
          </article>
        </div>
      </section>

      <section
        id="settings-auth-git-provider-integrations"
        class="rounded-3xl border border-base-300 bg-base-100 p-8 shadow-xl"
      >
        <div class="mb-6 flex items-start gap-6">
          <div class="space-y-2">
            <h3 class="text-2xl font-semibold text-base-content">Git Provider Integrations</h3>
            <p class="max-w-3xl text-sm leading-6 text-base-content/70">
              Deployment-local Git automation credentials stay separate from provider-login broker trust. GitHub App is preferred, PAT is fallback, and GitLab or Bitbucket remain placeholders for now.
            </p>
          </div>
        </div>

        <div class="grid gap-6 xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
          <article class="rounded-2xl border border-base-300 bg-base-200/40 p-5">
            <div class="flex items-start justify-between gap-4">
              <div>
                <h4 class="text-lg font-semibold text-base-content">GitHub Service Integration</h4>
                <p class="text-sm text-base-content/60">
                  Deployment-local automation credentials and repository access validation
                </p>
              </div>
              <span class={OperatorAuthSettings.integration_status_badge_class(@github_service_report.status)}>
                {OperatorAuthSettings.integration_status_label(@github_service_report.status)}
              </span>
            </div>

            <div id="settings-auth-github-service-status" class="mt-4 space-y-4">
              <p class="text-sm leading-6 text-base-content/70">
                {OperatorAuthSettings.github_service_summary(@github_service_report)}
              </p>

              <p class="text-xs uppercase tracking-[0.18em] text-base-content/45">
                Last checked: {OperatorAuthSettings.format_datetime(@github_service_report.checked_at)}
              </p>

              <div class="space-y-3">
                <div
                  :for={path_result <- @github_service_report.paths}
                  id={"settings-auth-github-service-path-#{path_result.path}"}
                  class="rounded-2xl border border-base-300 bg-base-100/70 p-4"
                >
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <p class="font-medium text-base-content">{path_result.name}</p>
                      <p class="mt-1 text-sm text-base-content/65">{path_result.detail}</p>
                    </div>
                    <span class={OperatorAuthSettings.integration_status_badge_class(path_result.status)}>
                      {OperatorAuthSettings.integration_status_label(path_result.status)}
                    </span>
                  </div>

                  <p class="mt-3 text-xs uppercase tracking-[0.18em] text-base-content/45">
                    Repository access: {OperatorAuthSettings.repository_access_label(path_result.repository_access)}
                  </p>

                  <p
                    :if={path_result.missing_repositories != []}
                    class="mt-2 text-sm text-warning"
                  >
                    Missing repositories: {Enum.join(path_result.missing_repositories, ", ")}
                  </p>

                  <p class="mt-2 text-sm text-base-content/70">
                    Remediation: {path_result.remediation}
                  </p>
                </div>
              </div>
            </div>
          </article>

          <div class="space-y-6">
            <article
              id="settings-auth-github-service-secret-refs"
              class="rounded-2xl border border-base-300 bg-base-200/40 p-5"
            >
              <h4 class="text-lg font-semibold text-base-content">Deployment-Local Secrets</h4>
              <p class="mt-2 text-sm leading-6 text-base-content/70">
                These secret refs back GitHub automation. They are not stored in the provider-login broker config.
              </p>

              <div class="mt-4 space-y-2 text-sm text-base-content/75">
                <p :for={{credential, secret_ref} <- @github_service_secret_refs}>
                  <span class="font-medium">{OperatorAuthSettings.service_credential_label(credential)}:</span>
                  <code class="ml-2 rounded bg-base-300/70 px-2 py-1 text-xs">{secret_ref}</code>
                </p>
              </div>
            </article>

            <article class="rounded-2xl border border-base-300 bg-base-200/40 p-5">
              <h4 class="text-lg font-semibold text-base-content">Future Providers</h4>
              <div class="mt-3 space-y-3 text-sm text-base-content/70">
                <div class="rounded-2xl border border-base-300 bg-base-100/70 p-4">
                  <p class="font-medium text-base-content">GitLab</p>
                  <p class="mt-1">
                    Login config is modeled, but GitLab service automation is still a named placeholder adapter.
                  </p>
                </div>
                <div class="rounded-2xl border border-base-300 bg-base-100/70 p-4">
                  <p class="font-medium text-base-content">Bitbucket</p>
                  <p class="mt-1">
                    Login config is modeled, but Bitbucket service automation is still a named placeholder adapter.
                  </p>
                </div>
              </div>
            </article>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp security_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h2 class="text-xl font-semibold">Security Controls</h2>
        <p class="text-sm text-base-content/70 mt-1">
          Review token/key expiry, revoke compromised credentials, and capture revocation audit timestamps.
        </p>
      </div>

      <div
        :if={@security_status_error}
        id="settings-security-status-error"
        class="rounded-lg border border-warning/50 bg-warning/10 p-4"
      >
        <p id="settings-security-status-error-type" class="text-sm font-medium">
          Typed error: {@security_status_error.error_type}
        </p>
        <p id="settings-security-status-error-message" class="text-sm mt-1">
          {@security_status_error.message}
        </p>
        <p id="settings-security-status-error-recovery" class="text-sm mt-1">
          {@security_status_error.recovery_instruction}
        </p>
      </div>

      <div
        :if={@security_revocation_error}
        id="settings-security-revocation-error"
        class="rounded-lg border border-warning/50 bg-warning/10 p-4"
      >
        <p id="settings-security-revocation-error-type" class="text-sm font-medium">
          Typed error: {@security_revocation_error.error_type}
        </p>
        <p id="settings-security-revocation-error-message" class="text-sm mt-1">
          {@security_revocation_error.message}
        </p>
        <p id="settings-security-revocation-recovery" class="text-sm mt-1">
          {@security_revocation_error.recovery_instruction}
        </p>
      </div>

      <div id="settings-security-secret-refs" class="rounded-lg border border-base-300 bg-base-100 p-4">
        <div class="space-y-4">
          <div>
            <h3 class="text-lg font-semibold">Operational Secret References</h3>
            <p class="text-sm text-base-content/70">
              Persist operational values as encrypted SecretRef ciphertext while keeping metadata queryable.
            </p>
          </div>

          <div
            :if={@security_secret_error}
            id="settings-security-secret-error"
            class="rounded-lg border border-warning/50 bg-warning/10 p-4"
          >
            <p id="settings-security-secret-error-type" class="text-sm font-medium">
              Typed error: {@security_secret_error.error_type}
            </p>
            <p id="settings-security-secret-error-message" class="text-sm mt-1">
              {@security_secret_error.message}
            </p>
            <p id="settings-security-secret-error-recovery" class="text-sm mt-1">
              {@security_secret_error.recovery_instruction}
            </p>
          </div>

          <.form
            id="settings-security-secret-form"
            for={@security_secret_form}
            phx-submit="save_security_secret_ref"
            class="grid gap-4 md:grid-cols-2"
          >
            <.input
              id="settings-security-secret-scope"
              field={@security_secret_form[:scope]}
              type="select"
              options={@secret_scope_options}
              label="Scope"
            />
            <.input
              id="settings-security-secret-name"
              field={@security_secret_form[:name]}
              type="text"
              label="Name"
              placeholder="github/webhook_secret"
            />
            <.input
              id="settings-security-secret-value"
              field={@security_secret_form[:value]}
              type="password"
              label="Secret Value"
              placeholder="Never shown after save"
            />

            <div class="md:col-span-2">
              <button id="settings-security-secret-save" type="submit" class="btn btn-primary">
                Save SecretRef
              </button>
            </div>
          </.form>

          <div id="settings-security-secret-metadata" class="space-y-3">
            <div
              :if={Enum.empty?(@security_secret_refs)}
              id="settings-security-secret-empty"
              class="rounded-lg border border-base-300 bg-base-100 p-4"
            >
              No SecretRef metadata stored yet.
            </div>

            <div
              :for={secret <- @security_secret_refs}
              id={"settings-security-secret-#{secret.id}"}
              class="rounded-lg border border-base-300 bg-base-100 p-4"
            >
              <div class="space-y-3">
                <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                  <div>
                    <dt class="text-xs uppercase text-base-content/60">Scope</dt>
                    <dd id={"settings-security-secret-scope-value-#{secret.id}"} class="font-medium">
                      {secret.scope}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs uppercase text-base-content/60">Name</dt>
                    <dd id={"settings-security-secret-name-value-#{secret.id}"} class="font-medium">
                      {secret.name}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs uppercase text-base-content/60">Source</dt>
                    <dd id={"settings-security-secret-source-value-#{secret.id}"} class="font-medium">
                      {secret.source}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs uppercase text-base-content/60">Key Version</dt>
                    <dd id={"settings-security-secret-key-version-#{secret.id}"} class="font-medium">
                      {secret.key_version}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs uppercase text-base-content/60">Last Rotated At</dt>
                    <dd id={"settings-security-secret-rotated-at-#{secret.id}"} class="font-medium">
                      {format_security_datetime(secret.last_rotated_at)}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs uppercase text-base-content/60">Expires At</dt>
                    <dd id={"settings-security-secret-expires-at-#{secret.id}"} class="font-medium">
                      {format_optional_security_datetime(secret.expires_at)}
                    </dd>
                  </div>
                </dl>
                <button
                  id={"settings-security-secret-revoke-#{secret.id}"}
                  type="button"
                  class="btn btn-outline btn-error"
                  phx-click="revoke_security_secret_ref"
                  phx-value-id={secret.id}
                >
                  Revoke secret
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div
        id="settings-security-provider-rotation"
        class="rounded-lg border border-base-300 bg-base-100 p-4"
      >
        <div class="space-y-4">
          <div>
            <h3 class="text-lg font-semibold">Provider Credential Rotation</h3>
            <p class="text-sm text-base-content/70">
              Rotate provider credentials with atomic reference updates and rollback protection.
            </p>
          </div>

          <div
            :if={@security_provider_rotation_error}
            id="settings-security-provider-rotation-error"
            class="rounded-lg border border-warning/50 bg-warning/10 p-4"
          >
            <p id="settings-security-provider-rotation-error-type" class="text-sm font-medium">
              Typed error: {@security_provider_rotation_error.error_type}
            </p>
            <p id="settings-security-provider-rotation-error-message" class="text-sm mt-1">
              {@security_provider_rotation_error.message}
            </p>
            <p id="settings-security-provider-rotation-error-recovery" class="text-sm mt-1">
              {@security_provider_rotation_error.recovery_instruction}
            </p>
          </div>

          <.form
            id="settings-security-provider-rotation-form"
            for={@security_provider_rotation_form}
            phx-submit="rotate_security_provider_credential"
            class="grid gap-4 md:grid-cols-2"
          >
            <.input
              id="settings-security-provider-rotation-provider"
              field={@security_provider_rotation_form[:provider]}
              type="select"
              options={@provider_rotation_options}
              label="Provider"
            />
            <.input
              id="settings-security-provider-rotation-value"
              field={@security_provider_rotation_form[:value]}
              type="password"
              label="New credential value"
              placeholder="Never shown after rotation"
            />
            <div class="md:col-span-2">
              <button id="settings-security-provider-rotation-submit" type="submit" class="btn btn-primary">
                Rotate provider credential
              </button>
            </div>
          </.form>

          <div
            :if={@security_provider_rotation_report}
            id="settings-security-provider-rotation-report"
            class="rounded-lg border border-base-300 bg-base-100 p-4"
          >
            <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div>
                <dt class="text-xs uppercase text-base-content/60">Provider</dt>
                <dd id="settings-security-provider-rotation-provider-value" class="font-medium">
                  {@security_provider_rotation_report.provider}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Credential Name</dt>
                <dd id="settings-security-provider-rotation-name-value" class="font-medium">
                  {@security_provider_rotation_report.name}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Before Version</dt>
                <dd id="settings-security-provider-rotation-before-version" class="font-medium">
                  {@security_provider_rotation_report.before.key_version}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Before Verification</dt>
                <dd id="settings-security-provider-rotation-before-status" class="font-medium">
                  {provider_rotation_verification_label(@security_provider_rotation_report.before.verification.status)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">After Version</dt>
                <dd id="settings-security-provider-rotation-after-version" class="font-medium">
                  {@security_provider_rotation_report.after.key_version}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">After Verification</dt>
                <dd id="settings-security-provider-rotation-after-status" class="font-medium">
                  {provider_rotation_verification_label(@security_provider_rotation_report.after.verification.status)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Rollback</dt>
                <dd id="settings-security-provider-rotation-rollback-status" class="font-medium">
                  {provider_rotation_rollback_label(@security_provider_rotation_report.rollback_performed)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Continuity Alarm</dt>
                <dd id="settings-security-provider-rotation-continuity-alarm" class="font-medium">
                  {provider_rotation_alarm_label(@security_provider_rotation_report.continuity_alarm)}
                </dd>
              </div>
            </dl>
          </div>
        </div>
      </div>

      <div id="settings-security-secret-audit-log" class="rounded-lg border border-base-300 bg-base-100 p-4">
        <div class="space-y-3">
          <h3 class="text-lg font-semibold">Secret Lifecycle Audit</h3>

          <div
            :if={@security_secret_audit_error}
            id="settings-security-secret-audit-error"
            class="rounded-lg border border-warning/50 bg-warning/10 p-4"
          >
            <p id="settings-security-secret-audit-error-type" class="text-sm font-medium">
              Typed error: {@security_secret_audit_error.error_type}
            </p>
            <p id="settings-security-secret-audit-error-message" class="text-sm mt-1">
              {@security_secret_audit_error.message}
            </p>
            <p id="settings-security-secret-audit-error-recovery" class="text-sm mt-1">
              {@security_secret_audit_error.recovery_instruction}
            </p>
          </div>

          <ul class="space-y-2">
            <li
              :for={audit <- @security_secret_lifecycle_audits}
              id={"settings-security-secret-audit-entry-#{audit.id}"}
              class="text-sm"
            >
              {security_secret_lifecycle_audit_message(audit)}
            </li>
          </ul>

          <p :if={Enum.empty?(@security_secret_lifecycle_audits)} class="text-sm text-base-content/60">
            No secret lifecycle events recorded yet.
          </p>
        </div>
      </div>

      <div id="settings-security-token-status" class="space-y-3">
        <h3 class="text-lg font-semibold">Session Tokens</h3>

        <div
          :if={Enum.empty?(@security_tokens)}
          id="settings-security-token-empty"
          class="rounded-lg border border-base-300 bg-base-100 p-4"
        >
          No owner session tokens found.
        </div>

        <div
          :for={token <- @security_tokens}
          id={"settings-security-token-#{token.id}"}
          class="rounded-lg border border-base-300 bg-base-100 p-4"
        >
          <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div>
                <dt class="text-xs uppercase text-base-content/60">Status</dt>
                <dd id={"settings-security-token-status-#{token.id}"} class="font-medium">
                  {security_status_label(token.status)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Purpose</dt>
                <dd id={"settings-security-token-purpose-#{token.id}"} class="font-medium">
                  {token.purpose}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Expires At</dt>
                <dd id={"settings-security-token-expires-at-#{token.id}"} class="font-medium">
                  {format_security_datetime(token.expires_at)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Revoked At</dt>
                <dd id={"settings-security-token-revoked-at-#{token.id}"} class="font-medium">
                  {format_security_datetime(token.revoked_at)}
                </dd>
              </div>
            </dl>

            <button
              id={"settings-security-revoke-token-#{token.id}"}
              type="button"
              class="btn btn-outline btn-error"
              phx-click="revoke_security_token"
              phx-value-jti={token.id}
            >
              Revoke token
            </button>
          </div>
        </div>
      </div>

      <div id="settings-security-api-key-status" class="space-y-3">
        <h3 class="text-lg font-semibold">API Keys</h3>

        <div
          :if={Enum.empty?(@security_api_keys)}
          id="settings-security-api-key-empty"
          class="rounded-lg border border-base-300 bg-base-100 p-4"
        >
          No owner API keys found.
        </div>

        <div
          :for={api_key <- @security_api_keys}
          id={"settings-security-api-key-#{api_key.id}"}
          class="rounded-lg border border-base-300 bg-base-100 p-4"
        >
          <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div>
                <dt class="text-xs uppercase text-base-content/60">Status</dt>
                <dd id={"settings-security-api-key-status-#{api_key.id}"} class="font-medium">
                  {security_status_label(api_key.status)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">ID</dt>
                <dd id={"settings-security-api-key-id-#{api_key.id}"} class="font-medium">
                  {api_key.id}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Expires At</dt>
                <dd id={"settings-security-api-key-expires-at-#{api_key.id}"} class="font-medium">
                  {format_security_datetime(api_key.expires_at)}
                </dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Revoked At</dt>
                <dd id={"settings-security-api-key-revoked-at-#{api_key.id}"} class="font-medium">
                  {format_security_datetime(api_key.revoked_at)}
                </dd>
              </div>
            </dl>

            <button
              id={"settings-security-revoke-api-key-#{api_key.id}"}
              type="button"
              class="btn btn-outline btn-error"
              phx-click="revoke_security_api_key"
              phx-value-id={api_key.id}
            >
              Revoke API key
            </button>
          </div>
        </div>
      </div>

      <div id="settings-security-audit-log" class="rounded-lg border border-base-300 bg-base-100 p-4">
        <h3 class="text-lg font-semibold mb-3">Revocation Audit</h3>
        <ul class="space-y-2">
          <li
            :for={audit <- @security_audit_events}
            id={"settings-security-audit-entry-#{audit.event_id}"}
            class="text-sm"
          >
            {security_audit_message(audit)}
          </li>
        </ul>
        <p :if={Enum.empty?(@security_audit_events)} class="text-sm text-base-content/60">
          No revocation events recorded in this browser session.
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_repo", %{"id" => id}, socket) do
    actor = settings_actor(socket)
    repo = RepoStore.get_by_id!(id, actor: actor)

    result =
      if repo.enabled do
        RepoStore.disable(repo, actor: actor)
      else
        RepoStore.enable(repo, actor: actor)
      end

    case result do
      {:ok, updated_repo} ->
        {:noreply,
         socket
         |> stream_insert(:repos, updated_repo)
         |> load_repos()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update repository")}
    end
  end

  def handle_event("delete_repo", %{"id" => id}, socket) do
    actor = settings_actor(socket)
    repo = RepoStore.get_by_id!(id, actor: actor)

    case RepoStore.delete(repo, actor: actor) do
      :ok ->
        {:noreply,
         socket
         |> stream_delete(:repos, repo)
         |> load_repos()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete repository")}
    end
  end

  def handle_event("open_add_modal", _params, socket) do
    {:noreply, assign(socket, show_add_modal: true, form: repo_form(), repo_save_error: nil)}
  end

  def handle_event("close_add_modal", _params, socket) do
    {:noreply, assign(socket, show_add_modal: false, form: nil, repo_save_error: nil)}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, form: repo_form(params), repo_save_error: nil)}
  end

  def handle_event("save_repo", %{"form" => params}, socket) do
    with {:ok, repo_identity} <- normalize_repo_identity(params),
         {:ok, import_report} <- import_settings_repo(repo_identity.full_name),
         {:ok, _repo} <- ensure_settings_repo_anchor(repo_identity, settings_actor(socket)) do
      socket =
        socket
        |> load_repos()
        |> assign(show_add_modal: false, form: nil, repo_save_error: nil)
        |> put_flash(:info, settings_repo_import_success_message(import_report))

      {:noreply, socket}
    else
      {:error, {_kind, message}} ->
        {:noreply, assign(socket, form: repo_form(params), repo_save_error: message)}
    end
  end

  def handle_event("save_provider_login", %{"provider_login" => params}, socket) do
    with {:ok, provider} <- OperatorAuthSettings.save_provider_login(params) do
      {:noreply,
       socket
       |> put_flash(:info, "Saved #{OperatorAuthSettings.provider_display_name(provider)} provider login settings.")
       |> load_operator_auth_settings()}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, inspect(error))}
    end
  end

  def handle_event("refresh_github_service_checks", _params, socket) do
    {:noreply, load_operator_auth_settings(socket)}
  end

  def handle_event("save_security_secret_ref", %{"security_secret" => params}, socket) do
    case SecretRefs.persist_operational_secret(Map.put(params, "actor", current_actor(socket))) do
      {:ok, _secret_metadata} ->
        socket =
          socket
          |> assign(:security_secret_error, nil)
          |> assign(:security_secret_form, empty_security_secret_form())
          |> load_security_secret_metadata()
          |> load_security_secret_lifecycle_audits()
          |> put_flash(:info, "SecretRef saved.")

        {:noreply, socket}

      {:error, typed_error} ->
        socket =
          socket
          |> assign(:security_secret_error, typed_error)
          |> assign(
            :security_secret_form,
            empty_security_secret_form(%{
              "scope" => Map.get(params, "scope", "integration"),
              "name" => Map.get(params, "name", ""),
              "value" => ""
            })
          )

        {:noreply, socket}
    end
  end

  def handle_event("rotate_security_provider_credential", %{"security_provider_rotation" => params}, socket) do
    case SecretRefs.rotate_provider_credential(Map.put(params, "actor", current_actor(socket))) do
      {:ok, rotation_report} ->
        socket =
          socket
          |> assign(:security_provider_rotation_error, nil)
          |> assign(:security_provider_rotation_report, rotation_report)
          |> assign(
            :security_provider_rotation_form,
            empty_security_provider_rotation_form(%{
              "provider" => Map.get(params, "provider", "anthropic"),
              "value" => ""
            })
          )
          |> load_security_secret_metadata()
          |> load_security_secret_lifecycle_audits()
          |> put_flash(:info, "Provider credential rotated.")

        {:noreply, socket}

      {:error, typed_error} ->
        socket =
          socket
          |> assign(:security_provider_rotation_error, typed_error)
          |> assign(:security_provider_rotation_report, Map.get(typed_error, :rotation_report))
          |> assign(
            :security_provider_rotation_form,
            empty_security_provider_rotation_form(%{
              "provider" => Map.get(params, "provider", "anthropic"),
              "value" => ""
            })
          )
          |> load_security_secret_metadata()
          |> load_security_secret_lifecycle_audits()

        {:noreply, socket}
    end
  end

  def handle_event("revoke_security_secret_ref", %{"id" => secret_ref_id}, socket) do
    params = %{"id" => secret_ref_id, "actor" => current_actor(socket)}

    case SecretRefs.revoke_operational_secret(params) do
      {:ok, _revoked_secret} ->
        socket =
          socket
          |> assign(:security_secret_error, nil)
          |> load_security_secret_metadata()
          |> load_security_secret_lifecycle_audits()
          |> put_flash(:info, "SecretRef revoked.")

        {:noreply, socket}

      {:error, typed_error} ->
        {:noreply, assign(socket, :security_secret_error, typed_error)}
    end
  end

  def handle_event("revoke_security_token", %{"jti" => jti}, socket) do
    owner_id = current_owner_id(socket)

    case SecurityTokens.revoke_owner_token(owner_id, jti) do
      {:ok, audit_entry} ->
        socket =
          socket
          |> assign(:security_revocation_error, nil)
          |> prepend_security_audit_event(audit_entry)
          |> load_security_status()
          |> put_flash(:info, "Token revoked.")

        {:noreply, socket}

      {:error, typed_error} ->
        {:noreply, assign(socket, :security_revocation_error, typed_error)}
    end
  end

  def handle_event("revoke_security_api_key", %{"id" => api_key_id}, socket) do
    owner_id = current_owner_id(socket)

    case SecurityTokens.revoke_owner_api_key(owner_id, api_key_id) do
      {:ok, audit_entry} ->
        socket =
          socket
          |> assign(:security_revocation_error, nil)
          |> prepend_security_audit_event(audit_entry)
          |> load_security_status()
          |> put_flash(:info, "API key revoked.")

        {:noreply, socket}

      {:error, typed_error} ->
        {:noreply, assign(socket, :security_revocation_error, typed_error)}
    end
  end

  defp maybe_load_settings_tab(socket, "auth") do
    load_operator_auth_settings(socket)
  end

  defp maybe_load_settings_tab(socket, "security") do
    socket
    |> load_security_status()
    |> load_security_secret_metadata()
    |> load_security_secret_lifecycle_audits()
  end

  defp maybe_load_settings_tab(socket, _tab), do: socket

  defp load_operator_auth_settings(socket) do
    assign(socket, OperatorAuthSettings.state(socket.assigns[:current_user]))
  end

  defp load_repos(socket) do
    repos =
      case RepoStore.list(actor: settings_actor(socket)) do
        {:ok, repos} -> repos
        {:error, _reason} -> []
      end

    socket
    |> assign(:repo_count, length(repos))
    |> assign(:enabled_repo_count, Enum.count(repos, &Map.get(&1, :enabled, false)))
    |> stream(:repos, repos, reset: true)
  end

  defp import_settings_repo(full_name) when is_binary(full_name) do
    case ProjectImport.run(nil, full_name, %{}) do
      %{status: :ready} = report ->
        {:ok, report}

      report ->
        {:error, {:import_failed, settings_repo_import_error_message(report)}}
    end
  end

  defp import_settings_repo(_full_name) do
    {:error, {:validation, "Enter a valid GitHub repository owner and name."}}
  end

  defp ensure_settings_repo_anchor(%{full_name: full_name} = repo_identity, actor) do
    case RepoStore.get_by_full_name(full_name, actor: actor) do
      {:ok, repo} ->
        {:ok, repo}

      _other ->
        create_settings_repo_anchor(repo_identity, actor)
    end
  end

  defp create_settings_repo_anchor(%{owner: owner, name: name}, actor) do
    case RepoStore.create(%{owner: owner, name: name}, actor: actor) do
      {:ok, repo} ->
        {:ok, repo}

      {:error, reason} ->
        case RepoStore.get_by_full_name("#{owner}/#{name}", actor: actor) do
          {:ok, repo} ->
            {:ok, repo}

          _other ->
            {:error,
             {:anchor_failed,
              "Repository import succeeded, but the settings GitHub anchor could not be saved (#{inspect(reason)})."}}
        end
    end
  end

  defp repo_form(params \\ %{}) do
    params
    |> Map.put_new("owner", "")
    |> Map.put_new("name", "")
    |> to_form(as: :form)
  end

  defp normalize_repo_identity(params) when is_map(params) do
    owner =
      params
      |> Map.get("owner")
      |> normalize_optional_string()

    name =
      params
      |> Map.get("name")
      |> normalize_optional_string()

    case {owner, name} do
      {owner, name} when is_binary(owner) and is_binary(name) ->
        {:ok, %{owner: owner, name: name, full_name: "#{owner}/#{name}"}}

      _other ->
        {:error, {:validation, "Enter a valid GitHub repository owner and name."}}
    end
  end

  defp normalize_repo_identity(_params) do
    {:error, {:validation, "Enter a valid GitHub repository owner and name."}}
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value),
    do: value |> Integer.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp settings_repo_import_success_message(%{detail: detail}) when is_binary(detail), do: detail

  defp settings_repo_import_success_message(_report) do
    "Repository imported into the managed-repository control plane."
  end

  defp settings_repo_import_error_message(%{detail: detail, remediation: remediation}) do
    [detail, remediation]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
    |> case do
      "" -> "Repository import failed."
      message -> message
    end
  end

  defp settings_repo_import_error_message(%{detail: detail}) when is_binary(detail), do: detail

  defp settings_repo_import_error_message(_report), do: "Repository import failed."

  defp load_security_status(socket) do
    owner_id = current_owner_id(socket)

    case SecurityTokens.list_owner_credentials(owner_id) do
      {:ok, %{tokens: tokens, api_keys: api_keys}} ->
        socket
        |> assign(:security_tokens, tokens)
        |> assign(:security_api_keys, api_keys)
        |> assign(:security_status_error, nil)

      {:error, typed_error} ->
        socket
        |> assign(:security_tokens, [])
        |> assign(:security_api_keys, [])
        |> assign(:security_status_error, typed_error)
    end
  end

  defp prepend_security_audit_event(socket, audit_entry) do
    event =
      audit_entry
      |> Map.put(:event_id, System.unique_integer([:positive]))

    assign(socket, :security_audit_events, [event | socket.assigns.security_audit_events])
  end

  defp load_security_secret_metadata(socket) do
    case SecretRefs.list_secret_metadata() do
      {:ok, secret_refs} ->
        socket
        |> assign(:security_secret_refs, secret_refs)
        |> assign(:security_secret_error, nil)

      {:error, typed_error} ->
        socket
        |> assign(:security_secret_refs, [])
        |> assign(:security_secret_error, typed_error)
    end
  end

  defp load_security_secret_lifecycle_audits(socket) do
    case SecretRefs.list_secret_lifecycle_audits() do
      {:ok, audits} ->
        socket
        |> assign(:security_secret_lifecycle_audits, audits)
        |> assign(:security_secret_audit_error, nil)

      {:error, typed_error} ->
        socket
        |> assign(:security_secret_lifecycle_audits, [])
        |> assign(:security_secret_audit_error, typed_error)
    end
  end

  defp current_owner_id(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp current_actor(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{id: id} = user ->
        %{
          "id" => id,
          "email" => Map.get(user, :email)
        }

      _other ->
        %{}
    end
  end

  defp security_status_label(:active), do: "Active"
  defp security_status_label(:expired), do: "Expired"
  defp security_status_label(:revoked), do: "Revoked"

  defp format_security_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_security_datetime(nil), do: "Not revoked"
  defp format_security_datetime(_value), do: "Unavailable"

  defp format_optional_security_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_optional_security_datetime(nil), do: "Never"
  defp format_optional_security_datetime(_value), do: "Unavailable"

  defp empty_security_secret_form(params \\ %{}) do
    defaults = %{"scope" => "integration", "name" => "", "value" => ""}
    params = Map.merge(defaults, params)
    to_form(params, as: :security_secret)
  end

  defp empty_security_provider_rotation_form(params \\ %{}) do
    defaults = %{"provider" => "anthropic", "value" => ""}
    params = Map.merge(defaults, params)
    to_form(params, as: :security_provider_rotation)
  end

  defp security_audit_message(audit) do
    source_label =
      case Map.get(audit, :source) do
        :session_token -> "Session token"
        :api_key -> "API key"
      end

    "#{source_label} #{Map.get(audit, :id)} revoked at #{format_security_datetime(Map.get(audit, :revoked_at))}."
  end

  defp security_secret_lifecycle_audit_message(audit) do
    action = audit |> Map.get(:action_type) |> to_string() |> String.upcase()
    outcome = audit |> Map.get(:outcome_status) |> to_string()
    target = "#{Map.get(audit, :scope)}/#{Map.get(audit, :name)}"

    actor =
      case Map.get(audit, :actor_email) do
        email when is_binary(email) and email != "" -> email
        _ -> Map.get(audit, :actor_id)
      end

    "#{action} #{target} outcome=#{outcome} actor=#{actor} at #{format_security_datetime(Map.get(audit, :occurred_at))}."
  end

  defp repo_settings_summary(settings) when is_map(settings) and map_size(settings) > 0 do
    rendered_settings = inspect(Map.keys(settings))
    redaction = UiRedaction.sanitize_text(rendered_settings)

    %{
      text: redaction.text,
      security_alert?: redaction.security_alert?,
      alert_message: UiRedaction.security_alert_message(redaction.reason)
    }
  end

  defp repo_settings_summary(_settings) do
    %{
      text: "No custom settings",
      security_alert?: false,
      alert_message: nil
    }
  end

  defp provider_rotation_verification_label(:passed), do: "Passed"
  defp provider_rotation_verification_label(:failed), do: "Failed"
  defp provider_rotation_verification_label(_status), do: "Unavailable"

  defp provider_rotation_rollback_label(true), do: "Yes"
  defp provider_rotation_rollback_label(false), do: "No"

  defp provider_rotation_alarm_label(true), do: "Raised"
  defp provider_rotation_alarm_label(false), do: "None"

  defp settings_breadcrumbs(assigns) do
    [
      OperatorShell.breadcrumb(%{
        id: "settings-breadcrumb-settings",
        label: "Settings",
        patch: ~p"/settings"
      }),
      OperatorShell.breadcrumb(%{
        id: "settings-breadcrumb-current",
        label: settings_tab_nav_label(Map.get(assigns, :active_tab)),
        current?: true
      })
    ]
  end

  defp settings_nav_items(assigns) do
    active_tab = Map.get(assigns, :active_tab) || "github"

    for tab <- ~w(github agents account auth security) do
      OperatorShell.child_subject(%{
        id: tab,
        label: settings_tab_nav_label(tab),
        summary: settings_tab_summary(tab, assigns),
        pane_id: "settings-pane-#{tab}",
        selected?: active_tab == tab,
        patch: settings_tab_path(tab)
      })
    end
  end

  defp settings_selected_pane(assigns) do
    active_tab = Map.get(assigns, :active_tab) || "github"

    OperatorShell.pane(%{
      id: "settings-pane-#{active_tab}",
      title: settings_pane_title(active_tab),
      summary: settings_active_tab_summary(assigns)
    })
  end

  defp settings_overview_cards(assigns) do
    [
      %{
        id: "github",
        label: "GitHub repos",
        value: Integer.to_string(Map.get(assigns, :repo_count, 0)),
        detail: "#{Map.get(assigns, :enabled_repo_count, 0)} enabled for operator workflows",
        active: Map.get(assigns, :active_tab) == "github"
      },
      %{
        id: "agents",
        label: "Agent config",
        value: "Soon",
        detail: "Agent behavior remains server-owned while the settings shell evolves.",
        active: Map.get(assigns, :active_tab) == "agents"
      },
      %{
        id: "account",
        label: "Account",
        value: "LiveView",
        detail: "Identity and session preferences still live in the routed host shell.",
        active: Map.get(assigns, :active_tab) == "account"
      },
      %{
        id: "auth",
        label: "Auth & integrations",
        value: auth_overview_value(assigns),
        detail: auth_overview_detail(assigns),
        active: Map.get(assigns, :active_tab) == "auth"
      },
      %{
        id: "security",
        label: "Security",
        value: security_overview_value(assigns),
        detail: security_overview_detail(assigns),
        active: Map.get(assigns, :active_tab) == "security"
      }
    ]
  end

  defp settings_active_tab_summary(assigns) do
    case Map.get(assigns, :active_tab) do
      "github" ->
        "#{Map.get(assigns, :repo_count, 0)} GitHub repo(s) connected, with #{Map.get(assigns, :enabled_repo_count, 0)} currently enabled for workflow execution."

      "agents" ->
        "Agent configuration remains an incremental adoption surface; richer client composition does not change server-owned policy or execution defaults."

      "account" ->
        "Account preferences stay routed through LiveView while this overview surfaces the active operator context."

      "auth" ->
        "Provider login broker trust and GitHub automation readiness stay grouped on this settings-owned authenticated surface."

      "security" ->
        "Security controls currently expose #{security_credential_count(assigns)} governed credential or secret record(s) in the active operator context."

      _other ->
        "Settings overview keeps the route in LiveView while grouping the active operator snapshot for faster scanning."
    end
  end

  defp security_overview_value(assigns) do
    if Map.get(assigns, :active_tab) == "security" do
      Integer.to_string(security_credential_count(assigns))
    else
      "Load tab"
    end
  end

  defp auth_overview_value(assigns) do
    if Map.get(assigns, :active_tab) == "auth" do
      assigns
      |> Map.get(:github_service_report, %{})
      |> Map.get(:status, :not_configured)
      |> OperatorAuthSettings.integration_status_label()
    else
      "Open tab"
    end
  end

  defp auth_overview_detail(assigns) do
    if Map.get(assigns, :active_tab) == "auth" do
      "#{length(Map.get(assigns, :provider_login_cards, []))} provider host(s) modeled, #{length(Map.get(assigns, :github_service_secret_refs, []))} deployment-local Git secret ref(s) listed."
    else
      "Open Auth & Integrations to manage provider login broker trust and GitHub automation readiness."
    end
  end

  defp security_overview_detail(assigns) do
    if Map.get(assigns, :active_tab) == "security" do
      "#{length(Map.get(assigns, :security_secret_refs, []))} secret ref(s), #{length(Map.get(assigns, :security_tokens, []))} session token(s), #{length(Map.get(assigns, :security_api_keys, []))} API key(s)."
    else
      "Open Security to load governed credentials, revocations, and secret metadata."
    end
  end

  defp security_credential_count(assigns) do
    length(Map.get(assigns, :security_tokens, [])) +
      length(Map.get(assigns, :security_api_keys, [])) +
      length(Map.get(assigns, :security_secret_refs, []))
  end

  defp settings_tab_path(tab) when tab in ~w(github agents account auth security), do: ~p"/settings/#{tab}"
  defp settings_tab_path(_tab), do: ~p"/settings"

  defp settings_tab_nav_label("github"), do: "GitHub"
  defp settings_tab_nav_label("agents"), do: "Agents"
  defp settings_tab_nav_label("account"), do: "Account"
  defp settings_tab_nav_label("auth"), do: "Auth & Integrations"
  defp settings_tab_nav_label("security"), do: "Security"
  defp settings_tab_nav_label(_tab), do: "Settings"

  defp settings_pane_title("github"), do: "GitHub repositories"
  defp settings_pane_title("agents"), do: "Agent settings"
  defp settings_pane_title("account"), do: "Account settings"
  defp settings_pane_title("auth"), do: "Auth & integrations"
  defp settings_pane_title("security"), do: "Security settings"
  defp settings_pane_title(_tab), do: "Settings"

  defp settings_tab_summary("github", assigns) do
    "#{Map.get(assigns, :repo_count, 0)} connected repo(s), #{Map.get(assigns, :enabled_repo_count, 0)} enabled for operator workflows."
  end

  defp settings_tab_summary("agents", _assigns) do
    "Agent behavior remains server-owned while this route reuses the shared signed-in shell."
  end

  defp settings_tab_summary("account", _assigns) do
    "Identity and session preferences stay routed through LiveView on this operator-owned surface."
  end

  defp settings_tab_summary("auth", assigns), do: auth_overview_detail(assigns)
  defp settings_tab_summary("security", assigns), do: security_overview_detail(assigns)
  defp settings_tab_summary(_tab, _assigns), do: nil

  defp settings_actor(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{} = user ->
        Actor.operator_actor(%{
          "id" => Map.get(user, :id) || Map.get(user, "id"),
          "email" => Map.get(user, :email) || Map.get(user, "email")
        })

      _other ->
        Actor.operator_actor(%{
          "id" => "system:settings-live",
          "email" => "settings-live@system.local"
        })
    end
  end
end
