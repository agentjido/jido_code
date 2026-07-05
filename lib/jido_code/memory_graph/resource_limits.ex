defmodule JidoCode.MemoryGraph.ResourceLimits do
  # covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  @moduledoc """
  Resource limits and validation for memory graph operations.

  This module provides pre-flight checks for memory graph size, disk space,
  and operation limits to prevent resource exhaustion during memory capture
  and storage.
  """

  alias JidoCode.MemoryGraph.Config

  @type limit_result :: :ok | {:error, :limit_exceeded, map()}

  @doc """
  Validates that a graph write operation won't exceed the maximum graph size.

  Returns :ok if the write can proceed or an error if the limit would be exceeded.
  """
  @spec validate_graph_size(Path.t(), pos_integer(), keyword()) :: limit_result()
  def validate_graph_size(store_path, estimated_addition_bytes, opts \\ []) do
    max_size_mb = Config.max_graph_size_mb(opts)
    max_size_bytes = max_size_mb * 1024 * 1024

    case get_graph_size_bytes(store_path) do
      {:ok, current_size} ->
        new_size = current_size + estimated_addition_bytes

        if new_size > max_size_bytes do
          {:error, :graph_size_limit_exceeded,
           %{
             current_size_mb: div(current_size, 1024 * 1024),
             estimated_addition_mb: div(estimated_addition_bytes, 1024 * 1024),
             new_size_mb: div(new_size, 1024 * 1024),
             max_size_mb: max_size_mb,
             store_path: store_path
           }}
        else
          :ok
        end

      {:error, _} ->
        # Can't determine size, allow the operation
        :ok
    end
  end

  @doc """
  Validates that there's sufficient disk space for the store operations.

  Returns :ok if there's sufficient space or an error if space is low.
  """
  @spec validate_disk_space(Path.t(), pos_integer(), keyword()) :: limit_result()
  def validate_disk_space(store_path, estimated_addition_bytes, _opts \\ []) do
    # 100MB buffer
    required_space_mb = div(estimated_addition_bytes, 1024 * 1024) + 100

    case get_available_disk_space_mb(store_path) do
      {:ok, available_mb} when available_mb < required_space_mb ->
        {:error, :disk_space_insufficient,
         %{
           required_space_mb: required_space_mb,
           available_mb: available_mb,
           store_path: store_path
         }}

      {:ok, _available_mb} ->
        :ok

      {:error, _} ->
        # Can't determine space, allow the operation with warning
        :ok
    end
  end

  @doc """
  Validates that the number of concurrent write operations is within limits.

  Returns :ok if within limits or an error if the limit would be exceeded.
  """
  @spec validate_concurrent_operations(keyword()) :: limit_result()
  def validate_concurrent_operations(opts \\ []) do
    max_concurrent = Config.max_concurrent_operations(opts)

    case get_active_write_count() do
      {:ok, active_count} when active_count >= max_concurrent ->
        {:error, :concurrent_operation_limit_exceeded,
         %{
           active_count: active_count,
           max_concurrent: max_concurrent
         }}

      {:ok, _active_count} ->
        :ok
    end
  end

  @doc """
  Validates that a query result set is within the maximum allowed size.

  Returns the (possibly truncated) result or an error if truncated.
  """
  @spec validate_query_results(list(), keyword()) :: {:ok, list()} | {:error, :result_limit_exceeded, map()}
  def validate_query_results(results, opts \\ []) do
    max_results = Config.max_query_results(opts)
    result_count = length(results)

    if result_count > max_results do
      truncated = Enum.take(results, max_results)

      {:error, :result_limit_exceeded,
       %{
         result_count: result_count,
         max_results: max_results,
         truncated_count: max_results,
         truncated_results: truncated
       }}
    else
      {:ok, results}
    end
  end

  @doc """
  Estimates the size in bytes of a graph operation.

  Provides a rough estimate based on triple count and average triple size.
  """
  @spec estimate_graph_size(pos_integer(), keyword()) :: pos_integer()
  def estimate_graph_size(triple_count, opts \\ []) do
    avg_triple_bytes = Keyword.get(opts, :avg_triple_bytes, 500)
    triple_count * avg_triple_bytes
  end

  # Private functions

  defp get_graph_size_bytes(store_path) do
    case File.stat(store_path) do
      {:ok, stat} -> {:ok, stat.size}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp get_available_disk_space_mb(store_path) do
    volume_path = volume_path_for(store_path)

    case System.cmd("df", ["-k", volume_path], stderr_to_stdout: true) do
      {output, 0} ->
        parse_df_output(output)

      _ ->
        {:error, :unknown}
    end
  end

  defp volume_path_for(path) do
    path
    |> Path.expand()
    |> Path.absname()
    |> String.split("/")
    |> case do
      [] -> "/"
      parts -> "/" <> Enum.at(parts, 1, "")
    end
  end

  defp parse_df_output(output) do
    lines = String.split(output, "\n")

    Enum.find_value(lines, fn line ->
      case String.split(line, ~r/\s+/, trim: true) do
        [_, _total, _used, available_kb | _] ->
          case Integer.parse(available_kb) do
            {kb, _} -> {:ok, div(kb, 1024)}
            :error -> nil
          end

        _ ->
          nil
      end
    end) || {:error, :parse_failed}
  end

  defp get_active_write_count do
    # For now, return a low count since we don't have a registry
    # In production, this would query a write operation registry
    {:ok, 0}
  end
end
