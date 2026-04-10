defmodule JidoCode.MemoryGraphWorkflowServiceTest do
  # covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
  # covers: architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
  # covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope, WorkflowService}

  setup do
    previous = Application.get_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    workspace_path = create_workspace_path!()

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous)
      File.rm_rf!(workspace_path)
    end)

    {:ok, workspace_path: workspace_path}
  end

  test "plan keeps workflow calls valid when memory context is not requested", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"
    work_item_id = "work-#{System.unique_integer([:positive])}"

    assert {:ok, result} =
             WorkflowService.plan(
               managed_repo_id,
               work_item_id,
               "Plan without memory context",
               workspace_path: workspace_path
             )

    assert result.workflow == :plan
    assert result.plan =~ "deterministic planner response"
    assert result.memory_input == nil
  end

  test "plan returns bounded memory workflow inputs for explicit memory requests", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"
    work_item_id = "work-#{System.unique_integer([:positive])}"
    revision = "rev-32-memory-plan"

    %{memory_resource_iri: memory_resource_iri} =
      seed_memory_graph!(managed_repo_id, workspace_path, revision)

    assert {:ok, result} =
             WorkflowService.plan(
               managed_repo_id,
               work_item_id,
               "Plan with memory context",
               workspace_path: workspace_path,
               memory: [
                 workspace_path: workspace_path,
                 prepare: :recover_if_needed,
                 revision: revision,
                 memories: [content_contains: "Repository decisions"],
                 provenance: [label_contains: "plan artifact"],
                 cross_links: [resource_iri: memory_resource_iri]
               ]
             )

    assert result.workflow == :plan
    assert result.plan =~ "deterministic planner response"
    assert result.memory_input.workflow == :plan
    assert result.memory_input.graph.state == :ready
    assert result.memory_input.freshness.state == :ready
    assert result.memory_input.results.memories.kind == :memories
    assert result.memory_input.results.provenance.kind == :provenance
    assert result.memory_input.results.cross_links.kind == :cross_links
    assert result.workflow_provenance.workflow == :plan
    assert is_binary(result.workflow_provenance.session_id)
    refute Map.has_key?(result.memory_input.results.memories, :bindings)
    refute Map.has_key?(result.memory_input.results.provenance, :compiled_sparql)

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

    assert provenance_query.row_count >= 1
  end

  test "workflow memory requests fail safely with explicit freshness and recovery feedback", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"
    work_item_id = "work-#{System.unique_integer([:positive])}"

    Application.put_env(:jido_code, :memory_graph_enabled, false)

    assert {:error, :memory_graph_disabled, error} =
             WorkflowService.explain(
               managed_repo_id,
               work_item_id,
               "Explain with disabled memory context",
               workspace_path: workspace_path,
               memory: [
                  workspace_path: workspace_path,
                  prepare: :none,
                 memories: [content_contains: "Repository decisions"]
               ]
             )

    assert error.workflow == :explain
    assert error.work_item_id == work_item_id
    assert error.graph.state == :disabled
    assert error.feedback.state == :disabled
    assert error.feedback.recovery.action == :none

    Application.put_env(:jido_code, :memory_graph_enabled, true)

    assert {:error, :unsupported_raw_memory_query, raw_query_error} =
             WorkflowService.review(
               managed_repo_id,
               "work-#{System.unique_integer([:positive])}",
               "Review with raw query",
               workspace_path: workspace_path,
               memory: [
                 workspace_path: workspace_path,
                 sparql: "SELECT * WHERE { ?s ?p ?o }"
               ]
             )

    assert raw_query_error.workflow == :review
    assert raw_query_error.error.type == :unsupported_raw_memory_query
    assert raw_query_error.feedback.state == :unavailable
    assert raw_query_error.feedback.label == "Memory graph unavailable"
  end

  defp seed_memory_graph!(managed_repo_id, workspace_path, revision) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "memory-workflow-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:memory-graph-workflow-service",
                 workflow: :plan,
                 work_item_id: "work-32",
                 goal: "Seed memory graph workflow service"
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, plan_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.plan(
                 session_id: session_id,
                 actor_id: "system:memory-graph-workflow-service",
                 workflow: :plan,
                 work_item_id: "work-32",
                 content: "Generated a plan artifact for memory-aware workflow tests.",
                 anchors: %{module_name: "ExampleMemoryWorkflow"}
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.decision(
                 session_id: session_id,
                 actor_id: "system:memory-graph-workflow-service",
                 workflow: :review,
                 work_item_id: "work-32",
                 content: "Repository decisions should keep ExampleMemoryWorkflow.greet/1 stable.",
                 rationale: "Greeting behavior is a durable convention in this repository.",
                 decision_status: :accepted,
                 revision: revision,
                 anchors: %{module_name: "ExampleMemoryWorkflow"},
                 classification: %{
                   source: "memory_workflow_service_test",
                   reason: "Section 32.3 needs durable memory for workflow tests."
                 }
               ),
               revision: revision
             )

    %{
      memory_resource_iri: memory_result.capture.resource_iri,
      plan_resource_iri: plan_result.capture.resource_iri,
      session_id: session_id
    }
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_memory_graph_workflow_service_#{System.unique_integer([:positive])}")

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

    rewrite_workspace_module!(workspace_path, "ExampleMemoryWorkflow")
    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    File.write!(
      Path.join(workspace_path, "lib/example_memory_workflow.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )
  end
end
