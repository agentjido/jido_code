defmodule JidoCode.Runtime.RepositoryRuntime do
  @moduledoc """
  Product-owned runtime container for one managed repository.

  This process is intentionally small at creation time: it owns repository
  runtime identity and state, while later phases attach pod managers and
  product workflow routing.
  """

  use GenServer

  @registry JidoCode.Runtime.Registry

  @type managed_repo_id :: String.t()
  @type lifecycle :: :starting | :ready | :degraded | :stopping | :stopped

  @type state :: %{
          managed_repo_id: managed_repo_id(),
          workspace_path: String.t() | nil,
          lifecycle: lifecycle(),
          active_pods: map(),
          active_work_items: map(),
          capacity: map(),
          diagnostics: [map()],
          monitors: map(),
          started_at: DateTime.t(),
          last_activity_at: DateTime.t(),
          last_failure_at: DateTime.t() | nil
        }

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

  @impl true
  def init(opts) do
    now = DateTime.utc_now()

    {:ok,
     %{
       managed_repo_id: Keyword.fetch!(opts, :managed_repo_id),
       workspace_path: Keyword.get(opts, :workspace_path),
       lifecycle: :ready,
       active_pods: %{},
       active_work_items: %{},
       capacity: Keyword.get(opts, :capacity, %{}),
       diagnostics: [],
       monitors: %{},
       started_at: now,
       last_activity_at: now,
       last_failure_at: nil
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, {:ok, Map.delete(state, :monitors)}, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    {monitor_key, monitors} = pop_monitor(state.monitors, ref)

    diagnostic = %{
      type: :owned_process_down,
      monitor_key: monitor_key,
      pid: pid,
      reason: reason,
      observed_at: DateTime.utc_now()
    }

    next_state =
      state
      |> Map.put(:monitors, monitors)
      |> Map.put(:lifecycle, :degraded)
      |> Map.put(:last_failure_at, diagnostic.observed_at)
      |> update_in([:diagnostics], &[diagnostic | &1])

    {:noreply, next_state}
  end

  defp pop_monitor(monitors, ref) do
    case Enum.find(monitors, fn {_key, monitor_ref} -> monitor_ref == ref end) do
      {key, _ref} -> {key, Map.delete(monitors, key)}
      nil -> {nil, monitors}
    end
  end
end
