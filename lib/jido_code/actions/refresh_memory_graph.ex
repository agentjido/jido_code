defmodule JidoCode.Actions.RefreshMemoryGraph do
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  @moduledoc """
  Bootstraps or refreshes the repository-local memory graph foundation.

  Phase 28 establishes the shared named-graph foundation by ensuring the memory
  ontology is present in the repository-local `memory` and `workflow_provenance`
  graphs without yet introducing the later capture-plane semantics.
  """

  use Jido.Action,
    name: "jido_code_refresh_memory_graph",
    description: "Bootstrap or refresh repository-local memory and workflow provenance graph foundation.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil],
      reset_store?: [type: :boolean, default: false]
    ]

  alias JidoCode.Actions.MemoryGraphSupport
  alias JidoCode.MemoryGraph.Store

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- MemoryGraphSupport.resolve_graph_context(params, context) do
      case Store.refresh(Map.put(graph_context, :reset_store?, Map.get(params, :reset_store?, false))) do
        {:ok, result} -> {:ok, result}
        {:error, diagnostics} -> {:error, :memory_graph_refresh_failed, diagnostics}
      end
    end
  end
end
