defmodule JidoCode.Actions.QuerySourceCodeGraph do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  @moduledoc """
  Defines post-load semantic query execution over the source_code named graph.
  """

  use Jido.Action,
    name: "jido_code_query_source_code_graph",
    description: "Execute a SPARQL query over the source_code named graph.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil],
      sparql: [type: :string, required: true]
    ]

  alias JidoCode.Actions.SourceCodeGraphSupport
  alias JidoCode.SourceCodeGraph.Query

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- SourceCodeGraphSupport.resolve_graph_context(params, context) do
      cond do
        not SourceCodeGraphSupport.ready?(graph_context.latest_import_status) ->
          {:error, :source_code_graph_not_ready,
           "The source_code graph must be loaded before semantic queries can run."}

        SourceCodeGraphSupport.stale?(
          graph_context.latest_import_status,
          graph_context.revision_metadata.revision
        ) ->
          {:error, :source_code_graph_stale,
           "The source_code graph must be refreshed for the requested revision before semantic queries can run."}

        true ->
          Query.run(graph_context, params.sparql)
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
