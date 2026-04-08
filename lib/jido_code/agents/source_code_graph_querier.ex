defmodule JidoCode.Agents.SourceCodeGraphQuerier do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  @moduledoc """
  Lazy specialist agent for semantic source-code graph query behavior.

  This specialist owns explicit SPARQL-backed semantic lookup for the
  repository-local source_code graph, including bounded helper queries for
  common module, function, runtime-pattern, and impact workflows.
  """

  use Jido.Agent,
    name: "source_code_graph_querier",
    priority: :normal,
    signal_routes: [
      {"source_graph.status", JidoCode.Actions.GetSourceCodeGraphStatus},
      {"source_graph.query", JidoCode.Actions.QuerySourceCodeGraph},
      {"source_graph.inspect", JidoCode.Actions.InspectSourceCodeGraphDataset},
      {"source_graph.find_modules", JidoCode.Actions.FindSourceCodeGraphModules},
      {"source_graph.find_functions", JidoCode.Actions.FindSourceCodeGraphFunctions},
      {"source_graph.find_runtime_patterns", JidoCode.Actions.FindSourceCodeGraphRuntimePatterns},
      {"source_graph.trace_impact", JidoCode.Actions.TraceSourceCodeGraphImpact}
    ],
    schema: [
      last_query_request: [
        type: :map,
        default: %{},
        doc: "Last requested semantic query inputs and metadata."
      ],
      last_query_result: [
        type: :map,
        default: %{},
        doc: "Last bounded semantic query result returned to the specialist."
      ],
      latest_import_status: [
        type: :map,
        default: %{},
        doc: "Latest graph-readiness summary available to semantic query behavior."
      ],
      available_helpers: [
        type: {:list, :atom},
        default: [:modules, :functions, :runtime_patterns, :impact],
        doc: "Semantic helper query families explicitly supported by this specialist."
      ],
      last_query_failure: [
        type: :map,
        default: %{},
        doc: "Last typed semantic query failure observed by the specialist."
      ],
      last_query_at: [
        type: :datetime,
        default: nil,
        doc: "Timestamp of the most recent semantic query handled by the specialist."
      ]
    ]
end
