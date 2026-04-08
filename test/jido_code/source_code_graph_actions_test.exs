defmodule JidoCode.SourceCodeGraphActionsTest do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  # covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  use ExUnit.Case, async: true

  alias JidoCode.Actions.{
    AnalyzeSourceCodeGraph,
    LoadSourceCodeGraph,
    RefreshSourceCodeGraph,
    GetSourceCodeGraphStatus,
    QuerySourceCodeGraph,
    InspectSourceCodeGraphDataset
  }

  @context %{managed_repo_id: "repo-123", workspace_path: "/tmp/example-repo"}

  describe "AnalyzeSourceCodeGraph" do
    test "returns full-profile ontology analysis metadata" do
      assert {:ok, result} = AnalyzeSourceCodeGraph.run(%{}, @context)

      assert result.status == :analysis_ready
      assert result.graph_name == "source_code"
      assert result.ontology_profile == "full"
      assert result.analysis.adapter == :elixir_ontologies
      assert result.analysis.extraction_mode == :full
    end
  end

  describe "Load and status actions" do
    test "return ready graph metadata once loaded" do
      assert {:ok, load_result} = LoadSourceCodeGraph.run(%{revision: "abc123"}, @context)
      assert load_result.status == :graph_loaded
      assert load_result.latest_import_status.ready? == true

      assert {:ok, status_result} =
               GetSourceCodeGraphStatus.run(
                 %{},
                 Map.put(@context, :latest_import_status, load_result.latest_import_status)
               )

      assert status_result.ready? == true
      assert status_result.latest_import_status.state == :loaded
    end

    test "returns coherent replacement metadata for refresh" do
      assert {:ok, result} = RefreshSourceCodeGraph.run(%{revision: "def456"}, @context)

      assert result.status == :graph_refreshed
      assert result.latest_import_status.ready? == true
      assert result.latest_import_status.refresh_mode == :replace_named_graph
    end
  end

  describe "QuerySourceCodeGraph" do
    test "returns typed not-ready error before load" do
      assert {:error, :source_code_graph_not_ready, _message} =
               QuerySourceCodeGraph.run(%{sparql: "SELECT * WHERE { ?s ?p ?o }"}, @context)
    end

    test "returns structured SPARQL query result after load" do
      loaded_context = %{
        managed_repo_id: "repo-123",
        workspace_path: "/tmp/example-repo",
        latest_import_status: %{state: :loaded, ready?: true}
      }

      assert {:ok, result} =
               QuerySourceCodeGraph.run(
                 %{sparql: "SELECT * WHERE { GRAPH <source_code> { ?s ?p ?o } }"},
                 loaded_context
               )

      assert result.engine == :sparql
      assert result.library == :sparql
      assert result.graph_name == "source_code"
      assert result.bindings == []
    end
  end

  describe "InspectSourceCodeGraphDataset" do
    test "returns bounded dataset diagnostics" do
      assert {:ok, result} = InspectSourceCodeGraphDataset.run(%{}, @context)

      assert result.dataset.graph_name == "source_code"
      assert result.diagnostics.ready? == false
    end
  end
end
