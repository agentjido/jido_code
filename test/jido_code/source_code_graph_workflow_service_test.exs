defmodule JidoCode.SourceCodeGraphWorkflowServiceTest do
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
  # covers: architecture.policy_layers.runtime_entrypoints_seed_explicit_collaboration_context
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.SourceCodeGraph.ProductService
  alias JidoCode.SourceCodeGraph.WorkflowService

  setup do
    previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    previous_memory = Application.get_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    workspace_path = create_workspace_path!()

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous)
      Application.put_env(:jido_code, :memory_graph_enabled, previous_memory)
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
    assert result.semantic_input.freshness.state == :ready
    assert result.semantic_input.freshness.label == "Semantic graph ready"
    assert result.semantic_input.results.modules.kind == :modules
    assert result.semantic_input.results.impact.kind == :impact
    assert result.workflow_provenance.workflow == :plan
    assert is_binary(result.workflow_provenance.session_id)
    refute Map.has_key?(result.semantic_input.results.modules, :bindings)
    refute Map.has_key?(result.semantic_input.results.impact, :compiled_sparql)

    assert {:ok, provenance_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo_id,
               workspace_path,
               """
               SELECT ?session ?prompt ?run ?plan
               WHERE {
                 ?session a jido:WorkSession ;
                   jido:sessionId "#{result.workflow_provenance.session_id}" ;
                   jido:hasPromptTurn ?prompt ;
                   jido:hasAgentRun ?run ;
                   jido:hasPlan ?plan .
               }
               """,
               graph_name: "workflow_provenance",
               allow_stale?: true
             )

    assert provenance_query.row_count == 1
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

    assert {:error, :unsupported_raw_semantic_query, raw_query_error} =
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

    assert raw_query_error.workflow == :explain
    assert raw_query_error.error.type == :unsupported_raw_semantic_query
    assert raw_query_error.feedback.state == :unavailable
    assert raw_query_error.feedback.label == "Semantic graph unavailable"
  end

  test "workflow semantic requests fail safely with explicit freshness and recovery feedback", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"
    work_item_id = "work-#{System.unique_integer([:positive])}"

    assert {:error, :source_code_graph_not_ready, error} =
             WorkflowService.explain(
               managed_repo_id,
               work_item_id,
               "Explain without prepared semantic context",
               workspace_path: workspace_path,
               semantic: [
                 workspace_path: workspace_path,
                 prepare: :none,
                 impact: [module_name: "ExampleWorkspace"]
               ]
             )

    assert error.workflow == :explain
    assert error.work_item_id == work_item_id
    assert error.graph.state == :not_ready
    assert error.feedback.state == :not_ready
    assert error.feedback.recovery.action == :load
    assert error.error.remediation == "Open repo detail to load semantic graph data."
  end

  test "record_memory inserts durable memory only through explicit workflow adoption", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"

    assert {:ok, _load_result} =
             AgentWorkspace.load_source_code_graph(
               managed_repo_id,
               workspace_path,
               revision: "rev-30-workflow-memory"
             )

    assert {:ok, projection} =
             ProductService.modules(
               managed_repo_id,
               workspace_path,
               module_name_contains: "ExampleWorkspace",
               revision: "rev-30-workflow-memory"
             )

    assert {:ok, memory_result} =
             WorkflowService.record_memory(
               projection,
               workspace_path: workspace_path,
               memory_kind: :convention,
               classification_reason: "The semantic workflow intentionally adopted this reusable module convention.",
               actor_id: "system:workflow-memory",
               query: %{module_name: "ExampleWorkspace"},
               run_id: "run-36",
               evidence_id: "evidence-36"
             )

    assert memory_result.memory_kind == :convention
    assert memory_result.record.status == :durable_memory_recorded

    assert memory_result.capture.governed_references
           |> Enum.map(& &1.kind)
           |> Enum.sort() == [:evidence, :run]

    assert {:ok, memory_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo_id,
               workspace_path,
               """
               SELECT ?memory ?session ?module
               WHERE {
                 ?memory a jido:Convention ;
                   jido:sourceSession ?session ;
                   jido:aboutModule ?module .
               }
               """,
               allow_stale?: true
             )

    assert memory_query.row_count == 1
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
