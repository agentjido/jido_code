defmodule JidoCode.SourceCodeGraph.Analysis do
  # covers: architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc false

  alias JidoCode.SourceCodeGraph

  @type graph_context :: map()

  @spec analyze(graph_context(), keyword()) :: {:ok, map()} | {:error, map()}
  def analyze(graph_context, opts \\ []) when is_map(graph_context) and is_list(opts) do
    started_at = DateTime.utc_now()
    analysis_options = analysis_options(graph_context, opts)
    revision_metadata = revision_metadata(graph_context)

    case ElixirOntologies.analyze_project(graph_context.workspace_path, analysis_options) do
      {:ok, analysis_result} ->
        build_success_result(graph_context, analysis_result, analysis_options, revision_metadata, started_at)

      {:error, reason} ->
        {:error,
         %{
           state: :analysis_failed,
           graph_name: graph_context.graph_name,
           ontology_profile: graph_context.ontology_profile,
           analyzed_revision: revision_metadata.analyzed_revision,
           analyzed_at: DateTime.utc_now(),
           source_commit: revision_metadata.source_commit,
           workspace_snapshot_identity: revision_metadata.workspace_snapshot_identity,
           failure: normalize_failure(reason)
         }}
    end
  end

  defp build_success_result(
         graph_context,
         analysis_result,
         analysis_options,
         revision_metadata,
         started_at
       ) do
    completed_at = DateTime.utc_now()
    rdf_graph = rdf_graph(analysis_result.graph)
    individual_triple_count = RDF.Graph.triple_count(rdf_graph)

    latest_analysis_status = %{
      state: :analyzed,
      ready?: true,
      graph_name: graph_context.graph_name,
      ontology_profile: graph_context.ontology_profile,
      analyzed_revision: revision_metadata.analyzed_revision,
      analyzed_at: completed_at,
      source_commit: revision_metadata.source_commit,
      workspace_snapshot_identity: revision_metadata.workspace_snapshot_identity,
      file_count: analysis_result.metadata.file_count,
      module_count: analysis_result.metadata.module_count,
      error_count: analysis_result.metadata.error_count,
      failure: nil
    }

    result = %{
      status: :analysis_ready,
      graph_name: graph_context.graph_name,
      ontology_profile: graph_context.ontology_profile,
      analysis: %{
        adapter: :elixir_ontologies,
        extraction_mode: :full,
        workspace_path: graph_context.workspace_path,
        options: %{
          base_iri: analysis_options[:base_iri],
          include_expressions: analysis_options[:include_expressions],
          include_git_info: analysis_options[:include_git_info],
          include_source_text: analysis_options[:include_source_text],
          exclude_tests: analysis_options[:exclude_tests]
        },
        metadata:
          Map.merge(analysis_result.metadata, %{
            started_at: started_at,
            completed_at: completed_at,
            duration_ms: DateTime.diff(completed_at, started_at, :millisecond)
          }),
        errors: normalize_analysis_errors(graph_context.workspace_path, analysis_result.errors)
      },
      revision_metadata: revision_metadata,
      dataset:
        graph_context.dataset_metadata
        |> Map.put(:revision, revision_metadata.analyzed_revision),
      load_artifacts: %{
        graph_name: graph_context.graph_name,
        ontology_schema: %{
          logical_group: :ontology_schema,
          artifacts: SourceCodeGraph.ontology_artifacts()
        },
        project_individuals: %{
          logical_group: :project_individuals,
          format: :rdf_graph,
          triple_count: individual_triple_count,
          graph: rdf_graph
        }
      },
      latest_analysis_status: latest_analysis_status
    }

    {:ok, result}
  end

  defp analysis_options(graph_context, opts) do
    [
      base_iri: SourceCodeGraph.base_iri(graph_context.managed_repo_id),
      include_source_text: Keyword.get(opts, :include_source_text, false),
      include_git_info: Keyword.get(opts, :include_git_info, false),
      include_expressions: true,
      exclude_tests: Keyword.get(opts, :exclude_tests, true)
    ]
  end

  defp revision_metadata(graph_context) do
    graph_context.revision_metadata
    |> Map.put_new(:refresh_mode, :replace_named_graph)
  end

  defp normalize_analysis_errors(workspace_path, errors) do
    Enum.map(errors, fn
      {file_path, reason} ->
        %{
          file: normalize_file_path(workspace_path, file_path),
          reason: normalize_failure(reason)
        }

      other ->
        %{file: nil, reason: normalize_failure(other)}
    end)
  end

  defp normalize_file_path(workspace_path, file_path) when is_binary(file_path) do
    Path.relative_to(file_path, workspace_path)
  rescue
    _ -> file_path
  end

  defp normalize_file_path(_workspace_path, file_path), do: inspect(file_path)

  defp normalize_failure(reason) when is_binary(reason), do: reason
  defp normalize_failure(reason), do: inspect(reason)

  defp rdf_graph(%RDF.Graph{} = graph), do: graph
  defp rdf_graph(%ElixirOntologies.Graph{graph: %RDF.Graph{} = graph}), do: graph
end
