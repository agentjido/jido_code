defmodule JidoCode.Actions.LoadSourceCodeGraph do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together
  @moduledoc """
  Defines named-graph load behavior for ontology/schema and project individuals.
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
  alias JidoCode.SourceCodeGraph.Analysis
  alias JidoCode.SourceCodeGraph.Store

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- SourceCodeGraphSupport.resolve_graph_context(params, context) do
      with {:ok, analysis_result} <- Analysis.analyze(graph_context),
           {:ok, load_result} <- Store.load_snapshot(analysis_result, mode: :load) do
        {:ok, load_result}
      else
        {:error, %{state: :analysis_failed} = diagnostics} ->
          {:error, :source_code_graph_analysis_failed, diagnostics}

        {:error, diagnostics} when is_map(diagnostics) ->
          {:error, :source_code_graph_store_failed, diagnostics}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
