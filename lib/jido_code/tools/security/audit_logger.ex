defmodule JidoCode.Tools.Security.AuditLogger do
  @moduledoc """
  Comprehensive invocation logging for tool executions.

  This module provides audit trail functionality for all tool invocations,
  storing entries in an ETS ring buffer for efficient memory-bounded logging.

  ## Features

  - **Ring Buffer Storage**: Fixed-size ETS table prevents unbounded growth
  - **Privacy Protection**: Arguments are hashed, not stored raw
  - **Session Filtering**: Query audit logs by session
  - **Telemetry Integration**: Emits events for monitoring
  - **Logger Integration**: Logs blocked invocations

  ## Usage

      # Log a tool invocation
      AuditLogger.log_invocation("session_123", "read_file", :ok, 150)

      # Get audit log for a session
      AuditLogger.get_audit_log("session_123")

      # Get full audit log
      AuditLogger.get_audit_log()

  ## Audit Entry Structure

  Each audit entry contains:
  - `:id` - Unique entry identifier
  - `:timestamp` - UTC timestamp of invocation
  - `:session_id` - Session identifier
  - `:tool` - Tool name
  - `:status` - `:ok`, `:error`, or `:blocked`
  - `:duration_us` - Execution duration in microseconds
  - `:args_hash` - SHA256 hash of arguments (for correlation without exposure)

  ## Configuration

  - Default buffer size: 10,000 entries
  - Configure via application config: `config :jido_code, audit_buffer_size: 20_000`
  """

  require Logger

  @ets_table :jido_code_audit_log
  @default_buffer_size 10_000

  @typedoc """
  Status of a tool invocation.
  """
  @type status :: :ok | :error | :blocked

  @typedoc """
  An audit log entry.
  """
  @type audit_entry :: %{
          id: pos_integer(),
          timestamp: DateTime.t(),
          session_id: String.t(),
          tool: String.t(),
          status: status(),
          duration_us: non_neg_integer(),
          args_hash: String.t() | nil
        }

  @typedoc """
  Options for logging invocations.
  """
  @type log_option ::
          {:args, map()}
          | {:emit_telemetry, boolean()}
          | {:log_blocked, boolean()}

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Logs a tool invocation to the audit trail.

  ## Parameters

  - `session_id` - Session identifier
  - `tool` - Tool name
  - `status` - `:ok`, `:error`, or `:blocked`
  - `duration_us` - Execution duration in microseconds
  - `opts` - Options:
    - `:args` - Tool arguments (will be hashed for privacy)
    - `:emit_telemetry` - Whether to emit telemetry (default: true)
    - `:log_blocked` - Whether to log blocked invocations to Logger (default: true)

  ## Returns

  The audit entry ID.

  ## Examples

      iex> AuditLogger.log_invocation("sess_123", "read_file", :ok, 1500)
      1

      iex> AuditLogger.log_invocation("sess_123", "write_file", :blocked, 0,
      ...>   args: %{"path" => "/etc/passwd"})
      2
  """
  @spec log_invocation(String.t(), String.t(), status(), non_neg_integer(), [log_option()]) ::
          pos_integer()
  def log_invocation(session_id, tool, status, duration_us, opts \\ []) do
    ensure_table_exists()

    args = Keyword.get(opts, :args)
    emit_telemetry = Keyword.get(opts, :emit_telemetry, true)
    log_blocked = Keyword.get(opts, :log_blocked, true)

    entry_id = next_entry_id()
    args_hash = hash_args(args)

    entry = %{
      id: entry_id,
      timestamp: DateTime.utc_now(),
      session_id: session_id,
      tool: tool,
      status: status,
      duration_us: duration_us,
      args_hash: args_hash
    }

    # Store in ring buffer
    insert_entry(entry)

    # Emit telemetry
    if emit_telemetry do
      emit_audit_telemetry(entry)
    end

    # Log blocked invocations
    if status == :blocked and log_blocked do
      Logger.warning(
        "[AuditLogger] Blocked invocation: session=#{session_id} tool=#{tool} args_hash=#{args_hash || "nil"}"
      )
    end

    entry_id
  end

  @doc """
  Retrieves the audit log, optionally filtered by session.

  ## Parameters

  - `session_id` - Optional session ID to filter by (default: nil returns all)
  - `opts` - Options:
    - `:limit` - Maximum entries to return (default: 1000)
    - `:order` - `:asc` or `:desc` by timestamp (default: `:desc`)

  ## Returns

  List of audit entries matching the criteria.

  ## Examples

      iex> AuditLogger.get_audit_log("session_123")
      [%{id: 5, session_id: "session_123", tool: "read_file", ...}, ...]

      iex> AuditLogger.get_audit_log(limit: 10)
      [%{id: 100, ...}, %{id: 99, ...}, ...]
  """
  @spec get_audit_log(String.t() | nil | keyword()) :: [audit_entry()]
  def get_audit_log(session_id_or_opts \\ nil)

  def get_audit_log(opts) when is_list(opts) do
    do_get_audit_log(nil, opts)
  end

  def get_audit_log(session_id) when is_binary(session_id) do
    do_get_audit_log(session_id, [])
  end

  def get_audit_log(nil) do
    do_get_audit_log(nil, [])
  end

  @doc """
  Retrieves the audit log filtered by session with options.

  ## Parameters

  - `session_id` - Session ID to filter by
  - `opts` - Options (see `get_audit_log/1`)

  ## Returns

  List of audit entries for the session.
  """
  @spec get_audit_log(String.t(), keyword()) :: [audit_entry()]
  def get_audit_log(session_id, opts) when is_binary(session_id) do
    do_get_audit_log(session_id, opts)
  end

  @doc """
  Clears all audit log entries.

  Primarily useful for testing.
  """
  @spec clear_all() :: :ok
  def clear_all do
    ensure_table_exists()
    :ets.delete_all_objects(@ets_table)
    reset_entry_counter()
    :ok
  end

  @doc """
  Clears audit log entries for a specific session.

  ## Parameters

  - `session_id` - Session identifier
  """
  @spec clear_session(String.t()) :: :ok
  def clear_session(session_id) do
    ensure_table_exists()

    # Find and delete all entries for this session
    :ets.foldl(
      fn {id, entry}, acc ->
        if entry.session_id == session_id do
          :ets.delete(@ets_table, id)
        end

        acc
      end,
      :ok,
      @ets_table
    )

    :ok
  end

  @doc """
  Returns the current count of audit log entries.
  """
  @spec count() :: non_neg_integer()
  def count do
    ensure_table_exists()
    :ets.info(@ets_table, :size)
  end

  @doc """
  Returns the configured buffer size.
  """
  @spec buffer_size() :: pos_integer()
  def buffer_size do
    Application.get_env(:jido_code, :audit_buffer_size, @default_buffer_size)
  end

  @doc """
  Hashes arguments for privacy-preserving logging.

  Returns a truncated SHA256 hash of the arguments.
  """
  @spec hash_args(map() | nil) :: String.t() | nil
  def hash_args(nil), do: nil

  def hash_args(args) when is_map(args) do
    args
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp do_get_audit_log(session_id, opts) do
    ensure_table_exists()

    limit = Keyword.get(opts, :limit, 1000)
    order = Keyword.get(opts, :order, :desc)

    entries =
      :ets.foldl(
        fn {_id, entry}, acc ->
          if session_id == nil or entry.session_id == session_id do
            [entry | acc]
          else
            acc
          end
        end,
        [],
        @ets_table
      )

    entries
    |> sort_entries(order)
    |> Enum.take(limit)
  end

  defp sort_entries(entries, :desc) do
    Enum.sort_by(entries, & &1.id, :desc)
  end

  defp sort_entries(entries, :asc) do
    Enum.sort_by(entries, & &1.id, :asc)
  end

  defp ensure_table_exists do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:named_table, :public, :set])
        init_entry_counter()

      _ ->
        :ok
    end
  end

  defp next_entry_id do
    counter = get_or_create_counter()
    :atomics.add_get(counter, 1, 1)
  end

  defp init_entry_counter do
    get_or_create_counter()
  end

  defp reset_entry_counter do
    counter = get_or_create_counter()
    :atomics.put(counter, 1, 0)
  end

  defp get_or_create_counter do
    case :persistent_term.get({__MODULE__, :counter}, nil) do
      nil ->
        counter = :atomics.new(1, signed: false)
        :persistent_term.put({__MODULE__, :counter}, counter)
        counter

      counter ->
        counter
    end
  end

  defp insert_entry(entry) do
    max_size = buffer_size()
    current_size = :ets.info(@ets_table, :size)

    # If at capacity, remove oldest entry
    if current_size >= max_size do
      remove_oldest_entry()
    end

    :ets.insert(@ets_table, {entry.id, entry})
  end

  defp remove_oldest_entry do
    # Find the entry with lowest ID (oldest)
    case :ets.first(@ets_table) do
      :"$end_of_table" -> :ok
      oldest_id -> :ets.delete(@ets_table, oldest_id)
    end
  end

  defp emit_audit_telemetry(entry) do
    :telemetry.execute(
      [:jido_code, :security, :audit],
      %{duration_us: entry.duration_us},
      %{
        session_id: entry.session_id,
        tool: entry.tool,
        status: entry.status,
        entry_id: entry.id
      }
    )
  end
end
