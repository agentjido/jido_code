defmodule JidoCode.PhaseThirtyFourIntegrationTest do
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.cross_graph_navigation_stays_consistent_across_surfaces
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo, RepoBridge}
  alias JidoCode.Governance.{Decision, Evidence}
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope, FollowUpSurface, GovernedSurfaceContext}
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

  test "34.4.1.3 governed context keeps cross-graph navigation and follow-up bounded", %{
    workspace_path: workspace_path
  } do
    {project, managed_repo} = create_project_and_repo!("phase-34-cross-graph", workspace_path)
    revision = "rev-34-governed-cross-graph"

    assert {:ok, _load_result} =
             AgentWorkspace.load_source_code_graph(
               managed_repo.id,
               workspace_path,
               revision: revision
             )

    {run, evidence, decision} = seed_governed_run!(project, managed_repo)

    assert {:ok, revision_metadata} = MemoryGraph.current_revision_metadata(workspace_path)
    current_revision = revision_metadata.current_revision

    seed_run_memory_context!(
      managed_repo.id,
      workspace_path,
      current_revision,
      run.run_id,
      evidence.id,
      decision.id
    )

    assert {:ok, repo_scope} = RepoBridge.repo_scope(project.id)

    context =
      GovernedSurfaceContext.load_run_detail(
        repo_scope,
        run,
        [evidence],
        [decision],
        revision: current_revision,
        managed_repo_id: managed_repo.id,
        workspace_path: workspace_path
      )

    assert context.available? == true
    assert context.graph.state == :ready

    memory_item =
      Enum.find(context.memories.items, fn item ->
        Enum.any?(item.navigation.governed_records) and Enum.any?(item.navigation.source_code)
      end)

    assert memory_item

    preview =
      FollowUpSurface.preview(
        context.memories,
        route: "/repos/#{managed_repo.id}/runs/#{run.run_id}#run-detail-memory-context",
        category: "governed_follow_up"
      )

    assert preview.available? == true
    assert preview.recommended_action == "promote_memory_follow_up"
    assert preview.route == "/repos/#{managed_repo.id}/runs/#{run.run_id}#run-detail-memory-context"
    assert preview.workflow_context["memory_resources"] != []
    assert preview.memory_kinds != []
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

  defp seed_governed_run!(project, managed_repo) do
    run_id = "phase-34-run-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Seed governed run memory context"},
        input_metadata: %{"task_summary" => %{required: true, source: "phase_thirty_four_integration"}},
        initiating_actor: %{id: "owner-34", email: "phase-thirty-four@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-11 03:00:00Z]
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-04-11 03:00:30Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-04-11 03:01:00Z]
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
          key: "phase_thirty_four_memory_history",
          evidence_type: "memory_graph_finding",
          summary: "Phase 34 integration needs governed run memory context.",
          evidence_details: %{"source" => "phase_thirty_four_integration"},
          source: "memory_graph",
          recorded_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, decision} =
      Decision.create(
        %{
          decision_key: "phase-thirty-four-run-#{run.id}",
          run_id: run.id,
          managed_repo_id: managed_repo.id,
          decision: :approve,
          actor: %{"id" => "owner-34", "email" => "phase-thirty-four@example.com"},
          rationale: "Phase 34 integration keeps memory rollout canonical and governed.",
          decision_metadata: %{"source" => "phase_thirty_four_integration"},
          decided_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {run, evidence, decision}
  end

  defp seed_run_memory_context!(managed_repo_id, workspace_path, revision, run_id, evidence_id, decision_id) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "phase-34-run-memory-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-four-run",
                 workflow: :review,
                 work_item_id: "work-34",
                 goal: "Seed phase thirty-four run memory context"
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
                 actor_id: "system:phase-thirty-four-run",
                 workflow: :review,
                 work_item_id: "work-34",
                 content: "Review artifact captured for governed run memory context.",
                 anchors: %{module_name: "ExamplePhaseThirtyFourRun"},
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
                 actor_id: "system:phase-thirty-four-run",
                 workflow: :review,
                 work_item_id: "work-34",
                 content: "Run detail should surface memory-aware follow-up context.",
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseThirtyFourRun"},
                 governed_context: %{run_id: run_id, evidence_id: evidence_id, decision_id: decision_id},
                 classification: %{
                   source: "phase_thirty_four_integration",
                   reason: "Phase 34 integration requires bounded run memory context."
                 }
               ),
               revision: revision
             )
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_thirty_four_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtyFour.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_four_example, version: "0.1.0"]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_phase_thirty_four_run.ex"),
      """
      defmodule ExamplePhaseThirtyFourRun do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
  end
end
