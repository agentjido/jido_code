defmodule JidoCode.PhaseThirtySevenIntegrationTest do
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  # covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  # covers: architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records
  # covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
  # covers: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
  # covers: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
  # covers: architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up
  # covers: architecture.run_governance.run_detail_can_host_bounded_memory_context
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo, RepoBridge}
  alias JidoCode.Governance.{Decision, Evidence}
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{
    CaptureEnvelope,
    DurableMemoryEnvelope,
    GovernedAdoption,
    GovernedSurfaceContext,
    OperatorService,
    ProductService,
    WorkflowService
  }

  alias JidoCode.Orchestration.{Run, WorkflowRun}
  alias JidoCode.Projects.Project

  @moduletag :integration

  setup do
    previous_memory = Application.get_env(:jido_code, :memory_graph_enabled, false)
    previous_source = Application.get_env(:jido_code, :source_code_graph_enabled, false)

    Application.put_env(:jido_code, :memory_graph_enabled, true)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    workspace_path = create_workspace_path!()

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous_memory)
      Application.put_env(:jido_code, :source_code_graph_enabled, previous_source)
      File.rm_rf!(workspace_path)
    end)

    {:ok, workspace_path: workspace_path}
  end

  test "37.3.1 typed governed queries and navigation stay explainable across run context and stale recall", %{
    workspace_path: workspace_path
  } do
    {project, managed_repo} = create_project_and_repo!("phase-37-query", workspace_path)
    {run, evidence, decision, revision, memory_resource_iri, plan_resource_iri} =
      seed_governed_memory_context!(project, managed_repo, workspace_path)

    assert {:ok, memories_projection} =
             ProductService.memories_for_governed_references(
               managed_repo.id,
               workspace_path,
               [
                 %{kind: :run, id: run.run_id},
                 %{kind: :evidence, id: evidence.id},
                 %{kind: :decision, id: decision.id}
               ],
               revision: revision
             )

    memory_item = Enum.find(memories_projection.items, &(&1.memory_iri == memory_resource_iri))
    assert memory_item

    assert Enum.any?(memory_item.governed_context, fn reference ->
             reference.kind == :run and reference.id == run.run_id and
               reference.route == "/repos/#{managed_repo.id}/runs/#{run.run_id}"
           end)

    assert Enum.any?(memory_item.governed_context, fn reference ->
             reference.kind == :evidence and reference.id == evidence.id and
               reference.label == "Evidence #{evidence.id}"
           end)

    assert {:ok, plan_navigation} =
             ProductService.cross_links(
               managed_repo.id,
               workspace_path,
               plan_resource_iri,
               revision: revision
             )

    assert Enum.any?(plan_navigation.navigation.governed_records, fn reference ->
             reference.kind == :run and reference.id == run.run_id and
               reference.route == "/repos/#{managed_repo.id}/runs/#{run.run_id}"
           end)

    assert Enum.any?(plan_navigation.navigation.governed_records, fn reference ->
             reference.kind == :evidence and reference.id == evidence.id and
               reference.label == "Evidence #{evidence.id}" and is_nil(reference.route)
           end)

    refute Enum.any?(plan_navigation.navigation.governed_records, &(&1.kind == :artifact))

    assert {:ok, repo_scope} = RepoBridge.repo_scope(project.id)

    governed_context =
      GovernedSurfaceContext.load_run_detail(
        repo_scope,
        run,
        [evidence],
        [decision],
        revision: revision,
        managed_repo_id: managed_repo.id,
        workspace_path: workspace_path
      )

    assert governed_context.available? == true

    run_memory_item =
      Enum.find(governed_context.memories.items, fn item ->
        item.memory_iri == memory_resource_iri
      end)

    assert run_memory_item

    assert Enum.any?(run_memory_item.navigation.governed_records, fn reference ->
             reference.kind == :decision and reference.id == decision.id and
               reference.route == "/repos/#{managed_repo.id}/decisions/#{decision.id}"
           end)

    rewrite_workspace_module!(workspace_path, "ExamplePhaseThirtySevenQueryUpdated")

    assert {:ok, stale_navigation} =
             ProductService.cross_links(
               managed_repo.id,
               workspace_path,
               memory_resource_iri,
               allow_stale?: true
             )

    assert stale_navigation.graph.stale? == true
    assert stale_navigation.graph.degraded? == true
    assert Enum.any?(stale_navigation.navigation.governed_records, &(&1.kind == :run))
  end

  test "37.3.2 product, operator, and workflow services preserve typed governed references end to end", %{
    workspace_path: workspace_path
  } do
    {project, managed_repo} = create_project_and_repo!("phase-37-services", workspace_path)
    {run, evidence, decision, revision, memory_resource_iri, _plan_resource_iri} =
      seed_governed_memory_context!(project, managed_repo, workspace_path)

    assert {:ok, projection} =
             ProductService.memories(
               managed_repo.id,
               workspace_path,
               content_contains: "Phase 37 governed memory should stay queryable.",
               revision: revision
             )

    assert {:ok, validation} =
             OperatorService.validate(
               projection,
               memory_resource_iri,
               workspace_path: workspace_path,
               revision: revision
             )

    assert {:ok, validation_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo.id,
               workspace_path,
               """
               SELECT ?run ?decision
               WHERE {
                 <#{validation.record.capture.update_iri}> jido:aboutRun ?run ;
                   jido:aboutDecision ?decision .
               }
               """,
               revision: revision,
               allow_stale?: true
             )

    assert validation_query.row_count == 1

    assert {:ok, workflow_result} =
             WorkflowService.review(
               managed_repo.id,
               "work-37",
               "Review phase 37 governed memory context",
               workspace_path: workspace_path,
               memory: [
                 workspace_path: workspace_path,
                 prepare: :recover_if_needed,
                 revision: revision,
                 memories: [content_contains: "Phase 37 governed memory should stay queryable."],
                 provenance: [label_contains: "Phase 37 review provenance"],
                 policy: [
                   intent: :review_risks,
                   memory_kinds: [:known_issue],
                   provenance_kinds: [:review],
                   freshness: :ready_only,
                   follow_up_intent: :work_item
                 ]
               ]
             )

    assert Enum.any?(workflow_result.follow_up_context["governed_references"], fn reference ->
             reference["kind"] == "run" and reference["id"] == run.run_id
           end)

    assert Enum.any?(workflow_result.follow_up_context["governed_references"], fn reference ->
             reference["kind"] == "decision" and reference["id"] == decision.id
           end)

    assert {:ok, adoption} =
             GovernedAdoption.adopt_work_item(
               projection,
               query: %{resource_iri: memory_resource_iri},
               workspace_path: workspace_path,
               workflow_context: WorkflowService.follow_up_context(workflow_result)
             )

    assert Enum.any?(adoption.work_item.work_metadata["workflow_memory"]["governed_references"], fn reference ->
             reference["kind"] == "run" and reference["id"] == run.run_id
           end)

    assert Enum.any?(adoption.work_item.work_metadata["workflow_memory"]["governed_references"], fn reference ->
             reference["kind"] == "decision" and reference["id"] == decision.id
           end)

    assert adoption.work_item.work_metadata["memory_finding"]["provenance"]["governed_references"] != []
    assert evidence.id != nil
  end

  defp create_project_and_repo!(name_suffix, workspace_path) do
    name = "#{name_suffix}-#{System.unique_integer([:positive])}"

    {:ok, project} =
      Project.create(%{
        name: name,
        github_full_name: "owner/#{name}",
        default_branch: "main",
        settings: %{workspace: %{workspace_path: workspace_path}}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {project, managed_repo}
  end

  defp seed_governed_memory_context!(project, managed_repo, workspace_path) do
    run_id = "phase-37-run-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Seed phase 37 governed memory context"},
        input_metadata: %{"task_summary" => %{required: true, source: "phase_thirty_seven_integration"}},
        initiating_actor: %{id: "owner-37", email: "phase-thirty-seven@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-11 15:00:00Z]
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "review_context",
        transitioned_at: ~U[2026-04-11 15:00:30Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-04-11 15:01:00Z]
      })

    {:ok, run} =
      Run.get_by_managed_repo_and_run_id(
        managed_repo.id,
        run_id,
        actor: Actor.operator_actor()
      )

    {:ok, evidence} =
      Evidence.create(
        %{
          run_id: run.id,
          managed_repo_id: managed_repo.id,
          key: "phase_thirty_seven_memory_history",
          evidence_type: "memory_graph_finding",
          summary: "Phase 37 integration needs typed governed navigation.",
          evidence_details: %{"source" => "phase_thirty_seven_integration"},
          source: "memory_graph",
          recorded_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, decision} =
      Decision.create(
        %{
          decision_key: "phase-thirty-seven-run-#{run.id}",
          run_id: run.id,
          managed_repo_id: managed_repo.id,
          decision: :approve,
          actor: %{"id" => "owner-37", "email" => "phase-thirty-seven@example.com"},
          rationale: "Phase 37 integration keeps typed governed references explainable.",
          decision_metadata: %{"source" => "phase_thirty_seven_integration"},
          decided_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, revision_metadata} = MemoryGraph.current_revision_metadata(workspace_path)
    revision = revision_metadata.current_revision

    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo.id,
               workspace_path,
               revision: revision
             )

    session_id = "phase-37-memory-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo.id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-seven",
                 workflow: :review,
                 work_item_id: "work-37",
                 goal: "Seed phase 37 governed memory context",
                 governed_context: %{run_id: run.run_id, decision_id: decision.id}
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, review_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo.id,
               workspace_path,
               CaptureEnvelope.review(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-seven",
                 workflow: :review,
                 work_item_id: "work-37",
                 content: "Phase 37 review provenance should preserve typed governed references.",
                 anchors: %{module_name: "ExamplePhaseThirtySeven"},
                 governed_context: %{run_id: run.run_id, evidence_id: evidence.id, decision_id: decision.id}
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo.id,
               workspace_path,
               DurableMemoryEnvelope.known_issue(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-seven",
                 workflow: :review,
                 work_item_id: "work-37",
                 content: "Phase 37 governed memory should stay queryable.",
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseThirtySeven"},
                 governed_context: %{run_id: run.run_id, evidence_id: evidence.id, decision_id: decision.id},
                 classification: %{
                   source: "phase_thirty_seven_integration",
                   reason: "Phase 37 needs typed governed query and workflow coverage."
                 }
               ),
               revision: revision
             )

    {run, evidence, decision, revision, memory_result.capture.resource_iri, review_result.capture.resource_iri}
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_thirty_seven_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtySeven.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_seven_example, version: "0.1.0"]
        end
      end
      """
    )

    rewrite_workspace_module!(workspace_path, "ExamplePhaseThirtySeven")
    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    File.write!(
      Path.join(workspace_path, "lib/example_phase_thirty_seven.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )
  end
end
