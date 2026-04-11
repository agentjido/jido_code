defmodule JidoCodeWeb.PhaseThirtyFourIntegrationTest do
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.{Decision, Evidence}
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope}
  alias JidoCode.Orchestration.{Run, WorkflowRun}
  alias JidoCode.Projects.Project

  setup do
    original_memory = Application.get_env(:jido_code, :memory_graph_enabled, false)

    Application.put_env(:jido_code, :memory_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, original_memory)
    end)

    :ok
  end

  test "34.4.1.1 dashboard summaries and governed run surfaces stay bounded and canonical", %{
    conn: _conn
  } do
    register_owner("phase34-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase34-owner@example.com", "owner-password-123")

    workspace_path = create_workspace_path!()

    {:ok, project} =
      Project.create(%{
        name: "phase-34-live-repo",
        github_full_name: "owner/phase-34-live-repo",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    managed_repo_id = managed_repo_route_id!(project.id)
    seed_repo_memory_graph!(managed_repo_id, workspace_path, "rev-34-live-dashboard")
    {run, evidence, decision} = seed_governed_run!(project, managed_repo_id, workspace_path)

    {:ok, dashboard_view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    assert has_element?(dashboard_view, "#dashboard-memory-summary-list")
    assert render(dashboard_view) =~ "owner/phase-34-live-repo"
    assert has_element?(dashboard_view, ~s([id^="dashboard-memory-summary-link-"]))

    {:ok, run_view, _run_html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}/runs/#{run.run_id}", on_error: :warn)

    assert has_element?(run_view, "#run-detail-governed-memory-contexts")
    assert has_element?(run_view, "#run-detail-memory-follow-up-preview")
    assert has_element?(run_view, "#run-detail-evidence-memory-#{evidence.id}-memory-list")
    assert has_element?(run_view, "#run-detail-decision-memory-supersede-#{decision.id}")

    render_click(element(run_view, "#run-detail-evidence-memory-#{evidence.id}-memory-promote-1"))
    assert has_element?(run_view, "#run-detail-memory-action-feedback", "Created governed follow-up work item")
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_thirty_four_live_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtyFourLive.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_four_live, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_phase_thirty_four_live.ex"),
      """
      defmodule ExamplePhaseThirtyFourLive do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp seed_repo_memory_graph!(managed_repo_id, workspace_path, revision) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "phase-34-live-#{System.unique_integer([:positive])}"

    assert {:ok, _provenance_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.review(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-four-live",
                 workflow: :review,
                 work_item_id: "work-34",
                 content: "Generated a review artifact for phase thirty-four live tests.",
                 anchors: %{module_name: "ExamplePhaseThirtyFourLive"}
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.known_issue(
                 id: "known-issue-live",
                 session_id: session_id,
                 actor_id: "system:phase-thirty-four-live",
                 workflow: :review,
                 work_item_id: "work-34",
                 content: "Greeting contract changes require bounded follow-up review.",
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseThirtyFourLive"},
                 governed_context: %{run_id: "run-34", work_item_id: "work-34"},
                 classification: %{
                   source: "phase_thirty_four_live",
                   reason: "Phase 34 live integration needs durable repository memory."
                 }
               ),
               revision: revision
             )
  end

  defp seed_governed_run!(project, managed_repo_id, workspace_path) do
    run_id = "phase-34-live-run-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Seed phase thirty-four live memory context"},
        input_metadata: %{"task_summary" => %{required: true, source: "phase_thirty_four_live"}},
        initiating_actor: %{id: "owner-34", email: "phase34-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-11 04:00:00Z]
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-04-11 04:00:30Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-04-11 04:01:00Z]
      })

    {:ok, run} =
      Run.get_by_managed_repo_and_run_id(
        managed_repo_id,
        run_id,
        actor: Actor.operator_actor()
      )

    {:ok, evidence} =
      Evidence.create(
        %{
          run_id: run.id,
          managed_repo_id: managed_repo_id,
          key: "phase_thirty_four_live_history",
          evidence_type: "memory_graph_finding",
          summary: "Phase 34 live integration keeps run memory context visible.",
          evidence_details: %{"source" => "phase_thirty_four_live"},
          source: "memory_graph",
          recorded_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, decision} =
      Decision.create(
        %{
          decision_key: "phase-thirty-four-live-#{run.id}",
          run_id: run.id,
          managed_repo_id: managed_repo_id,
          decision: :approve,
          actor: %{"id" => "owner-34", "email" => "phase34-owner@example.com"},
          rationale: "Phase 34 live integration keeps canonical memory actions visible.",
          decision_metadata: %{"source" => "phase_thirty_four_live"},
          decided_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    assert {:ok, revision_metadata} = MemoryGraph.current_revision_metadata(workspace_path)

    seed_run_memory_context!(
      managed_repo_id,
      workspace_path,
      revision_metadata.current_revision,
      run.run_id,
      evidence.id,
      decision.id
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

    session_id = "phase-34-live-run-memory-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-four-live-run",
                 workflow: :review,
                 work_item_id: "work-34",
                 goal: "Seed phase thirty-four live run memory context"
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.decision(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-four-live-run",
                 workflow: :review,
                 work_item_id: "work-34",
                 content: "Run detail should stage bounded follow-up from decision memory.",
                 rationale: "The canonical run surface must explain memory-driven follow-up.",
                 decision_status: :accepted,
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseThirtyFourLive"},
                 governed_context: %{run_id: run_id, evidence_id: evidence_id, decision_id: decision_id},
                 classification: %{
                   source: "phase_thirty_four_live",
                   reason: "Phase 34 live integration needs decision memory on the governed surface."
                 }
               ),
               revision: revision
             )
  end

  defp managed_repo_route_id!(legacy_project_id) do
    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(legacy_project_id, actor: Actor.operator_actor())

    managed_repo.id
  end
end
