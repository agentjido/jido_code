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
  alias JidoCode.SourceCodeGraph.Analysis
  alias JidoCode.SourceCodeGraph.Store

  @impl true
  def run(params, context) do
    with {:ok, graph_context} <- SourceCodeGraphSupport.resolve_graph_context(params, context) do
      case Analysis.analyze(graph_context) do
        {:ok, analysis_result} ->
          case Store.load_snapshot(analysis_result, mode: :refresh) do
            {:ok, refresh_result} ->
              {:ok, refresh_result}

            {:error, diagnostics} when is_map(diagnostics) ->
              {:error, :source_code_graph_store_failed,
               Map.put(diagnostics, :latest_analysis_status, analysis_result.latest_analysis_status)}
          end

        {:error, %{state: :analysis_failed} = diagnostics} ->
          {:error, :source_code_graph_analysis_failed, diagnostics}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
