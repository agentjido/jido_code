defmodule JidoCode.SourceProviders.GitHubAdapter do
  @moduledoc """
  Source provider adapter for GitHub service credentials and repository access.
  """

  # covers: source.provider_adapter.behavior_contract
  # covers: source.provider_adapter.github_adapter
  # covers: source.provider_adapter.github_app_preferred

  @behaviour JidoCode.SourceProviders.Adapter

  alias JidoCode.GitHub.{HTTPClient, ServiceCredentials}

  @impl true
  def provider, do: :github

  @impl true
  def config, do: ServiceCredentials.config()

  @impl true
  def path_definitions, do: ServiceCredentials.path_definitions()

  @impl true
  def resolve_service_credential(credential), do: ServiceCredentials.resolve(credential)

  @impl true
  def resolve_api_token(definition) when is_map(definition) do
    case Map.get(definition, :api_token_credential) do
      credential when credential in [:app_id, :app_private_key, :webhook_secret, :pat] ->
        case ServiceCredentials.resolve(credential) do
          {:ok, value, _diagnostics} -> value
          {:error, _status, _diagnostics} -> nil
        end

      _other ->
        token_env = Map.get(definition, :api_token_env)
        token_app_env = Map.get(definition, :api_token_app_env)

        if is_binary(token_env) and is_atom(token_app_env) do
          credential_value(token_env, token_app_env)
        else
          nil
        end
    end
  end

  @impl true
  def list_accessible_repositories(path, token, opts)
      when path in [:github_app, :pat] and is_binary(token) and is_list(opts) do
    client = Application.get_env(:jido_code, :setup_github_http_client, HTTPClient)
    options = Application.get_env(:jido_code, :setup_github_http_client_options, [])
    request_options = Keyword.merge(options, opts)

    case client do
      module when is_atom(module) ->
        if function_exported?(module, :list_accessible_repositories, 3) do
          module.list_accessible_repositories(path, token, request_options)
        else
          unavailable_client_error()
        end

      fun when is_function(fun, 3) ->
        fun.(path, token, request_options)

      _other ->
        invalid_client_error()
    end
  end

  def list_accessible_repositories(_path, _token, _opts), do: invalid_client_error()

  defp credential_value(env_key, app_env_key) do
    env_key
    |> System.get_env()
    |> present_runtime_value()
    |> case do
      nil ->
        Application.get_env(:jido_code, app_env_key)
        |> present_runtime_value()

      value ->
        value
    end
  end

  defp present_runtime_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_runtime_value(_value), do: nil

  defp unavailable_client_error do
    {:error,
     %{
       error_type: "github_http_client_unavailable",
       detail: "GitHub HTTP client module does not export list_accessible_repositories/3.",
       remediation: "Verify source provider adapter configuration and retry validation."
     }}
  end

  defp invalid_client_error do
    {:error,
     %{
       error_type: "github_http_client_invalid",
       detail: "GitHub HTTP client configuration is invalid.",
       remediation: "Verify source provider adapter configuration and retry validation."
     }}
  end
end
