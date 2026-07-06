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
         {:ok, pid} <-
           ensure_repository_process(
             managed_repo_id,
             normalized_workspace_path,
             Keyword.put_new(opts, :capacity, default_capacity())
           ),
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

  @spec admit_work_item(managed_repo_id(), String.t(), map()) :: :ok | {:error, term()}
  def admit_work_item(managed_repo_id, work_item_id, attrs \\ %{})

  def admit_work_item(managed_repo_id, work_item_id, attrs)
      when is_binary(managed_repo_id) and is_binary(work_item_id) and is_map(attrs) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} ->
        RepositoryRuntime.admit_work_item(pid, work_item_id, attrs)

      :error ->
        {:error, %{type: :runtime_unavailable, managed_repo_id: managed_repo_id}}
    end
  end

  def admit_work_item(_managed_repo_id, _work_item_id, _attrs), do: {:error, %{type: :invalid_work_item_id}}

  @spec complete_work_item(managed_repo_id(), String.t()) :: :ok
  def complete_work_item(managed_repo_id, work_item_id) when is_binary(managed_repo_id) and is_binary(work_item_id) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} -> RepositoryRuntime.complete_work_item(pid, work_item_id)
      :error -> :ok
    end
  end

  def complete_work_item(_managed_repo_id, _work_item_id), do: :ok

  @spec active_work_items(managed_repo_id()) :: [String.t()]
  def active_work_items(managed_repo_id) when is_binary(managed_repo_id) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} -> RepositoryRuntime.active_work_items(pid)
      :error -> []
    end
  end

  def active_work_items(_managed_repo_id), do: []

  @spec ensure_repo_pod(managed_repo_id()) :: {:ok, map()} | {:error, term()}
  def ensure_repo_pod(managed_repo_id), do: ensure_repository_pod(managed_repo_id, :ensure_repo_pod)

  @spec ensure_source_code_graph_pod(managed_repo_id()) :: {:ok, map()} | {:error, term()}
  def ensure_source_code_graph_pod(managed_repo_id),
    do: ensure_repository_pod(managed_repo_id, :ensure_source_code_graph_pod)

  @spec ensure_memory_graph_pod(managed_repo_id()) :: {:ok, map()} | {:error, term()}
  def ensure_memory_graph_pod(managed_repo_id), do: ensure_repository_pod(managed_repo_id, :ensure_memory_graph_pod)

  @spec ensure_coding_pod(managed_repo_id(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)
      when is_binary(managed_repo_id) and is_binary(work_item_id) do
    with {:ok, normalized_workspace_path} <- normalize_workspace_path(workspace_path),
         {:ok, _status} <- ensure_repository(managed_repo_id, normalized_workspace_path),
         :ok <- admit_work_item(managed_repo_id, work_item_id, %{workspace_path: normalized_workspace_path}),
         {:ok, pid} <- lookup_repository_pid(managed_repo_id) do
      RepositoryRuntime.ensure_coding_pod(pid, work_item_id, normalized_workspace_path)
    end
  end

  def ensure_coding_pod(_managed_repo_id, _work_item_id, _workspace_path),
    do: {:error, %{type: :invalid_work_item_id}}

  @spec ensure_context_management_pod(managed_repo_id(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def ensure_context_management_pod(managed_repo_id, work_item_id, workspace_path, attrs \\ %{})

  def ensure_context_management_pod(managed_repo_id, work_item_id, workspace_path, attrs)
      when is_binary(managed_repo_id) and is_binary(work_item_id) and is_map(attrs) do
    with {:ok, normalized_workspace_path} <- normalize_workspace_path(workspace_path),
         {:ok, _status} <- ensure_repository(managed_repo_id, normalized_workspace_path),
         :ok <- admit_work_item(managed_repo_id, work_item_id, %{workspace_path: normalized_workspace_path}),
         {:ok, pid} <- lookup_repository_pid(managed_repo_id) do
      RepositoryRuntime.ensure_context_management_pod(pid, work_item_id, normalized_workspace_path, attrs)
    end
  end

  def ensure_context_management_pod(_managed_repo_id, _work_item_id, _workspace_path, _attrs),
    do: {:error, %{type: :invalid_work_item_id}}

  @spec complete_work(managed_repo_id(), String.t()) :: :ok
  def complete_work(managed_repo_id, work_item_id) when is_binary(managed_repo_id) and is_binary(work_item_id) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} -> RepositoryRuntime.complete_work(pid, work_item_id)
      :error -> :ok
    end
  end

  def complete_work(_managed_repo_id, _work_item_id), do: :ok

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
      [{pid, _value}] when is_pid(pid) ->
        if Process.alive?(pid), do: {:ok, pid}, else: :error

      [] ->
        :error
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

  defp ensure_repository_pod(managed_repo_id, operation) when is_binary(managed_repo_id) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} -> apply(RepositoryRuntime, operation, [pid])
      :error -> {:error, %{type: :runtime_unavailable, managed_repo_id: managed_repo_id}}
    end
  end

  defp ensure_repository_pod(_managed_repo_id, _operation), do: {:error, %{type: :invalid_managed_repo_id}}

  defp normalize_workspace_path(nil), do: {:ok, nil}

  defp normalize_workspace_path(workspace_path) when is_binary(workspace_path) do
    workspace_path
    |> String.trim()
    |> case do
      "" -> {:error, %{type: :invalid_workspace_path}}
      path -> validate_workspace_path(Path.expand(path))
    end
  end

  defp normalize_workspace_path(_workspace_path), do: {:error, %{type: :invalid_workspace_path}}

  defp validate_workspace_path(path) do
    if File.dir?(path) do
      {:ok, path}
    else
      {:error, %{type: :workspace_unavailable, workspace_path: path}}
    end
  end

  defp default_capacity do
    %{max_active_work_items: work_queue_limit()}
  end

  defp work_queue_limit do
    case Application.get_env(:jido_code, :agent_workspace_max_concurrent_work_items, :infinity) do
      limit when is_integer(limit) and limit > 0 -> limit
      _other -> :infinity
    end
  end
end
