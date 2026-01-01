defmodule JidoCode.Tools.Security.RateLimiter do
  @moduledoc """
  Per-session, per-tool rate limiting using sliding window algorithm.

  This module tracks tool invocations and enforces rate limits to prevent
  abuse. Rate limits are stored in ETS for fast access.

  ## Usage

      # Check if invocation is allowed
      case RateLimiter.check_rate("session_123", "read_file", 100, 60_000) do
        :ok -> execute_tool()
        {:error, retry_after_ms} -> {:error, :rate_limited}
      end

  ## Algorithm

  Uses a sliding window algorithm:
  1. Track timestamps of recent invocations
  2. On each check, remove expired entries
  3. Count remaining entries
  4. Allow if under limit, reject if at/over limit

  ## Concurrency Note

  The read-modify-write operation in `check_rate/5` is not atomic, which means
  under high concurrency, slightly more requests than the limit may be allowed
  briefly. This is intentional and acceptable for rate limiting because:

  1. The window-based approach naturally corrects over time
  2. The slight over-allowance is bounded and temporary
  3. Using atomic operations would add significant complexity
  4. Rate limiting is about preventing abuse, not exact accounting

  For use cases requiring exact counting, consider using a GenServer wrapper.

  ## ETS Table

  The module creates an ETS table `:jido_code_rate_limits` on first use.
  Entries are keyed by `{session_id, tool_name}` and contain a list of
  invocation timestamps.

  ## Periodic Cleanup

  To prevent memory growth, schedule periodic cleanup:

      # In your application supervision tree or scheduler:
      :timer.apply_interval(:timer.minutes(5), RateLimiter, :cleanup, [])

  Or using a GenServer-based scheduler like `Quantum`:

      config :my_app, MyApp.Scheduler,
        jobs: [
          rate_limiter_cleanup: [
            schedule: "*/5 * * * *",  # Every 5 minutes
            task: {JidoCode.Tools.Security.RateLimiter, :cleanup, []}
          ]
        ]
  """

  @ets_table :jido_code_rate_limits

  @typedoc """
  Options for rate limiting.
  """
  @type option :: {:emit_telemetry, boolean()}

  @doc """
  Checks if an invocation is allowed within rate limits.

  ## Parameters

  - `session_id` - Session identifier
  - `tool_name` - Name of the tool being invoked
  - `limit` - Maximum allowed invocations in the window
  - `window_ms` - Time window in milliseconds
  - `opts` - Options:
    - `:emit_telemetry` - Whether to emit telemetry on rate limit (default: true)

  ## Returns

  - `:ok` - Invocation allowed, counter incremented
  - `{:error, retry_after_ms}` - Rate limit exceeded, includes time until reset

  ## Telemetry

  When rate limit is exceeded and `:emit_telemetry` is true (default), emits:
  `[:jido_code, :security, :rate_limited]` with:
  - measurements: `%{retry_after_ms: integer}`
  - metadata: `%{session_id: string, tool: string, limit: integer, window_ms: integer}`
  """
  @spec check_rate(String.t(), String.t(), pos_integer(), pos_integer(), [option()]) ::
          :ok | {:error, pos_integer()}
  def check_rate(session_id, tool_name, limit, window_ms, opts \\ []) do
    ensure_table_exists()
    key = {session_id, tool_name}
    now = System.monotonic_time(:millisecond)
    cutoff = now - window_ms

    # Get current invocations and filter expired ones
    invocations =
      case :ets.lookup(@ets_table, key) do
        [{^key, timestamps}] -> Enum.filter(timestamps, &(&1 > cutoff))
        [] -> []
      end

    count = length(invocations)

    if count < limit do
      # Add new invocation and update table
      new_invocations = [now | invocations]
      :ets.insert(@ets_table, {key, new_invocations})
      :ok
    else
      # Calculate retry_after based on oldest invocation in window
      oldest = Enum.min(invocations, fn -> now end)
      retry_after = max(oldest + window_ms - now, 1)

      # Emit telemetry for rate limiting
      maybe_emit_telemetry(session_id, tool_name, limit, window_ms, retry_after, opts)

      {:error, retry_after}
    end
  end

  @doc """
  Returns the current invocation count for a session/tool combination.

  ## Parameters

  - `session_id` - Session identifier
  - `tool_name` - Name of the tool
  - `window_ms` - Time window to consider

  ## Returns

  The number of invocations within the window.
  """
  @spec get_count(String.t(), String.t(), pos_integer()) :: non_neg_integer()
  def get_count(session_id, tool_name, window_ms) do
    ensure_table_exists()
    key = {session_id, tool_name}
    now = System.monotonic_time(:millisecond)
    cutoff = now - window_ms

    case :ets.lookup(@ets_table, key) do
      [{^key, timestamps}] -> Enum.count(timestamps, &(&1 > cutoff))
      [] -> 0
    end
  end

  @doc """
  Clears rate limit data for a session.

  Use this when a session ends to free memory.

  ## Parameters

  - `session_id` - Session identifier
  """
  @spec clear_session(String.t()) :: :ok
  def clear_session(session_id) do
    ensure_table_exists()

    # Match and delete all entries for this session
    :ets.match_delete(@ets_table, {{session_id, :_}, :_})
    :ok
  end

  @doc """
  Clears all rate limit data.

  Primarily useful for testing.
  """
  @spec clear_all() :: :ok
  def clear_all do
    ensure_table_exists()
    :ets.delete_all_objects(@ets_table)
    :ok
  end

  @doc """
  Removes expired entries from the rate limit table.

  Call this periodically to prevent memory growth.

  ## Parameters

  - `max_age_ms` - Maximum age of entries to keep (default: 5 minutes)

  ## Returns

  The number of entries cleaned up.
  """
  @spec cleanup(pos_integer()) :: non_neg_integer()
  def cleanup(max_age_ms \\ 300_000) do
    ensure_table_exists()
    now = System.monotonic_time(:millisecond)
    cutoff = now - max_age_ms

    # Get all entries and filter
    entries = :ets.tab2list(@ets_table)

    Enum.reduce(entries, 0, fn {key, timestamps}, cleaned ->
      valid_timestamps = Enum.filter(timestamps, &(&1 > cutoff))

      case valid_timestamps do
        [] ->
          :ets.delete(@ets_table, key)
          cleaned + 1

        ^timestamps ->
          # No change needed
          cleaned

        _ ->
          :ets.insert(@ets_table, {key, valid_timestamps})
          cleaned
      end
    end)
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp ensure_table_exists do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:named_table, :public, :set])

      _ ->
        :ok
    end
  end

  defp maybe_emit_telemetry(session_id, tool_name, limit, window_ms, retry_after, opts) do
    emit_telemetry = Keyword.get(opts, :emit_telemetry, true)

    if emit_telemetry do
      :telemetry.execute(
        [:jido_code, :security, :rate_limited],
        %{retry_after_ms: retry_after},
        %{
          session_id: session_id,
          tool: tool_name,
          limit: limit,
          window_ms: window_ms
        }
      )
    end
  end
end
