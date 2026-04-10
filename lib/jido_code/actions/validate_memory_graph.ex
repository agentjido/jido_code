defmodule JidoCode.Actions.ValidateMemoryGraph do
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  @moduledoc """
  Validates that the repository-local memory graph foundation is available and explainable.
  """

  use Jido.Action,
    name: "jido_code_validate_memory_graph",
    description: "Validate that the repository-local memory graph foundation is present and revision-aware.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil],
      graph_name: [type: :string, default: "memory"]
    ]

  alias JidoCode.Actions.MemoryGraphSupport
  alias JidoCode.MemoryGraph.Store

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- MemoryGraphSupport.resolve_graph_context(params, context) do
      case Store.validate(graph_context) do
        {:ok, result} -> {:ok, result}
        {:error, diagnostics} -> {:error, :memory_graph_validation_failed, diagnostics}
      end
    end
  end
end
