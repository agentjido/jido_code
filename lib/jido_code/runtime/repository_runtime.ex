defmodule JidoCode.Runtime.RepositoryRuntime do
  @moduledoc """
  Product-owned runtime container for one managed repository.

  This process is intentionally small at creation time: it owns repository
  runtime identity and state, while later phases attach pod managers and
  product workflow routing.
  """

  use GenServer

  alias Jido.Agent.InstanceManager
  alias Jido.Pod
  alias JidoCode.Runtime.RepositoryState
  alias JidoCode.Pods.{CodingPod, ContextManagementPod, MemoryGraphPod, RepoPod, SourceCodeGraphPod}

  @registry JidoCode.Runtime.Registry

  @type managed_repo_id :: String.t()
  @type lifecycle :: :starting | :ready | :degraded | :stopping | :stopped

  @type state :: RepositoryState.t()

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    managed_repo_id = Keyword.fetch!(opts, :managed_repo_id)

    %{
      id: {__MODULE__, managed_repo_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5_000,
      type: :worker
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    managed_repo_id = Keyword.fetch!(opts, :managed_repo_id)
    GenServer.start_link(__MODULE__, opts, name: via(managed_repo_id))
  end

  @spec via(managed_repo_id()) :: {:via, Registry, {module(), managed_repo_id()}}
  def via(managed_repo_id) when is_binary(managed_repo_id) do
    {:via, Registry, {@registry, managed_repo_id}}
  end

  @spec status(GenServer.server()) :: {:ok, state()}
  def status(server), do: GenServer.call(server, :status)

  @spec ensure_workspace(GenServer.server(), String.t() | nil) :: :ok | {:error, term()}
  def ensure_workspace(server, workspace_path), do: GenServer.call(server, {:ensure_workspace, workspace_path})

  @spec mark_stopping(GenServer.server()) :: :ok
  def mark_stopping(server), do: GenServer.call(server, :mark_stopping)

  @spec admit_work_item(GenServer.server(), String.t(), map()) :: :ok | {:error, term()}
  def admit_work_item(server, work_item_id, attrs), do: GenServer.call(server, {:admit_work_item, work_item_id, attrs})

  @spec complete_work_item(GenServer.server(), String.t()) :: :ok
  def complete_work_item(server, work_item_id), do: GenServer.call(server, {:complete_work_item, work_item_id})

  @spec active_work_items(GenServer.server()) :: [String.t()]
  def active_work_items(server), do: GenServer.call(server, :active_work_items)

  @spec ensure_repo_pod(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def ensure_repo_pod(server), do: GenServer.call(server, :ensure_repo_pod)

  @spec ensure_source_code_graph_pod(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def ensure_source_code_graph_pod(server), do: GenServer.call(server, :ensure_source_code_graph_pod)

  @spec ensure_memory_graph_pod(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def ensure_memory_graph_pod(server), do: GenServer.call(server, :ensure_memory_graph_pod)

  @spec ensure_coding_pod(GenServer.server(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def ensure_coding_pod(server, work_item_id, workspace_path),
    do: GenServer.call(server, {:ensure_coding_pod, work_item_id, workspace_path})

  @spec ensure_context_management_pod(GenServer.server(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def ensure_context_management_pod(server, work_item_id, workspace_path, attrs),
    do: GenServer.call(server, {:ensure_context_management_pod, work_item_id, workspace_path, attrs})

  @spec complete_work(GenServer.server(), String.t()) :: :ok
  def complete_work(server, work_item_id), do: GenServer.call(server, {:complete_work, work_item_id})

  @impl true
  def init(opts) do
    {:ok, RepositoryState.new(opts)}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, {:ok, RepositoryState.status(state)}, state}
  end

  def handle_call({:ensure_workspace, workspace_path}, _from, state) do
    case RepositoryState.ensure_workspace(state, workspace_path) do
      {:ok, next_state} -> {:reply, :ok, next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:mark_stopping, _from, state) do
    {:reply, :ok, RepositoryState.mark_stopping(state)}
  end

  def handle_call({:admit_work_item, work_item_id, attrs}, _from, state) do
    case RepositoryState.admit_work_item(state, work_item_id, attrs) do
      {:ok, next_state} -> {:reply, :ok, next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:complete_work_item, work_item_id}, _from, state) do
    {:reply, :ok, RepositoryState.complete_work_item(state, work_item_id)}
  end

  def handle_call(:active_work_items, _from, state) do
    {:reply, RepositoryState.active_work_item_ids(state), state}
  end

  def handle_call(:ensure_repo_pod, _from, state) do
    ensure_runtime_pod(
      state,
      :repo,
      {state.managed_repo_id, :repo},
      :jido_code_repo_pods,
      RepoPod,
      %{managed_repo_id: state.managed_repo_id, workspace_path: state.workspace_path}
    )
  end

  def handle_call(:ensure_source_code_graph_pod, _from, state) do
    ensure_runtime_pod(
      state,
      :source_code_graph,
      {state.managed_repo_id, :source_code_graph},
      :jido_code_source_code_graph_pods,
      SourceCodeGraphPod,
      %{managed_repo_id: state.managed_repo_id, workspace_path: state.workspace_path}
    )
  end

  def handle_call(:ensure_memory_graph_pod, _from, state) do
    ensure_runtime_pod(
      state,
      :memory_graph,
      {state.managed_repo_id, :memory_graph},
      :jido_code_memory_graph_pods,
      MemoryGraphPod,
      %{managed_repo_id: state.managed_repo_id, workspace_path: state.workspace_path}
    )
  end

  def handle_call({:ensure_coding_pod, work_item_id, workspace_path}, _from, state) do
    case RepositoryState.admit_work_item(state, work_item_id, %{workspace_path: workspace_path}) do
      {:ok, admitted_state} ->
        ensure_runtime_pod(
          admitted_state,
          :coding,
          {state.managed_repo_id, work_item_id, :coding},
          :jido_code_coding_pods,
          CodingPod,
          %{managed_repo_id: state.managed_repo_id, work_item_id: work_item_id, workspace_path: workspace_path}
        )
        |> put_work_item_pod(:coding_pod, work_item_id)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:ensure_context_management_pod, work_item_id, workspace_path, attrs}, _from, state) do
    case RepositoryState.admit_work_item(state, work_item_id, %{workspace_path: workspace_path}) do
      {:ok, admitted_state} ->
        initial_state =
          Map.merge(attrs, %{
            managed_repo_id: state.managed_repo_id,
            work_item_id: work_item_id,
            workspace_path: workspace_path
          })

        ensure_runtime_pod(
          admitted_state,
          :context_management,
          {state.managed_repo_id, work_item_id, :context_management},
          :jido_code_context_management_pods,
          ContextManagementPod,
          initial_state
        )
        |> put_work_item_pod(:context_management_pod, work_item_id)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:complete_work, work_item_id}, _from, state) do
    coding_key = {state.managed_repo_id, work_item_id, :coding}
    context_key = {state.managed_repo_id, work_item_id, :context_management}

    _ = InstanceManager.stop(:jido_code_coding_pods, coding_key)
    _ = InstanceManager.stop(:jido_code_context_management_pods, context_key)

    next_state =
      state
      |> RepositoryState.delete_pod(:coding, coding_key)
      |> RepositoryState.delete_pod(:context_management, context_key)
      |> RepositoryState.complete_work_item(work_item_id)

    {:reply, :ok, next_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    {:noreply, RepositoryState.mark_process_down(state, ref, pid, reason)}
  end

  defp ensure_runtime_pod(state, kind, key, manager, module, initial_state) do
    case Pod.get(manager, key, initial_state: initial_state) do
      {:ok, pod_pid} ->
        next_state = RepositoryState.put_pod(state, kind, key, module, pod_pid)
        {:reply, {:ok, RepositoryState.pod_status(next_state, kind, key)}, next_state}

      {:error, reason} ->
        diagnostic = %{
          type: :pod_start_failed,
          kind: kind,
          key: key,
          module: module,
          reason: reason,
          observed_at: DateTime.utc_now()
        }

        {:reply, {:error, diagnostic}, RepositoryState.record_diagnostic(state, diagnostic)}
    end
  end

  defp put_work_item_pod({:reply, {:ok, pod_status}, state}, field, work_item_id) do
    {:reply, {:ok, pod_status}, RepositoryState.put_work_item_pod(state, work_item_id, field, pod_status.key)}
  end

  defp put_work_item_pod(other, _field, _work_item_id), do: other
end
