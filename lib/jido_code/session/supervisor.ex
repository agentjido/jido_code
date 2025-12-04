defmodule JidoCode.Session.Supervisor do
  @moduledoc """
  Per-session supervisor that manages session-specific processes.

  Each session gets its own supervisor that manages child processes like
  Session.Manager and Session.State. This supervisor is started as a child
  of the main SessionSupervisor (DynamicSupervisor).

  ## Architecture

  ```
  SessionSupervisor (DynamicSupervisor)
  └── Session.Supervisor (this module)
      ├── Session.Manager (Task 1.4.2)
      └── Session.State (Task 1.4.2)
  ```

  ## Registry

  Each Session.Supervisor registers in `JidoCode.SessionProcessRegistry` with
  the key `{:session, session_id}`. This allows O(1) lookup of session
  supervisors by session ID.

  ## Strategy

  Uses `:one_for_all` strategy because session children are tightly coupled:
  - If Manager crashes, State should restart to ensure consistency
  - If State crashes, Manager needs fresh state
  - All children share the same session context

  ## Usage

  Typically started via SessionSupervisor.start_session/1:

      {:ok, session} = Session.new(project_path: "/tmp/project")
      {:ok, pid} = SessionSupervisor.start_session(session)

  Direct usage (for testing):

      {:ok, pid} = Session.Supervisor.start_link(session: session)
  """

  use Supervisor

  alias JidoCode.Session

  @registry JidoCode.SessionProcessRegistry

  @doc """
  Starts a per-session supervisor.

  ## Options

  - `:session` - (required) The `Session` struct for this session

  ## Returns

  - `{:ok, pid}` - Supervisor started successfully
  - `{:error, reason}` - Failed to start

  ## Examples

      iex> {:ok, session} = Session.new(project_path: "/tmp/project")
      iex> {:ok, pid} = Session.Supervisor.start_link(session: session)
      iex> is_pid(pid)
      true
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    Supervisor.start_link(__MODULE__, session, name: via(session.id))
  end

  @doc """
  Returns the child specification for this supervisor.

  This is used by DynamicSupervisor.start_child/2 when starting session
  supervisors from SessionSupervisor.

  ## Options

  - `:session` - (required) The `Session` struct

  ## Returns

  A child spec map with:
  - `id`: `{:session_supervisor, session_id}`
  - `start`: Module, function, and args for starting
  - `type`: `:supervisor`
  - `restart`: `:temporary` (sessions don't auto-restart)
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    session = Keyword.fetch!(opts, :session)

    %{
      id: {:session_supervisor, session.id},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :temporary
    }
  end

  @doc false
  @impl true
  def init(%Session{} = session) do
    # Session children - both register in SessionProcessRegistry for lookup
    # Manager: handles session coordination and lifecycle
    # State: manages conversation history, tool context, settings
    #
    # Strategy: :one_for_all because children are tightly coupled:
    # - Manager depends on State for session data
    # - State depends on Manager for coordination
    # - If either crashes, both should restart to ensure consistency
    children = [
      {JidoCode.Session.Manager, session: session},
      {JidoCode.Session.State, session: session}
      # Note: LLMAgent will be added in Phase 3 after tool integration
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  # Private helpers

  @doc false
  defp via(session_id) do
    {:via, Registry, {@registry, {:session, session_id}}}
  end
end
