defmodule JidoCode.SourceCodeGraph.Config do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc """
  Configuration and timeout settings for source code graph operations.

  This module centralizes configuration for timeouts, retry policies, and resource
  limits to ensure consistent behavior across the source code graph capability.
  """

  @type timeout_ms :: pos_integer() | :infinity

  @doc """
  Returns the timeout for ontology analysis operations.
  """
  @spec analysis_timeout(keyword()) :: timeout_ms()
  def analysis_timeout(opts \\ []) do
    Keyword.get(opts, :analysis_timeout_ms, :infinity) ||
      Application.get_env(:jido_code, :source_code_graph_analysis_timeout_ms, 300_000)
  end

  @doc """
  Returns the timeout for graph load operations.
  """
  @spec load_timeout(keyword()) :: timeout_ms()
  def load_timeout(opts \\ []) do
    Keyword.get(opts, :load_timeout_ms, :infinity) ||
      Application.get_env(:jido_code, :source_code_graph_load_timeout_ms, 120_000)
  end

  @doc """
  Returns the timeout for SPARQL query operations.
  """
  @spec query_timeout(keyword()) :: timeout_ms()
  def query_timeout(opts \\ []) do
    Keyword.get(opts, :query_timeout_ms, :infinity) ||
      Application.get_env(:jido_code, :source_code_graph_query_timeout_ms, 30_000)
  end

  @doc """
  Returns the maximum number of retries for transient failures.
  """
  @spec max_retries(keyword()) :: non_neg_integer()
  def max_retries(opts \\ []) do
    Keyword.get(opts, :max_retries, 3) ||
      Application.get_env(:jido_code, :source_code_graph_max_retries, 3)
  end

  @doc """
  Returns the base backoff time for retry attempts in milliseconds.
  """
  @spec retry_backoff_ms(keyword()) :: pos_integer()
  def retry_backoff_ms(opts \\ []) do
    Keyword.get(opts, :retry_backoff_ms, 1000) ||
      Application.get_env(:jido_code, :source_code_graph_retry_backoff_ms, 1000)
  end

  @doc """
  Returns the maximum file count allowed for analysis.
  """
  @spec max_file_count(keyword()) :: pos_integer()
  def max_file_count(opts \\ []) do
    Keyword.get(opts, :max_file_count, 10_000) ||
      Application.get_env(:jido_code, :source_code_graph_max_file_count, 10_000)
  end

  @doc """
  Returns the maximum graph size allowed in megabytes.
  """
  @spec max_graph_size_mb(keyword()) :: pos_integer()
  def max_graph_size_mb(opts \\ []) do
    Keyword.get(opts, :max_graph_size_mb, 500) ||
      Application.get_env(:jido_code, :source_code_graph_max_graph_size_mb, 500)
  end

  @doc """
  Returns whether partial results are allowed on analysis failure.
  """
  @spec allow_partial_results?(keyword()) :: boolean()
  def allow_partial_results?(opts \\ []) do
    Keyword.get(opts, :allow_partial_results, false) ||
      Application.get_env(:jido_code, :source_code_graph_allow_partial_results, false)
  end

  @doc """
  Returns whether the source code graph capability is enabled.
  """
  @spec capability_enabled?(keyword()) :: boolean()
  def capability_enabled?(opts \\ []) do
    Keyword.get(opts, :enabled?, false) ||
      Application.get_env(:jido_code, :source_code_graph_enabled, false)
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
