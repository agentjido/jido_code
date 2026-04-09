defmodule JidoCode.Actions.TraceSourceCodeGraphImpact do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  @moduledoc """
  Helper action for bounded semantic impact traversals over the source_code graph.
  """

  use Jido.Action,
    name: "jido_code_trace_source_code_graph_impact",
    description: "Trace bounded semantic relationships from a module or function in the loaded source_code graph.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil],
      allow_stale?: [type: :boolean, default: false],
      subject_iri: [type: :string, default: nil],
      module_name: [type: :string, default: nil],
      function_name: [type: :string, default: nil],
      arity: [type: :integer, default: nil],
      direction: [type: :atom, default: :outgoing, constraints: [one_of: [:outgoing, :incoming, :both]]],
      limit: [type: :integer, default: 50]
    ]

  alias JidoCode.Actions.{QuerySourceCodeGraph, SourceCodeGraphSupport}
  alias JidoCode.SourceCodeGraph.HelperQueries

  @impl true
  def run(params, context) do
    try do
      with {:ok, graph_context} <- SourceCodeGraphSupport.resolve_graph_context(params, context),
           compiled_query <- HelperQueries.impact(graph_context, params) do
        case QuerySourceCodeGraph.run(
               %{
                 sparql: compiled_query,
                 revision: params[:revision],
                 allow_stale?: Map.get(params, :allow_stale?, false) == true
               },
               context
             ) do
          {:ok, result} ->
            {:ok,
             result
             |> Map.put(:helper, :impact)
             |> Map.put(:compiled_sparql, compiled_query)}

          {:error, reason, diagnostics} ->
            {:error, reason, diagnostics}

          other ->
            other
        end
      end
    rescue
      error in ArgumentError ->
        {:error, :source_code_graph_invalid_query,
         %{
           stage: :compile_helper_query,
           reason: Exception.message(error),
           library: :sparql
         }}
    end
  end
end
