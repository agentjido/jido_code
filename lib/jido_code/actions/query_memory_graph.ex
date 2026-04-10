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
  alias JidoCode.MemoryGraph.ProductFeedback

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- MemoryGraphSupport.resolve_graph_context(params, context) do
      allow_stale? = Map.get(params, :allow_stale?) == true

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
          degraded?: stale_status.stale?,
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
                 "The memory graph foundation must be refreshed and validated before memory queries can run."
             }
           }}

        stale_status.stale? and not allow_stale? ->
          {:error, :memory_graph_stale,
           %{
             graph: normalized_graph,
             feedback: ProductFeedback.for_graph(normalized_graph, %{type: :memory_graph_stale}),
             error: %{
               type: :memory_graph_stale,
               detail:
                 "The memory graph must be revalidated for the requested revision before memory queries can run."
             }
           }}

        true ->
          case Query.run(graph_context, params.sparql) do
            {:ok, result} ->
              result_graph =
                graph
                |> Map.put(:degraded?, stale_status.stale?)
                |> ProductFeedback.normalize_graph()

              {:ok,
               Map.merge(result, %{
                 degraded?: stale_status.stale?,
                 stale_graph?: stale_status.stale?,
                 stale_reason: stale_status.stale_reason,
                 current_revision: graph_context.revision_metadata.current_revision,
                 requested_revision: graph_context.revision_metadata.requested_revision,
                 validated_revision: Map.get(graph_context.latest_validation_status, :validated_revision),
                 state: result_graph.state,
                 recovery_action: result_graph.recovery_action,
                 feedback: ProductFeedback.for_graph(result_graph)
               })}

            {:error, reason, diagnostics} ->
              failed_graph =
                graph
                |> Map.put(:latest_failure, diagnostics)
                |> ProductFeedback.normalize_graph()

              {:error, reason,
               %{
                 graph: failed_graph,
                 feedback: ProductFeedback.for_graph(failed_graph, %{type: reason}),
                 error: %{type: reason, detail: Map.get(diagnostics, :reason) || inspect(diagnostics)},
                 diagnostics: diagnostics
               }}
          end
      end
    end
  end
end
