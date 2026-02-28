defmodule JidoCode.Forge.Manager do
  @moduledoc """
  Session lifecycle management for Forge.

  Tracks active sessions, starts them under DynamicSupervisor,
  and registers them in Registry. Enforces concurrency limits
  per runner type to prevent resource exhaustion.
  """

  use GenServer

  require Logger

  alias JidoCode.Forge.Persistence
  alias JidoCode.Forge.PubSub, as: ForgePubSub
  alias JidoCode.Forge.InfraSession

  @supervisor JidoCode.Forge.InfraSupervisor
  @registry JidoCode.Forge.SessionRegistry

  @default_max_sessions 50
  @default_max_per_runner %{
    claude_code: 10,
    shell: 20,
    workflow: 10
  }

  # Public API

  @doc """
  Starts the manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Starts a new session.
  """
  @spec start_session(String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def start_session(session_id, spec) do
    GenServer.call(__MODULE__, {:start_session, session_id, spec})
  end

  @doc """
  Stops a session.
  """
  @spec stop_session(String.t(), term()) :: :ok | {:error, term()}
  def stop_session(session_id, reason \\ :normal) do
    GenServer.call(__MODULE__, {:stop_session, session_id, reason})
  end

  @doc """
  Lists all active session IDs.
  """
  @spec list_sessions() :: [String.t()]
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @doc """
  Gets the pid of a session.
  """
  @spec get_session(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_session(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    state = %{
      sessions: MapSet.new(),
      session_runners: %{},
      runner_counts: %{},
      max_sessions: Keyword.get(opts, :max_sessions, @default_max_sessions),
      max_per_runner: Keyword.get(opts, :max_per_runner, @default_max_per_runner)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_session, session_id, spec}, _from, state) do
    runner_type = Map.get(spec, :runner) || Map.get(spec, :runner_type) || Map.get(spec, "runner_type") || :shell

    cond do
      MapSet.size(state.sessions) >= state.max_sessions ->
        {:reply, {:error, :max_sessions_reached}, state}

      Map.get(state.runner_counts, runner_type, 0) >=
          Map.get(state.max_per_runner, runner_type, 100) ->
        {:reply, {:error, {:runner_limit_reached, runner_type}}, state}

      true ->
        case Registry.lookup(@registry, session_id) do
          [{pid, _}] ->
            {:reply, {:error, {:already_started, pid}}, state}

          [] ->
            Persistence.record_session_started(session_id, spec)

            child_spec = {InfraSession, {session_id, spec, []}}

            case DynamicSupervisor.start_child(@supervisor, child_spec) do
              {:ok, pid} ->
                Process.monitor(pid)
                new_sessions = MapSet.put(state.sessions, session_id)
                new_session_runners = Map.put(state.session_runners, session_id, runner_type)
                new_runner_counts = Map.update(state.runner_counts, runner_type, 1, &(&1 + 1))

                Logger.debug("Started session #{session_id} with pid #{inspect(pid)}")
                ForgePubSub.broadcast_sessions({:session_started, session_id})

                {:reply, {:ok, pid},
                 %{
                   state
                   | sessions: new_sessions,
                     session_runners: new_session_runners,
                     runner_counts: new_runner_counts
                 }}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end
        end
    end
  end

  def handle_call({:stop_session, session_id, reason}, _from, state) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(@supervisor, pid)
        new_state = decrement_session(state, session_id)
        Logger.debug("Stopped session #{session_id}")
        ForgePubSub.broadcast_sessions({:session_stopped, session_id, reason})
        {:reply, :ok, new_state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list_sessions, _from, state) do
    session_list = MapSet.to_list(state.sessions)
    {:reply, session_list, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    dead_sessions =
      state.sessions
      |> MapSet.to_list()
      |> Enum.reject(fn session_id ->
        case Registry.lookup(@registry, session_id) do
          [{_pid, _}] -> true
          [] -> false
        end
      end)

    new_state = Enum.reduce(dead_sessions, state, &decrement_session(&2, &1))
    {:noreply, new_state}
  end

  defp decrement_session(state, session_id) do
    runner_type = Map.get(state.session_runners, session_id)

    new_runner_counts =
      if runner_type do
        Map.update(state.runner_counts, runner_type, 0, &max(&1 - 1, 0))
      else
        state.runner_counts
      end

    %{
      state
      | sessions: MapSet.delete(state.sessions, session_id),
        session_runners: Map.delete(state.session_runners, session_id),
        runner_counts: new_runner_counts
    }
  end
end
