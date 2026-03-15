defmodule JidoCode.GitHub.ServiceCredentials do
  @moduledoc """
  Canonical deployment-local credential model for GitHub automation.

  Login broker configuration lives in `JidoCode.AuthProviders.ProviderConfig`.
  GitHub App, webhook, and PAT automation credentials remain deployment-local.
  """

  # covers: auth.github_service_credentials.secret_ref_names
  # covers: auth.github_service_credentials.login_service_split
  # covers: auth.github_service_credentials.secret_resolution

  alias JidoCode.AuthProviders.ProviderConfig
  alias JidoCode.Security.SecretRefs

  @service_credential_specs %{
    app_id: %{
      env: "GITHUB_APP_ID",
      app_env: :github_app_id,
      secret_ref_name: "vcs/github/app_id"
    },
    app_private_key: %{
      env: "GITHUB_APP_PRIVATE_KEY",
      app_env: :github_app_private_key,
      secret_ref_name: "vcs/github/app_private_key"
    },
    webhook_secret: %{
      env: "GITHUB_WEBHOOK_SECRET",
      app_env: :github_webhook_secret,
      secret_ref_name: "vcs/github/webhook_secret"
    },
    pat: %{
      env: "GITHUB_PAT",
      app_env: :github_pat,
      secret_ref_name: "vcs/github/pat"
    }
  }

  @login_config_fields [:broker_issuer, :broker_audience, :broker_base_url]

  @type service_credential :: :app_id | :app_private_key | :webhook_secret | :pat
  @type resolution_status :: :secret_unavailable | :resolution_failed

  @type resolution_diagnostics :: %{
          credential: service_credential(),
          selected_source: :env | :app_env | :secret_ref | :unavailable | :error,
          env_var: String.t(),
          app_env: atom(),
          secret_ref_scope: :integration,
          secret_ref_name: String.t(),
          secret_ref_key_version: integer() | nil,
          secret_ref_source: :env | :onboarding | :rotation | nil,
          resolution_error_type: String.t() | atom() | nil
        }

  defmodule Config do
    @enforce_keys [
      :provider,
      :secret_scope,
      :login_config_resource,
      :login_config_fields,
      :service_secret_refs,
      :paths
    ]
    defstruct [
      :provider,
      :secret_scope,
      :login_config_resource,
      :login_config_fields,
      :service_secret_refs,
      :paths
    ]
  end

  @type config :: %Config{
          provider: :github,
          secret_scope: :integration,
          login_config_resource: module(),
          login_config_fields: [atom()],
          service_secret_refs: %{service_credential() => String.t()},
          paths: [map()]
        }

  @doc """
  Returns the deployment-local GitHub service credential model.
  """
  @spec config() :: config()
  def config do
    %Config{
      provider: :github,
      secret_scope: :integration,
      login_config_resource: ProviderConfig,
      login_config_fields: @login_config_fields,
      service_secret_refs: service_secret_ref_names(),
      paths: path_definitions()
    }
  end

  @doc """
  Fields reserved for provider login and broker trust rather than automation secrets.
  """
  @spec login_config_fields() :: [atom()]
  def login_config_fields, do: @login_config_fields

  @doc """
  Canonical SecretRef name for a GitHub automation credential.
  """
  @spec service_secret_ref_name(service_credential()) :: String.t()
  def service_secret_ref_name(credential) do
    @service_credential_specs
    |> Map.fetch!(credential)
    |> Map.fetch!(:secret_ref_name)
  end

  @doc """
  Canonical SecretRef names for GitHub automation credentials.
  """
  @spec service_secret_ref_names() :: %{service_credential() => String.t()}
  def service_secret_ref_names do
    Map.new(@service_credential_specs, fn {credential, spec} ->
      {credential, Map.fetch!(spec, :secret_ref_name)}
    end)
  end

  @doc """
  Setup-time credential path definitions for GitHub automation.
  """
  @spec path_definitions() :: [map()]
  def path_definitions do
    [
      %{
        path: :github_app,
        name: "GitHub App",
        credential_keys: [:app_id, :app_private_key],
        api_token_env: "GITHUB_APP_INSTALLATION_TOKEN",
        api_token_app_env: :github_app_installation_token,
        repo_env: "GITHUB_APP_ACCESSIBLE_REPOS",
        repo_app_env: :github_app_accessible_repos,
        expected_repo_env: "GITHUB_APP_EXPECTED_REPOS",
        expected_repo_app_env: :github_app_expected_repos,
        tracks_expected_repositories: true,
        not_configured_detail:
          "GitHub App credentials are not fully configured (`GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` are required).",
        not_configured_remediation: "Set `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY`, then retry validation.",
        not_configured_error_type: "github_app_not_configured",
        owner_context_error_type: "github_app_owner_context_missing",
        repo_access_error_type: "github_app_repository_access_unverified",
        installation_access_error_type: "github_app_installation_access_missing_repositories",
        installation_access_remediation:
          "Grant GitHub App installation access to expected repositories and retry validation."
      },
      %{
        path: :pat,
        name: "Personal Access Token (PAT)",
        credential_keys: [:pat],
        api_token_credential: :pat,
        repo_env: "GITHUB_PAT_ACCESSIBLE_REPOS",
        repo_app_env: :github_pat_accessible_repos,
        tracks_expected_repositories: false,
        not_configured_detail: "No GitHub personal access token fallback is configured (`GITHUB_PAT`).",
        not_configured_remediation: "Set `GITHUB_PAT` and retry validation.",
        not_configured_error_type: "github_pat_not_configured",
        owner_context_error_type: "github_pat_owner_context_missing",
        repo_access_error_type: "github_pat_repository_access_unverified"
      }
    ]
  end

  @doc """
  Resolves a GitHub automation credential from runtime env, app env, or encrypted SecretRefs.
  """
  @spec resolve(service_credential()) ::
          {:ok, String.t(), resolution_diagnostics()}
          | {:error, resolution_status(), resolution_diagnostics()}
  def resolve(credential) when credential in [:app_id, :app_private_key, :webhook_secret, :pat] do
    spec = Map.fetch!(@service_credential_specs, credential)

    diagnostics = %{
      credential: credential,
      selected_source: :unavailable,
      env_var: Map.fetch!(spec, :env),
      app_env: Map.fetch!(spec, :app_env),
      secret_ref_scope: :integration,
      secret_ref_name: Map.fetch!(spec, :secret_ref_name),
      secret_ref_key_version: nil,
      secret_ref_source: nil,
      resolution_error_type: nil
    }

    cond do
      value = runtime_env_value(spec) ->
        {:ok, value, %{diagnostics | selected_source: :env}}

      value = app_env_value(spec) ->
        {:ok, value, %{diagnostics | selected_source: :app_env}}

      true ->
        resolve_from_secret_ref(spec, diagnostics)
    end
  end

  def resolve(_credential) do
    {:error, :resolution_failed,
     %{
       credential: :pat,
       selected_source: :error,
       env_var: "GITHUB_PAT",
       app_env: :github_pat,
       secret_ref_scope: :integration,
       secret_ref_name: service_secret_ref_name(:pat),
       secret_ref_key_version: nil,
       secret_ref_source: nil,
       resolution_error_type: :invalid_credential
     }}
  end

  defp resolve_from_secret_ref(spec, diagnostics) do
    case SecretRefs.operational_secret_value(:integration, Map.fetch!(spec, :secret_ref_name)) do
      {:ok, context} ->
        {:ok, Map.fetch!(context, :value),
         %{
           diagnostics
           | selected_source: :secret_ref,
             secret_ref_key_version: Map.fetch!(context, :key_version),
             secret_ref_source: Map.fetch!(context, :source)
         }}

      {:error, %{error_type: "secret_ref_missing"}} ->
        {:error, :secret_unavailable, diagnostics}

      {:error, %{error_type: error_type}} ->
        {:error, :resolution_failed, %{diagnostics | selected_source: :error, resolution_error_type: error_type}}

      {:error, reason} ->
        {:error, :resolution_failed, %{diagnostics | selected_source: :error, resolution_error_type: reason}}
    end
  end

  defp runtime_env_value(spec) do
    spec
    |> Map.fetch!(:env)
    |> System.get_env()
    |> present_runtime_value()
  end

  defp app_env_value(spec) do
    spec
    |> Map.fetch!(:app_env)
    |> then(&Application.get_env(:jido_code, &1))
    |> present_runtime_value()
  end

  defp present_runtime_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_runtime_value(_value), do: nil
end
