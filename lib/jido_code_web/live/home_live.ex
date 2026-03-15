defmodule JidoCodeWeb.HomeLive do
  # covers: auth.provider_login_flow.entrypoint_visible
  # covers: auth.provider_login_flow.local_auth_fallback_visible
  # covers: auth.operator_settings.sections_separated
  # covers: auth.operator_settings.broker_trust_configuration_ui
  # covers: auth.operator_settings.github_service_validation_feedback
  # covers: auth.operator_settings.integration_boundary_visible
  use JidoCodeWeb, :live_view

  require Ash.Query

  alias JidoCode.AuthProviders
  alias JidoCode.AuthProviders.ProviderConfig
  alias JidoCode.GitHub.ServiceCredentials
  alias JidoCode.Setup.GitHubCredentialChecks

  @provider_catalog [
    %{
      provider: :github,
      display_name: "GitHub",
      provider_host: "github.com",
      login_entrypoint_visible?: true,
      service_integration_status: :implemented
    },
    %{
      provider: :gitlab,
      display_name: "GitLab",
      provider_host: "gitlab.com",
      login_entrypoint_visible?: false,
      service_integration_status: :placeholder
    },
    %{
      provider: :bitbucket,
      display_name: "Bitbucket",
      provider_host: "bitbucket.org",
      login_entrypoint_visible?: false,
      service_integration_status: :placeholder
    }
  ]

  @allowlist_options [
    {"None", "none"},
    {"Users", "users"},
    {"Organizations", "organizations"},
    {"Teams", "teams"},
    {"Groups", "groups"},
    {"Workspaces", "workspaces"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        github_login_path: github_login_path(),
        github_login_enabled?: github_login_enabled?(),
        allowlist_options: @allowlist_options
      )
      |> refresh_operator_settings()

    {:ok, socket}
  end

  @impl true
  def handle_event("save_provider_login", %{"provider_login" => params}, socket) do
    with {:ok, provider} <- normalize_provider(Map.get(params, "provider")),
         {:ok, provider_host} <- provider_host_for(provider),
         {:ok, _config} <- save_provider_login(provider, provider_host, params) do
      {:noreply,
       socket
       |> put_flash(:info, "Saved #{provider_display_name(provider)} provider login settings.")
       |> refresh_operator_settings()}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, format_error(error))}
    end
  end

  def handle_event("refresh_github_service_checks", _params, socket) do
    {:noreply,
     socket
     |> assign(:github_service_report, github_service_report(socket.assigns[:current_user]))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-base-200 via-base-100 to-base-200">
      <div class={[
        "mx-auto flex w-full px-6",
        @current_user && "max-w-6xl py-12",
        !@current_user && "min-h-screen max-w-4xl items-center justify-center py-16"
      ]}>
        <div class={["w-full", !@current_user && "max-w-xl"]}>
          <div class="space-y-6 rounded-3xl border border-base-300 bg-base-100 p-10 shadow-2xl">
            <div class="space-y-3 text-center">
              <%!-- covers: baseline.surface.welcome_landing_copy --%>
              <p class="text-xs font-bold uppercase tracking-[0.24em] text-base-content/50">
                Spec Led Baseline
              </p>
              <h1 class="text-4xl font-bold text-base-content">Welcome to Jido Code</h1>
              <p class="text-base leading-7 text-base-content/70">
                The application is intentionally trimmed to a minimal landing page plus authentication while the baseline is being re-established.
              </p>
            </div>

            <%!-- covers: baseline.surface.auth_entrypoints_visible --%>
            <div class="space-y-4">
              <%= if @current_user do %>
                <div class="rounded-2xl border border-success/30 bg-success/10 p-4 text-center">
                  <p class="text-sm uppercase tracking-[0.16em] text-success">Signed In</p>
                  <p class="mt-2 text-lg font-semibold text-base-content">{@current_user.email}</p>
                </div>

                <div class="grid gap-3">
                  <a href="/sign-out" class="btn btn-primary btn-block">Sign Out</a>
                </div>

                <div class="rounded-2xl border border-base-300 bg-base-200/60 p-4 text-left text-sm text-base-content/70">
                  Local email auth remains the fallback path even when hosted provider sign-in is enabled.
                </div>
              <% else %>
                <div class="grid gap-3 sm:grid-cols-2">
                  <a href="/sign-in" class="btn btn-primary btn-block">Sign In</a>
                  <a href="/register" class="btn btn-outline btn-block">Create Account</a>
                </div>

                <%= if @github_login_enabled? do %>
                  <div class="grid gap-3">
                    <a href={@github_login_path} class="btn btn-neutral btn-block">
                      Sign In with GitHub
                    </a>
                  </div>
                <% end %>
              <% end %>
            </div>

            <div class="rounded-2xl border border-dashed border-base-300 bg-base-200/60 p-4 text-sm text-base-content/60">
              Product routes, demos, setup flows, APIs, and workbench surfaces are commented out until the new spec-led baseline is validated.
            </div>
          </div>

          <div :if={@current_user} class="mt-8 space-y-8">
            <%!-- covers: auth.operator_settings.sections_separated --%>
            <section
              id="provider-login-settings"
              class="rounded-3xl border border-base-300 bg-base-100 p-8 shadow-xl"
            >
              <div class="mb-6 flex items-start justify-between gap-6">
                <div class="space-y-2">
                  <p class="text-xs font-bold uppercase tracking-[0.22em] text-base-content/45">
                    Operator Settings
                  </p>
                  <h2 class="text-2xl font-semibold text-base-content">Provider Login</h2>
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
                  id={"provider-login-card-#{card.provider}"}
                  class="rounded-2xl border border-base-300 bg-base-200/40 p-5"
                >
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <h3 class="text-lg font-semibold text-base-content">{card.display_name}</h3>
                      <p class="text-sm text-base-content/60">{card.provider_host}</p>
                    </div>
                    <span class={provider_status_badge_class(card.status.tone)}>
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
                    id={"provider-login-form-#{card.provider}"}
                    phx-submit="save_provider_login"
                    class="mt-5 space-y-3"
                  >
                    <input type="hidden" name="provider_login[provider]" value={card.provider} />

                    <%!-- covers: auth.operator_settings.broker_trust_configuration_ui --%>
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
                      options={@allowlist_options}
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
              id="git-provider-integrations"
              class="rounded-3xl border border-base-300 bg-base-100 p-8 shadow-xl"
            >
              <div class="mb-6 flex items-start justify-between gap-6">
                <div class="space-y-2">
                  <h2 class="text-2xl font-semibold text-base-content">Git Provider Integrations</h2>
                  <%!-- covers: auth.operator_settings.integration_boundary_visible --%>
                  <p class="max-w-3xl text-sm leading-6 text-base-content/70">
                    Deployment-local Git automation credentials stay separate from provider-login broker trust. GitHub App is preferred, PAT is fallback, and GitLab or Bitbucket remain placeholders for now.
                  </p>
                </div>
                <button
                  id="refresh-github-service-checks"
                  type="button"
                  phx-click="refresh_github_service_checks"
                  class="btn btn-outline btn-sm"
                >
                  Refresh GitHub Validation
                </button>
              </div>

              <div class="grid gap-6 xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
                <article class="rounded-2xl border border-base-300 bg-base-200/40 p-5">
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <h3 class="text-lg font-semibold text-base-content">GitHub Service Integration</h3>
                      <p class="text-sm text-base-content/60">
                        Deployment-local automation credentials and repository access validation
                      </p>
                    </div>
                    <span class={integration_status_badge_class(@github_service_report.status)}>
                      {integration_status_label(@github_service_report.status)}
                    </span>
                  </div>

                  <%!-- covers: auth.operator_settings.github_service_validation_feedback --%>
                  <div id="github-service-status" class="mt-4 space-y-4">
                    <p class="text-sm leading-6 text-base-content/70">
                      {github_service_summary(@github_service_report)}
                    </p>

                    <p class="text-xs uppercase tracking-[0.18em] text-base-content/45">
                      Last checked: {format_datetime(@github_service_report.checked_at)}
                    </p>

                    <div class="space-y-3">
                      <div
                        :for={path_result <- @github_service_report.paths}
                        id={"github-service-path-#{path_result.path}"}
                        class="rounded-2xl border border-base-300 bg-base-100/70 p-4"
                      >
                        <div class="flex items-start justify-between gap-4">
                          <div>
                            <p class="font-medium text-base-content">{path_result.name}</p>
                            <p class="mt-1 text-sm text-base-content/65">{path_result.detail}</p>
                          </div>
                          <span class={integration_status_badge_class(path_result.status)}>
                            {integration_status_label(path_result.status)}
                          </span>
                        </div>

                        <p class="mt-3 text-xs uppercase tracking-[0.18em] text-base-content/45">
                          Repository access: {repository_access_label(path_result.repository_access)}
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
                  <article class="rounded-2xl border border-base-300 bg-base-200/40 p-5">
                    <h3 class="text-lg font-semibold text-base-content">Deployment-Local Secrets</h3>
                    <p class="mt-2 text-sm leading-6 text-base-content/70">
                      These secret refs back GitHub automation. They are not stored in the provider-login broker config.
                    </p>

                    <div class="mt-4 space-y-2 text-sm text-base-content/75">
                      <p :for={{credential, secret_ref} <- @github_service_secret_refs}>
                        <span class="font-medium">{service_credential_label(credential)}:</span>
                        <code class="ml-2 rounded bg-base-300/70 px-2 py-1 text-xs">{secret_ref}</code>
                      </p>
                    </div>
                  </article>

                  <article class="rounded-2xl border border-base-300 bg-base-200/40 p-5">
                    <h3 class="text-lg font-semibold text-base-content">Future Providers</h3>
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
        </div>
      </div>
    </div>
    """
  end

  defp refresh_operator_settings(%{assigns: %{current_user: nil}} = socket) do
    assign(socket,
      provider_login_cards: [],
      github_service_report: github_service_report(nil),
      github_service_secret_refs: service_secret_refs()
    )
  end

  defp refresh_operator_settings(socket) do
    assign(socket,
      provider_login_cards: provider_login_cards(),
      github_service_report: github_service_report(socket.assigns[:current_user]),
      github_service_secret_refs: service_secret_refs()
    )
  end

  defp provider_login_cards do
    Enum.map(@provider_catalog, fn provider_definition ->
      config =
        case ProviderConfig.get_by_provider_host(
               provider_definition.provider,
               provider_definition.provider_host,
               authorize?: false
             ) do
          {:ok, %ProviderConfig{} = provider_config} -> provider_config
          _other -> nil
        end

      allowlist_mode =
        (config || %{})
        |> Map.get(:allowlist_mode, :none)
        |> Atom.to_string()

      allowlist_values = Map.get(config || %{}, :allowlist_values, [])

      card =
        Map.merge(provider_definition, %{
          enabled: Map.get(config || %{}, :enabled, false),
          login_enabled: Map.get(config || %{}, :login_enabled, false),
          allowlist_mode: allowlist_mode,
          allowlist_values: allowlist_values,
          allowlist_values_text: Enum.join(allowlist_values, "\n"),
          broker_base_url: Map.get(config || %{}, :broker_base_url, nil),
          broker_issuer: Map.get(config || %{}, :broker_issuer, nil),
          broker_audience: Map.get(config || %{}, :broker_audience, nil)
        })

      card
      |> Map.put(:status, provider_login_status(card))
      |> Map.put(:entrypoint_note, provider_entrypoint_note(card))
    end)
  end

  defp provider_login_status(card) do
    missing_fields =
      []
      |> maybe_add_missing(blank?(card.broker_base_url), "broker base URL")
      |> maybe_add_missing(blank?(card.broker_issuer), "broker issuer")
      |> maybe_add_missing(blank?(card.broker_audience), "broker audience")
      |> maybe_add_missing(card.allowlist_mode != "none" and card.allowlist_values == [], "allowlist values")

    cond do
      not card.enabled ->
        %{
          tone: :muted,
          label: "Disabled",
          detail: "Provider host is disabled. Local email authentication remains the only sign-in path.",
          missing_fields: []
        }

      not card.login_enabled ->
        %{
          tone: :warning,
          label: "Host Enabled",
          detail: "Provider host is configured, but browser sign-in is still turned off.",
          missing_fields: missing_fields
        }

      missing_fields == [] ->
        %{
          tone: :success,
          label: "Ready",
          detail: "Broker trust is configured and this provider host is ready for hosted sign-in.",
          missing_fields: []
        }

      true ->
        %{
          tone: :warning,
          label: "Needs Broker Trust",
          detail: "Provider login is enabled, but broker trust or allowlist details are still incomplete.",
          missing_fields: missing_fields
        }
    end
  end

  defp provider_entrypoint_note(%{provider: :github, enabled: true, login_enabled: true}) do
    "Anonymous visitors can use the GitHub sign-in entrypoint on the landing page when this host stays enabled."
  end

  defp provider_entrypoint_note(%{provider: :github}) do
    "The landing page hides the GitHub sign-in entrypoint until both provider host and browser sign-in are enabled."
  end

  defp provider_entrypoint_note(_card) do
    "The provider login contract is modeled here, but the landing page still exposes only the GitHub browser entrypoint today."
  end

  defp save_provider_login(provider, provider_host, params) do
    ProviderConfig.upsert(
      %{
        provider: provider,
        provider_host: provider_host,
        enabled: truthy?(Map.get(params, "enabled")),
        login_enabled: truthy?(Map.get(params, "login_enabled")),
        allowlist_mode: normalize_allowlist_mode(Map.get(params, "allowlist_mode")),
        allowlist_values: parse_allowlist_values(Map.get(params, "allowlist_values")),
        broker_base_url: normalize_optional_string(Map.get(params, "broker_base_url")),
        broker_issuer: normalize_optional_string(Map.get(params, "broker_issuer")),
        broker_audience: normalize_optional_string(Map.get(params, "broker_audience"))
      },
      authorize?: false
    )
  end

  defp github_service_report(nil) do
    GitHubCredentialChecks.run(nil, nil)
  rescue
    _exception ->
      GitHubCredentialChecks.run(nil, nil)
  end

  defp github_service_report(current_user) do
    owner_context =
      current_user
      |> Map.get(:email)
      |> to_string()

    GitHubCredentialChecks.run(nil, owner_context)
  rescue
    _exception ->
      GitHubCredentialChecks.run(nil, nil)
  end

  defp service_secret_refs do
    ServiceCredentials.service_secret_ref_names()
    |> Enum.sort_by(fn {credential, _secret_ref} -> credential end)
  end

  defp github_service_summary(%{status: :ready, integration_health: integration_health}) do
    "GitHub automation is ready. GitHub App status is #{integration_status_label(integration_health.github_app_status)} with repository access #{repository_access_label(integration_health.github_app_repository_access)}."
  end

  defp github_service_summary(%{integration_health: integration_health}) do
    "GitHub automation is blocked. GitHub App status is #{integration_status_label(integration_health.github_app_status)} and the service path needs operator attention before automation should run."
  end

  defp github_service_summary(_report) do
    "GitHub automation readiness could not be determined."
  end

  defp provider_status_badge_class(:success),
    do:
      "rounded-full border border-success/40 bg-success/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-success"

  defp provider_status_badge_class(:warning),
    do:
      "rounded-full border border-warning/40 bg-warning/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-warning"

  defp provider_status_badge_class(_tone),
    do:
      "rounded-full border border-base-300 bg-base-200 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-base-content/60"

  defp integration_status_badge_class(:ready),
    do:
      "rounded-full border border-success/40 bg-success/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-success"

  defp integration_status_badge_class(:blocked),
    do:
      "rounded-full border border-warning/40 bg-warning/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-warning"

  defp integration_status_badge_class(:invalid),
    do:
      "rounded-full border border-warning/40 bg-warning/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-warning"

  defp integration_status_badge_class(:not_configured),
    do:
      "rounded-full border border-base-300 bg-base-200 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-base-content/60"

  defp integration_status_badge_class(_status),
    do:
      "rounded-full border border-base-300 bg-base-200 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-base-content/60"

  defp integration_status_label(:ready), do: "Ready"
  defp integration_status_label(:blocked), do: "Blocked"
  defp integration_status_label(:invalid), do: "Invalid"
  defp integration_status_label(:not_configured), do: "Not Configured"
  defp integration_status_label(:confirmed), do: "Confirmed"
  defp integration_status_label(:unconfirmed), do: "Unconfirmed"

  defp integration_status_label(status) when is_atom(status),
    do: status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp integration_status_label(status), do: status |> to_string() |> String.capitalize()

  defp repository_access_label(:confirmed), do: "Confirmed"
  defp repository_access_label(:unconfirmed), do: "Unconfirmed"
  defp repository_access_label(_status), do: "Unknown"

  defp service_credential_label(:app_id), do: "GitHub App ID"
  defp service_credential_label(:app_private_key), do: "GitHub App Private Key"
  defp service_credential_label(:webhook_secret), do: "GitHub Webhook Secret"
  defp service_credential_label(:pat), do: "PAT Fallback"

  defp service_credential_label(credential),
    do: credential |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp provider_display_name(:github), do: "GitHub"
  defp provider_display_name(:gitlab), do: "GitLab"
  defp provider_display_name(:bitbucket), do: "Bitbucket"

  defp provider_display_name(provider) when is_binary(provider) do
    case normalize_provider(provider) do
      {:ok, normalized_provider} -> provider_display_name(normalized_provider)
      {:error, _message} -> "Provider"
    end
  end

  defp provider_display_name(_provider), do: "Provider"

  defp provider_host_for(provider) do
    case Enum.find(@provider_catalog, fn definition -> definition.provider == provider end) do
      %{provider_host: provider_host} -> {:ok, provider_host}
      nil -> {:error, "Unsupported provider."}
    end
  end

  defp normalize_provider("github"), do: {:ok, :github}
  defp normalize_provider("gitlab"), do: {:ok, :gitlab}
  defp normalize_provider("bitbucket"), do: {:ok, :bitbucket}
  defp normalize_provider(:github), do: {:ok, :github}
  defp normalize_provider(:gitlab), do: {:ok, :gitlab}
  defp normalize_provider(:bitbucket), do: {:ok, :bitbucket}
  defp normalize_provider(_provider), do: {:error, "Unsupported provider."}

  defp normalize_allowlist_mode("users"), do: :users
  defp normalize_allowlist_mode("organizations"), do: :organizations
  defp normalize_allowlist_mode("teams"), do: :teams
  defp normalize_allowlist_mode("groups"), do: :groups
  defp normalize_allowlist_mode("workspaces"), do: :workspaces
  defp normalize_allowlist_mode(_mode), do: :none

  defp parse_allowlist_values(nil), do: []

  defp parse_allowlist_values(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_allowlist_values(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_allowlist_values(_value), do: []

  defp maybe_add_missing(fields, true, value), do: fields ++ [value]
  defp maybe_add_missing(fields, false, _value), do: fields

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("1"), do: true
  defp truthy?(1), do: true
  defp truthy?(_value), do: false

  defp blank?(value), do: normalize_optional_string(value) == nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil

  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(_datetime), do: "Not checked"

  defp format_error(error) when is_exception(error), do: Exception.message(error)
  defp format_error(%{errors: errors}) when is_list(errors), do: Enum.map_join(errors, "; ", &inspect/1)
  defp format_error(error), do: inspect(error)

  defp github_login_enabled? do
    ProviderConfig
    |> Ash.Query.filter(provider == ^:github and provider_host == ^"github.com")
    |> Ash.read_one(domain: AuthProviders, authorize?: false)
    |> case do
      {:ok, %ProviderConfig{enabled: true, login_enabled: true}} -> true
      _other -> false
    end
  end

  defp github_login_path do
    "/auth/providers/github/start?provider_host=github.com&redirect_path=/welcome"
  end
end
