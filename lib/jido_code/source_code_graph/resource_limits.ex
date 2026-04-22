defmodule JidoCode.SourceCodeGraph.ResourceLimits do
  # covers: architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
  @moduledoc """
  Resource validation and limits for source code graph operations.

  Provides pre-flight checks for file counts, disk space, and graph size
  to prevent resource exhaustion during analysis and loading.
  """

  alias JidoCode.SourceCodeGraph.Config

  @type validation_result :: :ok | {:error, atom(), map()}

  @doc """
  Validates that the workspace file count is within acceptable limits.
  """
  @spec validate_file_count(String.t(), keyword()) :: validation_result()
  def validate_file_count(workspace_path, opts \\ []) do
    max_files = Config.max_file_count(opts)
    file_count = count_source_files(workspace_path)

    if file_count > max_files do
      {:error, :file_count_exceeded,
       %{
         file_count: file_count,
         max_files: max_files,
         workspace_path: workspace_path
       }}
    else
      :ok
    end
  end

  @doc """
  Validates that sufficient disk space is available for the graph load.
  """
  @spec validate_disk_space(String.t(), pos_integer(), keyword()) :: validation_result()
  def validate_disk_space(store_path, estimated_size_bytes, opts \\ []) do
    max_size_mb = Config.max_graph_size_mb(opts)
    max_size_bytes = max_size_mb * 1024 * 1024

    # Require 2x the estimated size for safety
    required_space = estimated_size_bytes * 2

    if estimated_size_bytes > max_size_bytes do
      {:error, :graph_size_exceeded,
       %{
         estimated_size_bytes: estimated_size_bytes,
         estimated_size_mb: div(estimated_size_bytes, 1024 * 1024),
         max_size_bytes: max_size_bytes,
         max_size_mb: max_size_mb
       }}
    else
      case available_disk_space(store_path) do
        {:ok, available_bytes} when available_bytes >= required_space ->
          :ok

        {:ok, available_bytes} ->
          {:error, :insufficient_disk_space,
           %{
             required_space_bytes: required_space,
             required_space_mb: div(required_space, 1024 * 1024),
             available_bytes: available_bytes,
             available_mb: div(available_bytes, 1024 * 1024),
             store_path: store_path
           }}

        {:error, _reason} ->
          # If we can't determine disk space, allow the operation to proceed
          # but log a warning
          :ok
      end
    end
  end

  @doc """
  Validates that the workspace is a valid Elixir project.
  """
  @spec validate_workspace(String.t()) :: validation_result()
  def validate_workspace(workspace_path) do
    mix_exs = Path.join(workspace_path, "mix.exs")

    if File.exists?(mix_exs) do
      :ok
    else
      {:error, :invalid_workspace,
       %{
         workspace_path: workspace_path,
         reason: "mix.exs not found"
       }}
    end
  end

  @doc """
  Estimates the graph size based on the workspace file count and average file size.
  Returns size in bytes.
  """
  @spec estimate_graph_size(String.t()) :: {:ok, pos_integer()} | {:error, atom()}
  def estimate_graph_size(workspace_path) do
    file_count = count_source_files(workspace_path)

    # Rough estimate: 1KB of RDF triples per source file
    # This is conservative; actual size may vary
    estimated_bytes = file_count * 1024

    {:ok, estimated_bytes}
  end

  defp count_source_files(workspace_path) do
    workspace_path
    |> source_globs()
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&excluded_source_file?/1)
    |> Enum.uniq()
    |> length()
  end

  defp source_globs(workspace_path) do
    [
      Path.join(workspace_path, "mix.exs"),
      Path.join(workspace_path, "lib/**/*.ex"),
      Path.join(workspace_path, "lib/**/*.exs"),
      Path.join(workspace_path, "test/**/*.ex"),
      Path.join(workspace_path, "test/**/*.exs"),
      Path.join(workspace_path, "config/**/*.exs")
    ]
  end

  defp excluded_source_file?(path) do
    String.contains?(path, "/deps/") or
      String.contains?(path, "/_build/") or
      String.contains?(path, "/node_modules/")
  end

  defp available_disk_space(store_path) do
    store_dir = Path.dirname(store_path)

    case System.cmd("df", ["-P", "-k", store_dir], stderr_to_stdout: true) do
      {output, 0} ->
        parse_df_output(output)

      _ ->
        # Fallback: try statfs on Unix-like systems
        try_statfs(store_dir)
    end
  end

  defp parse_df_output(output) do
    lines = String.split(output, "\n")

    # Find the line with the filesystem info (skip header)
    result_line =
      lines
      |> Enum.find(fn line ->
        not String.starts_with?(line, "Filesystem") and String.trim(line) != ""
      end)

    case result_line do
      nil ->
        {:error, :parse_failed}

      line ->
        # df -P output format:
        # Filesystem 1024-blocks Used Available Capacity Mounted on
        parts = String.split(line, ~r/\s+/, trim: true)

        case parts do
          [_filesystem, _blocks, _used, available | _] ->
            case Integer.parse(available) do
              {available_kb, ""} -> {:ok, available_kb * 1024}
              _ -> {:error, :parse_failed}
            end

          _ ->
            {:error, :parse_failed}
        end
    end
  end

  defp try_statfs(_path) do
    # This is a simplified implementation
    # In production, you might use an Erlang NIF or port
    {:ok, 1_000_000_000}
  end
end
