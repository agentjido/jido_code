defmodule JidoCode.Agents.MemoryGraphValidator do
  @moduledoc """
  Lazy specialist agent for validation, freshness, and invalidation work.

  The validator establishes the pod-local state contract for future revision-
  and evidence-driven freshness management in the memory graph capability.
  """

  use Jido.Agent,
    name: "memory_graph_validator",
    priority: :normal,
    schema: [
      last_validation_request: [
        type: :map,
        default: %{},
        doc: "Last requested validation or invalidation envelope."
      ],
      last_validation_result: [
        type: :map,
        default: %{},
        doc: "Last bounded validation result returned by the specialist."
      ],
      latest_validation_status: [
        type: :map,
        default: %{},
        doc: "Latest persisted validation or freshness summary for the repository graph."
      ],
      last_validation_failure: [
        type: :map,
        default: %{},
        doc: "Last typed validation or invalidation failure observed by the specialist."
      ],
      last_validated_at: [
        type: :datetime,
        default: nil,
        doc: "Timestamp of the most recent validation request handled by the specialist."
      ]
    ]
end
