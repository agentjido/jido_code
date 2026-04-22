defmodule JidoCode.SourceCodeGraph.Health do
  # covers: architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
  @moduledoc """
  Health monitoring and integrity checks for the source code graph.

  Provides health status, integrity checks, and metrics for operational
  visibility into the source code graph capability.
  """

  alias JidoCode.SourceCodeGraph

  @type health_status :: %{
          ready?: boolean(),
          stale?: boolean(),
          corrupted?: boolean(),
          last_analysis_at: DateTime.t() | nil,
          last_analysis_duration_ms: non_neg_integer() | nil,
          graph_size_bytes: non_neg_integer() | nil,
          triple_count: non_neg_integer() | nil,
          file_count: non_neg_integer() | nil,
          error_count: non_neg_integer()
        }

  @doc """
  Returns the health status of the source code graph for a given workspace.

  ## Options

    * `:workspace_path` - Path to the repository workspace
    * `:graph_store_path` - Path to the TripleStore database (optional, derived from workspace)

  ## Returns

  A map containing:
    * `:ready?` - Whether the graph is loaded and ready for queries
    * `:stale?` - Whether the graph is out of sync with the workspace
    * `:corrupted?` - Whether the graph store appears corrupted
    * `:last_analysis_at` - Timestamp of the last successful analysis
    * `:last_analysis_duration_ms` - Duration of the last analysis
    * `:graph_size_bytes` - Estimated size of the graph on disk
    * `:triple_count` - Number of triples in the graph
    * `:file_count` - Number of files analyzed
    * `:error_count` - Number of errors during last analysis

  ## Examples

      iex> Health.check(workspace_path: "/path/to/repo")
      %{
        ready?: true,
        stale?: false,
        corrupted?: false,
        last_analysis_at: ~U[2024-01-01 12:00:00Z],
        ...
      }

  """
  @spec check(keyword()) :: health_status()
  def check(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path)
    graph_store_path = Keyword.get(opts, :graph_store_path) || SourceCodeGraph.graph_store_path(workspace_path)

    base_status = %{
      ready?: false,
      stale?: true,
      corrupted?: false,
      last_analysis_at: nil,
      last_analysis_duration_ms: nil,
      graph_size_bytes: nil,
      triple_count: nil,
      file_count: nil,
      error_count: 0
    }

    with {:ok, store_exists?} <- store_exists?(graph_store_path),
         true <- store_exists? do
      check_store_integrity(graph_store_path, base_status, opts)
    else
      _ ->
        base_status
    end
  end

  defp store_exists?(graph_store_path) do
    {:ok, File.exists?(graph_store_path)}
  end

  defp check_store_integrity(graph_store_path, base_status, opts) do
    case TripleStore.open(graph_store_path, schema: :quad, create_if_missing: false) do
      {:ok, store} ->
        try do
          check_graph_ready(store, base_status, opts)
        after
          TripleStore.close(store)
        end

      {:error, _reason} ->
        %{base_status | corrupted?: true}
    end
  end

  defp check_graph_ready(store, base_status, opts) do
    # Try to query the graph to verify it's functional
    case TripleStore.query(store, "SELECT (COUNT(*) AS ?count) WHERE { GRAPH ?g { ?s ?p ?o } }") do
      {:ok, results} ->
        triple_count = extract_count(results)
        graph_size = get_graph_size_bytes(Keyword.get(opts, :graph_store_path))

        %{base_status |
          ready?: true,
          stale?: check_stale?(opts),
          triple_count: triple_count,
          graph_size_bytes: graph_size
        }

      {:error, _reason} ->
        %{base_status | corrupted?: true}
    end
  end

  defp extract_count(results) when is_list(results) do
    case List.first(results) do
      %{count: count} when is_integer(count) -> count
      _ -> nil
    end
  end

  defp extract_count(_), do: nil

  defp get_graph_size_bytes(nil), do: nil

  defp get_graph_size_bytes(graph_store_path) when is_binary(graph_store_path) do
    case File.stat(graph_store_path) do
      {:ok, %File.Stat{size: size}} -> size
      _ -> nil
    end
  end

  defp check_stale?(opts) do
    workspace_path = Keyword.get(opts, :workspace_path)

    if workspace_path do
      check_workspace_freshness(workspace_path, opts)
    else
      true
    end
  end

  defp check_workspace_freshness(workspace_path, opts) do
    # Compare current workspace snapshot with imported revision
    current_snapshot = workspace_snapshot_identity(workspace_path)
    imported_revision = Keyword.get(opts, :imported_revision)

    if imported_revision do
      current_snapshot != imported_revision
    else
      true
    end
  end

  defp workspace_snapshot_identity(workspace_path) do
    manifest =
      workspace_path
      |> source_files()
      |> Enum.map(fn path ->
        stat = File.stat!(path, time: :posix)
        relative_path = Path.relative_to(path, workspace_path)
        "#{relative_path}:#{stat.size}:#{stat.mtime}"
      end)
      |> Enum.join("\n")

    case manifest do
      "" ->
        "snapshot:empty"

      data ->
        encoded =
          :sha256
          |> :crypto.hash(data)
          |> Base.encode16(case: :lower)

        "snapshot:#{encoded}"
    end
  end

  defp source_files(workspace_path) do
    workspace_path
    |> source_globs()
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&excluded_source_file?/1)
    |> Enum.uniq()
    |> Enum.sort()
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

  @doc """
  Returns a simplified health summary suitable for logging or alerts.

  ## Examples

      iex> Health.summary(workspace_path: "/path/to/repo")
      "healthy"

      iex> Health.summary(workspace_path: "/path/to/repo")
      "stale"

      iex> Health.summary(workspace_path: "/path/to/repo")
      "corrupted"

  """
  @spec summary(keyword()) :: String.t()
  def summary(opts \\ []) do
    health = check(opts)

    cond do
      health.corrupted? -> "corrupted"
      not health.ready? -> "not_ready"
      health.stale? -> "stale"
      true -> "healthy"
    end
  end
end
