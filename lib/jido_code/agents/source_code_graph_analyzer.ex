defmodule JidoCode.Agents.SourceCodeGraphAnalyzer do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc """
  Lazy specialist agent for source-code ontology analysis.

  Phase 20 defines the runtime role and lifecycle; later phases connect this
  specialist to ElixirOntologies full-mode analysis.
  """

  use Jido.Agent,
    name: "source_code_graph_analyzer",
    priority: :normal,
    signal_routes: [
      {"source_graph.analyze", JidoCode.Actions.AnalyzeSourceCodeGraph}
    ],
    schema: [
      last_analysis_request: [
        type: :map,
        default: %{},
        doc: "Last requested analysis inputs and metadata."
      ]
    ]
end
