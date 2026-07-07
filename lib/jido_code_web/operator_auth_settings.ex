defmodule JidoCodeWeb.OperatorAuthSettings do
  # covers: auth.operator_settings.sections_separated
  # covers: auth.operator_settings.broker_trust_configuration_ui
  # covers: auth.operator_settings.github_service_validation_feedback
  # covers: auth.operator_settings.integration_boundary_visible
  @moduledoc false

  alias JidoCode.AuthProviders.{ProviderConfig, ProviderConfigStore}
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

  def allowlist_options, do: @allowlist_options

  def state(current_user) do
    %{
      provider_login_cards: provider_login_cards(),
      github_service_report: github_service_report(current_user),
      github_service_secret_refs: service_secret_refs()
    }
  end

  def save_provider_login(params) when is_map(params) do
    with {:ok, provider} <- normalize_provider(Map.get(params, "provider")),
         {:ok, provider_host} <- provider_host_for(provider),
         {:ok, _config} <-
           ProviderConfigStore.upsert(%{
             provider: provider,
             provider_host: provider_host,
             enabled: truthy?(Map.get(params, "enabled")),
             login_enabled: truthy?(Map.get(params, "login_enabled")),
             allowlist_mode: normalize_allowlist_mode(Map.get(params, "allowlist_mode")),
             allowlist_values: parse_allowlist_values(Map.get(params, "allowlist_values")),
             broker_base_url: normalize_optional_string(Map.get(params, "broker_base_url")),
             broker_issuer: normalize_optional_string(Map.get(params, "broker_issuer")),
             broker_audience: normalize_optional_string(Map.get(params, "broker_audience"))
           }) do
      {:ok, provider}
    end
  end

  def github_service_summary(%{status: :ready, integration_health: integration_health}) do
    "GitHub automation is ready. GitHub App status is #{integration_status_label(integration_health.github_app_status)} with repository access #{repository_access_label(integration_health.github_app_repository_access)}."
  end

  def github_service_summary(%{integration_health: integration_health}) do
    "GitHub automation is blocked. GitHub App status is #{integration_status_label(integration_health.github_app_status)} and the service path needs operator attention before automation should run."
  end

  def github_service_summary(_report), do: "GitHub automation readiness could not be determined."

  def provider_status_badge_class(:success),
    do:
      "rounded-full border border-accent-green/40 bg-accent-green/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-accent-green"

  def provider_status_badge_class(:warning),
    do:
      "rounded-full border border-accent-yellow/40 bg-accent-yellow/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-accent-yellow"

  def provider_status_badge_class(_tone),
    do:
      "rounded-full border border-border bg-muted px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground"

  def integration_status_badge_class(:ready),
    do:
      "rounded-full border border-accent-green/40 bg-accent-green/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-accent-green"

  def integration_status_badge_class(:blocked),
    do:
      "rounded-full border border-accent-yellow/40 bg-accent-yellow/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-accent-yellow"

  def integration_status_badge_class(:invalid),
    do:
      "rounded-full border border-accent-yellow/40 bg-accent-yellow/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-accent-yellow"

  def integration_status_badge_class(:not_configured),
    do:
      "rounded-full border border-border bg-muted px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground"

  def integration_status_badge_class(_status),
    do:
      "rounded-full border border-border bg-muted px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground"

  def integration_status_label(:ready), do: "Ready"
  def integration_status_label(:blocked), do: "Blocked"
  def integration_status_label(:invalid), do: "Invalid"
  def integration_status_label(:not_configured), do: "Not Configured"
  def integration_status_label(:confirmed), do: "Confirmed"
  def integration_status_label(:unconfirmed), do: "Unconfirmed"

  def integration_status_label(status) when is_atom(status),
    do: status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  def integration_status_label(status), do: status |> to_string() |> String.capitalize()

  def repository_access_label(:confirmed), do: "Confirmed"
  def repository_access_label(:unconfirmed), do: "Unconfirmed"
  def repository_access_label(_status), do: "Unknown"

  def service_credential_label(:app_id), do: "GitHub App ID"
  def service_credential_label(:app_private_key), do: "GitHub App Private Key"
  def service_credential_label(:webhook_secret), do: "GitHub Webhook Secret"
  def service_credential_label(:pat), do: "PAT Fallback"

  def service_credential_label(credential),
    do: credential |> to_string() |> String.replace("_", " ") |> String.capitalize()

  def provider_display_name(:github), do: "GitHub"
  def provider_display_name(:gitlab), do: "GitLab"
  def provider_display_name(:bitbucket), do: "Bitbucket"

  def provider_display_name(provider) when is_binary(provider) do
    case normalize_provider(provider) do
      {:ok, normalized_provider} -> provider_display_name(normalized_provider)
      {:error, _message} -> "Provider"
    end
  end

  def provider_display_name(_provider), do: "Provider"

  def format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  def format_datetime(_datetime), do: "Not checked"

  defp provider_login_cards do
    Enum.map(@provider_catalog, fn provider_definition ->
      config =
        case ProviderConfigStore.get_by_provider_host(
               provider_definition.provider,
               provider_definition.provider_host
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
end
