defmodule JidoCode.Control.SourceRepo do
  # covers: architecture.repo_identity.source_repo_tracks_provider_identity
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Control.{Actor, SourceRepoStore}

  @allowed_actor_classes [:admin, :operator, :factory_system, :managed_repo_orchestrator]

  @spec upsert_identity(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def upsert_identity(attrs, opts \\ []) when is_map(attrs) do
    if Actor.allowed?(Keyword.get(opts, :actor), @allowed_actor_classes) do
      SourceRepoStore.upsert(attrs, opts)
    else
      {:error, forbidden_error()}
    end
  end

  @spec get_by_provider_and_full_name(atom() | String.t(), String.t(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_provider_and_full_name(provider, full_name, opts \\ []),
    do: SourceRepoStore.get_by_provider_and_full_name(provider, full_name, opts)

  @spec get_by_id(String.t(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_id(source_repo_id, opts \\ []), do: SourceRepoStore.get_by_id(source_repo_id, opts)

  defp forbidden_error do
    %{
      type: :forbidden,
      reason: :missing_allowed_actor,
      message: "control-plane mutation requires an allowed actor"
    }
  end
end
