defmodule JidoCode.Setup.SystemConfigPersistence do
  # covers: setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config
  # covers: setup.onboarding.runtime_environment_selection_persisted_metadata
  @moduledoc """
  Embedded control-plane store loader/saver for SystemConfig.

  Plugs into the existing :system_config_loader / :system_config_saver
  configuration to persist onboarding state across server restarts.
  """

  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError
  alias JidoCode.Setup.SystemConfig

  @singleton_key "singleton"
  @system_config_identity %{
    identity: :unique_key,
    predicate_iri: RDF.iri(JidoCode.ControlPlane.SemanticIdentity.ontology_namespace() <> "systemConfigId"),
    value: @singleton_key
  }

  @spec load() :: {:ok, map()} | {:error, term()}
  def load do
    case ProductStore.dispatch(:get, :system_config, identity: @system_config_identity) do
      {:ok, %{projection: projection}} ->
        with {:ok, record} <- Registry.decode(:system_config, projection) do
          {:ok, to_map(record)}
        end

      {:error, %NotFoundError{}} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec save(SystemConfig.t()) :: {:ok, map()} | {:error, term()}
  def save(%SystemConfig{} = config) do
    attrs = %{
      key: @singleton_key,
      onboarding_completed: config.onboarding_completed,
      onboarding_step: config.onboarding_step,
      onboarding_state: config.onboarding_state,
      default_environment: config.default_environment,
      workspace_root: config.workspace_root,
      updated_at: DateTime.utc_now()
    }

    case ProductStore.dispatch(:upsert, :system_config, record: attrs) do
      {:ok, %{record: record}} -> {:ok, to_map(record)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_map(record) do
    %{
      onboarding_completed: map_get(record, :onboarding_completed, false),
      onboarding_step: map_get(record, :onboarding_step, 1),
      onboarding_state: record |> map_get(:onboarding_state, %{}) |> decode_json_map(),
      default_environment: map_get(record, :default_environment, :sprite),
      workspace_root: map_get(record, :workspace_root, nil)
    }
  end

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode_json_map(value) when is_map(value), do: value
  defp decode_json_map(_value), do: %{}

  defp map_get(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
