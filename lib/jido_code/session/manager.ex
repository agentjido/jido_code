defmodule JidoCode.Session.Manager do
  @moduledoc """
  Session Manager coordinates session-level operations.

  This GenServer handles:
  - Session lifecycle events (start, stop, pause, resume)
  - Communication routing between session components
  - Session-specific configuration management

  ## Registry

  Each Manager registers in `JidoCode.SessionProcessRegistry` with the key
  `{:manager, session_id}` for O(1) lookup.

  ## Note

  This is a stub implementation for Phase 1. Full functionality will be
  added in Phase 2 (Session Manager Implementation).

  ## Usage

  Typically started as a child of Session.Supervisor:

      # In Session.Supervisor.init/1
      children = [
        {JidoCode.Session.Manager, session: session},
        # ...
      ]

  Direct lookup:

      [{pid, _}] = Registry.lookup(SessionProcessRegistry, {:manager, session_id})
  """

  use GenServer

  alias JidoCode.Session

  @registry JidoCode.SessionProcessRegistry

  @doc """
  Starts the Session Manager.

  ## Options

  - `:session` - (required) The `Session` struct for this session

  ## Returns

  - `{:ok, pid}` - Manager started successfully
  - `{:error, reason}` - Failed to start
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    GenServer.start_link(__MODULE__, session, name: via(session.id))
  end

  @doc """
  Returns the child specification for this GenServer.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    session = Keyword.fetch!(opts, :session)

    %{
      id: {:session_manager, session.id},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # Client API (stubs for Phase 2)

  @doc """
  Gets the session struct for this manager.

  ## Examples

      iex> {:ok, session} = Manager.get_session(pid)
  """
  @spec get_session(GenServer.server()) :: {:ok, Session.t()}
  def get_session(server) do
    GenServer.call(server, :get_session)
  end

  # Server callbacks

  @impl true
  def init(%Session{} = session) do
    {:ok, %{session: session}}
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    {:reply, {:ok, state.session}, state}
  end

  # Private helpers

  defp via(session_id) do
    {:via, Registry, {@registry, {:manager, session_id}}}
  end
end
