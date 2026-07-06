defmodule JidoCode.Runtime do
  @moduledoc """
  Product-owned repository runtime boundary.

  The runtime owns one supervised container per ManagedRepo. It is intentionally
  separate from pod topology: pods are started inside repository runtimes by
  later phases.
  """

  alias JidoCode.Runtime.{RepositoryRuntime, RepositorySupervisor}

  @registry JidoCode.Runtime.Registry

  @type managed_repo_id :: String.t()
  @type runtime_status :: map()

  @spec ensure_repository(managed_repo_id(), String.t() | nil, keyword()) ::
          {:ok, runtime_status()} | {:error, term()}
  def ensure_repository(managed_repo_id, workspace_path, opts \\ [])

  def ensure_repository(managed_repo_id, workspace_path, opts)
      when is_binary(managed_repo_id) and is_list(opts) do
    with {:ok, normalized_workspace_path} <- normalize_workspace_path(workspace_path),
         {:ok, pid} <- ensure_repository_process(managed_repo_id, normalized_workspace_path, opts),
         :ok <- RepositoryRuntime.ensure_workspace(pid, normalized_workspace_path),
         {:ok, status} <- RepositoryRuntime.status(pid) do
      {:ok, status}
    end
  end

  def ensure_repository(_managed_repo_id, _workspace_path, _opts) do
    {:error, %{type: :invalid_managed_repo_id}}
  end

  @spec fetch_repository(managed_repo_id()) :: {:ok, runtime_status()} | :error
  def fetch_repository(managed_repo_id) when is_binary(managed_repo_id) do
    with {:ok, pid} <- lookup_repository_pid(managed_repo_id),
         {:ok, status} <- RepositoryRuntime.status(pid) do
      {:ok, status}
    else
      :error -> :error
      {:error, _reason} -> :error
    end
  end

  def fetch_repository(_managed_repo_id), do: :error

  @spec repository_status(managed_repo_id()) :: runtime_status() | nil
  def repository_status(managed_repo_id) when is_binary(managed_repo_id) do
    case fetch_repository(managed_repo_id) do
      {:ok, status} -> status
      :error -> nil
    end
  end

  def repository_status(_managed_repo_id), do: nil

  @spec list_repositories() :: [runtime_status()]
  def list_repositories do
    @registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.flat_map(fn {_managed_repo_id, pid} ->
      case RepositoryRuntime.status(pid) do
        {:ok, status} -> [status]
        {:error, _reason} -> []
      end
    end)
  end

  @spec repository_count() :: non_neg_integer()
  def repository_count do
    list_repositories() |> length()
  end

  @spec shutdown_repository(managed_repo_id()) :: :ok
  def shutdown_repository(managed_repo_id) when is_binary(managed_repo_id) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} ->
        _ = RepositoryRuntime.mark_stopping(pid)
        _ = RepositorySupervisor.stop_repository(pid)
        :ok

      :error ->
        :ok
    end
  end

  def shutdown_repository(_managed_repo_id), do: :ok

  @spec lookup_repository_pid(managed_repo_id()) :: {:ok, pid()} | :error
  def lookup_repository_pid(managed_repo_id) when is_binary(managed_repo_id) do
    case Registry.lookup(@registry, managed_repo_id) do
      [{pid, _value}] when is_pid(pid) -> {:ok, pid}
      [] -> :error
    end
  end

  def lookup_repository_pid(_managed_repo_id), do: :error

  defp ensure_repository_process(managed_repo_id, workspace_path, opts) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        opts
        |> Keyword.put(:managed_repo_id, managed_repo_id)
        |> Keyword.put(:workspace_path, workspace_path)
        |> RepositorySupervisor.start_repository()
        |> normalize_start_result()
    end
  end

  defp normalize_start_result({:ok, pid}), do: {:ok, pid}
  defp normalize_start_result({:error, {:already_started, pid}}), do: {:ok, pid}
  defp normalize_start_result({:error, reason}), do: {:error, %{type: :runtime_start_failed, reason: reason}}

  defp normalize_workspace_path(nil), do: {:ok, nil}

  defp normalize_workspace_path(workspace_path) when is_binary(workspace_path) do
    workspace_path
    |> String.trim()
    |> case do
      "" -> {:error, %{type: :invalid_workspace_path}}
      path -> {:ok, Path.expand(path)}
    end
  end

  defp normalize_workspace_path(_workspace_path), do: {:error, %{type: :invalid_workspace_path}}
end
