defmodule JidoCode.Actions.GetSourceCodeGraphStatus do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
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
      {:ok,
       %{
         graph_name: graph_context.graph_name,
         ready?: SourceCodeGraphSupport.ready?(graph_context.latest_import_status),
         latest_import_status: graph_context.latest_import_status,
         dataset: graph_context.dataset_metadata
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
