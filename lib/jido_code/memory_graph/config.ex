defmodule JidoCode.MemoryGraph.Config do
  # covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  @moduledoc """
  Configuration and timeout settings for memory graph operations.

  This module centralizes configuration for timeouts, retry policies, and resource
  limits to ensure consistent behavior across the memory graph capability.
  """

  @type timeout_ms :: pos_integer() | :infinity

  @doc """
  Returns the timeout for TripleStore operations.
  """
  @spec store_timeout(keyword()) :: timeout_ms()
  def store_timeout(opts \\ []) do
    Keyword.get(opts, :store_timeout_ms, :infinity) ||
      Application.get_env(:jido_code, :memory_graph_store_timeout_ms, 30_000)
  end

  @doc """
  Returns the timeout for SPARQL query operations.
  """
  @spec query_timeout(keyword()) :: timeout_ms()
  def query_timeout(opts \\ []) do
    Keyword.get(opts, :query_timeout_ms, :infinity) ||
      Application.get_env(:jido_code, :memory_graph_query_timeout_ms, 60_000)
  end

  @doc """
  Returns the timeout for ontology validation operations.
  """
  @spec validation_timeout(keyword()) :: timeout_ms()
  def validation_timeout(opts \\ []) do
    Keyword.get(opts, :validation_timeout_ms, :infinity) ||
      Application.get_env(:jido_code, :memory_graph_validation_timeout_ms, 120_000)
  end

  @doc """
  Returns the timeout for recovery operations.
  """
  @spec recovery_timeout(keyword()) :: timeout_ms()
  def recovery_timeout(opts \\ []) do
    Keyword.get(opts, :recovery_timeout_ms, :infinity) ||
      Application.get_env(:jido_code, :memory_graph_recovery_timeout_ms, 300_000)
  end

  @doc """
  Returns the maximum number of retries for transient failures.
  """
  @spec max_retries(keyword()) :: non_neg_integer()
  def max_retries(opts \\ []) do
    Keyword.get(opts, :max_retries, 3) ||
      Application.get_env(:jido_code, :memory_graph_max_retries, 3)
  end

  @doc """
  Returns the maximum number of retries for write operations.
  """
  @spec max_write_retries(keyword()) :: non_neg_integer()
  def max_write_retries(opts \\ []) do
    Keyword.get(opts, :max_write_retries, 2) ||
      Application.get_env(:jido_code, :memory_graph_max_write_retries, 2)
  end

  @doc """
  Returns the base backoff time for retry attempts in milliseconds.
  """
  @spec retry_backoff_ms(keyword()) :: pos_integer()
  def retry_backoff_ms(opts \\ []) do
    Keyword.get(opts, :retry_backoff_ms, 1000) ||
      Application.get_env(:jido_code, :memory_graph_retry_backoff_ms, 1000)
  end

  @doc """
  Returns the maximum graph size allowed in megabytes.
  """
  @spec max_graph_size_mb(keyword()) :: pos_integer()
  def max_graph_size_mb(opts \\ []) do
    Keyword.get(opts, :max_graph_size_mb, 10_000) ||
      Application.get_env(:jido_code, :memory_graph_max_graph_size_mb, 10_000)
  end

  @doc """
  Returns the maximum number of query results allowed.
  """
  @spec max_query_results(keyword()) :: pos_integer()
  def max_query_results(opts \\ []) do
    Keyword.get(opts, :max_query_results, 10_000) ||
      Application.get_env(:jido_code, :memory_graph_max_query_results, 10_000)
  end

  @doc """
  Returns the maximum concurrent operations allowed.
  """
  @spec max_concurrent_operations(keyword()) :: pos_integer()
  def max_concurrent_operations(opts \\ []) do
    Keyword.get(opts, :max_concurrent_operations, 50) ||
      Application.get_env(:jido_code, :memory_graph_max_concurrent_operations, 50)
  end

  @doc """
  Returns whether the memory graph capability is enabled.
  """
  @spec capability_enabled?(keyword()) :: boolean()
  def capability_enabled?(opts \\ []) do
    Keyword.get(opts, :enabled?, false) ||
      Application.get_env(:jido_code, :memory_graph_enabled, false)
  end

  @doc """
  Calculates the retry delay for a given attempt number using exponential backoff.
  """
  @spec retry_delay(non_neg_integer(), keyword()) :: pos_integer()
  def retry_delay(attempt, opts \\ []) when attempt >= 0 do
    base_backoff = retry_backoff_ms(opts)
    round(base_backoff * :math.pow(2, attempt))
  end

  @doc """
  Checks if an error is retryable based on the error reason.
  """
  @spec retryable_error?(term()) :: boolean()
  def retryable_error?(reason) when is_atom(reason) do
    reason in [
      :econnrefused,
      :enoent,
      :eacces,
      :enospc,
      :timeout,
      :temporary,
      :eagain,
      :einval
    ]
  end

  def retryable_error?({:error, reason}), do: retryable_error?(reason)
  def retryable_error?(_), do: false
end
