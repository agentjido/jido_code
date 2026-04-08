defmodule JidoCode.Agents.SourceCodeGraphLoader do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc """
  Lazy specialist agent for source-code graph load and refresh behavior.

  Phase 20 defines the explicit agent role and boundaries before later phases
  connect it to TripleStore-backed named-graph persistence.
  """

  use Jido.Agent,
    name: "source_code_graph_loader",
    priority: :normal,
    schema: [
      last_load_request: [
        type: :map,
        default: %{},
        doc: "Last requested load or refresh inputs and metadata."
      ]
    ]
end
