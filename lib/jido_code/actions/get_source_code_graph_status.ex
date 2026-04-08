defmodule JidoCode.Actions.GetSourceCodeGraphStatus do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.graph_revision_state_is_explicit_and_explainable
  @moduledoc """
  Returns current graph readiness and latest import metadata.
  """

  use Jido.Action,
    name: "jido_code_get_source_code_graph_status",
    description: "Inspect graph readiness and latest import metadata.",
    schema: [
      managed_repo_id: [type: :string, default: nil],
      workspace_path: [type: :string, default: nil],
      revision: [type: :string, default: nil]
    ]

  alias JidoCode.Actions.SourceCodeGraphSupport

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- SourceCodeGraphSupport.resolve_graph_context(params, context) do
      requested_revision = graph_context.revision_metadata.requested_revision
      latest_import_status = graph_context.latest_import_status
      latest_analysis_status = graph_context.latest_analysis_status

      stale_status =
        SourceCodeGraphSupport.stale_status(latest_import_status, graph_context.revision_metadata)

      {:ok,
       %{
         graph_name: graph_context.graph_name,
         ready?: SourceCodeGraphSupport.ready?(latest_import_status),
         stale?: stale_status.stale?,
         stale_reason: stale_status.stale_reason,
         queryable_when_stale?: stale_status.queryable_when_stale?,
         requested_revision: requested_revision,
         current_revision: graph_context.revision_metadata.current_revision,
         current_source_commit: graph_context.revision_metadata.source_commit,
         current_workspace_snapshot_identity: graph_context.revision_metadata.workspace_snapshot_identity,
         imported_revision: Map.get(latest_import_status, :imported_revision),
         latest_import_status: latest_import_status,
         latest_analysis_status: latest_analysis_status,
         latest_failure: graph_context.latest_failure,
         dataset: graph_context.dataset_metadata
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
