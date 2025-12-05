defmodule JidoCode.Session.Manager do
  @moduledoc """
  Per-session security sandbox manager.

  This GenServer handles:
  - Session-scoped Lua sandbox execution
  - Project boundary enforcement for file operations
  - Session-specific security validation

  ## Registry

  Each Manager registers in `JidoCode.SessionProcessRegistry` with the key
  `{:manager, session_id}` for O(1) lookup.

  ## State

  The manager maintains the following state:

  - `session_id` - Unique identifier for the session
  - `project_root` - Root directory for file operation boundary
  - `lua_state` - Luerl sandbox state (initialized in Task 2.1.2)

  ## Usage

  Typically started as a child of Session.Supervisor:

      # In Session.Supervisor.init/1
      children = [
        {JidoCode.Session.Manager, session: session},
        # ...
      ]

  Direct lookup:

      [{pid, _}] = Registry.lookup(SessionProcessRegistry, {:manager, session_id})

  Access session's project root:

      {:ok, path} = Session.Manager.project_root(session_id)
  """

  use GenServer

  require Logger

  alias JidoCode.Session

  @registry JidoCode.SessionProcessRegistry

  @typedoc """
  Session Manager state.

  - `session_id` - The unique session identifier
  - `project_root` - The root directory for file operation boundary enforcement
  - `lua_state` - The Luerl sandbox state (nil until initialized)
  """
  @type state :: %{
          session_id: String.t(),
          project_root: String.t(),
          lua_state: :luerl.luerl_state() | nil
        }

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

  # Client API

  @doc """
  Gets the project root path for a session.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `{:ok, path}` - The project root path
  - `{:error, :not_found}` - Session manager not found

  ## Examples

      iex> {:ok, path} = Manager.project_root("session_123")
      {:ok, "/path/to/project"}
  """
  @spec project_root(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def project_root(session_id) do
    case Registry.lookup(@registry, {:manager, session_id}) do
      [{pid, _}] -> GenServer.call(pid, :project_root)
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets the session ID from a manager.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `{:ok, session_id}` - The session ID
  - `{:error, :not_found}` - Session manager not found

  ## Examples

      iex> {:ok, id} = Manager.session_id("session_123")
      {:ok, "session_123"}
  """
  @spec session_id(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def session_id(session_id) do
    case Registry.lookup(@registry, {:manager, session_id}) do
      [{pid, _}] -> GenServer.call(pid, :session_id)
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets the session struct for this manager.

  Deprecated: Use `project_root/1` or `session_id/1` instead.

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
    Logger.debug("Starting Session.Manager for session #{session.id} with project_root: #{session.project_path}")

    state = %{
      session_id: session.id,
      project_root: session.project_path,
      lua_state: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:project_root, _from, state) do
    {:reply, {:ok, state.project_root}, state}
  end

  @impl true
  def handle_call(:session_id, _from, state) do
    {:reply, {:ok, state.session_id}, state}
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    # For backwards compatibility, reconstruct a minimal session-like map
    # This will be deprecated in favor of project_root/1 and session_id/1
    session = %Session{
      id: state.session_id,
      project_path: state.project_root,
      name: Path.basename(state.project_root),
      config: %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    {:reply, {:ok, session}, state}
  end

  # Private helpers

  defp via(session_id) do
    {:via, Registry, {@registry, {:manager, session_id}}}
  end
end
