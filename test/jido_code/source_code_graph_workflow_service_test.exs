defmodule JidoCode.SourceCodeGraphWorkflowServiceTest do
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.SourceCodeGraph.WorkflowService

  setup do
    previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    workspace_path = create_workspace_path!()

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous)
      File.rm_rf!(workspace_path)
    end)

    {:ok, workspace_path: workspace_path}
  end

  test "plan keeps workflow calls valid when semantic context is not requested", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"
    work_item_id = "work-#{System.unique_integer([:positive])}"

    assert {:ok, result} =
             WorkflowService.plan(
               managed_repo_id,
               work_item_id,
               "Plan without semantic context",
               workspace_path: workspace_path
             )

    assert result.workflow == :plan
    assert result.plan =~ "deterministic planner response"
    assert result.semantic_input == nil
  end

  test "plan returns bounded semantic workflow inputs for explicit semantic requests", %{workspace_path: workspace_path} do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"
    work_item_id = "work-#{System.unique_integer([:positive])}"

    assert {:ok, result} =
             WorkflowService.plan(
               managed_repo_id,
               work_item_id,
               "Plan with semantic context",
               workspace_path: workspace_path,
               semantic: [
                 workspace_path: workspace_path,
                 prepare: :load_if_missing,
                 revision: "rev-26-plan",
                 modules: [module_name_contains: "ExampleWorkspace"],
                 impact: [module_name: "ExampleWorkspace"]
               ]
             )

    assert result.workflow == :plan
    assert result.plan =~ "deterministic planner response"
    assert result.semantic_input.workflow == :plan
    assert result.semantic_input.graph.state == :ready
    assert result.semantic_input.graph.imported_revision == "rev-26-plan"
    assert result.semantic_input.results.modules.kind == :modules
    assert result.semantic_input.results.impact.kind == :impact
    refute Map.has_key?(result.semantic_input.results.modules, :bindings)
    refute Map.has_key?(result.semantic_input.results.impact, :compiled_sparql)
  end

  test "review and explanation use bounded semantic inputs without raw SPARQL coupling", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"
    review_work_item_id = "review-#{System.unique_integer([:positive])}"
    explain_work_item_id = "explain-#{System.unique_integer([:positive])}"

    assert {:ok, review_result} =
             WorkflowService.review(
               managed_repo_id,
               review_work_item_id,
               "Review with semantic context",
               workspace_path: workspace_path,
               semantic: [
                 workspace_path: workspace_path,
                 prepare: :load_if_missing,
                 revision: "rev-26-review",
                 functions: [module_name: "ExampleWorkspace", function_name: "greet"],
                 runtime_patterns: []
               ]
             )

    assert review_result.workflow == :review
    assert review_result.feedback =~ "deterministic reviewer response"
    assert review_result.semantic_input.results.functions.kind == :functions
    assert review_result.semantic_input.results.runtime_patterns.kind == :runtime_patterns

    assert {:ok, explain_result} =
             WorkflowService.explain(
               managed_repo_id,
               explain_work_item_id,
               "Explain with semantic context",
               workspace_path: workspace_path,
               semantic: [
                 workspace_path: workspace_path,
                 prepare: :none,
                 revision: "rev-26-review",
                 impact: [module_name: "ExampleWorkspace"]
               ]
             )

    assert explain_result.workflow == :explain
    assert explain_result.explanation =~ "deterministic explainer response"
    assert explain_result.semantic_input.results.impact.kind == :impact

    assert {:error, :unsupported_raw_semantic_query} =
             WorkflowService.explain(
               managed_repo_id,
               "work-#{System.unique_integer([:positive])}",
               "Explain with raw query",
               workspace_path: workspace_path,
               semantic: [
                 workspace_path: workspace_path,
                 query: "SELECT * WHERE { ?s ?p ?o }"
               ]
             )
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_source_graph_workflow_service_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule Example.MixProject do
        use Mix.Project

        def project do
          [app: :example, version: "0.1.0"]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_workspace.ex"),
      """
      defmodule ExampleWorkspace do
        def greet(name), do: "hello \#{name}"
      end
      """
    )

    workspace_path
  end
end
