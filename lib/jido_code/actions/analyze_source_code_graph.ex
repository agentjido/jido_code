defmodule JidoCode.Actions.AnalyzeSourceCodeGraph do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
  @moduledoc """
  Defines full-profile ontology analysis over a repository workspace.

  Phase 20 establishes the explicit action surface and typed output contract.
  Later phases connect this action to ElixirOntologies full extraction.
  """

  use Jido.Action,
    name: "jido_code_analyze_source_code_graph",
    description: "Prepare a full-profile ontology analysis for a repository source graph.",
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
         status: :analysis_ready,
         graph_name: graph_context.graph_name,
         ontology_profile: graph_context.ontology_profile,
         analysis: %{
           adapter: :elixir_ontologies,
           extraction_mode: :full,
           workspace_path: graph_context.workspace_path
         },
         dataset: graph_context.dataset_metadata
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
