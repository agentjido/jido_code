defmodule JidoCode.Session.Persistence do
  require Logger

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

  # ETS table for tracking in-progress saves (per-session locks)
  @save_locks_table :jido_code_persistence_save_locks

  @doc """
  Returns the current schema version.
  """
  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  @doc """
  Initializes the persistence module.

  Creates the ETS table for tracking in-progress saves to prevent
  concurrent saves to the same session.

  Should be called during application startup.
  """
  @spec init() :: :ok
  def init do
    # Create ETS table for save locks if it doesn't exist
    case :ets.whereis(@save_locks_table) do
      :undefined ->
        :ets.new(@save_locks_table, [:set, :public, :named_table, read_concurrency: true])
        :ok

      _tid ->
        :ok
    end
  end

  # Returns the maximum file size for session files (configurable)
  # Files larger than this will be skipped to prevent DoS attacks
  defp max_file_size do
    Application.get_env(:jido_code, :persistence, [])
    |> Keyword.get(:max_file_size, 10 * 1024 * 1024)
  end

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
        # Log detailed error for debugging, return sanitized error
        require Logger
        Logger.debug("Validation failed for #{field}: #{inspect(value)}")
        {:halt, {:error, error_key}}
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
    require Logger
    required_fields = [:id, :role, :content, :timestamp]
    message = normalize_keys(message)
    missing = Enum.filter(required_fields, &(not Map.has_key?(message, &1)))

    cond do
      missing != [] ->
        {:error, {:missing_fields, missing}}

      not is_binary(message.id) ->
        Logger.debug("Invalid message ID type: #{inspect(message.id)}")
        {:error, :invalid_id}

      not is_binary(message.role) ->
        Logger.debug("Invalid message role type: #{inspect(message.role)}")
        {:error, :invalid_role}

      message.role not in ["user", "assistant", "system"] ->
        Logger.debug("Unknown message role: #{inspect(message.role)}")
        {:error, :unknown_role}

      not is_binary(message.content) ->
        Logger.debug("Invalid message content type")
        {:error, :invalid_content}

      not is_binary(message.timestamp) ->
        Logger.debug("Invalid message timestamp type: #{inspect(message.timestamp)}")
        {:error, :invalid_timestamp}

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
    require Logger
    required_fields = [:content, :status, :active_form]
    todo = normalize_keys(todo)
    missing = Enum.filter(required_fields, &(not Map.has_key?(todo, &1)))

    cond do
      missing != [] ->
        {:error, {:missing_fields, missing}}

      not is_binary(todo.content) ->
        Logger.debug("Invalid todo content type")
        {:error, :invalid_content}

      not is_binary(todo.status) ->
        Logger.debug("Invalid todo status type: #{inspect(todo.status)}")
        {:error, :invalid_status}

      todo.status not in ["pending", "in_progress", "completed"] ->
        Logger.debug("Unknown todo status: #{inspect(todo.status)}")
        {:error, :unknown_status}

      not is_binary(todo.active_form) ->
        Logger.debug("Invalid todo active_form type")
        {:error, :invalid_active_form}

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

  Validates the session ID to prevent path traversal attacks. Session IDs
  must be valid UUID v4 format.

  ## Parameters

  - `session_id` - The session's unique identifier (must be UUID v4 format)

  ## Returns

  The absolute path to the session file, or raises ArgumentError if the
  session ID is invalid.

  ## Examples

      iex> Persistence.session_file("550e8400-e29b-41d4-a716-446655440000")
      "/home/user/.jido_code/sessions/550e8400-e29b-41d4-a716-446655440000.json"

  ## Security

  Session IDs are validated against UUID v4 format to prevent path traversal
  attacks. Invalid IDs will raise ArgumentError.
  """
  @spec session_file(String.t()) :: String.t()
  def session_file(session_id) when is_binary(session_id) do
    unless valid_session_id?(session_id) do
      # Log detailed error for debugging, but raise generic message to avoid leaking session ID
      require Logger
      Logger.error("Invalid session ID format attempted: #{inspect(session_id)}")

      raise ArgumentError, """
      Invalid session ID format.
      Session IDs must be valid UUID v4 format.
      """
    end

    # Additional sanitization as defense-in-depth
    sanitized_id = sanitize_session_id(session_id)
    Path.join(sessions_dir(), "#{sanitized_id}.json")
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

    # Acquire lock to prevent concurrent saves to same session
    case acquire_save_lock(session_id) do
      :ok ->
        try do
          # Perform save with lock held
          with {:ok, state} <- State.get_state(session_id),
               :ok <- check_session_count_limit(session_id),
               persisted = build_persisted_session(state),
               :ok <- write_session_file(session_id, persisted) do
            {:ok, session_file(session_id)}
          end
        after
          # Always release lock, even if save fails
          release_save_lock(session_id)
        end

      {:error, :save_in_progress} ->
        Logger.debug("Save already in progress for session #{session_id}, skipping concurrent save")
        {:error, :save_in_progress}
    end
  end

  # Acquire per-session save lock using ETS
  # Returns :ok if lock acquired, {:error, :save_in_progress} if already locked
  defp acquire_save_lock(session_id) do
    # insert_new is atomic - returns true only if key didn't exist
    case :ets.insert_new(@save_locks_table, {session_id, :locked, System.monotonic_time()}) do
      true -> :ok
      false -> {:error, :save_in_progress}
    end
  end

  # Release per-session save lock
  defp release_save_lock(session_id) do
    :ets.delete(@save_locks_table, session_id)
    :ok
  end

  # Check if adding this session would exceed max_sessions limit
  # Allows updates to existing sessions, only blocks new sessions
  defp check_session_count_limit(session_id) do
    max_sessions = get_max_sessions()
    session_file = session_file(session_id)

    # If file already exists, this is an update, not a new session
    if File.exists?(session_file) do
      :ok
    else
      # New session - check count
      case list_resumable() do
        {:ok, sessions} ->
          current_count = length(sessions)

          if current_count >= max_sessions do
            require Logger
            Logger.warning("Session limit reached: #{current_count}/#{max_sessions}")
            {:error, :session_limit_reached}
          else
            :ok
          end

        {:error, reason} ->
          # If we can't list sessions, propagate the error
          {:error, reason}
      end
    end
  end

  # Get max_sessions config value
  defp get_max_sessions do
    Application.get_env(:jido_code, :persistence, [])
    |> Keyword.get(:max_sessions, 100)
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
    alias JidoCode.Session.Persistence.Crypto

    :ok = ensure_sessions_dir()
    path = session_file(session_id)
    temp_path = "#{path}.tmp"

    # First, normalize all keys to strings for consistent JSON encoding
    # This ensures decode->re-encode produces identical JSON
    normalized = normalize_keys_to_strings(persisted)

    # Encode to pretty JSON with strict maps for deterministic output
    case Jason.encode(normalized, pretty: true, maps: :strict) do
      {:ok, unsigned_json} ->
        # Generate HMAC signature over the JSON
        signature = Crypto.compute_signature(unsigned_json)

        # Add signature to the normalized map
        signed_map = Map.put(normalized, "signature", signature)

        case Jason.encode(signed_map, pretty: true, maps: :strict) do
          {:ok, signed_json} ->
            with :ok <- File.write(temp_path, signed_json),
                 :ok <- File.rename(temp_path, path) do
              :ok
            else
              {:error, reason} ->
                # Clean up temp file on failure, log detailed error
                File.rm(temp_path)
                require Logger
                Logger.error("Failed to write session file: #{inspect(reason)}")
                {:error, :write_failed}
            end

          {:error, reason} ->
            require Logger
            Logger.error("Failed to encode signed session to JSON: #{inspect(reason)}")
            {:error, :json_encode_error}
        end

      {:error, reason} ->
        require Logger
        Logger.error("Failed to encode session to JSON: #{inspect(reason)}")
        {:error, :json_encode_error}
    end
  end

  # Recursively converts all atom keys to string keys
  # This ensures consistent JSON encoding/decoding
  defp normalize_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) ->
        {Atom.to_string(key), normalize_keys_to_strings(value)}

      {key, value} ->
        {key, normalize_keys_to_strings(value)}
    end)
  end

  defp normalize_keys_to_strings(list) when is_list(list) do
    Enum.map(list, &normalize_keys_to_strings/1)
  end

  defp normalize_keys_to_strings(value), do: value

  # ============================================================================
  # Session Listing
  # ============================================================================

  @doc """
  Lists all persisted sessions from the sessions directory.

  Returns session metadata (id, name, project_path, closed_at) sorted by
  closed_at with most recent first. Corrupted files are skipped gracefully.

  ## Returns

  - `{:ok, sessions}` - List of session metadata maps
  - `{:error, :enoent}` - Sessions directory doesn't exist yet (returns `{:ok, []}`)
  - `{:error, :eacces}` - Permission denied accessing sessions directory
  - `{:error, reason}` - Other filesystem errors

  Session metadata maps contain:
  - `id` - Session identifier
  - `name` - Session name
  - `project_path` - Project path
  - `closed_at` - ISO 8601 timestamp when session was closed

  ## Examples

      iex> Persistence.list_persisted()
      {:ok, [
        %{id: "abc", name: "Session 1", project_path: "/path/1", closed_at: "2024-01-02T00:00:00Z"},
        %{id: "def", name: "Session 2", project_path: "/path/2", closed_at: "2024-01-01T00:00:00Z"}
      ]}

      iex> Persistence.list_persisted()  # Permission denied
      {:error, :eacces}
  """
  @spec list_persisted() :: {:ok, [map()]} | {:error, atom()}
  def list_persisted do
    dir = sessions_dir()

    case File.ls(dir) do
      {:ok, files} ->
        sessions =
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.map(&load_session_metadata/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(&parse_datetime(&1.closed_at), {:desc, DateTime})

        {:ok, sessions}

      {:error, :enoent} ->
        # Sessions directory doesn't exist yet - return empty list
        {:ok, []}

      {:error, reason} = error ->
        # Return distinct errors for permission failures and other issues
        # Caller can decide how to handle (retry, fail, log, etc.)
        Logger.warning("Failed to list sessions directory: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Lists all persisted sessions that can be resumed.

  Excludes sessions that are already active in memory. A session is considered
  active if either:
  - Its session ID matches an active session
  - Its project_path matches an active session's project_path

  Returns sessions sorted by `closed_at` (most recent first).

  ## Returns

  - `{:ok, sessions}` - List of resumable session metadata maps
  - `{:error, reason}` - Filesystem error from list_persisted/0

  ## Examples

      iex> Persistence.list_resumable()
      {:ok, [
        %{id: "sess-123", name: "project1", project_path: "/tmp/p1", closed_at: "2025-01-15T10:00:00Z"},
        %{id: "sess-456", name: "project2", project_path: "/tmp/p2", closed_at: "2025-01-14T09:00:00Z"}
      ]}

      iex> Persistence.list_resumable()
      {:error, :eacces}
  """
  @spec list_resumable() :: {:ok, [map()]} | {:error, atom()}
  def list_resumable do
    alias JidoCode.SessionRegistry

    # Get active sessions once and extract both IDs and paths
    active_sessions = SessionRegistry.list_all()
    active_ids = Enum.map(active_sessions, & &1.id)
    active_paths = Enum.map(active_sessions, & &1.project_path)

    # Filter out persisted sessions that conflict with active ones
    with {:ok, sessions} <- list_persisted() do
      resumable =
        Enum.reject(sessions, fn session ->
          session.id in active_ids or session.project_path in active_paths
        end)

      {:ok, resumable}
    end
  end

  @doc """
  Cleans up old persisted session files.

  Deletes session files that are older than the specified maximum age (in days).
  This function is idempotent and safe to run multiple times. It continues
  processing even if some deletions fail, returning detailed results.

  ## Parameters

  - `max_age_days` - Maximum age in days (default: 30). Sessions closed longer
    ago than this will be deleted.

  ## Returns

  - `{:ok, results}` - Cleanup completed with result map containing:
    - `:deleted` - Number of sessions successfully deleted
    - `:skipped` - Number of sessions skipped (recent or invalid timestamp)
    - `:failed` - Number of sessions that failed to delete
    - `:errors` - List of error tuples `{session_id, reason}` for failed deletions
  - `{:error, reason}` - Failed to list sessions (e.g., `:eacces` permission denied)

  ## Examples

      iex> Persistence.cleanup()
      {:ok, %{deleted: 5, skipped: 2, failed: 0, errors: []}}

      iex> Persistence.cleanup(7)
      {:ok, %{deleted: 10, skipped: 1, failed: 0, errors: []}}

      iex> Persistence.cleanup()
      {:error, :eacces}  # Permission denied

  ## Behavior

  - Uses `list_persisted/0` to get all persisted sessions
  - Compares `closed_at` timestamp with cutoff date
  - Deletes sessions older than cutoff
  - Skips sessions with invalid timestamps (logs warning)
  - Continues even if individual deletions fail
  - Returns detailed results for transparency

  ## Safety

  This function is safe to run multiple times. Already-deleted files won't cause
  errors. Invalid timestamps are logged and skipped rather than causing failures.
  """
  @spec cleanup(pos_integer()) ::
          {:ok,
           %{
             deleted: non_neg_integer(),
             skipped: non_neg_integer(),
             failed: non_neg_integer(),
             errors: [{String.t(), term()}]
           }}
          | {:error, atom()}
  def cleanup(max_age_days \\ 30) when is_integer(max_age_days) and max_age_days > 0 do
    require Logger

    # Calculate cutoff date
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days * 86400, :second)

    Logger.info("Starting session cleanup: removing sessions older than #{max_age_days} days")

    # Get all persisted sessions
    with {:ok, sessions} <- list_persisted() do
      # Process each session and collect results
      results =
        Enum.reduce(sessions, %{deleted: 0, skipped: 0, failed: 0, errors: []}, fn session, acc ->
        case parse_and_compare_timestamp(session.closed_at, cutoff) do
          :older ->
            # Session is old enough to delete
            case delete_persisted(session.id) do
              :ok ->
                Logger.debug("Deleted old session: #{session.id} (#{session.name})")
                %{acc | deleted: acc.deleted + 1}

              {:error, :enoent} ->
                # File already deleted - not an error, just skip
                Logger.debug("Session already deleted: #{session.id}")
                %{acc | skipped: acc.skipped + 1}

              {:error, reason} ->
                Logger.warning("Failed to delete session #{session.id}: #{inspect(reason)}")

                %{
                  acc
                  | failed: acc.failed + 1,
                    errors: [{session.id, reason} | acc.errors]
                }
            end

          :newer ->
            # Session is too recent, skip it
            %{acc | skipped: acc.skipped + 1}

          {:error, reason} ->
            # Invalid timestamp, skip and log
            Logger.warning(
              "Skipping session #{session.id} due to invalid timestamp: #{inspect(reason)}"
            )

            %{acc | skipped: acc.skipped + 1}
        end
      end)

      # Reverse errors list so it's in chronological order
      results = %{results | errors: Enum.reverse(results.errors)}

      Logger.info(
        "Cleanup complete: deleted=#{results.deleted}, skipped=#{results.skipped}, failed=#{results.failed}"
      )

      {:ok, results}
    end
  end

  # Parses timestamp and compares it with cutoff
  # Returns :older, :newer, or {:error, reason}
  @spec parse_and_compare_timestamp(String.t(), DateTime.t()) ::
          :older | :newer | {:error, term()}
  defp parse_and_compare_timestamp(iso_timestamp, cutoff) do
    case DateTime.from_iso8601(iso_timestamp) do
      {:ok, dt, _} ->
        if DateTime.compare(dt, cutoff) == :lt do
          :older
        else
          :newer
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Loads a persisted session from disk.

  Reads the JSON file for the given session ID, parses it, and deserializes
  it into properly typed Elixir data structures.

  ## Parameters

  - `session_id` - The session ID (must be valid UUID v4 format)

  ## Returns

  - `{:ok, session_data}` - Successfully loaded and deserialized session
  - `{:error, :not_found}` - Session file doesn't exist
  - `{:error, {:invalid_json, error}}` - JSON parsing failed
  - `{:error, reason}` - Validation or deserialization failed

  ## Examples

      iex> Persistence.load("550e8400-e29b-41d4-a716-446655440000")
      {:ok, %{id: "550e8400-...", name: "My Session", ...}}

      iex> Persistence.load("nonexistent")
      {:error, :not_found}

  ## Session Data Structure

  The returned map contains:
  - `:id` - Session ID (string)
  - `:name` - Session name (string)
  - `:project_path` - Project directory (string)
  - `:config` - Configuration map
  - `:created_at` - Creation timestamp (DateTime)
  - `:updated_at` - Last update timestamp (DateTime)
  - `:conversation` - List of message maps
  - `:todos` - List of todo maps
  """
  @spec load(String.t()) :: {:ok, map()} | {:error, term()}
  def load(session_id) when is_binary(session_id) do
    alias JidoCode.Session.Persistence.Crypto

    path = session_file(session_id)

    with {:ok, stat} <- File.stat(path),
         :ok <- validate_file_size(stat.size, path),
         {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content),
         {:ok, unsigned_data} <- verify_and_unwrap_signature(data),
         {:ok, session} <- deserialize_session(unsigned_data) do
      {:ok, session}
    else
      {:error, :enoent} ->
        {:error, :not_found}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, error}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Verifies HMAC signature and removes it from payload
  # Handles graceful migration from unsigned v1.0.0 files
  defp verify_and_unwrap_signature(data) do
    alias JidoCode.Session.Persistence.Crypto

    # Check if signature field exists
    case Map.pop(data, "signature") do
      {nil, _} ->
        # Unsigned file (v1.0.0 compatibility)
        Logger.warning(
          "Loading unsigned session file (legacy v1.0.0 format). " <>
          "File will be automatically signed on next save."
        )
        {:ok, data}

      {provided_signature, unsigned_data} ->
        # Signed file - verify it
        # Reconstruct JSON without signature field using same encoding options as when signed
        unsigned_json = Jason.encode!(unsigned_data, pretty: true, maps: :strict)

        case Crypto.verify_signature(unsigned_json, provided_signature) do
          :ok ->
            {:ok, unsigned_data}

          {:error, :signature_verification_failed} ->
            Logger.error("Session file signature verification failed - file may have been tampered with")
            {:error, :signature_verification_failed}
        end
    end
  end

  @doc """
  Deserializes a session from JSON data.

  Converts JSON maps (with string keys and values) into properly typed
  Elixir data structures with atom keys, DateTime structs, and atom enums.

  ## Parameters

  - `data` - Parsed JSON data (map with string keys)

  ## Returns

  - `{:ok, session_map}` - Successfully deserialized session
  - `{:error, reason}` - Validation or conversion failed

  ## Examples

      iex> data = %{"id" => "abc", "name" => "Test", ...}
      iex> Persistence.deserialize_session(data)
      {:ok, %{id: "abc", name: "Test", ...}}
  """
  @spec deserialize_session(map()) :: {:ok, map()} | {:error, term()}
  def deserialize_session(data) when is_map(data) do
    with {:ok, validated} <- validate_session(data),
         {:ok, _version} <- check_schema_version(validated.version),
         {:ok, messages} <- deserialize_messages(validated.conversation),
         {:ok, todos} <- deserialize_todos(validated.todos),
         {:ok, created_at} <- parse_datetime_required(validated.created_at),
         {:ok, updated_at} <- parse_datetime_required(validated.updated_at) do
      {:ok,
       %{
         id: validated.id,
         name: validated.name,
         project_path: validated.project_path,
         config: deserialize_config(validated.config),
         created_at: created_at,
         updated_at: updated_at,
         conversation: messages,
         todos: todos
       }}
    end
  end

  def deserialize_session(_), do: {:error, :not_a_map}

  # Loads minimal session metadata from a JSON file.
  # Returns nil if the file is corrupted, too large, or cannot be read.
  defp load_session_metadata(filename) do
    path = Path.join(sessions_dir(), filename)

    with {:ok, %{size: size}} <- File.stat(path),
         :ok <- validate_file_size(size, filename),
         {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      # Convert string keys to atoms for the fields we need
      %{
        id: Map.get(data, "id"),
        name: Map.get(data, "name"),
        project_path: Map.get(data, "project_path"),
        closed_at: Map.get(data, "closed_at")
      }
    else
      {:error, :file_too_large} ->
        nil

      {:error, reason} when reason != :enoent ->
        Logger.warning("Failed to read session file #{filename}: #{inspect(reason)}")
        nil

      _ ->
        nil
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

  # Validates session ID format (UUID v4)
  # Returns true if the ID matches UUID v4 format, false otherwise
  defp valid_session_id?(id) when is_binary(id) do
    # UUID v4 format: 8-4-4-4-12 hexadecimal characters
    # Version 4 has '4' in the version position and [89ab] in variant position
    Regex.match?(
      ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
      id
    )
  end

  defp valid_session_id?(_), do: false

  # Sanitizes session ID by removing any non-UUID characters
  # This is defense-in-depth after validation
  defp sanitize_session_id(id) do
    String.replace(id, ~r/[^a-zA-Z0-9\-]/, "")
  end

  # Validates file size to prevent DoS attacks
  # Returns :ok if size is within limits, {:error, :file_too_large} otherwise
  defp validate_file_size(size, filename) do
    max_size = max_file_size()

    if size > max_size do
      Logger.warning(
        "Session file #{filename} exceeds maximum size (#{size} bytes > #{max_size} bytes)"
      )

      {:error, :file_too_large}
    else
      :ok
    end
  end

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
  # Only converts keys that correspond to known fields (session, message, todo)
  defp normalize_keys(map) when is_map(map) do
    # Known fields that should be normalized
    # Includes session, message, and todo fields
    known_fields = [
      # Session fields
      "version",
      "id",
      "name",
      "project_path",
      "config",
      "created_at",
      "updated_at",
      "closed_at",
      "conversation",
      "todos",
      # Message fields
      "role",
      "content",
      "timestamp",
      # Task list fields
      "status",
      "active_form"
    ]

    {normalized, unknown} =
      Enum.reduce(map, {%{}, []}, fn
        {key, value}, {acc, unknown_keys} when is_binary(key) ->
          if key in known_fields do
            {Map.put(acc, String.to_atom(key), value), unknown_keys}
          else
            {acc, [key | unknown_keys]}
          end

        {key, value}, {acc, unknown_keys} ->
          {Map.put(acc, key, value), unknown_keys}
      end)

    # Log unknown keys for visibility (but don't warn for empty unknown list)
    if unknown != [] do
      Logger.warning("Unknown keys encountered and skipped: #{inspect(unknown)}")
    end

    normalized
  end

  # ============================================================================
  # Session Deserialization Helpers
  # ============================================================================

  # Check schema version compatibility
  defp check_schema_version(version) when is_integer(version) do
    current = schema_version()

    cond do
      version > current ->
        require Logger
        Logger.warning("Unsupported schema version: #{version} (current: #{current})")
        {:error, :unsupported_version}

      version < 1 ->
        require Logger
        Logger.warning("Invalid schema version: #{version}")
        {:error, :invalid_version}

      true ->
        {:ok, version}
    end
  end

  defp check_schema_version(version) do
    require Logger
    Logger.warning("Invalid schema version type: #{inspect(version)}")
    {:error, :invalid_version}
  end

  # Generic helper for deserializing lists with fail-fast behavior
  # Reduces code duplication between deserialize_messages and deserialize_todos
  defp deserialize_list(items, deserializer_fn, error_key) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case deserializer_fn.(item) do
        {:ok, deserialized} -> {:cont, {:ok, [deserialized | acc]}}
        {:error, reason} -> {:halt, {:error, {error_key, reason}}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp deserialize_list(_, _, error_key), do: {:error, :"#{error_key}s_not_list"}

  # Deserialize list of messages
  defp deserialize_messages(messages) do
    deserialize_list(messages, &deserialize_message/1, :invalid_message)
  end

  # Deserialize single message
  defp deserialize_message(msg) do
    with {:ok, validated} <- validate_message(msg),
         {:ok, timestamp} <- parse_datetime_required(validated.timestamp),
         {:ok, role} <- parse_role(validated.role) do
      {:ok,
       %{
         id: validated.id,
         role: role,
         content: validated.content,
         timestamp: timestamp
       }}
    end
  end

  # Deserialize list of todos
  defp deserialize_todos(todos) do
    deserialize_list(todos, &deserialize_todo/1, :invalid_todo)
  end

  # Deserialize single todo
  defp deserialize_todo(todo) do
    with {:ok, validated} <- validate_todo(todo),
         {:ok, status} <- parse_status(validated.status) do
      {:ok,
       %{
         content: validated.content,
         status: status,
         active_form: validated.active_form
       }}
    end
  end

  # Parse ISO 8601 timestamp (required field)
  defp parse_datetime_required(nil), do: {:error, :missing_timestamp}

  defp parse_datetime_required(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} ->
        {:ok, dt}

      {:error, reason} ->
        # Log detailed error for debugging, return sanitized error
        require Logger
        Logger.debug("Failed to parse timestamp: #{inspect(iso_string)}, reason: #{inspect(reason)}")
        {:error, :invalid_timestamp}
    end
  end

  defp parse_datetime_required(other) do
    require Logger
    Logger.debug("Invalid timestamp type: #{inspect(other)}")
    {:error, :invalid_timestamp}
  end

  # Parse message role string to atom
  defp parse_role("user"), do: {:ok, :user}
  defp parse_role("assistant"), do: {:ok, :assistant}
  defp parse_role("system"), do: {:ok, :system}
  defp parse_role("tool"), do: {:ok, :tool}

  defp parse_role(other) do
    require Logger
    Logger.debug("Invalid role value: #{inspect(other)}")
    {:error, :invalid_role}
  end

  # Parse todo status string to atom
  defp parse_status("pending"), do: {:ok, :pending}
  defp parse_status("in_progress"), do: {:ok, :in_progress}
  defp parse_status("completed"), do: {:ok, :completed}

  defp parse_status(other) do
    require Logger
    Logger.debug("Invalid status value: #{inspect(other)}")
    {:error, :invalid_status}
  end

  # Deserialize config map (string keys to appropriate types)
  defp deserialize_config(config) when is_map(config) do
    # Config uses string keys - just ensure expected structure with defaults
    %{
      "provider" => Map.get(config, "provider", "anthropic"),
      "model" => Map.get(config, "model", "claude-3-5-sonnet-20241022"),
      "temperature" => Map.get(config, "temperature", 0.7),
      "max_tokens" => Map.get(config, "max_tokens", 4096)
    }
  end

  defp deserialize_config(_), do: %{}

  # ============================================================================
  # Session Resume
  # ============================================================================

  @doc """
  Resumes a persisted session, restoring it to fully running state.

  Performs the following steps:
  1. Loads persisted session data from disk
  2. Validates project path still exists
  3. Rebuilds Session struct from persisted data
  4. Starts session processes (Manager, State, Agent)
  5. Restores conversation history and todos
  6. Deletes persisted file (session is now active)

  ## Parameters

  - `session_id` - The session ID (must be valid UUID v4 format)

  ## Returns

  - `{:ok, session}` - Session resumed successfully
  - `{:error, :not_found}` - No persisted session with this ID
  - `{:error, :project_path_not_found}` - Project path no longer exists
  - `{:error, :project_path_not_directory}` - Project path is not a directory
  - `{:error, :session_limit_reached}` - Already 10 sessions running
  - `{:error, :project_already_open}` - Another session for this project
  - `{:error, reason}` - Other errors (deserialization, validation, etc.)

  ## Examples

      iex> Persistence.resume("550e8400-e29b-41d4-a716-446655440000")
      {:ok, %Session{...}}

      iex> Persistence.resume("nonexistent")
      {:error, :not_found}

  ## Cleanup on Failure

  If session processes start successfully but state restoration fails,
  the session is automatically stopped to prevent inconsistent state.
  """
  @spec resume(String.t()) :: {:ok, JidoCode.Session.t()} | {:error, term()}
  def resume(session_id) when is_binary(session_id) do
    alias JidoCode.RateLimit

    with :ok <- RateLimit.check_rate_limit(:resume, session_id),
         {:ok, persisted} <- load(session_id),
         :ok <- validate_project_path(persisted.project_path),
         {:ok, session} <- rebuild_session(persisted),
         {:ok, _pid} <- start_session_processes(session),
         :ok <- restore_state_or_cleanup(session.id, persisted) do
      # Record successful resume for rate limiting
      RateLimit.record_attempt(:resume, session_id)
      {:ok, session}
    end
  end

  # Validates that the project path still exists and is a directory
  @spec validate_project_path(String.t()) :: :ok | {:error, atom()}
  defp validate_project_path(path) do
    cond do
      not File.exists?(path) ->
        {:error, :project_path_not_found}

      not File.dir?(path) ->
        {:error, :project_path_not_directory}

      true ->
        :ok
    end
  end

  # Rebuilds a Session struct from persisted data
  @spec rebuild_session(map()) :: {:ok, JidoCode.Session.t()} | {:error, term()}
  defp rebuild_session(persisted) do
    alias JidoCode.Session

    # Convert string-keyed config to atom-keyed (Session expects atom keys)
    config = %{
      provider: Map.get(persisted.config, "provider"),
      model: Map.get(persisted.config, "model"),
      temperature: Map.get(persisted.config, "temperature"),
      max_tokens: Map.get(persisted.config, "max_tokens")
    }

    session = %Session{
      id: persisted.id,
      name: persisted.name,
      project_path: persisted.project_path,
      config: config,
      created_at: persisted.created_at,
      updated_at: DateTime.utc_now()
    }

    # Validate the reconstructed session
    Session.validate(session)
  end

  # Starts the session processes via SessionSupervisor
  @spec start_session_processes(JidoCode.Session.t()) :: {:ok, pid()} | {:error, term()}
  defp start_session_processes(session) do
    alias JidoCode.SessionSupervisor
    SessionSupervisor.start_session(session)
  end

  # Restores conversation and todos, or cleans up session on failure
  # Includes re-validation of project path to prevent TOCTOU attacks
  @spec restore_state_or_cleanup(String.t(), map()) :: :ok | {:error, term()}
  defp restore_state_or_cleanup(session_id, persisted) do
    with :ok <- revalidate_project_path(persisted.project_path),
         :ok <- restore_conversation(session_id, persisted.conversation),
         :ok <- restore_todos(session_id, persisted.todos),
         :ok <- delete_persisted(session_id) do
      :ok
    else
      error ->
        # State restore or validation failed, stop the session to prevent inconsistent state
        alias JidoCode.SessionSupervisor
        SessionSupervisor.stop_session(session_id)
        error
    end
  end

  # Re-validates project path after session start to prevent TOCTOU attacks
  # This catches cases where the path was swapped/modified between initial
  # validation and session startup
  @spec revalidate_project_path(String.t()) :: :ok | {:error, term()}
  defp revalidate_project_path(project_path) do
    # Re-validate that path still exists and is a directory
    # This prevents TOCTOU attacks where the path is swapped between
    # initial validation and session start
    validate_project_path(project_path)
  end

  # Restores conversation messages to Session.State
  @spec restore_conversation(String.t(), [map()]) :: :ok | {:error, term()}
  defp restore_conversation(session_id, messages) do
    alias JidoCode.Session.State

    # Messages are already deserialized with proper atom keys and DateTime structs
    Enum.reduce_while(messages, :ok, fn message, :ok ->
      case State.append_message(session_id, message) do
        {:ok, _state} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:restore_message_failed, reason}}}
      end
    end)
  end

  # Restores todos to Session.State
  @spec restore_todos(String.t(), [map()]) :: :ok | {:error, term()}
  defp restore_todos(session_id, todos) do
    alias JidoCode.Session.State

    case State.update_todos(session_id, todos) do
      {:ok, _state} -> :ok
      {:error, reason} -> {:error, {:restore_todos_failed, reason}}
    end
  end

  @doc """
  Deletes a persisted session file.

  Removes the JSON file for the specified session ID from disk. This function
  is idempotent - deleting an already-deleted file returns `:ok`.

  ## Parameters

  - `session_id` - The session ID (UUID format)

  ## Returns

  - `:ok` - File successfully deleted or already deleted
  - `{:error, reason}` - Failed to delete file (e.g., permission denied)

  ## Examples

      iex> Persistence.delete_persisted("550e8400-e29b-41d4-a716-446655440000")
      :ok

      iex> Persistence.delete_persisted("nonexistent-id")
      :ok  # Already deleted

  ## Safety

  This function treats missing files (`:enoent`) as success, making it safe
  to call multiple times on the same session ID.
  """
  @spec delete_persisted(String.t()) :: :ok | {:error, term()}
  def delete_persisted(session_id) do
    path = session_file(session_id)

    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        # Already deleted, that's fine
        :ok

      {:error, reason} ->
        # Return error without logging (caller can decide to log)
        {:error, reason}
    end
  end
end
