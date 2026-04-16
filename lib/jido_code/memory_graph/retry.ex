defmodule JidoCode.MemoryGraph.Retry do
  # covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  @moduledoc """
  Retry policy and execution for memory graph operations.

  This module provides exponential backoff retry logic for transient failures
  in memory store operations, RDF parsing, and cross-graph queries.
  """

  alias JidoCode.MemoryGraph.Config

  @type retry_result :: {:ok, term()} | {:error, term()} | {:error, atom(), map()}
  @type retry_fun :: (-> retry_result())

  @doc """
  Executes a function with retry policy for transient failures.

  Returns the result on success or the last error on exhaustion.
  """
  @spec with_retry(retry_fun(), keyword()) :: retry_result()
  def with_retry(fun, opts \\ []) when is_function(fun, 0) do
    max_retries = Keyword.get(opts, :max_retries, Config.max_retries(opts))
    attempt_context = Keyword.get(opts, :attempt_context, %{})

    do_retry(fun, 0, max_retries, attempt_context, opts)
  end

  @doc """
  Executes a function with retry policy for write operations.

  Write operations have a lower retry limit to avoid duplicate writes.
  """
  @spec with_write_retry(retry_fun(), keyword()) :: retry_result()
  def with_write_retry(fun, opts \\ []) when is_function(fun, 0) do
    max_retries = Keyword.get(opts, :max_retries, Config.max_write_retries(opts))
    attempt_context = Keyword.get(opts, :attempt_context, %{})

    do_retry(fun, 0, max_retries, attempt_context, opts)
  end

  defp do_retry(fun, attempt, max_retries, attempt_context, opts) do
    case fun.() do
      {:ok, _} = ok_result ->
        ok_result

      {:error, reason} = error_result when is_map(reason) or is_atom(reason) ->
        should_retry = Config.retryable_error?(reason)

        if should_retry and attempt < max_retries do
          log_retry_attempt(attempt, max_retries, reason, attempt_context)
          delay = Config.retry_delay(attempt, opts)
          Process.sleep(delay)
          do_retry(fun, attempt + 1, max_retries, attempt_context, opts)
        else
          add_retry_info(error_result, attempt, max_retries)
        end

      {:error, _reason, _detail} = error_result ->
        # For structured errors, check if they're retryable
        if attempt < max_retries and retryable_error?(error_result) do
          log_retry_attempt(attempt, max_retries, error_result, attempt_context)
          delay = Config.retry_delay(attempt, opts)
          Process.sleep(delay)
          do_retry(fun, attempt + 1, max_retries, attempt_context, opts)
        else
          add_retry_info(error_result, attempt, max_retries)
        end

      other ->
        other
    end
  end

  @doc """
  Checks if an error tuple is retryable based on error diagnostics.
  """
  @spec retryable_error?(term()) :: boolean()
  def retryable_error?({:error, reason}) when is_atom(reason) do
    Config.retryable_error?(reason)
  end

  def retryable_error?({:error, _reason, detail}) when is_map(detail) do
    stage = Map.get(detail, :stage)

    # Retry on specific stages with transient errors
    stage in [:open_store, :load_ontology_graph, :export_named_graph] and
      transient_reason?(detail)
  end

  def retryable_error?({:error, detail}) when is_map(detail) do
    stage = Map.get(detail, :stage)

    stage in [:open_store, :load_ontology_graph, :export_named_graph] and
      transient_reason?(detail)
  end

  def retryable_error?(_), do: false

  defp transient_reason?(detail) do
    reason = Map.get(detail, :reason)

    case reason do
      r when is_atom(r) -> Config.retryable_error?(r)
      r when is_binary(r) -> String.contains?(r, "timeout") or String.contains?(r, "econnrefused")
      _ -> false
    end
  end

  defp add_retry_info({:error, reason}, attempt, max_retries) do
    {:error, :max_retries_exceeded,
     %{
       original_reason: reason,
       attempts: attempt + 1,
       max_retries: max_retries,
       exhausted?: true
     }}
  end

  defp add_retry_info({:error, error_type, detail}, attempt, max_retries) do
    {:error, error_type,
     Map.merge(detail, %{
       retry_attempts: attempt + 1,
       max_retries: max_retries,
       retry_exhausted?: true
     })}
  end

  defp log_retry_attempt(attempt, max_retries, reason, context) do
    require Logger

    context_str =
      context
      |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{inspect(v)}" end)

    Logger.warning(
      "Memory graph retry attempt #{attempt + 1}/#{max_retries + 1} after error: #{inspect(reason)}" <>
        if(context_str == "", do: "", else: " (#{context_str})")
    )
  end
end
