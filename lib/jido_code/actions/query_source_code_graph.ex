defmodule JidoCode.Actions.QuerySourceCodeGraph do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  # covers: architecture.source_code_graph_pod.stale_queries_and_failures_remain_bounded
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
      allow_stale?: [type: :boolean, default: false],
      sparql: [type: :string, required: true]
    ]

  alias JidoCode.Actions.SourceCodeGraphSupport
  alias JidoCode.SourceCodeGraph.Query

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- SourceCodeGraphSupport.resolve_graph_context(params, context) do
      stale_status =
        SourceCodeGraphSupport.stale_status(
          graph_context.latest_import_status,
          graph_context.revision_metadata
        )

      cond do
        not SourceCodeGraphSupport.ready?(graph_context.latest_import_status) ->
          {:error, :source_code_graph_not_ready,
           "The source_code graph must be loaded before semantic queries can run."}

        stale_status.stale? and not Map.get(params, :allow_stale?, false) ->
          {:error, :source_code_graph_stale,
           "The source_code graph must be refreshed for the requested revision before semantic queries can run."}

        true ->
          case Query.run(graph_context, params.sparql) do
            {:ok, result} ->
              {:ok, attach_query_state(result, graph_context, stale_status)}

            {:error, reason, diagnostics} ->
              {:error, reason, diagnostics}
          end
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp attach_query_state(result, graph_context, stale_status) do
    Map.merge(result, %{
      degraded?: stale_status.stale?,
      stale_graph?: stale_status.stale?,
      stale_reason: stale_status.stale_reason,
      current_revision: graph_context.revision_metadata.current_revision,
      requested_revision: graph_context.revision_metadata.requested_revision,
      imported_revision: Map.get(graph_context.latest_import_status, :imported_revision)
    })
  end
end
