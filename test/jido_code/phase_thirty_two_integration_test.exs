defmodule JidoCode.PhaseThirtyTwoIntegrationTest do
  # covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
  # covers: architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
  # covers: architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
  # covers: architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records
  # covers: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{
    CaptureEnvelope,
    DurableMemoryEnvelope,
    GovernedAdoption,
    ProductService,
    WorkflowService
  }

  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.ProjectMemoryInspection

  @moduletag :integration

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

  describe "32.4.1 Product service and operator-surface scenarios" do
    test "32.4.1.1 bounded memory inspection stays repository-scoped and cross-linkable", %{
      workspace_path: workspace_path
    } do
      managed_repo = create_managed_repo!()
      revision = "rev-32-inspection"

      seed = seed_memory_graph!(managed_repo.id, workspace_path, revision)

      inspection =
        ProjectMemoryInspection.load_repo_detail(
          %{
            managed_repo_id: managed_repo.id,
            workspace_path: workspace_path
          },
          revision: revision
        )

      assert inspection.available? == true
      assert inspection.summary.groups.memories.count >= 1
      assert inspection.summary.groups.provenance.count >= 1
      assert inspection.graph.state == :ready

      memory_item =
        Enum.find(inspection.memories.items, fn item ->
          Enum.any?(item.navigation.source_code) and
            Enum.any?(item.navigation.governed_records)
        end)

      assert memory_item

      assert Enum.any?(memory_item.navigation.source_code, fn link ->
               link.kind == :module and
                 link.route == "/repos/#{managed_repo.id}#project-detail-semantic-inspection"
             end)

      assert Enum.any?(memory_item.navigation.governed_records, fn link ->
               link.kind == :run and link.route == "/repos/#{managed_repo.id}/runs/#{seed.run_id}"
             end)
    end
  end

  describe "32.4.2 Workflow and governed follow-up scenarios" do
    test "32.4.2.1 workflows request memory only when explicitly asked and adoption preserves freshness metadata",
         %{
           workspace_path: workspace_path
         } do
      managed_repo = create_managed_repo!()
      revision = "rev-32-workflow"
      work_item_id = "work-#{System.unique_integer([:positive])}"

      seed = seed_memory_graph!(managed_repo.id, workspace_path, revision)

      assert {:ok, without_memory} =
               WorkflowService.plan(
                 managed_repo.id,
                 work_item_id,
                 "Plan without memory context",
                 workspace_path: workspace_path
               )

      assert without_memory.memory_input == nil

      assert {:ok, with_memory} =
               WorkflowService.plan(
                 managed_repo.id,
                 work_item_id,
                 "Plan with memory context",
                 workspace_path: workspace_path,
                 memory: [
                   workspace_path: workspace_path,
                   prepare: :recover_if_needed,
                   revision: revision,
                   memories: [content_contains: "Greeting contract changes require governed review."],
                   provenance: [label_contains: "review artifact"]
                 ]
               )

      assert with_memory.memory_input.results.memories.kind == :memories
      assert with_memory.memory_input.results.provenance.kind == :provenance

      assert {:ok, projection} =
               ProductService.memories(
                 managed_repo.id,
                 workspace_path,
                 content_contains: "Greeting contract changes require governed review.",
                 revision: revision
               )

      assert {:ok, adoption} =
               GovernedAdoption.adopt_work_item(
                 projection,
                 query: %{resource_iri: seed.memory_resource_iri},
                 workspace_path: workspace_path
               )

      assert adoption.work_item.work_metadata["memory_finding"]["freshness"]["state"] == "ready"
      assert adoption.work_item.work_metadata["memory_finding"]["provenance"]["projection_kind"] == "memories"

      assert {:ok, review_support} =
               GovernedAdoption.review_support(
                 projection,
                 query: %{resource_iri: seed.memory_resource_iri},
                 work_item_id: adoption.work_item.id,
                 workspace_path: workspace_path
               )

      assert review_support.decision_input.decision == :defer
      assert review_support.review_metadata["freshness"]["state"] == "ready"
    end
  end

  defp create_managed_repo! do
    name = "phase-32-integration-#{System.unique_integer([:positive])}"

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

  defp seed_memory_graph!(managed_repo_id, workspace_path, revision) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "phase-32-memory-#{System.unique_integer([:positive])}"
    run_id = "run-32"

    assert {:ok, provenance_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.review(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-two",
                 workflow: :review,
                 work_item_id: "work-32",
                 content: "Generated a review artifact for phase thirty-two integration tests.",
                 anchors: %{module_name: "ExamplePhaseThirtyTwo"}
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.known_issue(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-two",
                 workflow: :review,
                 work_item_id: "work-32",
                 content: "Greeting contract changes require governed review.",
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseThirtyTwo"},
                 governed_context: %{run_id: run_id, work_item_id: "work-32"},
                 classification: %{
                   source: "phase_thirty_two_integration",
                   reason: "Phase 32 integration needs durable repository memory."
                 }
               ),
               revision: revision
             )

    assert provenance_result.capture.resource_iri
    assert memory_result.capture.resource_iri

    %{
      run_id: run_id,
      provenance_resource_iri: provenance_result.capture.resource_iri,
      memory_resource_iri: memory_result.capture.resource_iri
    }
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_thirty_two_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtyTwo.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_two_example, version: "0.1.0"]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_phase_thirty_two.ex"),
      """
      defmodule ExamplePhaseThirtyTwo do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
  end
end
