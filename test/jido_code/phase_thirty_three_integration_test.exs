defmodule JidoCode.PhaseThirtyThreeIntegrationTest do
  # covers: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
  # covers: architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies
  # covers: architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
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
  alias JidoCode.Control.RepoBridge

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

  describe "33.4.1 Governed surfaces and operator actions" do
    test "33.4.1.1 run context stays bounded and operator actions preserve governed follow-up", %{
      workspace_path: workspace_path
    } do
      {project, managed_repo} = create_project_and_repo!("phase-33-run", workspace_path)
      {run, evidence, decision, revision} = seed_governed_run!(project, managed_repo, workspace_path)

      assert {:ok, repo_scope} = RepoBridge.repo_scope(project.id)

      context =
        GovernedSurfaceContext.load_run_detail(
          repo_scope,
          run,
          [evidence],
          [decision],
          revision: revision,
          managed_repo_id: managed_repo.id,
          workspace_path: workspace_path
        )

      assert context.available? == true
      assert context.graph.state == :ready
      assert context.memories.items != []

      memory_item =
        Enum.find(context.memories.items, fn item ->
          Enum.any?(item.navigation.governed_records) and Enum.any?(item.navigation.source_code)
        end)

      assert memory_item

      assert Enum.any?(memory_item.navigation.governed_records, fn link ->
               link.kind == :run and link.route == "/repos/#{managed_repo.id}/runs/#{run.run_id}"
             end)

      assert Enum.any?(memory_item.navigation.source_code, &(&1.kind == :module))

      assert {:ok, projection} =
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

      assert {:ok, validated} =
               OperatorService.validate(
                 projection,
                 memory_item.memory_iri,
                 workspace_path: workspace_path,
                 revision: revision
               )

      assert validated.status == :memory_validated

      assert {:ok, promoted} =
               OperatorService.promote_follow_up(
                 projection,
                 memory_item.memory_iri,
                 workspace_path: workspace_path,
                 revision: revision,
                 target: :work_item
               )

      assert promoted.result.work_item.work_metadata["memory_finding"]["freshness"]["state"] == "ready"
      assert promoted.result.work_item.work_metadata["memory_finding"]["provenance"]["projection_kind"] == "memories"
    end
  end

  describe "33.4.2 Workflow retrieval and governed follow-up" do
    test "33.4.2.1 explicit memory policies and governed follow-up remain explainable", %{
      workspace_path: workspace_path
    } do
      {_project, managed_repo} = create_project_and_repo!("phase-33-workflow", workspace_path)
      revision = "rev-33-workflow-integration"
      work_item_id = "work-#{System.unique_integer([:positive])}"

      %{memory_resource_iri: memory_resource_iri} =
        seed_memory_graph!(managed_repo.id, workspace_path, revision)

      assert {:ok, result} =
               WorkflowService.review(
                 managed_repo.id,
                 work_item_id,
                 "Review durable memory with explicit retrieval policy",
                 workspace_path: workspace_path,
                 memory: [
                   workspace_path: workspace_path,
                   prepare: :recover_if_needed,
                   revision: revision,
                   memories: [content_contains: "Greeting contract changes require governed review."],
                   provenance: [label_contains: "review artifact"],
                   policy: [
                     intent: :review_risks,
                     memory_kinds: [:known_issue],
                     provenance_kinds: [:review],
                     freshness: :ready_only,
                     follow_up_intent: :work_item
                   ]
                 ]
               )

      assert result.memory_input.policy.intent == :review_risks
      assert result.memory_input.selection.state == :filtered
      refute memory_resource_iri in result.memory_input.selection.related_resources

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
                 workspace_path: workspace_path,
                 workflow_context: WorkflowService.follow_up_context(result)
               )

      assert adoption.work_item.work_metadata["workflow_memory"]["retrieval_policy"]["intent"] == "review_risks"

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
                   ?plan jido:relatedTo <#{memory_resource_iri}> .
                 }
                 """,
                 graph_name: MemoryGraph.workflow_provenance_graph_name(),
                 allow_stale?: true
               )

      assert provenance_query.row_count == 1
    end
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

  defp seed_governed_run!(project, managed_repo, workspace_path) do
    run_id = "phase-33-run-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Seed governed run memory context"},
        input_metadata: %{"task_summary" => %{required: true, source: "phase_thirty_three_integration"}},
        initiating_actor: %{id: "owner-33", email: "phase-thirty-three@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-10 21:00:00Z]
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-04-10 21:00:30Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-04-10 21:01:00Z]
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
          key: "phase_thirty_three_memory_history",
          evidence_type: "memory_graph_finding",
          summary: "Phase 33 integration needs governed run memory context.",
          evidence_details: %{"source" => "phase_thirty_three_integration"},
          source: "memory_graph",
          recorded_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, decision} =
      Decision.create(
        %{
          decision_key: "phase-thirty-three-run-#{run.id}",
          run_id: run.id,
          managed_repo_id: managed_repo.id,
          decision: :defer,
          actor: %{"id" => "owner-33", "email" => "phase-thirty-three@example.com"},
          rationale: "Phase 33 integration keeps governed memory context reviewable.",
          decision_metadata: %{"source" => "phase_thirty_three_integration"},
          decided_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, revision_metadata} = MemoryGraph.current_revision_metadata(workspace_path)
    revision = revision_metadata.current_revision

    seed_run_memory_context!(
      managed_repo.id,
      workspace_path,
      revision,
      run.run_id,
      evidence.id,
      decision.id
    )

    {run, evidence, decision, revision}
  end

  defp seed_memory_graph!(managed_repo_id, workspace_path, revision) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "phase-33-memory-#{System.unique_integer([:positive])}"

    assert {:ok, provenance_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.review(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-three",
                 workflow: :review,
                 work_item_id: "work-33",
                 content: "Generated a review artifact for phase thirty-three integration tests.",
                 anchors: %{module_name: "ExamplePhaseThirtyThree"}
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
                 actor_id: "system:phase-thirty-three",
                 workflow: :review,
                 work_item_id: "work-33",
                 content: "Greeting contract changes require governed review.",
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseThirtyThree"},
                 governed_context: %{run_id: "run-33", work_item_id: "work-33"},
                 classification: %{
                   source: "phase_thirty_three_integration",
                   reason: "Phase 33 integration needs durable repository memory."
                 }
               ),
               revision: revision
             )

    %{
      provenance_resource_iri: provenance_result.capture.resource_iri,
      memory_resource_iri: memory_result.capture.resource_iri
    }
  end

  defp seed_run_memory_context!(managed_repo_id, workspace_path, revision, run_id, evidence_id, decision_id) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "phase-33-run-memory-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-three-run",
                 workflow: :review,
                 work_item_id: "work-33",
                 goal: "Seed phase thirty-three run memory context"
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _review_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.review(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-three-run",
                 workflow: :review,
                 work_item_id: "work-33",
                 content: "Review artifact captured for governed run memory context.",
                 anchors: %{module_name: "ExamplePhaseThirtyThreeRun"},
                 governed_context: %{run_id: run_id, decision_id: decision_id}
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.known_issue(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-three-run",
                 workflow: :review,
                 work_item_id: "work-33",
                 content: "Run detail should surface memory context for governed review.",
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseThirtyThreeRun"},
                 governed_context: %{run_id: run_id, evidence_id: evidence_id, decision_id: decision_id},
                 classification: %{
                   source: "phase_thirty_three_integration",
                   reason: "Phase 33 integration requires bounded run memory context."
                 }
               ),
               revision: revision
             )
  end

  defp governed_session_id(:plan, digest, work_item_id), do: "memory-governed-plan-#{digest}-#{work_item_id}"

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_thirty_three_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtyThree.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_three_example, version: "0.1.0"]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_phase_thirty_three.ex"),
      """
      defmodule ExamplePhaseThirtyThree do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
  end
end
