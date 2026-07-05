defmodule JidoCode.AuthProviders.ProviderConfigStore do
  @moduledoc """
  Store-backed provider login configuration service.
  """

  alias JidoCode.AuthProviders.ProviderConfig
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError

  @control_plane_ns JidoCode.ControlPlane.SemanticIdentity.ontology_namespace()
  @providers [:github, :gitlab, :bitbucket]
  @allowlist_modes [:none, :users, :organizations, :teams, :groups, :workspaces]

  @spec upsert(map(), keyword()) :: {:ok, ProviderConfig.t()} | {:error, term()}
  def upsert(attrs, opts \\ []) when is_map(attrs) do
    with {:ok, record} <- config_record(attrs) do
      case ProductStore.dispatch(:upsert, :provider_config, Keyword.merge([record: record], opts)) do
        {:ok, %{record: saved_record}} -> {:ok, to_config(saved_record)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec get_by_provider_host(atom() | String.t(), String.t(), keyword()) ::
          {:ok, ProviderConfig.t() | nil} | {:error, term()}
  def get_by_provider_host(provider, provider_host, opts \\ []) do
    source_key = source_key(provider, provider_host)

    request_opts =
      Keyword.merge(
        [
          identity: %{
            identity: :unique_provider_host,
            predicate_iri: RDF.iri(@control_plane_ns <> "sourceKey"),
            value: source_key
          }
        ],
        opts
      )

    case ProductStore.dispatch(:get, :provider_config, request_opts) do
      {:ok, %{projection: projection}} -> decode_projection(projection)
      {:error, %NotFoundError{}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def source_key(provider, provider_host), do: "#{provider}:#{provider_host}"

  def to_config(record) when is_map(record) do
    %ProviderConfig{
      id: map_get(record, :provider_config_id),
      provider: normalize_provider!(map_get(record, :provider)),
      provider_host: map_get(record, :provider_host),
      enabled: truthy?(map_get(record, :enabled, false)),
      login_enabled: truthy?(map_get(record, :login_enabled, false)),
      allowlist_mode: normalize_allowlist_mode!(map_get(record, :allowlist_mode, :none)),
      allowlist_values: record |> map_get(:allowlist_values, []) |> decode_json_list(),
      broker_issuer: map_get(record, :broker_issuer),
      broker_audience: map_get(record, :broker_audience),
      broker_base_url: map_get(record, :broker_base_url)
    }
  end

  defp config_record(attrs) do
    with {:ok, provider} <- normalize_provider(map_get(attrs, :provider)),
         {:ok, provider_host} <- normalize_required_string(map_get(attrs, :provider_host)),
         {:ok, allowlist_mode} <- normalize_allowlist_mode(map_get(attrs, :allowlist_mode, :none)) do
      source_key = source_key(provider, provider_host)

      {:ok,
       %{
         provider_config_id: map_get(attrs, :provider_config_id) || map_get(attrs, :id) || source_key,
         source_key: source_key,
         provider: Atom.to_string(provider),
         provider_host: provider_host,
         enabled: truthy?(map_get(attrs, :enabled, false)),
         login_enabled: truthy?(map_get(attrs, :login_enabled, false)),
         allowlist_mode: Atom.to_string(allowlist_mode),
         allowlist_values: normalize_string_list(map_get(attrs, :allowlist_values, [])),
         broker_issuer: map_get(attrs, :broker_issuer),
         broker_audience: map_get(attrs, :broker_audience),
         broker_base_url: map_get(attrs, :broker_base_url),
         updated_at: DateTime.utc_now(),
         metadata: map_get(attrs, :metadata, %{})
       }}
    end
  end

  defp decode_projection(projection) do
    with {:ok, record} <- Registry.decode(:provider_config, projection) do
      {:ok, to_config(record)}
    end
  end

  defp normalize_provider(provider) when provider in @providers, do: {:ok, provider}

  defp normalize_provider(provider) when is_binary(provider) do
    provider
    |> String.trim()
    |> String.downcase()
    |> case do
      "github" -> {:ok, :github}
      "gitlab" -> {:ok, :gitlab}
      "bitbucket" -> {:ok, :bitbucket}
      _other -> {:error, {:invalid_provider, provider}}
    end
  end

  defp normalize_provider(provider), do: {:error, {:invalid_provider, provider}}
  defp normalize_provider!(provider), do: elem(normalize_provider(provider), 1)

  defp normalize_allowlist_mode(mode) when mode in @allowlist_modes, do: {:ok, mode}

  defp normalize_allowlist_mode(mode) when is_binary(mode) do
    mode
    |> String.trim()
    |> String.downcase()
    |> String.to_existing_atom()
    |> normalize_allowlist_mode()
  rescue
    ArgumentError -> {:error, {:invalid_allowlist_mode, mode}}
  end

  defp normalize_allowlist_mode(mode), do: {:error, {:invalid_allowlist_mode, mode}}
  defp normalize_allowlist_mode!(mode), do: elem(normalize_allowlist_mode(mode), 1)

  defp normalize_required_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: {:error, :missing_provider_host}, else: {:ok, value}
  end

  defp normalize_required_string(_value), do: {:error, :missing_provider_host}

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_string_list(_values), do: []

  defp decode_json_list(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> decoded
      _other -> []
    end
  end

  defp decode_json_list(value) when is_list(value), do: value
  defp decode_json_list(_value), do: []

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_value), do: false

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default
end
