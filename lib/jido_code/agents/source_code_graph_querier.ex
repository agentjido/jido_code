defmodule JidoCode.Agents.SourceCodeGraphQuerier do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc """
  Lazy specialist agent for semantic source-code graph query behavior.

  Phase 20 defines the agent boundary and later phases connect it to SPARQL
  execution over the repository-local source_code named graph.
  """

  use Jido.Agent,
    name: "source_code_graph_querier",
    priority: :normal,
    signal_routes: [
      {"source_graph.status", JidoCode.Actions.GetSourceCodeGraphStatus},
      {"source_graph.query", JidoCode.Actions.QuerySourceCodeGraph},
      {"source_graph.inspect", JidoCode.Actions.InspectSourceCodeGraphDataset}
    ],
    schema: [
      last_query_request: [
        type: :map,
        default: %{},
        doc: "Last requested semantic query inputs and metadata."
      ]
    ]
end
