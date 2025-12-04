defmodule JidoCode.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for managing per-session supervision trees.

  The SessionSupervisor is the entry point for starting and stopping session
  processes. Each session gets its own supervision subtree managed by this
  supervisor.

  ## Architecture

  ```
  SessionSupervisor (DynamicSupervisor, :one_for_one)
  ├── Session.Supervisor for session_1
  │   ├── Session.Manager
  │   └── Session.State
  ├── Session.Supervisor for session_2
  │   ├── Session.Manager
  │   └── Session.State
  └── ...
  ```

  ## Usage

  The supervisor is typically started as part of the application supervision tree:

      children = [
        # ... other children ...
        JidoCode.SessionSupervisor
      ]

  Session lifecycle is managed via functions in this module (implemented in Task 1.3.2):

      # Start a new session
      {:ok, pid} = SessionSupervisor.start_session(session)

      # Stop a session
      :ok = SessionSupervisor.stop_session(session_id)

  ## Strategy

  Uses `:one_for_one` strategy because sessions are independent - if one
  session's processes crash, other sessions should continue unaffected.
  """

  use DynamicSupervisor

  alias JidoCode.Session
  alias JidoCode.SessionRegistry

  @registry JidoCode.SessionProcessRegistry

  @doc """
  Starts the SessionSupervisor.

  Called by the application supervision tree during startup.

  ## Options

  Currently accepts no meaningful options but follows the standard
  DynamicSupervisor interface for future extensibility.

  ## Examples

      iex> {:ok, pid} = JidoCode.SessionSupervisor.start_link([])
      iex> is_pid(pid)
      true
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # ============================================================================
  # Session Lifecycle (Task 1.3.2)
  # ============================================================================

  @doc """
  Starts a new session under this supervisor.

  Performs the following steps:
  1. Registers the session in SessionRegistry (validates limits/duplicates)
  2. Starts a per-session supervisor as a child of this DynamicSupervisor
  3. On failure, cleans up the registry entry

  ## Parameters

  - `session` - A valid `Session` struct
  - `opts` - Optional keyword list:
    - `:supervisor_module` - Module to use as per-session supervisor
      (default: `JidoCode.Session.Supervisor`)

  ## Returns

  - `{:ok, pid}` - Session started successfully, returns supervisor pid
  - `{:error, :session_limit_reached}` - Maximum sessions already registered
  - `{:error, :session_exists}` - Session with this ID already exists
  - `{:error, :project_already_open}` - Session for this project path exists

  ## Examples

      iex> {:ok, session} = Session.new(project_path: "/tmp/project")
      iex> {:ok, pid} = SessionSupervisor.start_session(session)
      iex> is_pid(pid)
      true
  """
  @spec start_session(Session.t(), keyword()) ::
          {:ok, pid()} | {:error, SessionRegistry.error_reason()}
  def start_session(%Session{} = session, opts \\ []) do
    supervisor_module = Keyword.get(opts, :supervisor_module, JidoCode.Session.Supervisor)

    with {:ok, session} <- SessionRegistry.register(session) do
      spec = {supervisor_module, session: session}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          {:ok, pid}

        {:ok, pid, _info} ->
          {:ok, pid}

        {:error, reason} ->
          # Cleanup on failure - unregister from SessionRegistry
          SessionRegistry.unregister(session.id)
          {:error, reason}
      end
    end
  end

  @doc """
  Stops a session by its ID.

  Performs the following steps:
  1. Finds the session's supervisor pid via Registry lookup
  2. Terminates the supervisor child
  3. Unregisters the session from SessionRegistry

  ## Parameters

  - `session_id` - The session's unique ID

  ## Returns

  - `:ok` - Session stopped successfully
  - `{:error, :not_found}` - No session with this ID exists

  ## Examples

      iex> :ok = SessionSupervisor.stop_session("session-id")
  """
  @spec stop_session(String.t()) :: :ok | {:error, :not_found}
  def stop_session(session_id) do
    with {:ok, pid} <- find_session_pid(session_id),
         :ok <- DynamicSupervisor.terminate_child(__MODULE__, pid) do
      SessionRegistry.unregister(session_id)
      :ok
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Finds the pid of a session's supervisor by session ID.
  # Uses Registry lookup with {:session, session_id} key.
  # This will become public in Task 1.3.3.
  @spec find_session_pid(String.t()) :: {:ok, pid()} | {:error, :not_found}
  defp find_session_pid(session_id) do
    case Registry.lookup(@registry, {:session, session_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
