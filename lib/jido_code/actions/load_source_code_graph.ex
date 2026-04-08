defmodule JidoCode.Actions.LoadSourceCodeGraph do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together
  @moduledoc """
  Defines named-graph load behavior for ontology/schema and project individuals.

  Phase 20 keeps the load contract explicit and typed before later phases connect
  the action to TripleStore-backed persistence.
  """

  use Jido.Action,
    name: "jido_code_load_source_code_graph",
    description: "Define the initial source_code named-graph load contract.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil]
    ]

  alias JidoCode.Actions.SourceCodeGraphSupport

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- SourceCodeGraphSupport.resolve_graph_context(params, context) do
      latest_import_status = %{
        state: :loaded,
        ready?: true,
        graph_name: graph_context.graph_name,
        imported_revision: graph_context.revision_metadata.revision,
        imported_at: DateTime.utc_now(),
        load_strategy: :replace_named_graph,
        schema_included?: true,
        individuals_included?: true
      }

      {:ok,
       %{
         status: :graph_loaded,
         graph_name: graph_context.graph_name,
         store: %{
           backend: :triple_store,
           schema: :quad,
           path: graph_context.graph_store_path
         },
         dataset: graph_context.dataset_metadata,
         latest_import_status: latest_import_status
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
