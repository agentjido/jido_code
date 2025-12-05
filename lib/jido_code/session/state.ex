defmodule JidoCode.Session.State do
  @moduledoc """
  Session State manages the runtime state for a session.

  This GenServer handles:
  - Conversation history
  - Tool execution context
  - Session-specific settings
  - Undo/redo history

  ## Registry

  Each State process registers in `JidoCode.SessionProcessRegistry` with the key
  `{:state, session_id}` for O(1) lookup.

  ## Note

  This is a stub implementation for Phase 1. Full functionality will be
  added in Phase 2 (Session State Implementation).

  ## Usage

  Typically started as a child of Session.Supervisor:

      # In Session.Supervisor.init/1
      children = [
        {JidoCode.Session.State, session: session},
        # ...
      ]

  Direct lookup:

      [{pid, _}] = Registry.lookup(SessionProcessRegistry, {:state, session_id})
  """

  use GenServer

  alias JidoCode.Session
  alias JidoCode.Session.ProcessRegistry

  @doc """
  Starts the Session State process.

  ## Options

  - `:session` - (required) The `Session` struct for this session

  ## Returns

  - `{:ok, pid}` - State process started successfully
  - `{:error, reason}` - Failed to start
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    GenServer.start_link(__MODULE__, session, name: ProcessRegistry.via(:state, session.id))
  end

  @doc """
  Returns the child specification for this GenServer.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    session = Keyword.fetch!(opts, :session)

    %{
      id: {:session_state, session.id},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # Client API (stubs for Phase 2)

  @doc """
  Gets the session struct for this state process.

  ## Examples

      iex> {:ok, session} = State.get_session(pid)
  """
  @spec get_session(GenServer.server()) :: {:ok, Session.t()}
  def get_session(server) do
    GenServer.call(server, :get_session)
  end

  # Server callbacks

  @impl true
  def init(%Session{} = session) do
    {:ok,
     %{
       session: session,
       # Placeholder state fields for Phase 2
       conversation_history: [],
       tool_context: %{},
       settings: %{}
     }}
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    {:reply, {:ok, state.session}, state}
  end

end
