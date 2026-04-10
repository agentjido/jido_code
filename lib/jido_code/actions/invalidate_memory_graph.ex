defmodule JidoCode.Actions.InvalidateMemoryGraph do
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  @moduledoc """
  Produces a bounded invalidation outcome for stale or manually invalidated memory state.
  """

  use Jido.Action,
    name: "jido_code_invalidate_memory_graph",
    description: "Invalidate the current memory graph validation state for the requested repository revision.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil],
      graph_name: [type: :string, default: "memory"],
      reason: [type: :atom, default: :manual_invalidation]
    ]

  alias JidoCode.Actions.MemoryGraphSupport

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- MemoryGraphSupport.resolve_graph_context(params, context) do
      invalidated_at = DateTime.utc_now()
      current_revision = graph_context.revision_metadata.current_revision

      latest_validation_status =
        graph_context.latest_validation_status
        |> Map.put(:state, :invalidated)
        |> Map.put(:ready?, false)
        |> Map.put(:graph_name, graph_context.selected_graph_name)
        |> Map.put(:current_revision, current_revision)
        |> Map.put(:stale?, true)
        |> Map.put(:stale_reason, params.reason)
        |> Map.put(:invalidated_at, invalidated_at)
        |> Map.put(:failure, nil)

      {:ok,
       %{
         status: :memory_graph_invalidated,
         graph_name: graph_context.selected_graph_name,
         named_graph_iri: graph_context.selected_named_graph_iri,
         current_revision: current_revision,
         latest_validation_status: latest_validation_status,
         stale?: true,
         stale_reason: params.reason,
         dataset: Map.put(graph_context.dataset_metadata, :revision, current_revision)
       }}
    end
  end
end
