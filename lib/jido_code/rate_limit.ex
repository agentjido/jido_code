defmodule JidoCode.RateLimit do
  @moduledoc """
  Simple ETS-based rate limiting for session operations.

  Implements sliding window rate limiting to prevent abuse of expensive
  operations like session resume. Uses GenServer for periodic cleanup of
  expired entries.

  ## Configuration

  Rate limits can be configured per operation type in application config:

      config :jido_code, :rate_limits,
        resume: [limit: 5, window_seconds: 60]

  ## Example

      iex> RateLimit.check_rate_limit(:resume, "session-123")
      :ok

      iex> # After 5 attempts within 60 seconds...
      iex> RateLimit.check_rate_limit(:resume, "session-123")
      {:error, :rate_limit_exceeded, 45}  # 45 seconds until reset
  """

  use GenServer
  require Logger

  @table_name :jido_code_rate_limits
  @cleanup_interval :timer.minutes(1)

  # Default limits per operation
  @default_limits %{
    resume: %{limit: 5, window_seconds: 60}
  }

  ## Client API

  @doc """
  Starts the rate limiter GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if an operation is allowed under the rate limit.

  Returns `:ok` if the operation is allowed, or an error tuple with
  retry-after time if the rate limit has been exceeded.

  ## Parameters

  - `operation` - The operation type (`:resume`, etc.)
  - `key` - The unique identifier (e.g., session_id)

  ## Returns

  - `:ok` - Operation is allowed
  - `{:error, :rate_limit_exceeded, retry_after_seconds}` - Rate limit exceeded

  ## Examples

      iex> RateLimit.check_rate_limit(:resume, "abc-123")
      :ok

      iex> # After exceeding limit...
      iex> RateLimit.check_rate_limit(:resume, "abc-123")
      {:error, :rate_limit_exceeded, 30}
  """
  @spec check_rate_limit(atom(), String.t()) :: :ok | {:error, :rate_limit_exceeded, pos_integer()}
  def check_rate_limit(operation, key) when is_atom(operation) and is_binary(key) do
    limits = get_limits(operation)
    now = System.system_time(:second)
    lookup_key = {operation, key}

    # Get all timestamps for this key
    timestamps = case :ets.lookup(@table_name, lookup_key) do
      [{^lookup_key, ts}] -> ts
      [] -> []
    end

    # Filter to timestamps within the window
    window_start = now - limits.window_seconds
    recent_timestamps = Enum.filter(timestamps, fn ts -> ts > window_start end)

    # Check if limit exceeded
    if length(recent_timestamps) >= limits.limit do
      # Calculate retry-after time
      oldest_recent = Enum.min(recent_timestamps)
      retry_after = oldest_recent + limits.window_seconds - now

      {:error, :rate_limit_exceeded, max(retry_after, 1)}
    else
      :ok
    end
  end

  @doc """
  Records an attempt for rate limiting tracking.

  Should be called after a successful operation to track it for rate limiting.

  ## Parameters

  - `operation` - The operation type (`:resume`, etc.)
  - `key` - The unique identifier (e.g., session_id)

  ## Examples

      iex> RateLimit.record_attempt(:resume, "abc-123")
      :ok
  """
  @spec record_attempt(atom(), String.t()) :: :ok
  def record_attempt(operation, key) when is_atom(operation) and is_binary(key) do
    now = System.system_time(:second)
    lookup_key = {operation, key}

    # Get current timestamps or initialize empty list
    timestamps = case :ets.lookup(@table_name, lookup_key) do
      [{^lookup_key, ts}] -> ts
      [] -> []
    end

    # Prepend new timestamp
    updated_timestamps = [now | timestamps]

    # Store updated list
    :ets.insert(@table_name, {lookup_key, updated_timestamps})

    :ok
  end

  @doc """
  Resets rate limit for a specific key.

  Useful for testing or administrative overrides.

  ## Examples

      iex> RateLimit.reset(:resume, "abc-123")
      :ok
  """
  @spec reset(atom(), String.t()) :: :ok
  def reset(operation, key) when is_atom(operation) and is_binary(key) do
    :ets.delete(@table_name, {operation, key})
    :ok
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for rate limit tracking
    :ets.new(@table_name, [:named_table, :public, :set])

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("[RateLimit] Initialized with table #{@table_name}")
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp get_limits(operation) do
    config_limits = Application.get_env(:jido_code, :rate_limits, %{})
    operation_config = Map.get(config_limits, operation)

    case operation_config do
      nil ->
        # Use default
        Map.get(@default_limits, operation, %{limit: 10, window_seconds: 60})

      config when is_list(config) ->
        %{
          limit: Keyword.get(config, :limit, 10),
          window_seconds: Keyword.get(config, :window_seconds, 60)
        }

      config when is_map(config) ->
        config
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired_entries do
    now = System.system_time(:second)

    # Iterate through all entries and remove expired timestamps
    :ets.foldl(
      fn {{operation, _key} = lookup_key, timestamps}, acc ->
        limits = get_limits(operation)
        window_start = now - limits.window_seconds

        # Keep only timestamps within the window
        recent_timestamps = Enum.filter(timestamps, fn ts -> ts > window_start end)

        if Enum.empty?(recent_timestamps) do
          # No recent attempts, delete the entry
          :ets.delete(@table_name, lookup_key)
        else
          # Update with filtered timestamps
          :ets.insert(@table_name, {lookup_key, recent_timestamps})
        end

        acc
      end,
      nil,
      @table_name
    )

    :ok
  end
end
