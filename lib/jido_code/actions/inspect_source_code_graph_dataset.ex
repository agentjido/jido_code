defmodule JidoCode.Actions.InspectSourceCodeGraphDataset do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc """
  Returns bounded dataset and load-health diagnostics for the source_code graph.
  """

  use Jido.Action,
    name: "jido_code_inspect_source_code_graph_dataset",
    description: "Inspect source_code dataset metadata and load diagnostics.",
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
         dataset: graph_context.dataset_metadata,
         diagnostics: %{
           graph_name: graph_context.graph_name,
           ready?: SourceCodeGraphSupport.ready?(graph_context.latest_import_status),
           latest_import_status: graph_context.latest_import_status
         }
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
