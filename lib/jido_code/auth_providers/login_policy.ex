defmodule JidoCode.AuthProviders.LoginPolicy do
  # covers: auth.provider_login_policy.provider_enablement
  # covers: auth.provider_login_policy.allowlist_evaluation
  # covers: auth.provider_login_policy.provider_neutral_logic
  alias JidoCode.AuthProviders.ProviderConfig
  alias JidoCode.AuthProviders.ProviderConfigStore

  @list_modes [:organizations, :teams, :groups, :workspaces]

  @spec authorize(map()) :: {:ok, ProviderConfig.t()} | {:error, map() | term()}
  def authorize(params) when is_map(params) do
    with {:ok, provider} <- fetch_required(params, :provider, "provider"),
         {:ok, provider_host} <- fetch_required(params, :provider_host, "provider_host"),
         {:ok, %ProviderConfig{} = config} <- load_config(provider, provider_host),
         :ok <- ensure_login_enabled(config),
         :ok <- ensure_allowlisted(config, params) do
      {:ok, config}
    end
  end

  def authorize(_params), do: {:error, invalid_input_error(:invalid_provider_login_policy_input)}

  defp load_config(provider, provider_host) do
    case ProviderConfigStore.get_by_provider_host(provider, provider_host) do
      {:ok, %ProviderConfig{} = config} ->
        {:ok, config}

      {:ok, nil} ->
        {:error,
         %{
           error_type: "provider_login_not_configured",
           provider: provider,
           provider_host: provider_host
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_login_enabled(%ProviderConfig{enabled: false} = config) do
    {:error, disabled_error(config)}
  end

  defp ensure_login_enabled(%ProviderConfig{login_enabled: false} = config) do
    {:error, disabled_error(config)}
  end

  defp ensure_login_enabled(_config), do: :ok

  defp ensure_allowlisted(%ProviderConfig{allowlist_mode: :none}, _params), do: :ok

  defp ensure_allowlisted(%ProviderConfig{} = config, params) do
    allowlist_values = Enum.map(config.allowlist_values || [], &normalize_value/1)
    subject_values = subject_values(config.allowlist_mode, params)

    if Enum.any?(subject_values, &(&1 in allowlist_values)) do
      :ok
    else
      {:error,
       %{
         error_type: "provider_identity_not_allowlisted",
         provider: config.provider,
         provider_host: config.provider_host,
         allowlist_mode: config.allowlist_mode
       }}
    end
  end

  defp subject_values(:users, params) do
    [map_get(params, :provider_login, "provider_login"), map_get(params, :provider_email, "provider_email")]
    |> Enum.map(&normalize_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp subject_values(mode, params) when mode in @list_modes do
    params
    |> list_field(mode)
    |> Enum.map(&normalize_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp subject_values(_mode, _params), do: []

  defp list_field(params, :organizations), do: list_values(params, :organizations, "organizations")
  defp list_field(params, :teams), do: list_values(params, :teams, "teams")
  defp list_field(params, :groups), do: list_values(params, :groups, "groups")
  defp list_field(params, :workspaces), do: list_values(params, :workspaces, "workspaces")

  defp list_values(params, atom_key, string_key) do
    case map_get(params, atom_key, string_key) do
      values when is_list(values) -> values
      nil -> []
      value -> [value]
    end
  end

  defp fetch_required(params, atom_key, string_key) do
    case normalize_value(map_get(params, atom_key, string_key)) do
      nil -> {:error, invalid_input_error({:missing_required_field, atom_key})}
      value -> {:ok, value}
    end
  end

  defp normalize_value(nil), do: nil
  defp normalize_value(""), do: nil
  defp normalize_value(value) when is_binary(value), do: value |> String.trim() |> blank_to_nil() |> downcase()
  defp normalize_value(value), do: value |> to_string() |> normalize_value()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp downcase(nil), do: nil
  defp downcase(value), do: String.downcase(value)

  defp disabled_error(%ProviderConfig{} = config) do
    %{
      error_type: "provider_login_disabled",
      provider: config.provider,
      provider_host: config.provider_host
    }
  end

  defp invalid_input_error(reason), do: %{error_type: "provider_login_policy_invalid_input", reason: reason}

  defp map_get(map, atom_key, string_key) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end
end
