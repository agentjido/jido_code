defmodule JidoCode.SourceCodeGraph.Store do
  # covers: architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
  # covers: architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
  # covers: architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together
  # covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  @moduledoc false

  alias JidoCode.SourceCodeGraph
  alias JidoCode.SourceCodeGraph.Config
  alias JidoCode.SourceCodeGraph.ResourceLimits
  alias JidoCode.SourceCodeGraph.RetryPolicy

  @type analysis_result :: map()

  @spec load_snapshot(analysis_result(), keyword()) :: {:ok, map()} | {:error, map()}
  def load_snapshot(analysis_result, opts \\ []) when is_map(analysis_result) and is_list(opts) do
    mode = Keyword.get(opts, :mode, :load)
    dataset = analysis_result.dataset
    revision_metadata = analysis_result.revision_metadata
    canonical_store_path = dataset.graph_store_path
    staging_store_path = staging_store_path(canonical_store_path, revision_metadata.analyzed_revision, mode)
    named_graph = SourceCodeGraph.named_graph_resource()
    timeout = Config.load_timeout(opts)

    # Estimate graph size for validation
    estimated_size_bytes = estimate_graph_size(analysis_result)

    with :ok <- ensure_parent_directory(canonical_store_path),
         :ok <- ResourceLimits.validate_disk_space(canonical_store_path, estimated_size_bytes, opts),
         :ok <- reset_directory(staging_store_path),
         {:ok, load_counts} <- build_staged_store(staging_store_path, analysis_result.load_artifacts, named_graph, timeout),
         :ok <- promote_store(staging_store_path, canonical_store_path) do
      imported_at = DateTime.utc_now()

      latest_import_status = %{
        state: import_state(mode),
        ready?: true,
        graph_name: dataset.graph_name,
        imported_revision: revision_metadata.analyzed_revision,
        imported_at: imported_at,
        requested_revision: revision_metadata.requested_revision,
        source_commit: revision_metadata.source_commit,
        workspace_snapshot_identity: revision_metadata.workspace_snapshot_identity,
        revision_source: revision_metadata.revision_source,
        load_strategy: :staged_store_swap,
        refresh_mode: revision_metadata.refresh_mode,
        schema_included?: true,
        individuals_included?: true,
        schema_triple_count: load_counts.schema_triple_count,
        individual_triple_count: load_counts.individual_triple_count,
        total_triple_count: load_counts.total_triple_count,
        graph_store_path: canonical_store_path,
        failure: nil
      }

      {:ok,
       %{
         status: import_result_status(mode),
         graph_name: dataset.graph_name,
         store: %{
           backend: :triple_store,
           schema: :quad,
           path: canonical_store_path,
           graph_name: dataset.graph_name,
           load_strategy: :staged_store_swap
         },
         dataset: Map.put(dataset, :revision, revision_metadata.analyzed_revision),
         latest_analysis_status: analysis_result.latest_analysis_status,
         latest_import_status: latest_import_status
       }}
    else
      {:error, diagnostics} when is_map(diagnostics) ->
        File.rm_rf(staging_store_path)
        {:error, diagnostics}

      {:error, reason} ->
        File.rm_rf(staging_store_path)
        {:error, failure_diagnostics(mode, dataset, revision_metadata, :unknown, reason)}
    end
  end

  defp build_staged_store(staging_store_path, load_artifacts, named_graph, timeout \\ :infinity) do
    task = Task.async(fn ->
      do_build_staged_store(staging_store_path, load_artifacts, named_graph)
    end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, %{stage: :load, reason: :timeout, timeout_ms: timeout}}
    end
  end

  defp do_build_staged_store(staging_store_path, load_artifacts, named_graph) do
    with {:ok, store} <- TripleStore.open(staging_store_path, schema: :quad, create_if_missing: true) do
      try do
        with {:ok, schema_count} <-
               load_schema_artifacts_with_retry(store, load_artifacts.ontology_schema.artifacts, named_graph),
             {:ok, individual_count} <-
               load_graph_with_retry(store, load_artifacts.project_individuals.graph, named_graph) do
          {:ok,
           %{
             schema_triple_count: schema_count,
             individual_triple_count: individual_count,
             total_triple_count: schema_count + individual_count
           }}
        else
          {:error, diagnostics} when is_map(diagnostics) -> {:error, diagnostics}
          {:error, reason} -> {:error, %{stage: :load_individuals, reason: inspect(reason)}}
        end
      after
        :ok = TripleStore.close(store)
      end
    else
      {:error, reason} ->
        {:error, %{stage: :open_store, reason: inspect(reason)}}
    end
  end

  defp load_schema_artifacts_with_retry(store, schema_artifacts, named_graph) do
    RetryPolicy.retry(fn ->
      load_schema_artifacts(store, schema_artifacts, named_graph)
    end, max_retries: 2)
  end

  defp load_graph_with_retry(store, graph, named_graph) do
    RetryPolicy.retry(fn ->
      TripleStore.load_graph(store, graph, graph: named_graph)
    end, max_retries: 2)
  end

  defp load_schema_artifacts(store, schema_artifacts, named_graph) do
    Enum.reduce_while(schema_artifacts, {:ok, 0}, fn artifact, {:ok, acc} ->
      case RDF.Turtle.read_file(artifact.path) do
        {:ok, graph} ->
          case TripleStore.load_graph(store, graph, graph: named_graph) do
            {:ok, count} ->
              {:cont, {:ok, acc + count}}

            {:error, reason} ->
              {:halt,
               {:error,
                %{
                  stage: :load_schema,
                  artifact: artifact.filename,
                  reason: inspect(reason)
                }}}
          end

        {:error, reason} ->
          {:halt,
           {:error,
            %{
              stage: :read_schema,
              artifact: artifact.filename,
              reason: inspect(reason)
            }}}
      end
    end)
  end

  defp ensure_parent_directory(store_path) do
    store_path
    |> Path.dirname()
    |> File.mkdir_p()
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, %{stage: :prepare_store_parent, reason: inspect(reason)}}
    end
  end

  defp reset_directory(path) do
    path
    |> File.rm_rf()
    |> case do
      {:error, reason, _path} -> {:error, %{stage: :prepare_staging, reason: inspect(reason)}}
      _ -> File.mkdir_p(Path.dirname(path))
    end
  end

  defp promote_store(staging_store_path, canonical_store_path) do
    backup_store_path = canonical_store_path <> ".backup"

    File.rm_rf(backup_store_path)

    if File.exists?(canonical_store_path) do
      case File.rename(canonical_store_path, backup_store_path) do
        :ok -> :ok
        {:error, reason} -> {:error, %{stage: :promote_previous_store, reason: inspect(reason)}}
      end
    else
      :ok
    end
    |> case do
      :ok ->
        case File.rename(staging_store_path, canonical_store_path) do
          :ok ->
            File.rm_rf(backup_store_path)
            :ok

          {:error, reason} ->
            if File.exists?(backup_store_path) do
              File.rename(backup_store_path, canonical_store_path)
            end

            {:error, %{stage: :promote_staging_store, reason: inspect(reason)}}
        end

      {:error, _} = error ->
        error
    end
  end

  defp staging_store_path(canonical_store_path, analyzed_revision, mode) do
    suffix =
      analyzed_revision
      |> to_string()
      |> String.replace(~r/[^a-zA-Z0-9_-]+/, "_")

    canonical_store_path <> ".#{mode}.#{suffix}"
  end

  defp estimate_graph_size(analysis_result) do
    # Use the individual triple count as a baseline
    # Each triple is approximately 100-200 bytes in storage
    triple_count = get_in(analysis_result, [:load_artifacts, :project_individuals, :triple_count]) || 0
    triple_count * 200
  end

  defp import_state(:refresh), do: :refreshed
  defp import_state(_mode), do: :loaded

  defp import_result_status(:refresh), do: :graph_refreshed
  defp import_result_status(_mode), do: :graph_loaded

  defp failure_diagnostics(mode, dataset, revision_metadata, stage, reason) do
    %{
      state: if(mode == :refresh, do: :refresh_failed, else: :load_failed),
      graph_name: dataset.graph_name,
      imported_revision: revision_metadata.analyzed_revision,
      graph_store_path: dataset.graph_store_path,
      stage: stage,
      reason: inspect(reason)
    }
  end
end
