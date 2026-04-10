defmodule JidoCode.PhaseTwentySixIntegrationTest do
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.Evidence
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Orchestration.RunBridge
  alias JidoCode.Projects.Project
  alias JidoCode.SourceCodeGraph.{GovernedAdoption, ProductService, WorkflowService}

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

  describe "26.3.1 Explicit workflow semantic context scenarios" do
    test "26.3.1.1 planning flows opt into semantic repository context explicitly", %{
      workspace_path: workspace_path
    } do
      managed_repo = create_managed_repo!()

      assert {:ok, plain_result} =
               WorkflowService.plan(
                 managed_repo.id,
                 "work-#{System.unique_integer([:positive])}",
                 "Plan without semantic context",
                 workspace_path: workspace_path
               )

      assert plain_result.semantic_input == nil

      assert {:ok, semantic_result} =
               WorkflowService.plan(
                 managed_repo.id,
                 "work-#{System.unique_integer([:positive])}",
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

      assert semantic_result.semantic_input.workflow == :plan
      assert semantic_result.semantic_input.graph.state == :ready
      assert semantic_result.semantic_input.results.modules.kind == :modules
      assert semantic_result.semantic_input.results.impact.kind == :impact
      refute Map.has_key?(semantic_result.semantic_input.results.modules, :bindings)
    end

    test "26.3.1.2 review and explanation flows use bounded semantic inputs without direct graph coupling", %{
      workspace_path: workspace_path
    } do
      managed_repo = create_managed_repo!()

      assert {:ok, review_result} =
               WorkflowService.review(
                 managed_repo.id,
                 "review-#{System.unique_integer([:positive])}",
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

      assert review_result.semantic_input.workflow == :review
      assert review_result.semantic_input.results.functions.kind == :functions
      assert review_result.semantic_input.results.runtime_patterns.kind == :runtime_patterns

      assert {:ok, explain_result} =
               WorkflowService.explain(
                 managed_repo.id,
                 "explain-#{System.unique_integer([:positive])}",
                 "Explain with semantic context",
                 workspace_path: workspace_path,
                 semantic: [
                   workspace_path: workspace_path,
                   prepare: :none,
                   revision: "rev-26-review",
                   impact: [module_name: "ExampleWorkspace"]
                 ]
               )

      assert explain_result.semantic_input.workflow == :explain
      assert explain_result.semantic_input.results.impact.kind == :impact
      refute Map.has_key?(explain_result.semantic_input.results.impact, :compiled_sparql)
    end
  end

  describe "26.3.2 Governed semantic finding scenarios" do
    test "26.3.2.1 semantic findings become governed work only after explicit adoption", %{
      workspace_path: workspace_path
    } do
      managed_repo = create_managed_repo!()

      assert {:ok, _load_result} =
               JidoCode.AgentWorkspace.load_source_code_graph(
                 managed_repo.id,
                 workspace_path,
                 revision: "rev-26-work"
               )

      assert {:ok, projection} =
               ProductService.runtime_patterns(
                 managed_repo.id,
                 workspace_path,
                 revision: "rev-26-work"
               )

      assert {:ok, []} =
               WorkItem.read(
                 query: [filter: [managed_repo_id: managed_repo.id]],
                 actor: Actor.operator_actor()
               )

      assert {:ok, adoption} = GovernedAdoption.adopt_work_item(projection)

      assert adoption.action == :created
      assert adoption.work_item.managed_repo_id == managed_repo.id
      assert adoption.work_item.work_metadata["semantic_finding"]["graph"]["imported_revision"] == "rev-26-work"

      assert adoption.work_item.work_metadata["semantic_finding"]["provenance"]["projection_kind"] ==
               "runtime_patterns"
    end

    test "26.3.2.2 semantic findings can become governed evidence with provenance and freshness retained", %{
      workspace_path: workspace_path
    } do
      managed_repo = create_managed_repo!()

      assert {:ok, _load_result} =
               JidoCode.AgentWorkspace.load_source_code_graph(
                 managed_repo.id,
                 workspace_path,
                 revision: "rev-26-evidence"
               )

      assert {:ok, projection} =
               ProductService.functions(
                 managed_repo.id,
                 workspace_path,
                 module_name: "ExampleWorkspace",
                 function_name: "greet",
                 revision: "rev-26-evidence"
               )

      assert {:ok, adoption} =
               GovernedAdoption.adopt_work_item(
                 projection,
                 query: %{module_name: "ExampleWorkspace", function_name: "greet"}
               )

      assert {:ok, %{run: run}} =
               RunBridge.launch_work_item(adoption.work_item, %{
                 workflow_name: "implement_task"
               })

      assert {:ok, evidence} =
               GovernedAdoption.adopt_evidence(
                 projection,
                 query: %{module_name: "ExampleWorkspace", function_name: "greet"},
                 run_id: run.id,
                 work_item_id: adoption.work_item.id
               )

      assert evidence.evidence_details["graph"]["imported_revision"] == "rev-26-evidence"
      assert evidence.evidence_details["provenance"]["projection_kind"] == "functions"

      assert {:ok, [persisted_evidence]} =
               Evidence.read(
                 query: [filter: [id: evidence.id]],
                 actor: Actor.operator_actor()
               )

      assert persisted_evidence.evidence_details["finding_digest"] ==
               adoption.finding.digest
    end
  end

  defp create_managed_repo! do
    name = "phase-26-integration-#{System.unique_integer([:positive])}"

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

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_twenty_six_#{System.unique_integer([:positive])}")

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
