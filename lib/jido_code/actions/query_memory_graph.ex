defmodule JidoCode.Actions.QueryMemoryGraph do
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  @moduledoc """
  Executes a bounded SPARQL query against one repository-local memory graph.
  """

  use Jido.Action,
    name: "jido_code_query_memory_graph",
    description: "Execute a SPARQL query over the repository-local memory or workflow provenance graph.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil],
      graph_name: [type: :string, default: "memory"],
      allow_stale?: [type: :boolean, default: false],
      sparql: [type: :string, required: true]
    ]

  alias JidoCode.Actions.MemoryGraphSupport
  alias JidoCode.MemoryGraph.Query

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- MemoryGraphSupport.resolve_graph_context(params, context) do
      allow_stale? = Map.get(params, :allow_stale?) == true

      stale_status =
        MemoryGraphSupport.stale_status(
          graph_context.latest_validation_status,
          graph_context.revision_metadata
        )

      cond do
        not MemoryGraphSupport.ready?(graph_context.latest_validation_status) ->
          {:error, :memory_graph_not_ready,
           "The memory graph foundation must be refreshed and validated before memory queries can run."}

        stale_status.stale? and not allow_stale? ->
          {:error, :memory_graph_stale,
           "The memory graph must be revalidated for the requested revision before memory queries can run."}

        true ->
          case Query.run(graph_context, params.sparql) do
            {:ok, result} ->
              {:ok,
               Map.merge(result, %{
                 degraded?: stale_status.stale?,
                 stale_graph?: stale_status.stale?,
                 stale_reason: stale_status.stale_reason,
                 current_revision: graph_context.revision_metadata.current_revision,
                 requested_revision: graph_context.revision_metadata.requested_revision,
                 validated_revision: Map.get(graph_context.latest_validation_status, :validated_revision)
               })}

            {:error, reason, diagnostics} ->
              {:error, reason, diagnostics}
          end
      end
    end
  end
end
