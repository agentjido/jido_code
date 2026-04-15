defmodule JidoCode.SourceCodeGraph.RetryPolicy do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc """
  Retry policy and execution helpers for transient failure handling.

  Provides exponential backoff retry for operations that may fail due to
  transient conditions like file locks, temporary I/O errors, or network issues.
  """

  alias JidoCode.SourceCodeGraph.Config

  @type retry_result :: {:ok, any()} | {:error, :max_retries_exceeded, map()}

  @doc """
  Executes a function with retry policy using exponential backoff.

  ## Options

    * `:max_retries` - Maximum number of retry attempts (default: from config)
    * `:retry_backoff_ms` - Base backoff time in milliseconds (default: from config)
    * `:on_retry` - Optional callback function called before each retry

  ## Examples

      iex> RetryPolicy.retry(fn -> :risky_operation() end, max_retries: 2)
      {:ok, result}

  """
  @spec retry((-> retry_result()), keyword()) :: retry_result()
  def retry(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    max_retries = Config.max_retries(opts)
    execute_with_retry(fun, 0, max_retries, opts)
  end

  defp execute_with_retry(fun, attempt, max_retries, opts) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} = error ->
        if attempt < max_retries and Config.retryable_error?(reason) do
          backoff_ms = Config.retry_delay(attempt, opts)

          if on_retry = Keyword.get(opts, :on_retry) do
            on_retry.(attempt, backoff_ms, reason)
          end

          Process.sleep(backoff_ms)
          execute_with_retry(fun, attempt + 1, max_retries, opts)
        else
          format_retry_error(error, attempt, max_retries)
        end

      other ->
        # Non-matching return values are treated as errors
        if attempt < max_retries do
          backoff_ms = Config.retry_delay(attempt, opts)
          Process.sleep(backoff_ms)
          execute_with_retry(fun, attempt + 1, max_retries, opts)
        else
          {:error, :max_retries_exceeded, %{attempt: attempt, max_retries: max_retries, result: other}}
        end
    end
  end

  defp format_retry_error({:error, reason}, attempt, max_retries) do
    {:error, :max_retries_exceeded,
     %{
       attempt: attempt,
       max_retries: max_retries,
       reason: reason
     }}
  end

  defp format_retry_error(other, attempt, max_retries) do
    {:error, :max_retries_exceeded,
     %{
       attempt: attempt,
       max_retries: max_retries,
       result: other
     }}
  end

  @doc """
  Returns true if the given error should be retried based on the retry policy.
  """
  @spec should_retry?(term(), non_neg_integer(), non_neg_integer()) :: boolean()
  def should_retry?(error, attempt, max_retries) when attempt < max_retries do
    Config.retryable_error?(error)
  end

  def should_retry?(_error, _attempt, _max_retries), do: false

  @doc """
  Calculates the delay for a retry attempt using exponential backoff.
  """
  @spec calculate_delay(non_neg_integer(), keyword()) :: pos_integer()
  def calculate_delay(attempt, opts \\ []) do
    Config.retry_delay(attempt, opts)
  end
end
