defmodule JidoCode.Actions.RecordMemoryGraph do
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  # covers: architecture.agent_os_integration.memory_graph_read_write_and_query_stay_workspace_bound
  # covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption
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
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.CaptureEnvelope
  alias JidoCode.MemoryGraph.CaptureWriter
  alias JidoCode.MemoryGraph.DurableMemoryEnvelope
  alias JidoCode.MemoryGraph.DurableMemoryWriter

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

      cond do
        not MemoryGraphSupport.ready?(graph_context.latest_validation_status) ->
          {:error, :memory_graph_not_ready,
           "The memory graph foundation must be refreshed and validated before capture requests can be accepted."}

        stale_status.stale? ->
          {:error, :memory_graph_stale,
           "The memory graph must be revalidated for the requested revision before capture requests can be accepted."}

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
end
