defmodule JidoCodeWeb.SetupLive do
  # covers: baseline.surface.public_entry_routes
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.product_owned_mounting_boundary
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions
  # covers: setup.onboarding.post_bootstrap_start_surface
  # covers: setup.onboarding.deployment_mode_auto_detected
  # covers: setup.onboarding.runtime_environment_selection_distinct_from_install_flavor
  # covers: setup.onboarding.runtime_environment_selection_persisted_metadata
  # covers: setup.onboarding.explicit_completion_path_to_dashboard
  # covers: setup.onboarding.deferred_integrations
  # covers: setup.onboarding.github_repository_selection_persisted_metadata
  # covers: setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback
  # covers: setup.onboarding.github_pat_capture_persisted_secret_ref
  # covers: setup.onboarding.github_pat_capture_requires_encryption_ready_secret_storage
  # covers: setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
  # covers: setup.onboarding.start_path_preference_persisted
  use JidoCodeWeb, :live_view

  alias JidoCode.Control.Actor
  alias JidoCode.GitHub.ServiceCredentials
  alias JidoCode.Setup.EnvironmentDefaults
  alias JidoCode.Setup.DeploymentMode
  alias JidoCode.Setup.GitHubCredentialChecks
  alias JidoCode.Setup.GitHubRepositoryListing
  alias JidoCode.Setup.ProjectImport
  alias JidoCode.Setup.SystemConfig
  alias JidoCode.Security.{Encryption, SecretRefs}

  @github_setup_step 7
  @start_paths [:local_repo, :github, :later]
  @runtime_environment_options [{"Cloud", "cloud"}, {"Local", "local"}]

  @type start_path :: :local_repo | :github | :later

  @impl true
  def mount(params, _session, socket) do
    diagnostic = normalize_optional_string(params["diagnostic"])

    case SystemConfig.load() do
      {:ok, %SystemConfig{} = config} ->
        route_setup(socket, config, diagnostic, false)

      {:error, %{diagnostic: load_diagnostic, onboarding_step: onboarding_step}} ->
        fallback_config = %SystemConfig{
          onboarding_completed: false,
          onboarding_step: max(onboarding_step, 3),
          onboarding_state: %{},
          default_environment: :sprite,
          workspace_root: nil
        }

        route_setup(socket, fallback_config, diagnostic || load_diagnostic, true)
    end
  end

  @impl true
  def handle_event("choose_start_path", %{"choice" => choice}, socket) do
    normalized_choice = normalize_start_path(choice)
    allowed_choices = Enum.map(socket.assigns.start_options, & &1.id)

    cond do
      socket.assigns.buttons_disabled? ->
        {:noreply, assign(socket, :save_error, "Resolve the setup state issue before saving a start path.")}

      normalized_choice not in allowed_choices ->
        {:noreply, assign(socket, :save_error, "Choose a valid way to start.")}

      true ->
        case persist_start_path(
               socket.assigns.deployment_mode,
               normalized_choice,
               socket.assigns.owner_email
             ) do
          {:ok, %SystemConfig{} = config} ->
            {:noreply,
             socket
             |> assign_start_surface(config, socket.assigns.diagnostic, false)
             |> put_flash(:info, "#{start_path_title(normalized_choice)} saved as your default start path.")}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply, assign(socket, :save_error, diagnostic)}
        end
    end
  end

  @impl true
  def handle_event("change_runtime_environment", %{"runtime_environment" => runtime_params}, socket) do
    {:noreply,
     socket
     |> assign_runtime_environment_form(runtime_params)
     |> assign(:runtime_save_error, nil)}
  end

  @impl true
  def handle_event("save_runtime_environment", %{"runtime_environment" => runtime_params}, socket) do
    runtime_report = EnvironmentDefaults.run(runtime_params)

    cond do
      socket.assigns.buttons_disabled? ->
        {:noreply,
         assign(
           socket,
           :runtime_save_error,
           "Resolve the setup state issue before saving runtime defaults."
         )}

      EnvironmentDefaults.blocked?(runtime_report) ->
        {:noreply,
         socket
         |> assign_runtime_environment_form(runtime_params)
         |> assign(:runtime_save_error, runtime_environment_error_message(runtime_report))}

      true ->
        case persist_runtime_environment(socket.assigns.deployment_mode, runtime_report) do
          {:ok, %SystemConfig{} = config} ->
            {:noreply,
             socket
             |> assign_start_surface(config, socket.assigns.diagnostic, false)
             |> put_flash(
               :info,
               "#{runtime_environment_title(runtime_report.mode)} runtime defaults saved."
             )}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply,
             socket
             |> assign_runtime_environment_form(runtime_params)
             |> assign(:runtime_save_error, diagnostic)}
        end
    end
  end

  @impl true
  def handle_event("complete_setup", _params, socket) do
    cond do
      socket.assigns.buttons_disabled? ->
        {:noreply,
         assign(
           socket,
           :save_error,
           "Resolve the setup state issue before continuing into the app."
         )}

      true ->
        case complete_setup(socket.assigns.deployment_mode, socket.assigns.selected_start_path) do
          {:ok, _config} ->
            {:noreply,
             socket
             |> put_flash(:info, "Setup complete. Optional follow-up work remains available from the dashboard.")
             |> push_navigate(to: ~p"/dashboard?onboarding=completed")}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply, assign(socket, :save_error, diagnostic)}
        end
    end
  end

  @impl true
  def handle_event("select_github_repository", params, socket) do
    selected_repository = extract_repository_selection(params)

    cond do
      socket.assigns.buttons_disabled? ->
        {:noreply,
         assign(
           socket,
           :save_error,
           "Resolve the setup state issue before saving a GitHub repository selection."
         )}

      not valid_github_repository_selection?(
        selected_repository,
        socket.assigns.github_repository_full_names
      ) ->
        {:noreply, assign(socket, :save_error, "Choose a validated GitHub repository.")}

      true ->
        case persist_github_repository_selection(selected_repository) do
          {:ok, %SystemConfig{} = config} ->
            {:noreply, assign_start_surface(socket, config, socket.assigns.diagnostic, false)}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply, assign(socket, :save_error, diagnostic)}
        end
    end
  end

  @impl true
  def handle_event("refresh_github_repository_listing", _params, socket) do
    cond do
      socket.assigns.buttons_disabled? ->
        {:noreply,
         assign(
           socket,
           :save_error,
           "Resolve the setup state issue before refreshing GitHub repositories."
         )}

      true ->
        case refresh_github_repository_listing(socket.assigns.owner_email) do
          {:ok, %SystemConfig{} = config} ->
            {:noreply,
             socket
             |> assign_start_surface(config, socket.assigns.diagnostic, false)
             |> put_flash(:info, "GitHub repository access refreshed.")}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply, assign(socket, :save_error, diagnostic)}
        end
    end
  end

  @impl true
  def handle_event("save_github_pat", %{"github_pat" => params}, socket) do
    github_pat =
      params
      |> map_get(:value, "value")
      |> normalize_optional_string()

    cond do
      socket.assigns.buttons_disabled? ->
        {:noreply,
         assign(
           socket,
           :github_pat_save_error,
           "Resolve the setup state issue before saving GitHub credentials."
         )}

      not socket.assigns.github_pat_capture_state.encryption_ready? ->
        {:noreply,
         socket
         |> assign_github_pat_form()
         |> assign(
           :github_pat_save_error,
           socket.assigns.github_pat_capture_state.encryption_preflight_detail
         )}

      is_nil(github_pat) ->
        {:noreply,
         socket
         |> assign_github_pat_form()
         |> assign(:github_pat_save_error, "Enter a GitHub PAT before saving it.")}

      true ->
        case SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: ServiceCredentials.service_secret_ref_name(:pat),
               value: github_pat,
               source: :onboarding,
               actor: current_actor(socket)
             }) do
          {:ok, _secret_metadata} ->
            case refresh_github_repository_listing(socket.assigns.owner_email) do
              {:ok, %SystemConfig{} = config} ->
                {:noreply,
                 socket
                 |> assign_start_surface(config, socket.assigns.diagnostic, false)
                 |> put_flash(
                   :info,
                   "GitHub PAT saved to encrypted deployment-local secret storage. Repository access refreshed."
                 )}

              {:error, %{diagnostic: diagnostic}} ->
                {:noreply,
                 socket
                 |> assign_github_pat_form()
                 |> assign(
                   :github_pat_save_error,
                   "GitHub PAT was saved, but repository access could not be refreshed. #{diagnostic}"
                 )}
            end

          {:error, typed_error} ->
            {:noreply,
             socket
             |> assign_github_pat_form()
             |> assign(:github_pat_save_error, secret_persistence_error_message(typed_error))}
        end
    end
  end

  @impl true
  def handle_event("import_selected_github_repository", params, socket) do
    selected_repository =
      extract_repository_selection(params) || socket.assigns.github_selected_repository

    cond do
      socket.assigns.buttons_disabled? ->
        {:noreply,
         assign(
           socket,
           :save_error,
           "Resolve the setup state issue before importing a GitHub repository."
         )}

      is_nil(selected_repository) ->
        {:noreply, assign(socket, :save_error, "Select a GitHub repository before importing it.")}

      not valid_github_repository_selection?(
        selected_repository,
        socket.assigns.github_repository_full_names
      ) ->
        {:noreply, assign(socket, :save_error, "Choose a validated GitHub repository.")}

      true ->
        case persist_github_project_import(selected_repository, socket.assigns.owner_email) do
          {:ok, %SystemConfig{} = config} ->
            project_import_report = github_project_import_report(config.onboarding_state)

            flash_kind =
              if github_project_import_ready?(project_import_report), do: :info, else: :error

            {:noreply,
             socket
             |> assign_start_surface(config, socket.assigns.diagnostic, false)
             |> put_flash(
               flash_kind,
               github_project_import_flash(project_import_report, selected_repository)
             )}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply, assign(socket, :save_error, diagnostic)}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section id="setup-start-surface" class="mx-auto w-full max-w-6xl px-6 py-10">
        <div class="grid gap-8 lg:grid-cols-[minmax(0,20rem)_minmax(0,1fr)] lg:gap-12">
          <div class="space-y-6">
            <div class="space-y-3">
              <p id="setup-eyebrow" class="text-xs font-medium uppercase tracking-[0.3em] text-base-content/60">
                Setup
              </p>
              <h1 id="setup-title" class="text-4xl font-semibold tracking-tight sm:text-5xl">
                Choose how to start
              </h1>
              <p id="setup-description" class="max-w-md text-base text-base-content/70">
                {setup_description(@deployment_mode)}
              </p>
            </div>

            <section
              id="setup-runtime-defaults-panel"
              class="space-y-4 rounded-2xl border border-base-300 bg-base-100/80 p-5"
            >
              <div class="space-y-2">
                <p class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">
                  Runtime defaults
                </p>
                <p id="setup-runtime-defaults-description" class="text-sm text-base-content/70">
                  {runtime_environment_description(@runtime_environment_mode)}
                </p>
              </div>

              <div :if={@runtime_save_error} id="setup-runtime-save-error" class="alert alert-error">
                <.icon name="hero-x-circle-mini" class="size-5" />
                <span>{@runtime_save_error}</span>
              </div>

              <.form
                id="setup-runtime-environment-form"
                for={@runtime_environment_form}
                phx-change="change_runtime_environment"
                phx-submit="save_runtime_environment"
                class="space-y-3"
              >
                <.input
                  id="setup-runtime-environment-select"
                  field={@runtime_environment_form[:mode]}
                  type="select"
                  label="Runtime environment"
                  options={@runtime_environment_options}
                />

                <.input
                  :if={@runtime_environment_mode == :local}
                  id="setup-runtime-workspace-root"
                  field={@runtime_environment_form[:workspace_root]}
                  type="text"
                  label="Workspace root"
                  placeholder="/absolute/path/to/workspaces"
                  autocomplete="off"
                />

                <button
                  id="setup-runtime-environment-save"
                  type="submit"
                  disabled={@buttons_disabled?}
                  class={[
                    "btn btn-primary w-full sm:w-auto",
                    @buttons_disabled? && "btn-disabled"
                  ]}
                >
                  Save runtime default
                </button>
              </.form>

              <dl class="space-y-4 border-t border-base-300/70 pt-4">
                <div class="space-y-1">
                  <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">
                    Install flavor
                  </dt>
                  <dd id="setup-install-flavor" class="text-sm font-medium">
                    {deployment_mode_label(@deployment_mode)}
                  </dd>
                </div>

                <div class="space-y-1">
                  <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">
                    Admin email
                  </dt>
                  <dd id="setup-owner-email" class="text-sm font-medium">
                    {@owner_email}
                  </dd>
                </div>

                <div class="space-y-1">
                  <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">
                    Saved runtime default
                  </dt>
                  <dd id="setup-saved-runtime-environment" class="text-sm font-medium">
                    {saved_runtime_environment_label(@persisted_default_environment)}
                  </dd>
                  <p id="setup-saved-runtime-note" class="text-sm text-base-content/60">
                    {saved_runtime_environment_note(
                      @persisted_default_environment,
                      @persisted_workspace_root
                    )}
                  </p>
                </div>

                <div class="space-y-1">
                  <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">
                    Saved choice
                  </dt>
                  <dd id="setup-selected-start-path" class="text-sm font-medium">
                    {selected_start_path_label(@selected_start_path)}
                  </dd>
                </div>
              </dl>
            </section>

            <p id="setup-selected-start-note" class="max-w-md text-sm text-base-content/60">
              {selected_start_path_note(@selected_start_path, @deployment_mode)}
            </p>
          </div>

          <div class="space-y-4">
            <div :if={@diagnostic} id="setup-diagnostic" class="alert alert-warning">
              <.icon name="hero-exclamation-triangle-mini" class="size-5" />
              <span>{@diagnostic}</span>
            </div>

            <div :if={@save_error} id="setup-save-error" class="alert alert-error">
              <.icon name="hero-x-circle-mini" class="size-5" />
              <span>{@save_error}</span>
            </div>

            <article
              :for={option <- @start_options}
              id={"setup-start-choice-#{option.id}"}
              class={[
                "rounded-2xl border p-5 transition",
                @selected_start_path == option.id && "border-primary/50 bg-base-100 shadow-sm",
                @selected_start_path != option.id && "border-base-300 bg-base-100/80"
              ]}
            >
              <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                <div class="space-y-2">
                  <div class="flex flex-wrap items-center gap-2">
                    <h2 class="text-xl font-semibold">{option.title}</h2>
                    <span
                      :if={choice_badge_label(option.id, @selected_start_path, option.recommended?)}
                      id={"setup-start-choice-#{option.id}-badge"}
                      class="badge badge-outline text-xs"
                    >
                      {choice_badge_label(option.id, @selected_start_path, option.recommended?)}
                    </span>
                  </div>
                  <p class="text-sm font-medium text-base-content/80">{option.summary}</p>
                  <p class="max-w-2xl text-sm text-base-content/60">{option.detail}</p>
                </div>

                <button
                  id={"setup-start-choice-#{option.id}-save"}
                  type="button"
                  phx-click="choose_start_path"
                  phx-value-choice={option.id}
                  disabled={@buttons_disabled? or @selected_start_path == option.id}
                  class={[
                    "btn btn-sm w-full sm:w-auto",
                    option.button_class,
                    (@buttons_disabled? or @selected_start_path == option.id) && "btn-disabled"
                  ]}
                >
                  {choice_button_label(option.id, @selected_start_path)}
                </button>
              </div>
            </article>

            <section
              :if={show_github_repository_selector?(@selected_start_path)}
              id="setup-github-repository-panel"
              class="space-y-4 rounded-2xl border border-base-300 bg-base-100 p-5"
            >
              <div class="space-y-2">
                <div class="flex flex-wrap items-center gap-2">
                  <h2 class="text-xl font-semibold">Choose a GitHub repository</h2>
                  <span id="setup-github-repository-badge" class="badge badge-outline text-xs">
                    Optional follow-up
                  </span>
                </div>
                <p id="setup-github-repository-summary" class="text-sm font-medium text-base-content/80">
                  {github_repository_panel_summary(
                    @github_pat_capture_state,
                    @github_repository_listing_report,
                    @github_project_import_report
                  )}
                </p>
                <p class="max-w-2xl text-sm text-base-content/60">
                  Pick one linked GitHub repository to import into the control plane now, or finish onboarding and come back later.
                </p>
              </div>

              <section
                :if={github_pat_capture_visible?(@github_pat_capture_state, @github_project_import_report)}
                id="setup-github-pat-panel"
                class="space-y-4 rounded-2xl border border-base-300/70 bg-base-200/20 p-4"
              >
                <div class="space-y-2">
                  <div class="flex flex-wrap items-center gap-2">
                    <h3 class="text-lg font-semibold">Save a GitHub PAT for this install</h3>
                    <span id="setup-github-pat-badge" class="badge badge-outline text-xs">
                      Required for repo listing
                    </span>
                  </div>
                  <p id="setup-github-pat-summary" class="text-sm text-base-content/80">
                    {@github_pat_capture_state.detail}
                  </p>
                  <p class="text-sm text-base-content/60">
                    Save a deployment-local PAT now and setup will retry repository access automatically. The token is stored as an encrypted secret for this install, not in plaintext setup state.
                  </p>
                </div>

                <div :if={@github_pat_save_error} id="setup-github-pat-save-error" class="alert alert-error">
                  <.icon name="hero-x-circle-mini" class="size-5" />
                  <span>{@github_pat_save_error}</span>
                </div>

                <div
                  :if={not @github_pat_capture_state.encryption_ready?}
                  id="setup-github-pat-encryption-preflight"
                  class="alert alert-warning"
                >
                  <.icon name="hero-exclamation-triangle-mini" class="size-5" />
                  <span>{@github_pat_capture_state.encryption_preflight_detail}</span>
                </div>

                <.form
                  id="setup-github-pat-form"
                  for={@github_pat_form}
                  phx-submit="save_github_pat"
                  class="grid gap-3 md:grid-cols-[minmax(0,1fr)_auto]"
                >
                  <.input
                    id="setup-github-pat-input"
                    field={@github_pat_form[:value]}
                    type="password"
                    label="GitHub PAT"
                    placeholder="github_pat_..."
                    autocomplete="off"
                    disabled={@buttons_disabled? or not @github_pat_capture_state.encryption_ready?}
                  />

                  <button
                    id="setup-github-pat-save"
                    type="submit"
                    disabled={@buttons_disabled? or not @github_pat_capture_state.encryption_ready?}
                    class={[
                      "btn btn-primary md:self-end",
                      (@buttons_disabled? or not @github_pat_capture_state.encryption_ready?) &&
                        "btn-disabled"
                    ]}
                  >
                    Save GitHub PAT
                  </button>
                </.form>

                <div
                  :if={@github_pat_capture_state.remediation}
                  id="setup-github-pat-remediation"
                  class="rounded-xl border border-warning/40 bg-warning/10 px-4 py-3 text-sm text-base-content/80"
                >
                  {@github_pat_capture_state.remediation}
                </div>

                <p id="setup-github-pat-note" class="text-xs text-base-content/60">
                  Stored as encrypted SecretRef {@github_pat_capture_state.secret_ref_name}.
                </p>
              </section>

              <section
                :if={github_repository_selector_deferred?(@github_pat_capture_state, @github_project_import_report)}
                id="setup-github-repository-selector-deferred"
                class="rounded-2xl border border-base-300/70 bg-base-200/20 p-4"
              >
                <div class="space-y-2">
                  <p class="text-sm font-medium text-base-content/80">
                    Repository selection unlocks after this install has a saved GitHub PAT and setup refreshes access.
                  </p>
                  <p class="text-sm text-base-content/60">
                    Once the token is saved successfully, the repository picker will appear here automatically.
                  </p>
                </div>
              </section>

              <.vue_surface
                :if={
                  not github_repository_selector_deferred?(
                    @github_pat_capture_state,
                    @github_project_import_report
                  )
                }
                id="setup-github-repository-selector"
                component="SetupGitHubRepositorySelectorWidget"
                socket={@socket}
                props={github_repository_selector_props(assigns)}
                events={
                  %{
                    "selectRepository" => "select_github_repository",
                    "refreshRepositories" => "refresh_github_repository_listing",
                    "importRepository" => "import_selected_github_repository"
                  }
                }
                fallback_title="Interactive GitHub repository picker temporarily unavailable"
                fallback_detail="Use the server-rendered selector below while the richer picker is unavailable."
              >
                <section id="setup-github-repository-selector-fallback-body" class="space-y-4">
                  <div class="grid gap-3 md:grid-cols-3">
                    <article class="rounded-xl border border-base-300/70 bg-base-200/20 p-3">
                      <p class="text-xs uppercase text-base-content/60">Repository access</p>
                      <p
                        id="setup-github-repository-fallback-status"
                        class="mt-1 text-lg font-semibold"
                      >
                        {github_listing_status_label(@github_repository_listing_report)}
                      </p>
                      <p class="mt-2 text-xs text-base-content/70">
                        {@github_repository_listing_report.detail}
                      </p>
                    </article>
                    <article class="rounded-xl border border-base-300/70 bg-base-200/20 p-3">
                      <p class="text-xs uppercase text-base-content/60">Saved selection</p>
                      <p
                        id="setup-github-repository-fallback-selection"
                        class="mt-1 text-lg font-semibold"
                      >
                        {@github_selected_repository || "Not selected"}
                      </p>
                      <p class="mt-2 text-xs text-base-content/70">
                        {github_repository_count_label(@github_repository_options)}
                      </p>
                    </article>
                    <article class="rounded-xl border border-base-300/70 bg-base-200/20 p-3">
                      <p class="text-xs uppercase text-base-content/60">Import state</p>
                      <p id="setup-github-import-fallback-status" class="mt-1 text-lg font-semibold">
                        {github_import_status_label(@github_project_import_report)}
                      </p>
                      <p class="mt-2 text-xs text-base-content/70">
                        {github_import_detail(@github_project_import_report)}
                      </p>
                    </article>
                  </div>

                  <div
                    :if={@github_repository_listing_report.remediation}
                    id="setup-github-repository-fallback-remediation"
                    class="rounded-xl border border-warning/40 bg-warning/10 px-4 py-3 text-sm text-base-content/80"
                  >
                    {@github_repository_listing_report.remediation}
                  </div>

                  <.form
                    id="setup-github-repository-selector-fallback-form"
                    for={@github_repository_selection_form}
                    phx-change="select_github_repository"
                    phx-submit="import_selected_github_repository"
                    class="space-y-4"
                  >
                    <input
                      type="hidden"
                      name="repository_selection[repository_full_name]"
                      value={@github_selected_repository || ""}
                    />

                    <div class="space-y-2">
                      <div class="flex flex-wrap items-center justify-between gap-2">
                        <p class="text-sm font-medium text-base-content/80">
                          Linked GitHub repositories
                        </p>
                        <p
                          id="setup-github-repository-fallback-count"
                          class="text-xs uppercase tracking-[0.2em] text-base-content/50"
                        >
                          {github_repository_count_label(@github_repository_options)}
                        </p>
                      </div>

                      <div
                        id="setup-github-repository-fallback-list"
                        class="max-h-[28rem] space-y-2 overflow-y-auto rounded-xl border border-base-300/70 bg-base-200/10 p-2"
                      >
                        <button
                          :for={repository <- @github_repository_options}
                          id={"setup-github-repository-fallback-option-#{repository.id}"}
                          type="button"
                          phx-click="select_github_repository"
                          phx-value-repository_full_name={repository.full_name}
                          disabled={@buttons_disabled?}
                          class={[
                            "w-full rounded-xl border p-3 text-left transition",
                            repository.full_name == @github_selected_repository &&
                              "border-primary/60 bg-primary/10",
                            repository.full_name != @github_selected_repository &&
                              "border-base-300/70 bg-base-100 hover:border-primary/40",
                            @buttons_disabled? && "opacity-60"
                          ]}
                        >
                          <div class="flex items-start justify-between gap-3">
                            <div class="space-y-1">
                              <p class="font-medium">{repository.full_name}</p>
                              <p class="text-xs uppercase tracking-[0.2em] text-base-content/50">
                                {repository.owner}
                              </p>
                            </div>
                            <span class={[
                              "badge badge-outline text-xs",
                              repository.full_name == @github_selected_repository && "badge-primary"
                            ]}>
                              {if repository.full_name == @github_selected_repository,
                                do: "Selected",
                                else: "Linked"}
                            </span>
                          </div>
                          <p class="mt-3 text-sm text-base-content/70">
                            Import {repository.name} as a managed repository and keep GitHub as its source identity.
                          </p>
                        </button>

                        <div
                          :if={@github_repository_options == []}
                          id="setup-github-repository-fallback-empty"
                          class="rounded-xl border border-dashed border-base-300/70 bg-base-100/70 px-4 py-5 text-sm text-base-content/70"
                        >
                          No linked repositories are currently available.
                        </div>
                      </div>
                    </div>

                    <div class="grid gap-3 lg:grid-cols-[auto_auto] lg:justify-end">
                      <button
                        id="setup-github-repository-fallback-refresh"
                        type="button"
                        phx-click="refresh_github_repository_listing"
                        disabled={@buttons_disabled?}
                        class={[
                          "btn btn-outline",
                          @buttons_disabled? && "btn-disabled"
                        ]}
                      >
                        Refresh repositories
                      </button>

                      <button
                        id="setup-github-repository-fallback-import"
                        type="submit"
                        disabled={
                          @buttons_disabled? or is_nil(@github_selected_repository) or
                            @github_repository_options == []
                        }
                        class={[
                          "btn btn-primary",
                          (@buttons_disabled? or is_nil(@github_selected_repository) or
                             @github_repository_options == []) && "btn-disabled"
                        ]}
                      >
                        Import selected repository
                      </button>
                    </div>
                  </.form>

                  <div
                    :if={github_project_import_ready?(@github_project_import_report)}
                    id="setup-github-import-fallback-success"
                    class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-success/40 bg-success/10 px-4 py-3"
                  >
                    <div class="space-y-1">
                      <p class="font-medium">
                        {github_import_detail(@github_project_import_report)}
                      </p>
                      <p class="text-sm text-base-content/70">
                        You can open the imported managed repository now or continue to the dashboard.
                      </p>
                    </div>

                    <.link
                      :if={github_project_path(@github_project_import_report)}
                      id="setup-github-import-fallback-open-repo"
                      navigate={github_project_path(@github_project_import_report)}
                      class="btn btn-sm btn-outline"
                    >
                      Open managed repo
                    </.link>
                  </div>
                </section>
              </.vue_surface>
            </section>

            <section id="setup-complete-panel" class="rounded-2xl border border-base-300 bg-base-100 p-5">
              <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                <div class="space-y-2">
                  <div class="flex flex-wrap items-center gap-2">
                    <h2 class="text-xl font-semibold">Continue into the app</h2>
                    <span id="setup-complete-badge" class="badge badge-outline text-xs">Available now</span>
                  </div>
                  <p class="text-sm font-medium text-base-content/80">
                    {completion_summary(@selected_start_path)}
                  </p>
                  <p class="max-w-2xl text-sm text-base-content/60">
                    GitHub setup, repo import, and runtime defaults remain editable after onboarding.
                  </p>
                </div>

                <button
                  id="setup-complete-continue"
                  type="button"
                  phx-click="complete_setup"
                  disabled={@buttons_disabled?}
                  class={[
                    "btn w-full sm:w-auto btn-primary",
                    @buttons_disabled? && "btn-disabled"
                  ]}
                >
                  Continue to dashboard
                </button>
              </div>
            </section>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp route_setup(socket, %SystemConfig{} = config, diagnostic, config_load_error?) do
    cond do
      config.onboarding_step < 3 ->
        {:ok, push_navigate(socket, to: ~p"/welcome")}

      is_nil(socket.assigns[:current_user]) ->
        {:ok, push_navigate(socket, to: ~p"/welcome")}

      config.onboarding_completed ->
        {:ok, push_navigate(socket, to: ~p"/dashboard")}

      true ->
        {:ok, assign_start_surface(socket, config, diagnostic, config_load_error?)}
    end
  end

  defp assign_start_surface(socket, %SystemConfig{} = config, diagnostic, buttons_disabled?) do
    deployment_mode = DeploymentMode.current()
    owner_email = owner_email(config.onboarding_state, socket.assigns[:current_user])
    selected_start_path = selected_start_path(config.onboarding_state)

    onboarding_state =
      if show_github_repository_selector?(selected_start_path) do
        hydrate_github_setup_state(config.onboarding_state, owner_email)
      else
        normalize_keyed_map(config.onboarding_state)
      end

    github_repository_listing_report = github_repository_listing_report(onboarding_state)
    github_project_import_report = github_project_import_report(onboarding_state)

    github_pat_capture_state =
      github_pat_capture_state(onboarding_state, github_repository_listing_report)

    github_selected_repository =
      github_selected_repository(
        onboarding_state,
        github_repository_listing_report,
        github_project_import_report
      )

    socket
    |> assign(:deployment_mode, deployment_mode)
    |> assign(:onboarding_state, onboarding_state)
    |> assign(:owner_email, owner_email)
    |> assign(:selected_start_path, selected_start_path)
    |> assign(:persisted_default_environment, config.default_environment)
    |> assign(:persisted_workspace_root, config.workspace_root)
    |> assign(:runtime_environment_options, @runtime_environment_options)
    |> assign(:start_options, start_options(deployment_mode))
    |> assign(:diagnostic, diagnostic)
    |> assign(:buttons_disabled?, buttons_disabled?)
    |> assign(:github_repository_listing_report, github_repository_listing_report)
    |> assign(:github_repository_options, GitHubRepositoryListing.repository_options(github_repository_listing_report))
    |> assign(
      :github_repository_full_names,
      GitHubRepositoryListing.repository_full_names(github_repository_listing_report)
    )
    |> assign(:github_pat_capture_state, github_pat_capture_state)
    |> assign(:github_selected_repository, github_selected_repository)
    |> assign(:github_project_import_report, github_project_import_report)
    |> assign_github_pat_form()
    |> assign_github_repository_selection_form(github_selected_repository)
    |> assign_runtime_environment_form(runtime_environment_form_values(config))
    |> assign(:github_pat_save_error, nil)
    |> assign(:runtime_save_error, nil)
    |> assign(:save_error, nil)
  end

  defp assign_github_pat_form(socket) do
    assign(socket, :github_pat_form, to_form(%{"value" => ""}, as: :github_pat))
  end

  defp assign_github_repository_selection_form(socket, selected_repository) do
    assign(
      socket,
      :github_repository_selection_form,
      to_form(
        %{"repository_full_name" => selected_repository || ""},
        as: :repository_selection
      )
    )
  end

  defp start_options(:desktop) do
    [
      %{
        id: :local_repo,
        title: "Add local repo",
        summary: "Start from a folder on this machine.",
        detail: "Use this when your source of truth already lives on your desktop.",
        recommended?: true,
        button_class: "btn-primary"
      },
      %{
        id: :github,
        title: "Connect GitHub",
        summary: "Use a hosted repository and GitHub-backed workflows.",
        detail: "Choose this if GitHub should stay your primary source-control path.",
        recommended?: false,
        button_class: "btn-outline"
      },
      %{
        id: :later,
        title: "Do this later",
        summary: "Keep moving and come back when you are ready to attach a repo.",
        detail: "This keeps the setup path simple while you finish the rest of the product wiring.",
        recommended?: false,
        button_class: "btn-ghost"
      }
    ]
  end

  defp start_options(:cloud) do
    [
      %{
        id: :github,
        title: "Connect GitHub",
        summary: "Use GitHub as the first source-control path for this install.",
        detail: "This is the cleanest starting point for a hosted deployment.",
        recommended?: true,
        button_class: "btn-primary"
      },
      %{
        id: :later,
        title: "Do this later",
        summary: "Keep moving and connect source control when you need it.",
        detail: "You can defer GitHub setup until the first feature that depends on it.",
        recommended?: false,
        button_class: "btn-outline"
      }
    ]
  end

  defp persist_start_path(deployment_mode, start_path, owner_context) do
    SystemConfig.update_onboarding_state(fn current_state ->
      current_state =
        current_state
        |> normalize_keyed_map()
        |> maybe_hydrate_github_setup_state(start_path, owner_context)

      existing_step_state = current_state |> fetch_step_state(3) |> normalize_keyed_map()

      updated_step_state =
        existing_step_state
        |> Map.put("start_path", Atom.to_string(start_path))
        |> Map.put("deployment_mode", Atom.to_string(deployment_mode))
        |> Map.put("validated_note", start_path_note(start_path))

      {:ok, Map.put(current_state, "3", updated_step_state)}
    end)
  end

  defp persist_runtime_environment(deployment_mode, runtime_report) do
    runtime_state = EnvironmentDefaults.serialize_for_state(runtime_report)
    config_updates = EnvironmentDefaults.system_config_updates(runtime_report)

    SystemConfig.update(fn %SystemConfig{} = config ->
      current_state = normalize_keyed_map(config.onboarding_state)
      existing_step_state = current_state |> fetch_step_state(3) |> normalize_keyed_map()

      updated_step_state =
        existing_step_state
        |> Map.put("deployment_mode", Atom.to_string(deployment_mode))
        |> Map.put("runtime_environment", runtime_state)
        |> Map.put("runtime_environment_note", runtime_environment_note(runtime_report))

      {:ok,
       %SystemConfig{
         config
         | default_environment: config_updates.default_environment,
           workspace_root: config_updates.workspace_root,
           onboarding_state: Map.put(current_state, "3", updated_step_state)
       }}
    end)
  end

  defp persist_github_repository_selection(selected_repository) do
    SystemConfig.update_onboarding_state(fn current_state ->
      current_state = normalize_keyed_map(current_state)
      existing_step_state = current_state |> fetch_step_state(@github_setup_step) |> normalize_keyed_map()

      updated_step_state =
        existing_step_state
        |> maybe_put_selected_repository(selected_repository)
        |> Map.put(
          "repository_selection_note",
          github_repository_selection_note(selected_repository)
        )

      {:ok, Map.put(current_state, Integer.to_string(@github_setup_step), updated_step_state)}
    end)
  end

  defp refresh_github_repository_listing(owner_context) do
    SystemConfig.update_onboarding_state(fn current_state ->
      current_state =
        current_state
        |> normalize_keyed_map()
        |> hydrate_github_setup_state(owner_context, force?: true)

      existing_step_state = current_state |> fetch_step_state(@github_setup_step) |> normalize_keyed_map()

      previous_report =
        existing_step_state
        |> map_get(:repository_listing, "repository_listing")
        |> GitHubRepositoryListing.from_state()

      listing_report = GitHubRepositoryListing.run(previous_report, current_state)

      selected_repository =
        github_selected_repository(
          current_state,
          listing_report,
          existing_step_state |> map_get(:project_import, "project_import") |> ProjectImport.from_state()
        )

      updated_step_state =
        existing_step_state
        |> Map.put(
          "repository_listing",
          GitHubRepositoryListing.serialize_for_state(listing_report)
        )
        |> maybe_put_selected_repository(selected_repository)
        |> Map.put(
          "repository_selection_note",
          github_repository_selection_note(selected_repository)
        )

      {:ok, Map.put(current_state, Integer.to_string(@github_setup_step), updated_step_state)}
    end)
  end

  defp persist_github_project_import(selected_repository, owner_context) do
    SystemConfig.update_onboarding_state(fn current_state ->
      current_state =
        current_state
        |> normalize_keyed_map()
        |> hydrate_github_setup_state(owner_context, force?: true)

      existing_step_state = current_state |> fetch_step_state(@github_setup_step) |> normalize_keyed_map()

      previous_listing =
        existing_step_state
        |> map_get(:repository_listing, "repository_listing")
        |> GitHubRepositoryListing.from_state()

      listing_report = GitHubRepositoryListing.run(previous_listing, current_state)

      previous_import =
        existing_step_state
        |> map_get(:project_import, "project_import")
        |> ProjectImport.from_state()

      project_import_report = ProjectImport.run(previous_import, selected_repository, current_state)

      updated_step_state =
        existing_step_state
        |> Map.put(
          "repository_listing",
          GitHubRepositoryListing.serialize_for_state(listing_report)
        )
        |> Map.put("project_import", ProjectImport.serialize_for_state(project_import_report))
        |> maybe_put_selected_repository(selected_repository)
        |> Map.put(
          "repository_selection_note",
          github_repository_selection_note(selected_repository)
        )

      {:ok, Map.put(current_state, Integer.to_string(@github_setup_step), updated_step_state)}
    end)
  end

  defp complete_setup(deployment_mode, selected_start_path) do
    SystemConfig.update(fn %SystemConfig{} = config ->
      current_state = normalize_keyed_map(config.onboarding_state)
      existing_step_state = current_state |> fetch_step_state(3) |> normalize_keyed_map()

      completed_start_path =
        selected_start_path ||
          existing_step_state |> map_get(:start_path, "start_path") |> normalize_start_path() ||
          :later

      updated_step_state =
        existing_step_state
        |> Map.put("start_path", Atom.to_string(completed_start_path))
        |> Map.put("deployment_mode", Atom.to_string(deployment_mode))
        |> Map.put("validated_note", start_path_note(completed_start_path))
        |> Map.put(
          "completion_note",
          "Setup completed. Optional follow-up work remains available from the signed-in app."
        )

      {:ok,
       %SystemConfig{
         config
         | onboarding_completed: true,
           onboarding_step: max(config.onboarding_step, 4),
           onboarding_state: Map.put(current_state, "3", updated_step_state)
       }}
    end)
  end

  defp github_repository_listing_report(onboarding_state) do
    onboarding_state
    |> fetch_step_state(@github_setup_step)
    |> map_get(:repository_listing, "repository_listing")
    |> GitHubRepositoryListing.from_state()
    |> case do
      nil -> GitHubRepositoryListing.run(nil, onboarding_state)
      report -> report
    end
  end

  defp github_project_import_report(onboarding_state) do
    onboarding_state
    |> fetch_step_state(@github_setup_step)
    |> map_get(:project_import, "project_import")
    |> ProjectImport.from_state()
  end

  defp github_selected_repository(onboarding_state, listing_report, project_import_report) do
    step_state = fetch_step_state(onboarding_state, @github_setup_step)

    persisted_selection =
      step_state
      |> map_get(:selected_repository, "selected_repository")
      |> normalize_optional_string()

    available_repositories = GitHubRepositoryListing.repository_full_names(listing_report)
    imported_selection = ProjectImport.selected_repository(project_import_report)

    cond do
      repository_selection_available?(persisted_selection, available_repositories) ->
        persisted_selection

      repository_selection_available?(imported_selection, available_repositories) ->
        imported_selection

      true ->
        List.first(available_repositories)
    end
  end

  defp show_github_repository_selector?(:github), do: true
  defp show_github_repository_selector?(_selected_start_path), do: false

  defp github_repository_panel_summary(github_pat_capture_state, listing_report, project_import_report) do
    cond do
      github_project_import_ready?(project_import_report) ->
        github_import_detail(project_import_report)

      github_repository_selector_deferred?(github_pat_capture_state, project_import_report) ->
        "Save a deployment-local GitHub PAT first, then repository selection will unlock automatically."

      GitHubRepositoryListing.blocked?(listing_report) ->
        listing_report.detail

      true ->
        "Pick one of your linked GitHub repositories and import it into the control plane."
    end
  end

  defp github_pat_capture_visible?(%{required?: true}, project_import_report),
    do: not github_project_import_ready?(project_import_report)

  defp github_pat_capture_visible?(_github_pat_capture_state, _project_import_report), do: false

  defp github_repository_selector_deferred?(github_pat_capture_state, project_import_report),
    do: github_pat_capture_visible?(github_pat_capture_state, project_import_report)

  defp github_repository_selector_props(assigns) do
    %{
      listingStatus: github_listing_status(assigns.github_repository_listing_report),
      listingDetail: assigns.github_repository_listing_report.detail,
      listingRemediation: assigns.github_repository_listing_report.remediation,
      listingErrorType: assigns.github_repository_listing_report.error_type,
      listingCheckedAt: checked_at_label(assigns.github_repository_listing_report.checked_at),
      repositoryCountLabel: github_repository_count_label(assigns.github_repository_options),
      repositoryOptions: Enum.map(assigns.github_repository_options, &github_repository_option_props/1),
      selectedRepository: assigns.github_selected_repository,
      importStatus: github_import_status(assigns.github_project_import_report),
      importDetail: github_import_detail(assigns.github_project_import_report),
      importRemediation: github_import_remediation(assigns.github_project_import_report),
      importErrorType: github_import_error_type(assigns.github_project_import_report),
      importSelectedRepository: ProjectImport.selected_repository(assigns.github_project_import_report),
      importProjectId: github_project_id(assigns.github_project_import_report),
      importProjectDisplayName: github_project_display_name(assigns.github_project_import_report),
      importProjectPath: github_project_path(assigns.github_project_import_report),
      importMode: github_project_import_mode(assigns.github_project_import_report),
      buttonsDisabled: assigns.buttons_disabled?
    }
  end

  defp github_pat_capture_state(onboarding_state, listing_report) do
    pat_path = github_pat_path(onboarding_state)
    encryption_status = Encryption.config_status()

    %{
      required?: GitHubRepositoryListing.blocked?(listing_report) and github_pat_capture_required?(pat_path),
      detail: github_pat_capture_detail(pat_path, listing_report),
      remediation: github_pat_capture_remediation(pat_path, listing_report),
      error_type: github_pat_capture_error_type(pat_path),
      secret_ref_name: ServiceCredentials.service_secret_ref_name(:pat),
      encryption_ready?: encryption_status == :ready,
      encryption_preflight_detail: github_pat_encryption_preflight_detail(encryption_status),
      encryption_error_type: github_pat_encryption_error_type(encryption_status)
    }
  end

  defp github_pat_path(onboarding_state) do
    onboarding_state
    |> fetch_step_state(4)
    |> map_get(:github_credentials, "github_credentials")
    |> GitHubCredentialChecks.from_state()
    |> case do
      %{paths: paths} when is_list(paths) -> Enum.find(paths, &(&1.path == :pat))
      _other -> nil
    end
  end

  defp github_pat_capture_required?(%{status: :ready, repository_access: :confirmed}), do: false
  defp github_pat_capture_required?(_pat_path), do: true

  defp github_pat_capture_detail(%{detail: detail}, _listing_report) when is_binary(detail), do: detail
  defp github_pat_capture_detail(_pat_path, %{detail: detail}) when is_binary(detail), do: detail

  defp github_pat_capture_detail(_pat_path, _listing_report) do
    "Save a deployment-local GitHub PAT to validate repository access for this install."
  end

  defp github_pat_capture_remediation(%{remediation: remediation}, _listing_report)
       when is_binary(remediation),
       do: remediation

  defp github_pat_capture_remediation(_pat_path, %{remediation: remediation})
       when is_binary(remediation),
       do: remediation

  defp github_pat_capture_remediation(_pat_path, _listing_report), do: nil

  defp github_pat_capture_error_type(%{error_type: error_type}) when is_binary(error_type),
    do: error_type

  defp github_pat_capture_error_type(_pat_path), do: nil

  defp github_pat_encryption_preflight_detail(:ready), do: nil

  defp github_pat_encryption_preflight_detail(:invalid) do
    "Encrypted secret storage is unavailable because the configured `JIDO_CODE_SECRET_REF_ENCRYPTION_KEY` is invalid. Replace it with a base64-encoded 32-byte key and restart JidoCode before saving a GitHub PAT."
  end

  defp github_pat_encryption_preflight_detail(:missing) do
    "Encrypted secret storage is unavailable in this running JidoCode process. Set `JIDO_CODE_SECRET_REF_ENCRYPTION_KEY` to a base64-encoded 32-byte key and restart JidoCode before saving a GitHub PAT."
  end

  defp github_pat_encryption_error_type(:ready), do: nil
  defp github_pat_encryption_error_type(:invalid), do: "secret_encryption_key_invalid"
  defp github_pat_encryption_error_type(:missing), do: "secret_encryption_unavailable"

  defp github_repository_option_props(repository_option) do
    %{
      id: Map.get(repository_option, :id),
      fullName: Map.get(repository_option, :full_name),
      owner: Map.get(repository_option, :owner),
      name: Map.get(repository_option, :name)
    }
  end

  defp github_listing_status(%{status: :ready}), do: "ready"
  defp github_listing_status(%{status: :blocked}), do: "blocked"
  defp github_listing_status(_report), do: "blocked"

  defp github_listing_status_label(%{status: :ready}), do: "Ready"
  defp github_listing_status_label(_report), do: "Needs attention"

  defp github_repository_count_label([]), do: "No linked repositories are currently available."

  defp github_repository_count_label(repository_options) do
    "#{length(repository_options)} linked repositories available for import."
  end

  defp github_project_import_ready?(%{status: :ready}), do: true
  defp github_project_import_ready?(_report), do: false

  defp github_import_status(%{status: :ready}), do: "ready"
  defp github_import_status(%{status: :blocked}), do: "blocked"
  defp github_import_status(_report), do: "idle"

  defp github_import_status_label(%{status: :ready}), do: "Imported"
  defp github_import_status_label(%{status: :blocked}), do: "Needs attention"
  defp github_import_status_label(_report), do: "Not started"

  defp github_import_detail(%{detail: detail}) when is_binary(detail), do: detail
  defp github_import_detail(_report), do: "No repository import has run yet."

  defp github_import_remediation(%{remediation: remediation}) when is_binary(remediation),
    do: remediation

  defp github_import_remediation(_report), do: nil

  defp github_import_error_type(%{error_type: error_type}) when is_binary(error_type), do: error_type
  defp github_import_error_type(_report), do: nil

  defp github_project_import_mode(%{project_record: %{import_mode: import_mode}})
       when import_mode in [:created, :existing],
       do: Atom.to_string(import_mode)

  defp github_project_import_mode(_report), do: nil

  defp github_project_id(%{project_record: %{id: id}}) when is_binary(id), do: id
  defp github_project_id(_report), do: nil

  defp github_project_display_name(%{project_record: %{name: name}}) when is_binary(name), do: name

  defp github_project_display_name(%{selected_repository: selected_repository})
       when is_binary(selected_repository) do
    selected_repository
    |> String.split("/")
    |> List.last()
  end

  defp github_project_display_name(_report), do: nil

  defp github_project_path(project_import_report) do
    case github_project_id(project_import_report) do
      nil -> nil
      managed_repo_id -> ~p"/repos/#{managed_repo_id}"
    end
  end

  defp github_project_import_flash(project_import_report, selected_repository) do
    case project_import_report do
      %{status: :ready} ->
        "Imported #{selected_repository} into the managed-repository control plane."

      %{detail: detail} when is_binary(detail) ->
        detail

      _other ->
        "GitHub repository import could not complete."
    end
  end

  defp github_repository_selection_note(selected_repository) when is_binary(selected_repository) do
    "GitHub repository #{selected_repository} selected for optional import."
  end

  defp github_repository_selection_note(_selected_repository) do
    "GitHub repository selection cleared."
  end

  defp maybe_put_selected_repository(step_state, selected_repository) when is_binary(selected_repository),
    do: Map.put(step_state, "selected_repository", selected_repository)

  defp maybe_put_selected_repository(step_state, _selected_repository),
    do: Map.delete(step_state, "selected_repository")

  defp extract_repository_selection(%{"repository_selection" => selection_params})
       when is_map(selection_params),
       do: extract_repository_selection(selection_params)

  defp extract_repository_selection(%{"repository_full_name" => repository_full_name}),
    do: normalize_optional_string(repository_full_name)

  defp extract_repository_selection(%{repository_full_name: repository_full_name}),
    do: normalize_optional_string(repository_full_name)

  defp extract_repository_selection(_params), do: nil

  defp valid_github_repository_selection?(nil, _available_repositories), do: true

  defp valid_github_repository_selection?(selected_repository, []),
    do: is_binary(selected_repository)

  defp valid_github_repository_selection?(selected_repository, available_repositories),
    do: selected_repository in available_repositories

  defp repository_selection_available?(selected_repository, []), do: is_binary(selected_repository)

  defp repository_selection_available?(selected_repository, available_repositories),
    do: selected_repository in available_repositories

  defp checked_at_label(%DateTime{} = checked_at), do: Calendar.strftime(checked_at, "%Y-%m-%d %H:%M UTC")
  defp checked_at_label(_checked_at), do: "Not checked yet"

  defp selected_start_path(onboarding_state) do
    onboarding_state
    |> fetch_step_state(3)
    |> map_get(:start_path, "start_path")
    |> normalize_start_path()
  end

  defp owner_email(onboarding_state, current_user) do
    onboarding_state
    |> fetch_step_state(2)
    |> map_get(:owner_email, "owner_email")
    |> normalize_optional_string()
    |> case do
      nil -> current_user_email(current_user)
      owner_email -> owner_email
    end
  end

  defp current_user_email(%{email: email}), do: email
  defp current_user_email(_current_user), do: "Admin account"

  defp setup_description(:desktop),
    do: "Your admin account is ready. Pick the first path you want this desktop install to guide next."

  defp setup_description(:cloud),
    do: "Your admin account is ready. Pick the first path you want this install to guide next."

  defp runtime_environment_description(:cloud),
    do: "Choose whether repository work should default to cloud-backed execution or local workspaces."

  defp runtime_environment_description(:local),
    do: "Choose whether repository work should default to cloud-backed execution or local workspaces."

  defp deployment_mode_label(:desktop), do: "Desktop"
  defp deployment_mode_label(:cloud), do: "Cloud"

  defp saved_runtime_environment_label(:local), do: "Local"
  defp saved_runtime_environment_label(:sprite), do: "Cloud"
  defp saved_runtime_environment_label(_default_environment), do: "Cloud"

  defp saved_runtime_environment_note(:local, workspace_root) when is_binary(workspace_root) do
    "Local execution will use #{workspace_root} as the default workspace root."
  end

  defp saved_runtime_environment_note(:local, _workspace_root) do
    "Local execution is selected, but the workspace root still needs to be supplied."
  end

  defp saved_runtime_environment_note(:sprite, _workspace_root) do
    "Cloud defaults currently map to Sprite-backed execution with no local workspace root."
  end

  defp saved_runtime_environment_note(_default_environment, _workspace_root) do
    "Cloud defaults currently map to Sprite-backed execution with no local workspace root."
  end

  defp selected_start_path_label(nil), do: "Not chosen yet"
  defp selected_start_path_label(start_path), do: start_path_title(start_path)

  defp selected_start_path_note(nil, :desktop),
    do: "Pick a default path now. You can still change it later once more setup moves into the app."

  defp selected_start_path_note(nil, :cloud),
    do: "Pick a default path now. You can still change it later once more setup moves into the app."

  defp selected_start_path_note(:local_repo, _deployment_mode),
    do: "Local repositories are the default path for this install until you choose something else."

  defp selected_start_path_note(:github, _deployment_mode),
    do: "GitHub is saved as the default source-control path for this install."

  defp selected_start_path_note(:later, _deployment_mode),
    do: "Repo setup is deferred for now. You can come back and choose a source-control path later."

  defp completion_summary(nil),
    do: "Finish onboarding now. You can defer source-control setup until you are inside the app."

  defp completion_summary(:local_repo),
    do: "Local repo is saved as your preferred next step. You can finish onboarding and attach it from inside the app."

  defp completion_summary(:github),
    do: "GitHub is saved as your preferred next step. You can finish onboarding and connect it from inside the app."

  defp completion_summary(:later),
    do: "Repository setup is deferred for now. You can finish onboarding and come back later."

  defp choice_badge_label(option_id, selected_start_path, _recommended?) when option_id == selected_start_path,
    do: "Saved"

  defp choice_badge_label(_option_id, _selected_start_path, true), do: "Recommended"
  defp choice_badge_label(_option_id, _selected_start_path, _recommended?), do: nil

  defp choice_button_label(option_id, selected_start_path) when option_id == selected_start_path,
    do: "Saved"

  defp choice_button_label(option_id, _selected_start_path), do: start_path_title(option_id)

  defp start_path_title(:local_repo), do: "Add local repo"
  defp start_path_title(:github), do: "Connect GitHub"
  defp start_path_title(:later), do: "Do this later"

  defp start_path_note(:local_repo), do: "Local repo path selected."
  defp start_path_note(:github), do: "GitHub path selected."
  defp start_path_note(:later), do: "Repo setup deferred for now."

  defp runtime_environment_note(%{mode: :local, workspace_root: workspace_root})
       when is_binary(workspace_root) do
    "Local runtime defaults saved for #{Path.expand(workspace_root)}."
  end

  defp runtime_environment_note(%{mode: :local}),
    do: "Local runtime defaults saved."

  defp runtime_environment_note(%{mode: :cloud}),
    do: "Cloud runtime defaults saved."

  defp runtime_environment_title(:local), do: "Local"
  defp runtime_environment_title(:cloud), do: "Cloud"
  defp runtime_environment_title(_mode), do: "Cloud"

  defp runtime_environment_error_message(runtime_report) do
    runtime_report
    |> EnvironmentDefaults.blocked_checks()
    |> Enum.map(fn check ->
      [Map.get(check, :detail), Map.get(check, :remediation)]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> case do
      "" -> "Runtime defaults could not be validated."
      message -> message
    end
  end

  defp secret_persistence_error_message(%{
         message: message,
         recovery_instruction: recovery_instruction
       })
       when is_binary(message) and is_binary(recovery_instruction) do
    "#{message} #{recovery_instruction}"
  end

  defp secret_persistence_error_message(%{message: message}) when is_binary(message), do: message
  defp secret_persistence_error_message(_typed_error), do: "GitHub PAT could not be saved."

  defp assign_runtime_environment_form(socket, runtime_params) do
    normalized_form_values = normalize_runtime_environment_form_values(runtime_params)

    socket
    |> assign(:runtime_environment_form, to_form(normalized_form_values, as: :runtime_environment))
    |> assign(
      :runtime_environment_mode,
      normalized_form_values |> Map.get("mode", "cloud") |> normalize_runtime_environment_mode()
    )
  end

  defp runtime_environment_form_values(%SystemConfig{} = config) do
    %{
      "mode" => config.default_environment |> runtime_environment_mode() |> Atom.to_string(),
      "workspace_root" => config.workspace_root || ""
    }
  end

  defp normalize_runtime_environment_form_values(runtime_params) when is_map(runtime_params) do
    %{
      "mode" =>
        runtime_params
        |> map_get(:mode, "mode", "cloud")
        |> normalize_runtime_environment_mode()
        |> Atom.to_string(),
      "workspace_root" =>
        runtime_params
        |> map_get(:workspace_root, "workspace_root", "")
        |> normalize_optional_string()
        |> case do
          nil -> ""
          workspace_root -> workspace_root
        end
    }
  end

  defp normalize_runtime_environment_form_values(_runtime_params),
    do: %{"mode" => "cloud", "workspace_root" => ""}

  defp runtime_environment_mode(:local), do: :local
  defp runtime_environment_mode(:sprite), do: :cloud
  defp runtime_environment_mode(_default_environment), do: :cloud

  defp maybe_hydrate_github_setup_state(current_state, :github, owner_context),
    do: hydrate_github_setup_state(current_state, owner_context)

  defp maybe_hydrate_github_setup_state(current_state, _start_path, _owner_context),
    do: current_state

  defp hydrate_github_setup_state(onboarding_state, owner_context, opts \\ []) do
    current_state = normalize_keyed_map(onboarding_state)
    force? = Keyword.get(opts, :force?, false)

    cond do
      not is_binary(owner_context) ->
        current_state

      force? or missing_github_credential_snapshot?(current_state) ->
        step_state = current_state |> fetch_step_state(4) |> normalize_keyed_map()

        github_credentials =
          step_state
          |> map_get(:github_credentials, "github_credentials")
          |> GitHubCredentialChecks.run(owner_context)
          |> GitHubCredentialChecks.serialize_for_state()

        updated_step_state =
          step_state
          |> Map.put("github_credentials", github_credentials)
          |> Map.put(
            "validated_note",
            "GitHub credential readiness captured for optional repository follow-up."
          )

        Map.put(current_state, "4", updated_step_state)

      true ->
        current_state
    end
  end

  defp missing_github_credential_snapshot?(onboarding_state) when is_map(onboarding_state) do
    onboarding_state
    |> fetch_step_state(4)
    |> map_get(:github_credentials, "github_credentials")
    |> GitHubCredentialChecks.from_state()
    |> case do
      %{paths: [_ | _]} -> false
      _other -> true
    end
  end

  defp missing_github_credential_snapshot?(_onboarding_state), do: true

  defp current_actor(socket) do
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
          "id" => "system:setup-live",
          "email" => "setup-live@system.local"
        })
    end
  end

  defp normalize_runtime_environment_mode("local"), do: :local
  defp normalize_runtime_environment_mode(:local), do: :local
  defp normalize_runtime_environment_mode("cloud"), do: :cloud
  defp normalize_runtime_environment_mode(:cloud), do: :cloud
  defp normalize_runtime_environment_mode(_mode), do: :cloud

  defp fetch_step_state(onboarding_state, onboarding_step) when is_map(onboarding_state) do
    step_key = Integer.to_string(onboarding_step)
    Map.get(onboarding_state, step_key) || Map.get(onboarding_state, onboarding_step) || %{}
  end

  defp fetch_step_state(_onboarding_state, _onboarding_step), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) and is_atom(atom_key) do
    Map.get(map, atom_key, Map.get(map, string_key, default))
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_start_path(start_path) when start_path in @start_paths, do: start_path

  defp normalize_start_path(start_path) when is_binary(start_path) do
    case String.trim(start_path) do
      "local_repo" -> :local_repo
      "github" -> :github
      "later" -> :later
      _other -> nil
    end
  end

  defp normalize_start_path(_start_path), do: nil

  defp normalize_keyed_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, Atom.to_string(key), value)

      {key, value}, acc when is_binary(key) ->
        Map.put(acc, key, value)

      {key, value}, acc ->
        Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_keyed_map(_map), do: %{}

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(_value), do: nil
end
