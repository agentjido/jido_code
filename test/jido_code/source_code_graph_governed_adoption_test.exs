defmodule JidoCode.SourceCodeGraphGovernedAdoptionTest do
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.Evidence
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Orchestration.RunBridge
  alias JidoCode.Projects.Project
  alias JidoCode.SourceCodeGraph.{GovernedAdoption, ProductService}

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

  test "adopt_work_item routes semantic findings through governed assessment and work synthesis", %{
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
             ProductService.impact(
               managed_repo.id,
               workspace_path,
               module_name: "ExampleWorkspace",
               revision: "rev-26-work"
             )

    assert {:ok, adoption} =
             GovernedAdoption.adopt_work_item(
               projection,
               query: %{module_name: "ExampleWorkspace"}
             )

    assert adoption.action == :created
    assert adoption.work_item.managed_repo_id == managed_repo.id
    assert adoption.work_item.assessment_id == adoption.assessment.id
    assert adoption.work_item.work_metadata["semantic_finding"]["digest"] == adoption.finding.digest
    assert adoption.work_item.work_metadata["semantic_finding"]["graph"]["imported_revision"] == "rev-26-work"
    assert adoption.work_item.work_metadata["semantic_finding"]["provenance"]["projection_kind"] == "impact"

    assert {:ok, [persisted_work_item]} =
             WorkItem.read(
               query: [filter: [id: adoption.work_item.id]],
               actor: JidoCode.Control.Actor.operator_actor()
             )

    assert persisted_work_item.work_metadata["semantic_finding"]["summary"] == adoption.finding.summary
  end

  test "review support and evidence adoption retain semantic provenance and freshness", %{
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

    assert {:ok, review_support} =
             GovernedAdoption.review_support(
               projection,
               query: %{module_name: "ExampleWorkspace", function_name: "greet"},
               work_item_id: adoption.work_item.id
             )

    assert review_support.evidence_input.evidence_details["graph"]["imported_revision"] == "rev-26-evidence"
    assert review_support.review_metadata["provenance"]["projection_kind"] == "functions"

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

    assert evidence.run_id == run.id
    assert evidence.work_item_id == adoption.work_item.id
    assert evidence.evidence_details["graph"]["imported_revision"] == "rev-26-evidence"
    assert evidence.evidence_details["provenance"]["projection_kind"] == "functions"

    assert {:ok, [persisted_evidence]} =
             Evidence.read(
               query: [filter: [id: evidence.id]],
               actor: JidoCode.Control.Actor.operator_actor()
             )

    assert persisted_evidence.evidence_details["finding_digest"] ==
             review_support.evidence_input.evidence_details["finding_digest"]
  end

  defp create_managed_repo! do
    name = "phase-26-#{System.unique_integer([:positive])}"

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
      |> Path.join("jido_code_source_graph_governed_adoption_#{System.unique_integer([:positive])}")

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
