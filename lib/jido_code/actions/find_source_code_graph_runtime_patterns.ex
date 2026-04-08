defmodule JidoCode.Actions.FindSourceCodeGraphRuntimePatterns do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  @moduledoc """
  Helper action for runtime-pattern lookups over the source_code graph.
  """

  use Jido.Action,
    name: "jido_code_find_source_code_graph_runtime_patterns",
    description:
      "Find runtime-pattern classifications in the loaded source_code graph through an explicit SPARQL helper query.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil],
      allow_stale?: [type: :boolean, default: false],
      pattern_name_contains: [type: :string, default: nil],
      limit: [type: :integer, default: 50]
    ]

  alias JidoCode.Actions.{QuerySourceCodeGraph, SourceCodeGraphSupport}
  alias JidoCode.SourceCodeGraph.HelperQueries

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- SourceCodeGraphSupport.resolve_graph_context(params, context) do
      compiled_query = HelperQueries.runtime_patterns(graph_context, params)

      case QuerySourceCodeGraph.run(
             %{sparql: compiled_query, revision: params[:revision], allow_stale?: params[:allow_stale?]},
             context
           ) do
        {:ok, result} ->
          {:ok,
           result
           |> Map.put(:helper, :runtime_patterns)
           |> Map.put(:compiled_sparql, compiled_query)}

        {:error, reason, diagnostics} ->
          {:error, reason, diagnostics}

        other ->
          other
      end
    end
  end
end
