defmodule JidoCode.AuthProviders.ProviderLogin do
  @moduledoc """
  Resolves a broker-validated provider identity into a local authenticated session.
  """

  # covers: auth.provider_login_flow.local_user_resolution
  # covers: auth.provider_login_flow.local_session_issuance
  # covers: auth.provider_login_flow.provider_neutral_session_service

  alias JidoCode.Accounts.SessionTokens
  alias JidoCode.Accounts.ProviderIdentityLinker
  alias JidoCode.Accounts.User

  @type result :: %{
          resolution: ProviderIdentityLinker.resolution(),
          user: User.t(),
          identity: struct(),
          token: String.t(),
          session_user: User.t()
        }

  @spec sign_in(map(), Keyword.t()) :: {:ok, result()} | {:error, term()}
  def sign_in(params, opts \\ [])

  def sign_in(params, opts) when is_map(params) and is_list(opts) do
    with {:ok, normalized} <- normalize_claims(params),
         {:ok, linked} <- ProviderIdentityLinker.link(normalized, opts),
         {:ok, token} <- issue_session_token(linked.user) do
      session_user = put_session_token(linked.user, token)

      {:ok,
       linked
       |> Map.put(:token, token)
       |> Map.put(:session_user, session_user)}
    end
  end

  def sign_in(_params, _opts) do
    {:error,
     %{
       error_type: "provider_sign_in_invalid_input",
       message: "Provider sign-in claims are invalid.",
       recovery_instruction: "Restart provider sign-in and retry."
     }}
  end

  defp normalize_claims(params) do
    with {:ok, provider} <- required_provider(params),
         {:ok, provider_host} <- required_string(params, :provider_host, "provider_host"),
         {:ok, provider_subject} <- required_string(params, :provider_subject, "provider_subject") do
      {:ok,
       %{
         provider: provider,
         provider_host: provider_host,
         provider_subject: provider_subject,
         provider_login: optional_string(params, :provider_login, "provider_login"),
         provider_email: optional_string(params, :provider_email, "provider_email"),
         email_verified: truthy?(map_get(params, :email_verified, "email_verified")),
         organizations: string_list(params, :organizations, "organizations"),
         teams: string_list(params, :teams, "teams"),
         groups: string_list(params, :groups, "groups"),
         workspaces: string_list(params, :workspaces, "workspaces"),
         authenticated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
       }}
    end
  end

  defp required_provider(params) do
    case map_get(params, :provider, "provider") |> normalize_provider() do
      nil ->
        {:error,
         %{
           error_type: "provider_sign_in_invalid_input",
           message: "Provider sign-in is missing the provider identifier.",
           recovery_instruction: "Restart provider sign-in and retry."
         }}

      provider ->
        {:ok, provider}
    end
  end

  defp required_string(params, atom_key, string_key) do
    case optional_string(params, atom_key, string_key) do
      nil ->
        {:error,
         %{
           error_type: "provider_sign_in_invalid_input",
           message: "Provider sign-in is missing required identity claims.",
           recovery_instruction: "Restart provider sign-in and retry."
         }}

      value ->
        {:ok, value}
    end
  end

  defp optional_string(params, atom_key, string_key) do
    params
    |> map_get(atom_key, string_key)
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      nil ->
        nil

      value ->
        value
        |> to_string()
        |> optional_string_value()
    end
  end

  defp optional_string_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp string_list(params, atom_key, string_key) do
    case map_get(params, atom_key, string_key) do
      values when is_list(values) ->
        values
        |> Enum.map(&optional_string_value(to_string(&1)))
        |> Enum.reject(&is_nil/1)

      nil ->
        []

      value ->
        value
        |> to_string()
        |> List.wrap()
        |> Enum.map(&optional_string_value/1)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp issue_session_token(%User{} = user) do
    case SessionTokens.issue(user) do
      {:ok, token} ->
        {:ok, token}

      {:error, _reason} ->
        {:error,
         %{
           error_type: "provider_session_token_generation_failed",
           message: "Local session credentials could not be issued for the provider sign-in.",
           recovery_instruction: "Retry provider sign-in or use local email authentication."
         }}
    end
  end

  defp put_session_token(%User{} = user, token) when is_binary(token) do
    metadata =
      user
      |> Map.get(:__metadata__, %{})
      |> Map.put(:token, token)

    %{user | __metadata__: metadata}
  end

  defp normalize_provider(:github), do: :github
  defp normalize_provider(:gitlab), do: :gitlab
  defp normalize_provider(:bitbucket), do: :bitbucket
  defp normalize_provider("github"), do: :github
  defp normalize_provider("gitlab"), do: :gitlab
  defp normalize_provider("bitbucket"), do: :bitbucket
  defp normalize_provider(_provider), do: nil

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(1), do: true
  defp truthy?("1"), do: true
  defp truthy?(_value), do: false

  defp map_get(map, atom_key, string_key) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end
end
