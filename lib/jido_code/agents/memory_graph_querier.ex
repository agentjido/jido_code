defmodule JidoCode.Agents.MemoryGraphQuerier do
  @moduledoc """
  Lazy specialist agent for bounded memory recall and provenance lookup.

  The querier establishes the pod-local state contract for future memory and
  provenance query behavior without requiring raw store access.
  """

  use Jido.Agent,
    name: "memory_graph_querier",
    priority: :normal,
    schema: [
      last_query_request: [
        type: :map,
        default: %{},
        doc: "Last bounded memory or provenance query request."
      ],
      last_query_result: [
        type: :map,
        default: %{},
        doc: "Last bounded memory or provenance query result."
      ],
      latest_query_status: [
        type: :map,
        default: %{},
        doc: "Latest persisted query summary for the repository memory graph."
      ],
      available_helpers: [
        type: {:list, :string},
        default: ["memories", "workflow_provenance", "validation_status"],
        doc: "Helper lookups intended to stay bounded as product-facing contracts evolve."
      ],
      last_query_failure: [
        type: :map,
        default: %{},
        doc: "Last typed query failure observed by the specialist."
      ]
    ]
end
