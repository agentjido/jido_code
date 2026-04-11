defmodule JidoCode.Actions.GetMemoryGraphStatus do
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  @moduledoc """
  Returns current memory-graph readiness, validation freshness, and failure state.
  """

  use Jido.Action,
    name: "jido_code_get_memory_graph_status",
    description: "Inspect memory graph readiness, validation freshness, and bounded failure metadata.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil],
      graph_name: [type: :string, default: "memory"]
    ]

  alias JidoCode.Actions.MemoryGraphSupport
  alias JidoCode.MemoryGraph.ProductFeedback

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- MemoryGraphSupport.resolve_graph_context(params, context) do
      latest_validation_status = graph_context.latest_validation_status

      stale_status =
        MemoryGraphSupport.stale_status(
          latest_validation_status,
          graph_context.revision_metadata
        )

      graph =
        %{
          graph_name: graph_context.selected_graph_name,
          named_graph_iri: graph_context.selected_named_graph_iri,
          ready?: MemoryGraphSupport.ready?(latest_validation_status),
          stale?: stale_status.stale?,
          degraded?: false,
          stale_reason: stale_status.stale_reason,
          queryable_when_stale?: stale_status.queryable_when_stale?,
          requested_revision: graph_context.revision_metadata.requested_revision,
          current_revision: graph_context.revision_metadata.current_revision,
          validated_revision: Map.get(latest_validation_status, :validated_revision),
          latest_record_status: graph_context.latest_record_status,
          latest_query_status: graph_context.latest_query_status,
          latest_validation_status: latest_validation_status,
          latest_failure: graph_context.latest_failure,
          dataset: graph_context.dataset_metadata,
          semantic_model: Map.get(latest_validation_status, :semantic_model)
        }

      normalized_graph = ProductFeedback.normalize_graph(graph)

      {:ok,
       Map.merge(graph, %{
         state: normalized_graph.state,
         recovery_action: normalized_graph.recovery_action,
         feedback: ProductFeedback.for_graph(normalized_graph)
       })}
    end
  end
end
