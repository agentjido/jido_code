defmodule JidoCode.Session.Persistence do
  @moduledoc """
  Session persistence schema and utilities.

  This module defines the data structures used for persisting sessions to disk,
  enabling session state to be saved and restored via the `/resume` command.

  ## Schema Version

  Current schema version: 1

  Schema versioning enables forward-compatible migrations as the persistence
  format evolves. When loading persisted sessions, the version field is checked
  and migrations are applied if needed.

  ### Version History

  - **Version 1** (Initial): Basic session persistence with conversation and todos

  ## Data Types

  Three main types are defined for persistence:

  - `persisted_session/0` - Complete session state including metadata
  - `persisted_message/0` - Single conversation message
  - `persisted_todo/0` - Single todo item

  ## File Format

  Sessions are persisted as JSON files in `~/.jido_code/sessions/` with the
  naming pattern `{session_id}.json`.

  ## Usage

  This module is used internally by the session management system. Sessions
  are automatically saved when closed and can be restored using the `/resume`
  command.
  """

  # ============================================================================
  # Schema Version
  # ============================================================================

  # Current schema version for persisted sessions.
  # Increment this when making breaking changes to the persistence format.
  # The `deserialize_session/1` function should handle migration from older versions.
  @schema_version 1

  @doc """
  Returns the current schema version.
  """
  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @typedoc """
  Complete persisted session data.

  Contains all information needed to restore a session, including:

  - `version` - Schema version for migrations
  - `id` - Unique session identifier (preserved on restore)
  - `name` - User-visible session name
  - `project_path` - Absolute path to the project directory
  - `config` - LLM configuration (provider, model, temperature, etc.)
  - `created_at` - ISO 8601 timestamp when session was first created
  - `updated_at` - ISO 8601 timestamp of last activity
  - `closed_at` - ISO 8601 timestamp when session was saved/closed
  - `conversation` - List of conversation messages
  - `todos` - List of todo items
  """
  @type persisted_session :: %{
          version: pos_integer(),
          id: String.t(),
          name: String.t(),
          project_path: String.t(),
          config: map(),
          created_at: String.t(),
          updated_at: String.t(),
          closed_at: String.t(),
          conversation: [persisted_message()],
          todos: [persisted_todo()]
        }

  @typedoc """
  Single conversation message for persistence.

  Contains:

  - `id` - Unique message identifier
  - `role` - Message role (user, assistant, system)
  - `content` - Message text content
  - `timestamp` - ISO 8601 timestamp when message was created
  """
  @type persisted_message :: %{
          id: String.t(),
          role: String.t(),
          content: String.t(),
          timestamp: String.t()
        }

  @typedoc """
  Single todo item for persistence.

  Contains:

  - `content` - Todo description (imperative form, e.g., "Run tests")
  - `status` - Current status (pending, in_progress, completed)
  - `active_form` - Present continuous form (e.g., "Running tests")
  """
  @type persisted_todo :: %{
          content: String.t(),
          status: String.t(),
          active_form: String.t()
        }

  # ============================================================================
  # Schema Validation
  # ============================================================================

  @doc """
  Validates a persisted session map matches the expected schema.

  Returns `{:ok, session}` if valid, `{:error, reason}` otherwise.

  ## Examples

      iex> session = %{version: 1, id: "abc", name: "Test", ...}
      iex> Persistence.validate_session(session)
      {:ok, session}

      iex> Persistence.validate_session(%{})
      {:error, {:missing_fields, [:version, :id, ...]}}
  """
  @spec validate_session(map()) :: {:ok, persisted_session()} | {:error, term()}
  def validate_session(session) when is_map(session) do
    required_fields = [
      :version,
      :id,
      :name,
      :project_path,
      :config,
      :created_at,
      :updated_at,
      :closed_at,
      :conversation,
      :todos
    ]

    # Convert string keys to atoms for validation
    session = normalize_keys(session)

    missing = Enum.filter(required_fields, &(not Map.has_key?(session, &1)))

    if missing != [] do
      {:error, {:missing_fields, missing}}
    else
      validate_session_fields(session)
    end
  end

  def validate_session(_), do: {:error, :not_a_map}

  defp validate_session_fields(session) do
    validations = [
      {&valid_version?/1, :version, :invalid_version},
      {&is_binary/1, :id, :invalid_id},
      {&is_binary/1, :name, :invalid_name},
      {&is_binary/1, :project_path, :invalid_project_path},
      {&is_map/1, :config, :invalid_config},
      {&is_list/1, :conversation, :invalid_conversation},
      {&is_list/1, :todos, :invalid_todos}
    ]

    Enum.reduce_while(validations, {:ok, session}, fn {validator, field, error_key}, acc ->
      value = Map.get(session, field)

      if validator.(value) do
        {:cont, acc}
      else
        {:halt, {:error, {error_key, value}}}
      end
    end)
  end

  defp valid_version?(v), do: is_integer(v) and v >= 1

  @doc """
  Validates a persisted message map matches the expected schema.

  ## Examples

      iex> msg = %{id: "1", role: "user", content: "Hello", timestamp: "2024-01-01T00:00:00Z"}
      iex> Persistence.validate_message(msg)
      {:ok, msg}
  """
  @spec validate_message(map()) :: {:ok, persisted_message()} | {:error, term()}
  def validate_message(message) when is_map(message) do
    required_fields = [:id, :role, :content, :timestamp]
    message = normalize_keys(message)
    missing = Enum.filter(required_fields, &(not Map.has_key?(message, &1)))

    cond do
      missing != [] ->
        {:error, {:missing_fields, missing}}

      not is_binary(message.id) ->
        {:error, {:invalid_id, message.id}}

      not is_binary(message.role) ->
        {:error, {:invalid_role, message.role}}

      message.role not in ["user", "assistant", "system"] ->
        {:error, {:unknown_role, message.role}}

      not is_binary(message.content) ->
        {:error, {:invalid_content, message.content}}

      not is_binary(message.timestamp) ->
        {:error, {:invalid_timestamp, message.timestamp}}

      true ->
        {:ok, message}
    end
  end

  def validate_message(_), do: {:error, :not_a_map}

  @doc """
  Validates a persisted todo map matches the expected schema.

  ## Examples

      iex> todo = %{content: "Run tests", status: "pending", active_form: "Running tests"}
      iex> Persistence.validate_todo(todo)
      {:ok, todo}
  """
  @spec validate_todo(map()) :: {:ok, persisted_todo()} | {:error, term()}
  def validate_todo(todo) when is_map(todo) do
    required_fields = [:content, :status, :active_form]
    todo = normalize_keys(todo)
    missing = Enum.filter(required_fields, &(not Map.has_key?(todo, &1)))

    cond do
      missing != [] ->
        {:error, {:missing_fields, missing}}

      not is_binary(todo.content) ->
        {:error, {:invalid_content, todo.content}}

      not is_binary(todo.status) ->
        {:error, {:invalid_status, todo.status}}

      todo.status not in ["pending", "in_progress", "completed"] ->
        {:error, {:unknown_status, todo.status}}

      not is_binary(todo.active_form) ->
        {:error, {:invalid_active_form, todo.active_form}}

      true ->
        {:ok, todo}
    end
  end

  def validate_todo(_), do: {:error, :not_a_map}

  # ============================================================================
  # Schema Helpers
  # ============================================================================

  @doc """
  Creates a new persisted session map with the current schema version.

  This is a convenience function for building valid persisted session data.
  All timestamps should be in ISO 8601 format.
  """
  @spec new_session(map()) :: persisted_session()
  def new_session(attrs) when is_map(attrs) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      version: @schema_version,
      id: Map.fetch!(attrs, :id),
      name: Map.fetch!(attrs, :name),
      project_path: Map.fetch!(attrs, :project_path),
      config: Map.get(attrs, :config, %{}),
      created_at: Map.get(attrs, :created_at, now),
      updated_at: Map.get(attrs, :updated_at, now),
      closed_at: Map.get(attrs, :closed_at, now),
      conversation: Map.get(attrs, :conversation, []),
      todos: Map.get(attrs, :todos, [])
    }
  end

  @doc """
  Creates a new persisted message map.
  """
  @spec new_message(map()) :: persisted_message()
  def new_message(attrs) when is_map(attrs) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      id: Map.fetch!(attrs, :id),
      role: Map.fetch!(attrs, :role),
      content: Map.fetch!(attrs, :content),
      timestamp: Map.get(attrs, :timestamp, now)
    }
  end

  @doc """
  Creates a new persisted todo map.
  """
  @spec new_todo(map()) :: persisted_todo()
  def new_todo(attrs) when is_map(attrs) do
    %{
      content: Map.fetch!(attrs, :content),
      status: Map.get(attrs, :status, "pending"),
      active_form: Map.fetch!(attrs, :active_form)
    }
  end

  # ============================================================================
  # Storage Location
  # ============================================================================

  @doc """
  Returns the directory path where persisted sessions are stored.

  The sessions directory is located at `~/.jido_code/sessions/`.

  ## Examples

      iex> Persistence.sessions_dir()
      "/home/user/.jido_code/sessions"
  """
  @spec sessions_dir() :: String.t()
  def sessions_dir do
    Path.join([System.user_home!(), ".jido_code", "sessions"])
  end

  @doc """
  Returns the file path for a persisted session.

  Session files are named `{session_id}.json` within the sessions directory.

  ## Examples

      iex> Persistence.session_file("abc123")
      "/home/user/.jido_code/sessions/abc123.json"
  """
  @spec session_file(String.t()) :: String.t()
  def session_file(session_id) when is_binary(session_id) do
    Path.join(sessions_dir(), "#{session_id}.json")
  end

  @doc """
  Ensures the sessions directory exists, creating it if necessary.

  Returns `:ok` if the directory exists or was created successfully,
  or `{:error, reason}` if creation failed.

  ## Examples

      iex> Persistence.ensure_sessions_dir()
      :ok
  """
  @spec ensure_sessions_dir() :: :ok | {:error, term()}
  def ensure_sessions_dir do
    case File.mkdir_p(sessions_dir()) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Session Saving
  # ============================================================================

  @doc """
  Saves a session to disk as a JSON file.

  Fetches the current session state, serializes it to JSON, and writes it
  atomically to the sessions directory.

  ## Arguments

  - `session_id` - The unique session identifier

  ## Returns

  - `{:ok, path}` - The path where the session was saved
  - `{:error, :not_found}` - Session not found
  - `{:error, reason}` - Write failed

  ## Examples

      iex> Persistence.save("session-123")
      {:ok, "/home/user/.jido_code/sessions/session-123.json"}
  """
  @spec save(String.t()) :: {:ok, String.t()} | {:error, term()}
  def save(session_id) when is_binary(session_id) do
    alias JidoCode.Session.State

    with {:ok, state} <- State.get_state(session_id),
         persisted = build_persisted_session(state),
         :ok <- write_session_file(session_id, persisted) do
      {:ok, session_file(session_id)}
    end
  end

  @doc """
  Builds a persisted session map from runtime state.

  Converts the live session state into the persistence format, including
  serializing messages and todos to their string-based representations.
  """
  @spec build_persisted_session(map()) :: persisted_session()
  def build_persisted_session(state) do
    session = state.session

    %{
      version: schema_version(),
      id: session.id,
      name: session.name,
      project_path: session.project_path,
      config: serialize_config(session.config),
      created_at: format_datetime(session.created_at),
      updated_at: format_datetime(session.updated_at),
      closed_at: DateTime.to_iso8601(DateTime.utc_now()),
      conversation: Enum.map(state.messages, &serialize_message/1),
      todos: Enum.map(state.todos, &serialize_todo/1)
    }
  end

  @doc """
  Writes a persisted session to disk atomically.

  Uses a temporary file and rename to ensure atomic writes, preventing
  partial or corrupted files if the write is interrupted.
  """
  @spec write_session_file(String.t(), persisted_session()) :: :ok | {:error, term()}
  def write_session_file(session_id, persisted) do
    :ok = ensure_sessions_dir()
    path = session_file(session_id)
    temp_path = "#{path}.tmp"

    case Jason.encode(persisted, pretty: true) do
      {:ok, json} ->
        with :ok <- File.write(temp_path, json),
             :ok <- File.rename(temp_path, path) do
          :ok
        else
          {:error, reason} ->
            # Clean up temp file on failure
            File.rm(temp_path)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:json_encode_error, reason}}
    end
  end

  # ============================================================================
  # Session Listing
  # ============================================================================

  @doc """
  Lists all persisted sessions from the sessions directory.

  Returns session metadata (id, name, project_path, closed_at) sorted by
  closed_at with most recent first. Corrupted files are skipped gracefully.

  ## Returns

  A list of maps with session metadata:
  - `id` - Session identifier
  - `name` - Session name
  - `project_path` - Project path
  - `closed_at` - ISO 8601 timestamp when session was closed

  ## Examples

      iex> Persistence.list_persisted()
      [
        %{id: "abc", name: "Session 1", project_path: "/path/1", closed_at: "2024-01-02T00:00:00Z"},
        %{id: "def", name: "Session 2", project_path: "/path/2", closed_at: "2024-01-01T00:00:00Z"}
      ]
  """
  @spec list_persisted() :: [map()]
  def list_persisted do
    dir = sessions_dir()

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(&load_session_metadata/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(&parse_datetime(&1.closed_at), {:desc, DateTime})

      {:error, :enoent} ->
        # Sessions directory doesn't exist yet - return empty list
        []

      {:error, _} ->
        # Other errors (permissions, etc.) - return empty list
        []
    end
  end

  # Loads minimal session metadata from a JSON file.
  # Returns nil if the file is corrupted or cannot be read.
  defp load_session_metadata(filename) do
    path = Path.join(sessions_dir(), filename)

    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      # Convert string keys to atoms for the fields we need
      %{
        id: Map.get(data, "id"),
        name: Map.get(data, "name"),
        project_path: Map.get(data, "project_path"),
        closed_at: Map.get(data, "closed_at")
      }
    else
      _ -> nil
    end
  end

  # Parse ISO 8601 datetime string, returning a default old date on error
  defp parse_datetime(nil), do: ~U[1970-01-01 00:00:00Z]

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> dt
      {:error, _} -> ~U[1970-01-01 00:00:00Z]
    end
  end

  defp parse_datetime(_), do: ~U[1970-01-01 00:00:00Z]

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Serialize a message to the persisted format
  defp serialize_message(msg) do
    %{
      id: msg.id,
      role: to_string(msg.role),
      content: msg.content,
      timestamp: format_datetime(msg.timestamp)
    }
  end

  # Serialize a todo to the persisted format
  defp serialize_todo(todo) do
    %{
      content: todo.content,
      status: to_string(todo.status),
      # Fall back to content if active_form not present
      active_form: Map.get(todo, :active_form) || todo.content
    }
  end

  # Serialize config, converting atoms to strings for JSON
  defp serialize_config(config) when is_struct(config) do
    config
    |> Map.from_struct()
    |> serialize_config()
  end

  defp serialize_config(config) when is_map(config) do
    Map.new(config, fn
      {key, value} when is_atom(value) -> {to_string(key), to_string(value)}
      {key, value} when is_map(value) -> {to_string(key), serialize_config(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp serialize_config(other), do: other

  # Format datetime to ISO 8601 string, handling nil
  defp format_datetime(nil), do: DateTime.to_iso8601(DateTime.utc_now())
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  # Normalize map keys from strings to atoms for validation
  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  rescue
    ArgumentError -> map
  end
end
