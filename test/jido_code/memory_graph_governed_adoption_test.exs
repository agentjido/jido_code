defmodule JidoCode.MemoryGraphGovernedAdoptionTest do
  # covers: architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records
  # covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.Evidence
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope, GovernedAdoption, ProductService}
  alias JidoCode.Orchestration.RunBridge
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Projects.Project

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

  test "adopt_work_item routes memory findings through governed assessment and work synthesis", %{
    workspace_path: workspace_path
  } do
    managed_repo = create_managed_repo!()
    revision = "rev-32-memory-work"

    %{memory_resource_iri: memory_resource_iri} =
      seed_memory_graph!(managed_repo.id, workspace_path, revision)

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
               query: %{resource_iri: memory_resource_iri},
               workspace_path: workspace_path
             )

    assert adoption.action == :created
    assert adoption.work_item.managed_repo_id == managed_repo.id
    assert adoption.work_item.assessment_id == adoption.assessment.id
    assert adoption.work_item.work_metadata["memory_finding"]["digest"] == adoption.finding.digest
    assert adoption.work_item.work_metadata["memory_finding"]["graph"]["validated_revision"] == revision
    assert adoption.work_item.work_metadata["memory_finding"]["freshness"]["state"] == "ready"
    assert adoption.work_item.work_metadata["memory_finding"]["provenance"]["projection_kind"] == "memories"

    assert {:ok, [persisted_work_item]} =
             WorkItem.read(
               query: [filter: [id: adoption.work_item.id]],
               actor: JidoCode.Control.Actor.operator_actor()
             )

    assert persisted_work_item.work_metadata["memory_finding"]["summary"] == adoption.finding.summary

    assert {:ok, provenance_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo.id,
               workspace_path,
               """
               SELECT ?session ?plan
               WHERE {
                 ?session a jido:WorkSession ;
                   jido:sessionId "#{governed_session_id(:plan, adoption.finding.digest, adoption.work_item.id)}" ;
                   jido:hasPlan ?plan .
               }
               """,
               graph_name: "workflow_provenance",
               allow_stale?: true
             )

    assert provenance_query.row_count == 1
  end

  test "review support and evidence adoption retain memory freshness and decision input", %{
    workspace_path: workspace_path
  } do
    managed_repo = create_managed_repo!()
    revision = "rev-32-memory-evidence"

    %{provenance_resource_iri: provenance_resource_iri} =
      seed_memory_graph!(managed_repo.id, workspace_path, revision)

    assert {:ok, projection} =
             ProductService.provenance(
               managed_repo.id,
               workspace_path,
               label_contains: "review artifact",
               revision: revision
             )

    assert {:ok, adoption} =
             GovernedAdoption.adopt_work_item(
               projection,
               query: %{resource_iri: provenance_resource_iri},
               workspace_path: workspace_path
             )

    assert {:ok, review_support} =
             GovernedAdoption.review_support(
               projection,
               query: %{resource_iri: provenance_resource_iri},
               work_item_id: adoption.work_item.id,
               workspace_path: workspace_path
             )

    assert review_support.evidence_input.evidence_details["graph"]["validated_revision"] == revision
    assert review_support.evidence_input.evidence_details["freshness"]["state"] == "ready"
    assert review_support.review_metadata["provenance"]["projection_kind"] == "provenance"
    assert review_support.decision_input.decision == :defer
    assert review_support.decision_input.decision_metadata["freshness"]["state"] == "ready"

    assert {:ok, %{run: run}} =
             RunBridge.launch_work_item(adoption.work_item, %{
               workflow_name: "implement_task"
             })

    assert {:ok, evidence} =
             GovernedAdoption.adopt_evidence(
               projection,
               query: %{resource_iri: provenance_resource_iri},
               run_id: run.id,
               work_item_id: adoption.work_item.id,
               workspace_path: workspace_path
             )

    assert evidence.run_id == run.id
    assert evidence.work_item_id == adoption.work_item.id
    assert evidence.evidence_details["graph"]["validated_revision"] == revision
    assert evidence.evidence_details["freshness"]["state"] == "ready"
    assert evidence.evidence_details["provenance"]["projection_kind"] == "provenance"

    assert {:ok, [persisted_evidence]} =
             Evidence.read(
               query: [filter: [id: evidence.id]],
               actor: JidoCode.Control.Actor.operator_actor()
             )

    assert persisted_evidence.evidence_details["finding_digest"] ==
             review_support.evidence_input.evidence_details["finding_digest"]

    assert {:ok, provenance_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo.id,
               workspace_path,
               """
               SELECT ?session ?review
               WHERE {
                 ?session a jido:WorkSession ;
                   jido:sessionId "#{governed_session_id(:review, review_support.finding.digest, adoption.work_item.id)}" ;
                   jido:hasReview ?review .
               }
               """,
               graph_name: "workflow_provenance",
               allow_stale?: true
             )

    assert provenance_query.row_count >= 1
  end

  defp governed_session_id(:plan, digest, work_item_id), do: "memory-governed-plan-#{digest}-#{work_item_id}"
  defp governed_session_id(:review, digest, work_item_id), do: "memory-governed-review-#{digest}-#{work_item_id}"

  defp create_managed_repo! do
    name = "phase-32-memory-#{System.unique_integer([:positive])}"

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

    session_id = "memory-governed-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:memory-graph-governed-adoption",
                 workflow: :review,
                 work_item_id: "work-32",
                 goal: "Seed memory graph governed adoption"
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, provenance_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.review(
                 session_id: session_id,
                 actor_id: "system:memory-graph-governed-adoption",
                 workflow: :review,
                 work_item_id: "work-32",
                 content: "Generated a review artifact for governed adoption tests.",
                 anchors: %{module_name: "ExampleMemoryGoverned"}
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
                 actor_id: "system:memory-graph-governed-adoption",
                 workflow: :review,
                 work_item_id: "work-32",
                 content: "Greeting contract changes require governed review.",
                 revision: revision,
                 anchors: %{module_name: "ExampleMemoryGoverned"},
                 classification: %{
                   source: "memory_governed_adoption_test",
                   reason: "Section 32.3 needs durable memory for governed follow-up tests."
                 }
               ),
               revision: revision
             )

    %{
      memory_resource_iri: memory_result.capture.resource_iri,
      provenance_resource_iri: provenance_result.capture.resource_iri,
      session_id: session_id
    }
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_memory_graph_governed_adoption_#{System.unique_integer([:positive])}")

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
      Path.join(workspace_path, "lib/example_memory_governed.ex"),
      """
      defmodule ExampleMemoryGoverned do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
  end
end
