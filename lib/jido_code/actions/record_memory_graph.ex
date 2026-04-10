defmodule JidoCode.Actions.RecordMemoryGraph do
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  @moduledoc """
  Establishes the explicit memory-recording action contract for later capture work.

  Phase 28 introduces the bounded action surface now so callers stop assuming
  direct store writes, while the actual capture-plane insertion semantics arrive
  in the later provenance and durable-memory phases.
  """

  use Jido.Action,
    name: "jido_code_record_memory_graph",
    description: "Define the explicit memory recording contract without exposing raw graph writes.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil],
      graph_name: [type: :string, default: "memory"],
      capture: [type: :map, default: %{}]
    ]

  alias JidoCode.Actions.MemoryGraphSupport

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- MemoryGraphSupport.resolve_graph_context(params, context) do
      stale_status =
        MemoryGraphSupport.stale_status(
          graph_context.latest_validation_status,
          graph_context.revision_metadata
        )

      cond do
        not MemoryGraphSupport.ready?(graph_context.latest_validation_status) ->
          {:error, :memory_graph_not_ready,
           "The memory graph foundation must be refreshed and validated before capture requests can be accepted."}

        stale_status.stale? ->
          {:error, :memory_graph_stale,
           "The memory graph must be revalidated for the requested revision before capture requests can be accepted."}

        true ->
          {:error, :memory_capture_plane_not_ready,
           %{
             state: :capture_plane_not_ready,
             graph_name: graph_context.selected_graph_name,
             named_graph_iri: graph_context.selected_named_graph_iri,
             capture_ready?: false,
             current_revision: graph_context.revision_metadata.current_revision,
             requested_revision: graph_context.revision_metadata.requested_revision,
             capture: Map.get(params, :capture, %{})
           }}
      end
    end
  end
end
