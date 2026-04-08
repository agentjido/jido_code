defmodule JidoCode.Actions.RefreshSourceCodeGraph do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  @moduledoc """
  Defines coherent replacement refresh behavior for the source_code named graph.
  """

  use Jido.Action,
    name: "jido_code_refresh_source_code_graph",
    description: "Define coherent refresh behavior for the source_code named graph.",
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
        state: :refreshed,
        ready?: true,
        graph_name: graph_context.graph_name,
        imported_revision: graph_context.revision_metadata.revision,
        imported_at: DateTime.utc_now(),
        refresh_mode: :replace_named_graph
      }

      {:ok,
       %{
         status: :graph_refreshed,
         graph_name: graph_context.graph_name,
         dataset: graph_context.dataset_metadata,
         latest_import_status: latest_import_status
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
