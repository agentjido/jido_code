defmodule JidoCode.Runtime.RepositoryRuntime do
  @moduledoc """
  Product-owned runtime container for one managed repository.

  This process is intentionally small at creation time: it owns repository
  runtime identity and state, while later phases attach pod managers and
  product workflow routing.
  """

  use GenServer

  alias JidoCode.Runtime.RepositoryState

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

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    {:noreply, RepositoryState.mark_process_down(state, ref, pid, reason)}
  end
end
