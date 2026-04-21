defmodule JidoCode.Setup.SystemConfigPersistence do
  # covers: setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config
  # covers: setup.onboarding.runtime_environment_selection_persisted_metadata
  @moduledoc """
  Database-backed loader/saver for SystemConfig.

  Plugs into the existing :system_config_loader / :system_config_saver
  configuration to persist onboarding state across server restarts.
  """

  require Ash.Query

  alias JidoCode.Setup.SystemConfig
  alias JidoCode.Setup.SystemConfigRecord

  @spec load() :: {:ok, map()} | {:error, term()}
  def load do
    singleton_key = "singleton"

    query =
      SystemConfigRecord
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(key == ^singleton_key)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [record]} -> {:ok, to_map(record)}
      {:ok, []} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec save(SystemConfig.t()) :: {:ok, map()} | {:error, term()}
  def save(%SystemConfig{} = config) do
    attrs = %{
      onboarding_completed: config.onboarding_completed,
      onboarding_step: config.onboarding_step,
      onboarding_state: config.onboarding_state,
      default_environment: config.default_environment,
      workspace_root: config.workspace_root
    }

    case SystemConfigRecord.upsert_singleton(attrs) do
      {:ok, record} -> {:ok, to_map(record)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_map(record) do
    %{
      onboarding_completed: record.onboarding_completed,
      onboarding_step: record.onboarding_step,
      onboarding_state: record.onboarding_state,
      default_environment: record.default_environment,
      workspace_root: record.workspace_root
    }
  end
end
