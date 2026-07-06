defmodule JidoCode.Runtime do
  @moduledoc """
  Product-owned repository runtime boundary.

  The runtime owns one supervised container per ManagedRepo. It is intentionally
  separate from pod topology: pods are started inside repository runtimes by
  later phases.
  """

  alias JidoCode.Operations.RecordStore, as: OperationsRecordStore
  alias JidoCode.Runtime.{RepositoryRuntime, RepositorySupervisor, Snapshot, SnapshotStore}
  alias Jido.Pod

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
         :ok <- maybe_ensure_workspace(pid, normalized_workspace_path),
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

  @spec pod_status(managed_repo_id(), String.t()) :: map() | nil
  def pod_status(managed_repo_id, pod_id) when is_binary(managed_repo_id) and is_binary(pod_id) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} -> RepositoryRuntime.pod_status(pid, pod_id)
      :error -> nil
    end
  end

  def pod_status(_managed_repo_id, _pod_id), do: nil

  @spec list_pods(managed_repo_id()) :: [map()]
  def list_pods(managed_repo_id) when is_binary(managed_repo_id) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} -> RepositoryRuntime.list_pods(pid)
      :error -> []
    end
  end

  def list_pods(_managed_repo_id), do: []

  @spec update_pod_metadata(managed_repo_id(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_pod_metadata(managed_repo_id, pod_id, updates)
      when is_binary(managed_repo_id) and is_binary(pod_id) and is_map(updates) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} -> RepositoryRuntime.update_pod_metadata(pid, pod_id, updates)
      :error -> {:error, %{type: :runtime_unavailable, managed_repo_id: managed_repo_id}}
    end
  end

  def update_pod_metadata(_managed_repo_id, _pod_id, _updates), do: {:error, %{type: :invalid_pod_metadata}}

  @spec coding_pod_status(managed_repo_id(), String.t()) :: map() | nil
  def coding_pod_status(managed_repo_id, work_item_id)
      when is_binary(managed_repo_id) and is_binary(work_item_id) do
    pod_status(managed_repo_id, coding_pod_id(work_item_id))
  end

  def coding_pod_status(_managed_repo_id, _work_item_id), do: nil

  @spec coding_pod_pid(managed_repo_id(), String.t()) :: {:ok, pid()} | {:error, term()}
  def coding_pod_pid(managed_repo_id, work_item_id)
      when is_binary(managed_repo_id) and is_binary(work_item_id) do
    pod_id = coding_pod_id(work_item_id)

    case pod_status(managed_repo_id, pod_id) do
      %{runtime_pid: pid} when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          {:error,
           %{type: :coding_pod_stopped, managed_repo_id: managed_repo_id, work_item_id: work_item_id, pod_id: pod_id}}
        end

      _other ->
        {:error,
         %{type: :coding_pod_unavailable, managed_repo_id: managed_repo_id, work_item_id: work_item_id, pod_id: pod_id}}
    end
  end

  def coding_pod_pid(_managed_repo_id, _work_item_id), do: {:error, %{type: :invalid_work_item_id}}

  @spec ensure_work_item_node(managed_repo_id(), String.t(), atom() | String.t()) ::
          {:ok, pid()} | {:error, term()}
  def ensure_work_item_node(managed_repo_id, work_item_id, node_name)
      when is_binary(managed_repo_id) and is_binary(work_item_id) and (is_atom(node_name) or is_binary(node_name)) do
    with {:ok, pod_pid} <- coding_pod_pid(managed_repo_id, work_item_id) do
      case Pod.ensure_node(pod_pid, node_name) do
        {:ok, node_pid} ->
          {:ok, node_pid}

        {:error, reason} ->
          {:error,
           %{
             type: :work_item_node_unavailable,
             managed_repo_id: managed_repo_id,
             work_item_id: work_item_id,
             node_name: node_name,
             reason: reason
           }}
      end
    end
  end

  def ensure_work_item_node(_managed_repo_id, _work_item_id, _node_name), do: {:error, %{type: :invalid_node_name}}

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

  @spec shutdown_context_management_pod(managed_repo_id(), String.t()) :: :ok
  def shutdown_context_management_pod(managed_repo_id, work_item_id)
      when is_binary(managed_repo_id) and is_binary(work_item_id) do
    case lookup_repository_pid(managed_repo_id) do
      {:ok, pid} -> RepositoryRuntime.shutdown_context_management_pod(pid, work_item_id)
      :error -> :ok
    end
  end

  def shutdown_context_management_pod(_managed_repo_id, _work_item_id), do: :ok

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

  @spec snapshot_repository(managed_repo_id(), keyword()) :: {:ok, Snapshot.t()} | {:error, term()}
  def snapshot_repository(managed_repo_id, opts \\ [])

  def snapshot_repository(managed_repo_id, opts) when is_binary(managed_repo_id) and is_list(opts) do
    with {:ok, status} <- fetch_repository(managed_repo_id),
         {:ok, snapshot} <- Snapshot.from_status(status, opts) do
      {:ok, snapshot}
    else
      :error -> {:error, %{type: :runtime_unavailable, managed_repo_id: managed_repo_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  def snapshot_repository(_managed_repo_id, _opts), do: {:error, %{type: :invalid_managed_repo_id}}

  @spec save_repository_snapshot(managed_repo_id(), keyword()) :: {:ok, Snapshot.t()} | {:error, term()}
  def save_repository_snapshot(managed_repo_id, opts \\ [])

  def save_repository_snapshot(managed_repo_id, opts) when is_binary(managed_repo_id) and is_list(opts) do
    with {:ok, snapshot} <- snapshot_repository(managed_repo_id, opts),
         :ok <- SnapshotStore.save(snapshot, snapshot_store_opts(opts)) do
      {:ok, snapshot}
    end
  end

  def save_repository_snapshot(_managed_repo_id, _opts), do: {:error, %{type: :invalid_managed_repo_id}}

  @spec restore_repository(managed_repo_id(), keyword()) :: {:ok, runtime_status()} | {:error, term()}
  def restore_repository(managed_repo_id, opts \\ [])

  def restore_repository(managed_repo_id, opts) when is_binary(managed_repo_id) and is_list(opts) do
    with {:ok, snapshot} <- load_repository_snapshot(managed_repo_id, opts),
         :ok <- validate_snapshot_workspace(snapshot, opts),
         {:ok, pid} <-
           ensure_repository_process(
             managed_repo_id,
             snapshot.workspace_path,
             Keyword.put_new(opts, :capacity, capacity_from_snapshot(snapshot))
           ),
         :ok <- maybe_ensure_workspace(pid, snapshot.workspace_path),
         {:ok, restore_plan} <- restore_plan(snapshot, opts),
         {:ok, status} <- RepositoryRuntime.restore_snapshot(pid, Snapshot.to_record(snapshot), restore_plan) do
      {:ok, status}
    end
  end

  def restore_repository(_managed_repo_id, _opts), do: {:error, %{type: :invalid_managed_repo_id}}

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

  defp maybe_ensure_workspace(_pid, nil), do: :ok
  defp maybe_ensure_workspace(pid, workspace_path), do: RepositoryRuntime.ensure_workspace(pid, workspace_path)

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

  defp load_repository_snapshot(managed_repo_id, opts) do
    case SnapshotStore.load(managed_repo_id, snapshot_store_opts(opts)) do
      {:ok, %Snapshot{} = snapshot} ->
        {:ok, snapshot}

      :error ->
        {:error, %{type: :runtime_snapshot_not_found, managed_repo_id: managed_repo_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_snapshot_workspace(%Snapshot{workspace_path: nil}, _opts), do: :ok

  defp validate_snapshot_workspace(%Snapshot{workspace_path: workspace_path}, opts) do
    if Keyword.get(opts, :validate_workspace?, true) do
      validate_workspace_path(workspace_path)
      |> case do
        {:ok, _workspace_path} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp restore_plan(%Snapshot{} = snapshot, opts) do
    validate_work_items? = Keyword.get(opts, :validate_work_items?, true)

    {work_items, diagnostics} =
      snapshot.active_work_items
      |> Enum.reduce({[], []}, fn work_item, {work_items, diagnostics} ->
        case restorable_work_item(work_item, snapshot, opts, validate_work_items?) do
          {:ok, restored_work_item} ->
            {[restored_work_item | work_items], diagnostics}

          {:stale, diagnostic} ->
            {work_items, [diagnostic | diagnostics]}
        end
      end)

    {:ok, %{work_items: Enum.reverse(work_items), diagnostics: Enum.reverse(diagnostics)}}
  end

  defp restorable_work_item(work_item, snapshot, opts, validate_work_items?) do
    work_item_id = Map.get(work_item, "work_item_id") || Map.get(work_item, :work_item_id)

    workspace_path =
      Map.get(work_item, "workspace_path") || Map.get(work_item, :workspace_path) || snapshot.workspace_path

    cond do
      not is_binary(work_item_id) ->
        {:stale, stale_work_diagnostic(nil, :invalid_work_item_id)}

      snapshot.workspace_path && workspace_path && snapshot.workspace_path != workspace_path ->
        {:stale, stale_work_diagnostic(work_item_id, :workspace_mismatch)}

      Keyword.get(opts, :validate_workspace?, true) and is_binary(workspace_path) and not File.dir?(workspace_path) ->
        {:stale, stale_work_diagnostic(work_item_id, :workspace_unavailable)}

      validate_work_items? ->
        validate_restorable_work_item(
          Map.put(work_item, "workspace_path", workspace_path),
          work_item_id,
          snapshot.managed_repo_id,
          opts
        )

      true ->
        {:ok, Map.put(work_item, "workspace_path", workspace_path)}
    end
  end

  defp validate_restorable_work_item(work_item, work_item_id, managed_repo_id, opts) do
    case resolve_work_item(work_item_id, managed_repo_id, opts) do
      {:ok, %{managed_repo_id: ^managed_repo_id}} ->
        {:ok, work_item}

      {:ok, %{managed_repo_id: other_repo_id}} ->
        {:stale, stale_work_diagnostic(work_item_id, {:wrong_managed_repo, other_repo_id})}

      {:ok, nil} ->
        {:stale, stale_work_diagnostic(work_item_id, :work_item_not_found)}

      {:error, reason} ->
        {:stale, stale_work_diagnostic(work_item_id, {:work_item_lookup_failed, reason})}
    end
  end

  defp resolve_work_item(work_item_id, managed_repo_id, opts) do
    resolver = Keyword.get(opts, :work_item_resolver, &default_work_item_resolver/1)

    cond do
      is_function(resolver, 2) -> resolver.(managed_repo_id, work_item_id)
      is_function(resolver, 1) -> resolver.(work_item_id)
      true -> {:error, :invalid_work_item_resolver}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp default_work_item_resolver(work_item_id) do
    OperationsRecordStore.get(:work_item, work_item_id)
  end

  defp stale_work_diagnostic(work_item_id, reason) do
    %{
      type: :runtime_snapshot_stale_work,
      work_item_id: work_item_id,
      reason: reason,
      observed_at: DateTime.utc_now()
    }
  end

  defp capacity_from_snapshot(%Snapshot{capacity: capacity}) when is_map(capacity) do
    limit = Map.get(capacity, "max_active_work_items") || Map.get(capacity, :max_active_work_items)
    %{max_active_work_items: restore_capacity_limit(limit)}
  end

  defp capacity_from_snapshot(_snapshot), do: default_capacity()

  defp restore_capacity_limit("infinity"), do: :infinity
  defp restore_capacity_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp restore_capacity_limit(_limit), do: :infinity

  defp snapshot_store_opts(opts), do: Keyword.take(opts, [:backend])

  defp default_capacity do
    %{max_active_work_items: work_queue_limit()}
  end

  defp coding_pod_id(work_item_id), do: "coding-pod-#{work_item_id}"

  defp work_queue_limit do
    case Application.get_env(:jido_code, :agent_workspace_max_concurrent_work_items, :infinity) do
      limit when is_integer(limit) and limit > 0 -> limit
      _other -> :infinity
    end
  end
end
