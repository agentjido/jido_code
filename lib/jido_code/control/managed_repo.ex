defmodule JidoCode.Control.ManagedRepo do
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Control.ManagedRepoStore

  @spec get_by_legacy_project_id(String.t(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_legacy_project_id(project_id, opts \\ []), do: ManagedRepoStore.get_by_legacy_project_id(project_id, opts)

  @spec get_by_source_repo_id(String.t(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_source_repo_id(source_repo_id, opts \\ []),
    do: ManagedRepoStore.get_by_source_repo_id(source_repo_id, opts)

  @spec get_by_id(String.t(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_id(managed_repo_id, opts \\ []), do: ManagedRepoStore.get_by_id(managed_repo_id, opts)
end
