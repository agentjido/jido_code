defmodule JidoCode.Actions.RecordMemoryGraph do
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  # covers: architecture.repository_runtime_integration.memory_graph_read_write_and_query_stay_workspace_bound
  # covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption
  @moduledoc """
  Records repository-scoped workflow provenance, durable memory, and durable-memory
  update operations through the canonical memory capture plane.
  """

  use Jido.Action,
    name: "jido_code_record_memory_graph",
    description:
      "Record workflow provenance, durable memory, and durable-memory updates without exposing raw graph writes.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil],
      graph_name: [type: :string, default: "memory"],
      capture: [type: :map, default: %{}]
    ]

  alias JidoCode.Actions.MemoryGraphSupport
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.CaptureEnvelope
  alias JidoCode.MemoryGraph.CaptureWriter
  alias JidoCode.MemoryGraph.DurableMemoryEnvelope
  alias JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope
  alias JidoCode.MemoryGraph.DurableMemoryUpdateWriter
  alias JidoCode.MemoryGraph.DurableMemoryWriter
  alias JidoCode.MemoryGraph.ProductFeedback

  @impl true
  def run(params, context) do
    params = normalize_graph_target(params)

    with {:ok, graph_context} <- MemoryGraphSupport.resolve_graph_context(params, context) do
      capture = Map.get(params, :capture, %{})

      stale_status =
        MemoryGraphSupport.stale_status(
          graph_context.latest_validation_status,
          graph_context.revision_metadata
        )

      graph =
        %{
          graph_name: graph_context.selected_graph_name,
          named_graph_iri: graph_context.selected_named_graph_iri,
          ready?: MemoryGraphSupport.ready?(graph_context.latest_validation_status),
          stale?: stale_status.stale?,
          degraded?: false,
          stale_reason: stale_status.stale_reason,
          queryable_when_stale?: stale_status.queryable_when_stale?,
          requested_revision: graph_context.revision_metadata.requested_revision,
          current_revision: graph_context.revision_metadata.current_revision,
          validated_revision: Map.get(graph_context.latest_validation_status, :validated_revision),
          latest_validation_status: graph_context.latest_validation_status,
          latest_record_status: graph_context.latest_record_status,
          latest_query_status: graph_context.latest_query_status,
          latest_failure: graph_context.latest_failure,
          dataset: graph_context.dataset_metadata
        }

      normalized_graph = ProductFeedback.normalize_graph(graph)

      cond do
        not MemoryGraphSupport.ready?(graph_context.latest_validation_status) ->
          {:error, :memory_graph_not_ready,
           %{
             graph: normalized_graph,
             feedback: ProductFeedback.for_graph(normalized_graph, %{type: :memory_graph_not_ready}),
             error: %{
               type: :memory_graph_not_ready,
               detail:
                 "The memory graph foundation must be refreshed and validated before capture requests can be accepted."
             }
           }}

        stale_status.stale? and not memory_update_kind?(capture) ->
          {:error, :memory_graph_stale,
           %{
             graph: normalized_graph,
             feedback: ProductFeedback.for_graph(normalized_graph, %{type: :memory_graph_stale}),
             error: %{
               type: :memory_graph_stale,
               detail:
                 "The memory graph must be revalidated for the requested revision before capture requests can be accepted."
             }
           }}

        memory_update_kind?(capture) ->
          DurableMemoryUpdateWriter.write(graph_context, capture)

        memory_kind?(capture) ->
          DurableMemoryWriter.write(graph_context, capture)

        true ->
          CaptureWriter.write(graph_context, capture)
      end
    end
  end

  defp normalize_graph_target(params) do
    capture = Map.get(params, :capture, %{})
    graph_name = Map.get(params, :graph_name)
    kind = Map.get(capture, :kind) || Map.get(capture, "kind")

    cond do
      provenance_kind?(kind) and graph_name in [nil, MemoryGraph.memory_graph_name()] ->
        Map.put(params, :graph_name, MemoryGraph.workflow_provenance_graph_name())

      true ->
        params
    end
  end

  defp provenance_kind?(kind) when is_atom(kind), do: kind in CaptureEnvelope.provenance_kinds()

  defp provenance_kind?(kind) when is_binary(kind) do
    case kind |> String.trim() do
      "work_session" -> true
      "agent_run" -> true
      "tool_invocation" -> true
      "prompt_turn" -> true
      "plan" -> true
      "patch" -> true
      "review" -> true
      _other -> false
    end
  end

  defp provenance_kind?(_kind), do: false

  defp memory_kind?(capture) when is_map(capture) do
    DurableMemoryEnvelope.supported_kind?(Map.get(capture, :kind) || Map.get(capture, "kind"))
  end

  defp memory_update_kind?(capture) when is_map(capture) do
    DurableMemoryUpdateEnvelope.supported_kind?(Map.get(capture, :kind) || Map.get(capture, "kind"))
  end
end
