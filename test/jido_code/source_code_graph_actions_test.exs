defmodule JidoCode.SourceCodeGraphActionsTest do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  # covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  # covers: package.jido_code.version_controlled_quality_surfaces
  use ExUnit.Case, async: true

  alias JidoCode.Actions.{
    AnalyzeSourceCodeGraph,
    LoadSourceCodeGraph,
    RefreshSourceCodeGraph,
    GetSourceCodeGraphStatus,
    QuerySourceCodeGraph,
    InspectSourceCodeGraphDataset
  }

  setup do
    workspace_path = create_workspace_path!()
    %{context: %{managed_repo_id: "repo-123", workspace_path: workspace_path}}
  end

  describe "AnalyzeSourceCodeGraph" do
    test "returns full-profile ontology analysis metadata and staged artifacts", %{context: context} do
      assert {:ok, result} = AnalyzeSourceCodeGraph.run(%{revision: "abc123"}, context)

      assert result.status == :analysis_ready
      assert result.graph_name == "source_code"
      assert result.ontology_profile == "full"
      assert result.analysis.adapter == :elixir_ontologies
      assert result.analysis.extraction_mode == :full
      assert result.analysis.options.include_expressions == true
      assert result.analysis.options.exclude_tests == true
      assert result.analysis.metadata.file_count >= 1
      assert result.analysis.metadata.module_count >= 1
      assert result.revision_metadata.analyzed_revision == "abc123"
      assert String.starts_with?(result.revision_metadata.workspace_snapshot_identity, "snapshot:")
      assert length(result.load_artifacts.ontology_schema.artifacts) == 5
      assert result.load_artifacts.project_individuals.triple_count > 0
      assert result.latest_analysis_status.state == :analyzed
      assert result.latest_analysis_status.ready? == true
    end

    test "returns typed diagnostics when ontology analysis fails" do
      assert {:error, :source_code_graph_analysis_failed, diagnostics} =
               AnalyzeSourceCodeGraph.run(
                 %{managed_repo_id: "repo-123", workspace_path: "/tmp/does-not-exist"},
                 %{}
               )

      assert diagnostics.state == :analysis_failed
      assert diagnostics.graph_name == "source_code"
      assert is_binary(diagnostics.failure)
    end
  end

  describe "Load and status actions" do
    test "return ready graph metadata once loaded", %{context: context} do
      assert {:ok, load_result} = LoadSourceCodeGraph.run(%{revision: "abc123"}, context)
      assert load_result.status == :graph_loaded
      assert load_result.latest_import_status.ready? == true

      assert {:ok, status_result} =
               GetSourceCodeGraphStatus.run(
                 %{},
                 Map.put(context, :latest_import_status, load_result.latest_import_status)
               )

      assert status_result.ready? == true
      assert status_result.latest_import_status.state == :loaded
    end

    test "returns coherent replacement metadata for refresh", %{context: context} do
      assert {:ok, result} = RefreshSourceCodeGraph.run(%{revision: "def456"}, context)

      assert result.status == :graph_refreshed
      assert result.latest_import_status.ready? == true
      assert result.latest_import_status.refresh_mode == :replace_named_graph
    end
  end

  describe "QuerySourceCodeGraph" do
    test "returns typed not-ready error before load", %{context: context} do
      assert {:error, :source_code_graph_not_ready, _message} =
               QuerySourceCodeGraph.run(%{sparql: "SELECT * WHERE { ?s ?p ?o }"}, context)
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
    test "returns bounded dataset diagnostics", %{context: context} do
      assert {:ok, result} = InspectSourceCodeGraphDataset.run(%{}, context)

      assert result.dataset.graph_name == "source_code"
      assert result.diagnostics.ready? == false
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_source_code_graph_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))
    File.mkdir_p!(Path.join(workspace_path, "test"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule Example.MixProject do
        use Mix.Project

        def project do
          [app: :example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule Example do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "test/example_test.exs"),
      """
      defmodule ExampleTest do
        use ExUnit.Case

        test "greets" do
          assert Example.greet("world") == "hello world"
        end
      end
      """
    )

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end
end
