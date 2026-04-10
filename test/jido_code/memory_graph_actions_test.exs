defmodule JidoCode.MemoryGraphActionsTest do
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: package.jido_code.version_controlled_quality_surfaces
  use ExUnit.Case, async: true

  alias JidoCode.Actions.{
    GetMemoryGraphStatus,
    InvalidateMemoryGraph,
    QueryMemoryGraph,
    RecordMemoryGraph,
    RefreshMemoryGraph,
    ValidateMemoryGraph
  }

  alias JidoCode.MemoryGraph

  setup do
    workspace_path = create_workspace_path!()
    %{context: %{managed_repo_id: "repo-123", workspace_path: workspace_path}}
  end

  describe "Refresh and validate actions" do
    test "bootstrap the shared store foundation and report ready validation state", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{revision: "abc123"}, context)

      assert refresh_result.status == :memory_graph_refreshed
      assert refresh_result.store.backend == :triple_store
      assert refresh_result.store.schema == :quad
      assert File.dir?(refresh_result.store.path)
      assert refresh_result.load_counts.memory > 0
      assert refresh_result.load_counts.workflow_provenance > 0
      assert refresh_result.latest_validation_status.state == :validated
      assert refresh_result.latest_validation_status.ready? == true

      assert {:ok, validate_result} =
               ValidateMemoryGraph.run(
                 %{revision: "abc123"},
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert validate_result.status == :memory_graph_validated
      assert validate_result.latest_validation_status.ready? == true
      assert validate_result.graph_stats.memory.present? == true
      assert validate_result.graph_stats.workflow_provenance.present? == true
    end

    test "returns explicit not-ready status before the shared store is bootstrapped", %{context: context} do
      assert {:ok, status_result} = GetMemoryGraphStatus.run(%{revision: "abc123"}, context)

      assert status_result.ready? == false
      assert status_result.stale? == false
      assert status_result.latest_validation_status.state == :not_validated
    end
  end

  describe "QueryMemoryGraph" do
    test "returns typed not-ready error before validation", %{context: context} do
      assert {:error, :memory_graph_not_ready, _message} =
               QueryMemoryGraph.run(%{sparql: "SELECT * WHERE { ?s ?p ?o }"}, context)
    end

    test "returns structured SPARQL results for the memory graph after refresh", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{revision: "abc123"}, context)

      assert {:ok, result} =
               QueryMemoryGraph.run(
                 %{
                   sparql: """
                   SELECT ?class
                   WHERE {
                     ?class a owl:Class .
                     FILTER(?class = jido:Fact)
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: "abc123"}
                 }
               )

      assert result.status == :query_succeeded
      assert result.engine == :sparql
      assert result.graph_name == "memory"
      assert result.named_graph_iri == MemoryGraph.memory_named_graph_iri()
      assert result.row_count == 1

      assert Enum.any?(result.bindings, fn row ->
               get_in(row, ["class", :value]) == "https://jido.run/ontology/memory#Fact"
             end)

      assert result.degraded? == false
      assert result.stale_graph? == false
    end

    test "allows bounded degraded queries when the workspace revision moved", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)
      rewrite_workspace_module!(context.workspace_path, "ExampleMemoryGraphRenamed")

      assert {:ok, result} =
               QueryMemoryGraph.run(
                 %{sparql: "SELECT * WHERE { ?s ?p ?o } LIMIT 5", allow_stale?: true},
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert result.degraded? == true
      assert result.stale_graph? == true
      assert result.stale_reason == :workspace_revision_changed
      assert result.current_revision != result.validated_revision
    end
  end

  describe "record and invalidate actions" do
    test "returns a typed capture-plane-not-ready outcome for record requests", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)

      assert {:error, :memory_capture_plane_not_ready, diagnostics} =
               RecordMemoryGraph.run(
                 %{capture: %{kind: :fact, content: "example"}},
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert diagnostics.state == :capture_plane_not_ready
      assert diagnostics.capture_ready? == false
      assert diagnostics.graph_name == "memory"
    end

    test "returns a bounded invalidation outcome", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{revision: "abc123"}, context)

      assert {:ok, result} =
               InvalidateMemoryGraph.run(
                 %{reason: :manual_invalidation, revision: "abc123"},
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert result.status == :memory_graph_invalidated
      assert result.stale? == true
      assert result.stale_reason == :manual_invalidation
      assert result.latest_validation_status.state == :invalidated
      assert result.latest_validation_status.ready? == false
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_memory_graph_actions_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule MemoryGraphActionsExample.MixProject do
        use Mix.Project

        def project do
          [app: :memory_graph_actions_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule ExampleMemoryGraph do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )
  end
end
