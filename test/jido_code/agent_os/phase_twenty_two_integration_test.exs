defmodule JidoCode.AgentOSPhaseTwentyTwoIntegrationTest do
  # covers: architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  # covers: architecture.agent_os_integration.workspace_context_hides_kernel_topology
  # covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  # covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.SourceCodeGraph

  setup do
    previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous)
    end)

    :ok
  end

  describe "22.4.1 SPARQL query scenarios" do
    test "22.4.1.1 query actions use sparql and target the repository-local source_code graph" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyTwo.Alpha")

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "rev-one"
               )

      assert {:ok, query_result} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?module
                 WHERE {
                   ?module a struct:Module .
                 }
                 ORDER BY ?module
                 """,
                 revision: "rev-one"
               )

      assert query_result.engine == :sparql
      assert query_result.library == :sparql
      assert query_result.graph_name == "source_code"
      assert query_result.named_graph_iri == SourceCodeGraph.named_graph_iri()
      assert query_result.target.backend == :triple_store
      assert query_result.row_count >= 1
    end

    test "22.4.1.2 helper entrypoints return structured module, function, and runtime rows" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyTwo.Alpha")

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, modules_result} =
               AgentWorkspace.find_source_code_graph_modules(
                 managed_repo_id,
                 workspace_path,
                 module_name_contains: "PhaseTwentyTwo"
               )

      assert modules_result.helper == :modules
      assert modules_result.row_count >= 1

      assert {:ok, functions_result} =
               AgentWorkspace.find_source_code_graph_functions(
                 managed_repo_id,
                 workspace_path,
                 module_name: "PhaseTwentyTwo.Alpha",
                 function_name: "greet"
               )

      assert functions_result.helper == :functions
      assert functions_result.row_count >= 1

      assert {:ok, runtime_result} =
               AgentWorkspace.find_source_code_graph_runtime_patterns(
                 managed_repo_id,
                 workspace_path
               )

      assert runtime_result.helper == :runtime_patterns
      assert is_list(runtime_result.bindings)
    end

    test "22.4.1.3 query failures and not-ready states stay typed and bounded" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyTwo.Alpha")

      assert {:error, :source_code_graph_not_ready, _message} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o }"
               )

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:error, :source_code_graph_invalid_query, diagnostics} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { GRAPH <https://jido.run/graphs/source_code> { ?s ?p ?o } }"
               )

      assert diagnostics.stage == :validate_query
      assert diagnostics.library == :sparql
    end
  end

  describe "22.4.2 Pod and workflow adoption scenarios" do
    test "22.4.2.1 specialist pod behavior can analyze, refresh, and query one repository graph" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyTwo.Alpha")

      assert {:ok, analysis_result} =
               AgentWorkspace.analyze_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "rev-one"
               )

      assert analysis_result.latest_analysis_status.state == :analyzed

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "rev-one"
               )

      rewrite_workspace_module!(workspace_path, "PhaseTwentyTwo.Beta")

      assert {:ok, refresh_result} =
               AgentWorkspace.refresh_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "rev-two"
               )

      assert refresh_result.latest_import_status.imported_revision == "rev-two"

      assert {:ok, modules_result} =
               AgentWorkspace.find_source_code_graph_modules(
                 managed_repo_id,
                 workspace_path,
                 module_name_contains: "PhaseTwentyTwo"
               )

      refute Enum.any?(modules_result.bindings, fn row ->
               get_in(row, ["module_name", :value]) == "PhaseTwentyTwo.Alpha"
             end)

      assert Enum.any?(modules_result.bindings, fn row ->
               get_in(row, ["module_name", :value]) == "PhaseTwentyTwo.Beta"
             end)
    end

    test "22.4.2.2 workspace entrypoints hide pod topology details" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyTwo.Alpha")

      assert {:ok, pod_summary} =
               AgentWorkspace.ensure_source_code_graph_pod(managed_repo_id, workspace_path)

      assert pod_summary.pod_id == "source_code_graph"
      refute Map.has_key?(pod_summary, :module)
      refute Map.has_key?(pod_summary, :metadata)

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, impact_result} =
               AgentWorkspace.trace_source_code_graph_impact(
                 managed_repo_id,
                 workspace_path,
                 module_name: "PhaseTwentyTwo.Alpha"
               )

      assert impact_result.helper == :impact
      refute Map.has_key?(impact_result, :db)
      refute Map.has_key?(impact_result, :dict_manager)
    end

    test "22.4.2.3 higher-level workflows consult the graph only through explicit bounded entrypoints" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyTwo.Alpha")

      assert {:ok, plain_plan} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Plan with no semantic context",
                 workspace_path: workspace_path
               )

      assert plain_plan.semantic_context == %{}

      assert {:ok, semantic_plan} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Plan with semantic context",
                 workspace_path: workspace_path,
                 source_code_graph: [
                   workspace_path: workspace_path,
                   prepare: :load_if_missing,
                   modules: [module_name_contains: "PhaseTwentyTwo"],
                   impact: [module_name: "PhaseTwentyTwo.Alpha"]
                 ]
               )

      assert semantic_plan.semantic_context.workflow == :plan
      assert semantic_plan.semantic_context.graph_status.ready? == true
      assert semantic_plan.semantic_context.results.modules.helper == :modules
      assert semantic_plan.semantic_context.results.impact.helper == :impact
    end
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_twenty_two_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseTwentyTwo.MixProject do
        use Mix.Project

        def project do
          [app: :phase_twenty_two_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    rewrite_workspace_module!(workspace_path, module_name)

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    module_basename =
      module_name
      |> String.split(".")
      |> List.last()
      |> Macro.underscore()

    File.write!(
      Path.join(workspace_path, "lib/#{module_basename}.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
    |> Path.join("lib/*.ex")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, "#{module_basename}.ex"))
    |> Enum.each(&File.rm!/1)
  end
end
