defmodule JidoCode.SessionRegistry do
  @moduledoc """
  ETS-backed registry for tracking active JidoCode sessions.

  The SessionRegistry provides centralized session management with:
  - Session registration with 10-session limit enforcement
  - Lookup by session ID, project path, or name
  - Session listing and counting
  - Session updates and removal

  ## ETS Table Structure

  Sessions are stored as `{session_id, session_struct}` tuples in a `:set` table.
  The table is `:public` for concurrent access but all operations should go through
  this module's API functions.

  ## Usage

      # Create the table (called by Application.start/2)
      SessionRegistry.create_table()

      # Register a new session
      {:ok, session} = SessionRegistry.register(session)

      # Lookup by ID
      {:ok, session} = SessionRegistry.lookup("session-id")

      # List all sessions
      sessions = SessionRegistry.list_all()

  ## Session Limit

  The registry enforces a maximum of 10 concurrent sessions. This limit is
  configurable via the `@max_sessions` module attribute.
  """

  alias JidoCode.Session

  @max_sessions 10
  @table __MODULE__

  @typedoc "Error reasons for registry operations"
  @type error_reason ::
          :session_limit_reached
          | :session_exists
          | :project_already_open
          | :not_found

  # ============================================================================
  # Table Management
  # ============================================================================

  @doc """
  Creates the ETS table for session storage.

  The table is created with the following options:
  - `:named_table` - accessible by name (#{inspect(@table)})
  - `:public` - any process can read/write
  - `:set` - unique keys (session IDs)
  - `read_concurrency: true` - optimized for concurrent reads

  Returns `:ok` if the table was created or already exists.

  ## Examples

      iex> JidoCode.SessionRegistry.create_table()
      :ok

      # Idempotent - can be called multiple times
      iex> JidoCode.SessionRegistry.create_table()
      :ok
  """
  @spec create_table() :: :ok
  def create_table do
    if table_exists?() do
      :ok
    else
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
      :ok
    end
  end

  @doc """
  Checks if the ETS table exists.

  Returns `true` if the table exists, `false` otherwise.

  ## Examples

      iex> JidoCode.SessionRegistry.table_exists?()
      false

      iex> JidoCode.SessionRegistry.create_table()
      :ok
      iex> JidoCode.SessionRegistry.table_exists?()
      true
  """
  @spec table_exists?() :: boolean()
  def table_exists? do
    case :ets.whereis(@table) do
      :undefined -> false
      _tid -> true
    end
  end

  @doc """
  Returns the maximum number of allowed concurrent sessions.

  ## Examples

      iex> JidoCode.SessionRegistry.max_sessions()
      10
  """
  @spec max_sessions() :: pos_integer()
  def max_sessions, do: @max_sessions

  # ============================================================================
  # Session Registration (Task 1.2.2)
  # ============================================================================

  @doc """
  Registers a session in the registry.

  Performs three validations before registration:
  1. Session count limit (max 10)
  2. Duplicate session ID detection
  3. Duplicate project path detection

  ## Parameters

  - `session` - A valid `Session` struct

  ## Returns

  - `{:ok, session}` - Session registered successfully
  - `{:error, :session_limit_reached}` - Maximum 10 sessions already registered
  - `{:error, :session_exists}` - Session with this ID already exists
  - `{:error, :project_already_open}` - Session for this project path already exists

  ## Examples

      iex> {:ok, session} = Session.new(project_path: "/tmp/project")
      iex> {:ok, session} = SessionRegistry.register(session)
      iex> session.id
      "some-uuid"
  """
  @spec register(Session.t()) :: {:ok, Session.t()} | {:error, error_reason()}
  def register(%Session{} = session) do
    cond do
      count() >= @max_sessions ->
        {:error, :session_limit_reached}

      session_exists?(session.id) ->
        {:error, :session_exists}

      path_in_use?(session.project_path) ->
        {:error, :project_already_open}

      true ->
        :ets.insert(@table, {session.id, session})
        {:ok, session}
    end
  end

  # Checks if a session with the given ID exists in the registry
  @spec session_exists?(String.t()) :: boolean()
  defp session_exists?(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, _session}] -> true
      [] -> false
    end
  end

  # Checks if a session with the given project_path exists in the registry
  @spec path_in_use?(String.t()) :: boolean()
  defp path_in_use?(project_path) do
    # Use match_object to find sessions with matching project_path
    # Pattern: {_id, %Session{project_path: path}} where path matches
    match_spec = [{
      {:_, %Session{project_path: :"$1", id: :_, name: :_, config: :_, created_at: :_, updated_at: :_}},
      [{:==, :"$1", project_path}],
      [true]
    }]

    case :ets.select(@table, match_spec) do
      [true | _] -> true
      [] -> false
    end
  end

  # ============================================================================
  # Session Lookup (Task 1.2.3)
  # ============================================================================

  @doc """
  Looks up a session by ID.

  Uses direct ETS key lookup for O(1) performance.

  ## Parameters

  - `session_id` - The session's unique ID

  ## Returns

  - `{:ok, session}` - Session found
  - `{:error, :not_found}` - No session with this ID

  ## Examples

      iex> {:ok, session} = SessionRegistry.lookup("session-id")
      iex> session.name
      "my-project"
  """
  @spec lookup(String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def lookup(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, session}] -> {:ok, session}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Looks up a session by project path.

  Since project paths are unique (enforced by `register/1`), this will
  return at most one session.

  ## Parameters

  - `project_path` - The absolute path to the project directory

  ## Returns

  - `{:ok, session}` - Session found
  - `{:error, :not_found}` - No session for this path

  ## Examples

      iex> {:ok, session} = SessionRegistry.lookup_by_path("/home/user/project")
      iex> session.name
      "project"
  """
  @spec lookup_by_path(String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def lookup_by_path(project_path) do
    # Match spec to find session with matching project_path
    match_spec = [{
      {:_, %Session{project_path: :"$1", id: :_, name: :_, config: :_, created_at: :_, updated_at: :_}},
      [{:==, :"$1", project_path}],
      [:"$_"]
    }]

    case :ets.select(@table, match_spec) do
      [{_id, session} | _] -> {:ok, session}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Looks up a session by name.

  Note: Names are not unique, so this returns the first matching session
  sorted by `created_at` (oldest first) for consistent results.

  ## Parameters

  - `name` - The session name to search for

  ## Returns

  - `{:ok, session}` - First matching session found
  - `{:error, :not_found}` - No session with this name

  ## Examples

      iex> {:ok, session} = SessionRegistry.lookup_by_name("my-project")
      iex> session.project_path
      "/home/user/my-project"
  """
  @spec lookup_by_name(String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def lookup_by_name(name) do
    # Match spec to find sessions with matching name
    match_spec = [{
      {:_, %Session{name: :"$1", id: :_, project_path: :_, config: :_, created_at: :_, updated_at: :_}},
      [{:==, :"$1", name}],
      [:"$_"]
    }]

    case :ets.select(@table, match_spec) do
      [] ->
        {:error, :not_found}

      matches ->
        # Sort by created_at and return first (oldest)
        {_id, session} =
          matches
          |> Enum.sort_by(fn {_id, s} -> s.created_at end, DateTime)
          |> List.first()

        {:ok, session}
    end
  end

  # ============================================================================
  # Session Listing (Task 1.2.4)
  # ============================================================================

  @doc """
  Lists all registered sessions.

  Returns sessions sorted by `created_at` timestamp (oldest first).

  ## Examples

      iex> SessionRegistry.list_all()
      [%Session{name: "project1", ...}, %Session{name: "project2", ...}]
  """
  @spec list_all() :: [Session.t()]
  def list_all do
    if table_exists?() do
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, session} -> session end)
      |> Enum.sort_by(& &1.created_at, DateTime)
    else
      []
    end
  end

  @doc """
  Returns the number of registered sessions.

  Uses `:ets.info/2` for efficient counting without iterating.

  ## Examples

      iex> SessionRegistry.count()
      3
  """
  @spec count() :: non_neg_integer()
  def count do
    case :ets.info(@table, :size) do
      :undefined -> 0
      size -> size
    end
  end

  @doc """
  Lists all registered session IDs.

  Returns IDs sorted by `created_at` timestamp (oldest first).

  ## Examples

      iex> SessionRegistry.list_ids()
      ["session-id-1", "session-id-2", "session-id-3"]
  """
  @spec list_ids() :: [String.t()]
  def list_ids do
    list_all()
    |> Enum.map(& &1.id)
  end

  # ============================================================================
  # Session Removal (Task 1.2.5 - stub for now)
  # ============================================================================

  @doc """
  Removes a session from the registry.

  Returns `:ok` regardless of whether the session existed.

  ## Parameters

  - `session_id` - The session's unique ID

  ## Examples

      iex> SessionRegistry.unregister("session-id")
      :ok
  """
  @spec unregister(String.t()) :: :ok
  def unregister(_session_id) do
    # TODO: Implement in Task 1.2.5
    :ok
  end

  @doc """
  Removes all sessions from the registry.

  Primarily used for testing.

  ## Examples

      iex> SessionRegistry.clear()
      :ok
  """
  @spec clear() :: :ok
  def clear do
    # TODO: Implement in Task 1.2.5
    :ok
  end

  # ============================================================================
  # Session Updates (Task 1.2.6 - stub for now)
  # ============================================================================

  @doc """
  Updates a session in the registry.

  The session must already exist in the registry.

  ## Parameters

  - `session` - The updated session struct

  ## Returns

  - `{:ok, session}` - Session updated successfully
  - `{:error, :not_found}` - Session not in registry

  ## Examples

      iex> {:ok, updated} = Session.rename(session, "new-name")
      iex> {:ok, _} = SessionRegistry.update(updated)
  """
  @spec update(Session.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def update(%Session{} = _session) do
    # TODO: Implement in Task 1.2.6
    {:error, :not_implemented}
  end
end
