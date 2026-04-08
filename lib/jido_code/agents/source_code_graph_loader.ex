defmodule JidoCode.Agents.SourceCodeGraphLoader do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc """
  Lazy specialist agent for source-code graph load and refresh behavior.

  This specialist owns explicit named-graph load and coherent refresh requests
  for the repository-local `source_code` graph.
  """

  use Jido.Agent,
    name: "source_code_graph_loader",
    priority: :normal,
    signal_routes: [
      {"source_graph.status", JidoCode.Actions.GetSourceCodeGraphStatus},
      {"source_graph.load", JidoCode.Actions.LoadSourceCodeGraph},
      {"source_graph.refresh", JidoCode.Actions.RefreshSourceCodeGraph},
      {"source_graph.inspect", JidoCode.Actions.InspectSourceCodeGraphDataset}
    ],
    schema: [
      last_load_request: [
        type: :map,
        default: %{},
        doc: "Last requested load or refresh inputs and metadata."
      ],
      last_load_result: [
        type: :map,
        default: %{},
        doc: "Last bounded load or refresh result returned to this specialist."
      ],
      latest_analysis_status: [
        type: :map,
        default: %{},
        doc: "Latest analysis-readiness summary paired with load or refresh."
      ],
      latest_import_status: [
        type: :map,
        default: %{},
        doc: "Latest persisted import/readiness summary for the repository graph."
      ],
      last_load_failure: [
        type: :map,
        default: %{},
        doc: "Last typed load or refresh failure observed by the specialist."
      ],
      last_load_at: [
        type: :datetime,
        default: nil,
        doc: "Timestamp of the most recent load or refresh request handled by the specialist."
      ]
    ]
end
