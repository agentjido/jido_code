defmodule JidoCode.AgentOSPhaseTwentyNineIntegrationTest do
  # covers: architecture.agent_os_integration.memory_graph_capture_stays_workspace_bound
  # covers: architecture.agent_os_integration.missing_kernel_runtime_recovers_from_snapshot
  # covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project
  alias JidoCode.SourceCodeGraph.{GovernedAdoption, ProductService, WorkflowService}

  @moduletag :integration

  setup do
    previous_source = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    previous_memory = Application.get_env(:jido_code, :memory_graph_enabled, false)

    Application.put_env(:jido_code, :source_code_graph_enabled, true)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous_source)
      Application.put_env(:jido_code, :memory_graph_enabled, previous_memory)
    end)

    :ok
  end

  describe "29.3.1 Workflow provenance seam scenarios" do
    test "29.3.1.1 semantic workflow preparation and specialist execution share the workflow_provenance graph" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      work_item_id = "work-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!("PhaseTwentyNine.Workflow")

      assert {:ok, result} =
               WorkflowService.plan(
                 managed_repo_id,
                 work_item_id,
                 "Plan with semantic provenance",
                 workspace_path: workspace_path,
                 semantic: [
                   workspace_path: workspace_path,
                   prepare: :load_if_missing,
                   revision: "rev-29-workflow",
                   modules: [module_name_contains: "PhaseTwentyNine"]
                 ]
               )

      assert result.workflow_provenance.workflow == :plan

      assert {:ok, workflow_query} =
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

      assert workflow_query.row_count == 1

      assert {:ok, _memory_refresh} =
               AgentWorkspace.refresh_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: result.workflow_provenance.revision
               )

      assert {:ok, memory_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session
                 WHERE {
                   ?session jido:sessionId "#{result.workflow_provenance.session_id}" .
                 }
                 """,
                 graph_name: "memory",
                 allow_stale?: true
               )

      assert memory_query.row_count == 0
    end
  end

  describe "29.3.2 Runtime recovery and governed adoption scenarios" do
    test "29.3.2.1 recovered kernels continue to emit bounded workflow provenance" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      work_item_id = "work-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!("PhaseTwentyNine.Recovery")

      assert {:ok, plan_result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Plan before recovery",
                 workspace_path: workspace_path
               )

      assert :ok = AgentWorkspace.shutdown_kernel(managed_repo_id)
      assert {:ok, _kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)

      assert {:ok, execute_result} =
               AgentWorkspace.execute_work(
                 managed_repo_id,
                 work_item_id,
                 "Execute after recovery",
                 workspace_path: workspace_path
               )

      assert {:ok, plan_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session ?plan
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{plan_result.workflow_provenance.session_id}" ;
                     jido:hasPlan ?plan .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert plan_query.row_count == 1

      assert {:ok, patch_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session ?patch
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{execute_result.workflow_provenance.session_id}" ;
                     jido:hasPatch ?patch .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert patch_query.row_count == 1
    end

    test "29.3.2.2 governed adoption emits workflow provenance without inserting workflow sessions into memory" do
      managed_repo = create_managed_repo!()
      workspace_path = create_workspace_path!("PhaseTwentyNine.Governed")

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo.id,
                 workspace_path,
                 revision: "rev-29-governed"
               )

      assert {:ok, projection} =
               ProductService.impact(
                 managed_repo.id,
                 workspace_path,
                 module_name: "PhaseTwentyNine.Governed",
                 revision: "rev-29-governed"
               )

      assert {:ok, adoption} =
               GovernedAdoption.adopt_work_item(
                 projection,
                 query: %{module_name: "PhaseTwentyNine.Governed"},
                 workspace_path: workspace_path
               )

      assert {:ok, review_support} =
               GovernedAdoption.review_support(
                 projection,
                 query: %{module_name: "PhaseTwentyNine.Governed"},
                 work_item_id: adoption.work_item.id,
                 workspace_path: workspace_path
               )

      plan_session_id = "governed-plan-#{adoption.finding.digest}-#{adoption.work_item.id}"
      review_session_id = "governed-review-#{review_support.finding.digest}-#{adoption.work_item.id}"

      assert {:ok, plan_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 """
                 SELECT ?session ?plan
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{plan_session_id}" ;
                     jido:hasPlan ?plan .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert plan_query.row_count == 1

      assert {:ok, review_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 """
                 SELECT ?session ?review
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{review_session_id}" ;
                     jido:hasReview ?review .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert review_query.row_count == 1

      assert {:ok, _memory_refresh} =
               AgentWorkspace.refresh_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 revision: "rev-29-governed"
               )

      assert {:ok, memory_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 """
                 SELECT ?session
                 WHERE {
                   ?session jido:sessionId ?session_id .
                   FILTER(?session_id IN ("#{plan_session_id}", "#{review_session_id}"))
                 }
                 """,
                 graph_name: "memory",
                 allow_stale?: true
               )

      assert memory_query.row_count == 0
    end
  end

  defp create_managed_repo! do
    name = "phase-29-#{System.unique_integer([:positive])}"

    {:ok, project} =
      Project.create(%{
        name: name,
        github_full_name: "owner/#{name}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_twenty_nine_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseTwentyNine.MixProject do
        use Mix.Project

        def project do
          [app: :phase_twenty_nine_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
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
