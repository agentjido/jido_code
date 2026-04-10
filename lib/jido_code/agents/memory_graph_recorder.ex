defmodule JidoCode.Agents.MemoryGraphRecorder do
  @moduledoc """
  Lazy specialist agent for durable memory recording.

  The recorder establishes the pod-local contract for future capture-plane and
  durable memory insertion work without exposing direct graph writes elsewhere.
  """

  use Jido.Agent,
    name: "memory_graph_recorder",
    priority: :normal,
    schema: [
      last_record_request: [
        type: :map,
        default: %{},
        doc: "Last requested durable memory recording envelope."
      ],
      last_record_result: [
        type: :map,
        default: %{},
        doc: "Last bounded memory recording result returned by the specialist."
      ],
      latest_record_status: [
        type: :map,
        default: %{},
        doc: "Latest persisted memory-recording summary for the repository graph."
      ],
      last_record_failure: [
        type: :map,
        default: %{},
        doc: "Last typed recording failure observed by the specialist."
      ],
      last_recorded_at: [
        type: :datetime,
        default: nil,
        doc: "Timestamp of the most recent recording request handled by the specialist."
      ]
    ]
end
