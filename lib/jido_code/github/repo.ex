defmodule JidoCode.GitHub.Repo do
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.GitHub.RepoStore

  @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(attrs, opts \\ []) when is_map(attrs), do: RepoStore.create(attrs, opts)

  @spec update(t() | String.t(), map(), keyword()) :: {:ok, t()} | {:error, term()}
  def update(repo_or_id, attrs, opts \\ []) when is_map(attrs), do: RepoStore.update(repo_or_id, attrs, opts)

  @spec disable(t() | String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def disable(repo_or_id, opts \\ []), do: RepoStore.disable(repo_or_id, opts)

  @spec get_by_id(String.t(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_id(id, opts \\ []), do: RepoStore.get_by_id(id, opts)

  @spec get_by_full_name(String.t(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_full_name(full_name, opts \\ []), do: RepoStore.get_by_full_name(full_name, opts)
end
