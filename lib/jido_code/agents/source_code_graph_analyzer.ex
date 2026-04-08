defmodule JidoCode.Agents.SourceCodeGraphAnalyzer do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc """
  Lazy specialist agent for source-code ontology analysis.

  This specialist is the pod-local entrypoint for explicit full-mode ontology
  analysis. It keeps repository-scoped analysis requests and results bounded to
  the semantic graph lifecycle instead of pushing analysis into ambient helper
  behavior elsewhere in the product.
  """

  use Jido.Agent,
    name: "source_code_graph_analyzer",
    priority: :normal,
    signal_routes: [
      {"source_graph.status", JidoCode.Actions.GetSourceCodeGraphStatus},
      {"source_graph.analyze", JidoCode.Actions.AnalyzeSourceCodeGraph},
      {"source_graph.inspect", JidoCode.Actions.InspectSourceCodeGraphDataset}
    ],
    schema: [
      last_analysis_request: [
        type: :map,
        default: %{},
        doc: "Last requested analysis inputs and metadata."
      ],
      last_analysis_result: [
        type: :map,
        default: %{},
        doc: "Last bounded ontology-analysis result returned to this specialist."
      ],
      latest_analysis_status: [
        type: :map,
        default: %{},
        doc: "Latest persisted analysis-readiness summary for the repository graph."
      ],
      last_analysis_failure: [
        type: :map,
        default: %{},
        doc: "Last typed analysis failure observed by the specialist."
      ],
      last_analysis_at: [
        type: :datetime,
        default: nil,
        doc: "Timestamp of the most recent analysis request handled by the specialist."
      ]
    ]
end
