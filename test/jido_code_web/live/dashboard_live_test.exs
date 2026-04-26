defmodule JidoCodeWeb.DashboardLiveTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  # covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.Actor
  alias JidoCode.Control.RepoBridge
  alias JidoCode.Orchestration.{Run, WorkflowRun}
  alias JidoCode.Projects.Project
  alias JidoCode.Repo

  setup do
    original_loader = Application.get_env(:jido_code, :dashboard_run_summary_loader, :__missing__)

    original_runtime_loader =
      Application.get_env(:jido_code, :dashboard_runtime_evidence_loader, :__missing__)

    original_memory_loader =
      Application.get_env(:jido_code, :dashboard_memory_summary_loader, :__missing__)

    original_conversation_loader =
      Application.get_env(:jido_code, :dashboard_conversation_summary_loader, :__missing__)

    on_exit(fn ->
      restore_env(:dashboard_run_summary_loader, original_loader)
      restore_env(:dashboard_runtime_evidence_loader, original_runtime_loader)
      restore_env(:dashboard_memory_summary_loader, original_memory_loader)
      restore_env(:dashboard_conversation_summary_loader, original_conversation_loader)
    end)

    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE users RESTART IDENTITY CASCADE", [])

    :ok
  end

  test "renders recent runs with status and recency indicators", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    %{route_id: route_id} =
      provision_managed_repo!(%{
        name: "repo-dashboard-recent-runs",
        github_full_name: "owner/repo-dashboard-recent-runs",
        default_branch: "main",
        settings: %{}
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, completed_run} =
      create_run(route_id, "dashboard-run-completed", DateTime.add(now, -3_600, :second), %{
        status: :completed,
        current_step: "publish_pr",
        current_stage: "publish_pr",
        completed_at: DateTime.add(now, -3_480, :second)
      })

    {:ok, _pending_run} =
      create_run(route_id, "dashboard-run-pending", DateTime.add(now, -120, :second))

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard?section=runs", on_error: :warn)

    assert has_element?(view, "#dashboard-entry-summary", "authenticated product overview")
    assert has_element?(view, ~s|a[href="/settings/auth"]|, "Settings")
    assert has_element?(view, "#dashboard-section-nav")
    assert has_element?(view, "#dashboard-run-summaries")
    assert has_element?(view, "#dashboard-run-summary-fallback")
    assert has_element?(view, "#dashboard-run-status-dashboard-run-completed", "completed")
    assert has_element?(view, "#dashboard-run-status-dashboard-run-pending", "pending")
    assert has_element?(view, "#dashboard-run-recency-dashboard-run-completed", "Started")
    assert has_element?(view, "#dashboard-run-recency-dashboard-run-completed", "ago")

    vue = assert_vue_component(view, "DashboardRunSummaryWidget", id: "dashboard-run-summary-widget")

    assert vue.props["runSummaryCount"] == 2

    assert Enum.any?(vue.props["runSummaries"], fn run_summary ->
             run_summary["runId"] == "dashboard-run-completed" and
               run_summary["terminal"] == true
            end)
  end

  test "renders a summary-first overview with tab handoff cards by default", %{conn: _conn} do
    register_owner("dashboard-overview-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-overview-owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    assert has_element?(view, "#dashboard-root[data-dashboard-section='overview']")
    assert has_element?(view, "#dashboard-section-nav")
    assert has_element?(view, "#dashboard-overview-panel")
    assert has_element?(view, "#dashboard-overview-note", "jump into the bounded concern tab")
    assert has_element?(view, "#dashboard-overview-card-runs")
    assert has_element?(view, "#dashboard-overview-card-conversations")
    assert has_element?(view, "#dashboard-overview-card-memory")
    assert has_element?(view, "#dashboard-overview-card-runtime")

    refute has_element?(view, "#dashboard-run-summaries")
    refute has_element?(view, "#dashboard-conversation-supervision")
    refute has_element?(view, "#dashboard-memory-summaries")
    refute has_element?(view, "#dashboard-runtime-evidence")
  end

  test "defaults dashboard section selection to overview and ignores unknown section params", %{
    conn: _conn
  } do
    register_owner("dashboard-section-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-section-owner@example.com", "owner-password-123")

    {:ok, overview_view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    assert has_element?(overview_view, "#dashboard-root[data-dashboard-section='overview']")

    {:ok, invalid_view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?section=unknown", on_error: :warn)

    assert has_element?(invalid_view, "#dashboard-root[data-dashboard-section='overview']")
  end

  test "route-owned dashboard section selection accepts canonical concern families", %{conn: _conn} do
    register_owner("dashboard-route-section-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-route-section-owner@example.com", "owner-password-123")

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?section=conversations", on_error: :warn)

    assert has_element?(view, "#dashboard-root[data-dashboard-section='conversations']")
    assert has_element?(view, "#dashboard-conversation-supervision")
    refute has_element?(view, "#dashboard-run-summaries")
    refute has_element?(view, "#dashboard-memory-summaries")

    {:ok, runtime_view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?section=runtime", on_error: :warn)

    assert has_element?(runtime_view, "#dashboard-root[data-dashboard-section='runtime']")
    assert has_element?(runtime_view, "#dashboard-runtime-evidence")
    refute has_element?(runtime_view, "#dashboard-conversation-supervision")
    refute has_element?(runtime_view, "#dashboard-memory-summaries")
  end

  test "next_steps section is only selectable when onboarding follow-up is present", %{conn: _conn} do
    register_owner("dashboard-next-steps-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-next-steps-owner@example.com", "owner-password-123")

    {:ok, blocked_view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?section=next_steps", on_error: :warn)

    assert has_element?(blocked_view, "#dashboard-root[data-dashboard-section='overview']")

    {:ok, next_steps_view, _html} =
      live(
        recycle(authed_conn),
        ~p"/dashboard?onboarding=completed&section=next_steps",
        on_error: :warn
      )

    assert has_element?(next_steps_view, "#dashboard-root[data-dashboard-section='next_steps']")
    assert has_element?(next_steps_view, "#dashboard-onboarding-next-actions")
    assert has_element?(next_steps_view, "#dashboard-next-steps-note", "bounded onboarding completion cues")
    refute has_element?(next_steps_view, "#dashboard-run-summaries")
    refute has_element?(next_steps_view, "#dashboard-runtime-evidence")
  end

  test "updates run summaries when runs start and complete", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    loader_calls = start_supervised!({Agent, fn -> 0 end}, id: make_ref())
    run_id = "dashboard-live-update-#{System.unique_integer([:positive])}"
    run_dom_token = run_dom_token(run_id)

    Application.put_env(:jido_code, :dashboard_run_summary_loader, fn ->
      call_number =
        Agent.get_and_update(loader_calls, fn call_count ->
          next_call_number = call_count + 1
          {next_call_number, next_call_number}
        end)

      case call_number do
        1 ->
          {:ok, [], nil}

        2 ->
          {:ok, [], nil}

        3 ->
          {:ok,
           [
             %{
               id: "dashboard-run-summary-#{run_id}",
               run_id: run_id,
               project_id: nil,
               workflow_name: "implement_task",
               status: "pending",
               started_at: DateTime.add(DateTime.utc_now(), -90, :second),
               completed_at: nil
             }
           ], nil}

        _other ->
          {:ok,
           [
             %{
               id: "dashboard-run-summary-#{run_id}",
               run_id: run_id,
               project_id: nil,
               workflow_name: "implement_task",
               status: "completed",
               started_at: DateTime.add(DateTime.utc_now(), -90, :second),
               completed_at: DateTime.add(DateTime.utc_now(), -30, :second)
             }
           ], nil}
      end
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard?section=runs", on_error: :warn)
    assert has_element?(view, "#dashboard-run-summaries-empty-state")

    send(view.pid, {:run_event, %{"event" => "run_started"}})

    assert_eventually(fn ->
      has_element?(view, "#dashboard-run-status-#{run_dom_token}", "pending")
    end)

    send(view.pid, {:run_event, %{"event" => "run_completed"}})

    assert_eventually(fn ->
      has_element?(view, "#dashboard-run-status-#{run_dom_token}", "completed")
    end)
  end

  test "shows stale warning and manual refresh control when summary feed is stale", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    loader_calls = start_supervised!({Agent, fn -> 0 end}, id: make_ref())

    run_id = "dashboard-refresh-after-stale-#{System.unique_integer([:positive])}"
    run_dom_token = run_dom_token(run_id)

    Application.put_env(:jido_code, :dashboard_run_summary_loader, fn ->
      call_number =
        Agent.get_and_update(loader_calls, fn call_count ->
          next_call_number = call_count + 1
          {next_call_number, next_call_number}
        end)

      case call_number do
        1 ->
          {:ok, [],
           %{
             error_type: "dashboard_run_summary_feed_stale",
             detail: "Run summary feed has fallen behind recent lifecycle events.",
             remediation: "Refresh run summaries after validating workflow persistence health."
           }}

        2 ->
          {:ok, [],
           %{
             error_type: "dashboard_run_summary_feed_stale",
             detail: "Run summary feed has fallen behind recent lifecycle events.",
             remediation: "Refresh run summaries after validating workflow persistence health."
           }}

        _other ->
          {:ok,
           [
             %{
               id: "dashboard-run-summary-#{run_id}",
               run_id: run_id,
               project_id: nil,
               workflow_name: "issue_triage",
               status: "completed",
               started_at: DateTime.add(DateTime.utc_now(), -900, :second),
               completed_at: DateTime.add(DateTime.utc_now(), -840, :second)
             }
           ], nil}
      end
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard?section=runs", on_error: :warn)

    assert has_element?(view, "#dashboard-run-summary-warning")
    assert has_element?(view, "#dashboard-run-summary-warning-type", "dashboard_run_summary_feed_stale")
    assert has_element?(view, "#dashboard-run-summary-refresh", "Refresh run summaries")

    view
    |> element("#dashboard-run-summary-refresh")
    |> render_click()

    assert_eventually(fn ->
      has_element?(view, "#dashboard-run-status-#{run_dom_token}", "completed")
    end)

    refute has_element?(view, "#dashboard-run-summary-warning")
  end

  test "renders governed run review metadata when the summary feed includes governance state", %{conn: _conn} do
    register_owner("governed-dashboard-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("governed-dashboard-owner@example.com", "owner-password-123")

    run_id = "dashboard-governed-run-#{System.unique_integer([:positive])}"
    run_dom_token = run_dom_token(run_id)

    Application.put_env(:jido_code, :dashboard_run_summary_loader, fn ->
      {:ok,
       [
         %{
           id: "dashboard-run-summary-#{run_id}",
           run_id: run_id,
           project_id: Ecto.UUID.generate(),
           managed_repo_id: Ecto.UUID.generate(),
           workflow_name: "fix_failing_tests",
           status: "awaiting_approval",
           current_stage: "approval",
           evidence_count: 3,
           change_request_status: "open",
           latest_decision: nil,
           started_at: DateTime.add(DateTime.utc_now(), -600, :second),
           completed_at: nil
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard?section=runs", on_error: :warn)

    assert has_element?(view, "#dashboard-run-status-#{run_dom_token}", "awaiting_approval")
    assert has_element?(view, "#dashboard-run-governance-#{run_dom_token}", "Stage: approval")
    assert has_element?(view, "#dashboard-run-governance-#{run_dom_token}", "Evidence: 3")
    assert has_element?(view, "#dashboard-run-governance-#{run_dom_token}", "Review: open")
  end

  test "renders bounded conversation supervision summaries that route back to repo detail", %{
    conn: _conn
  } do
    register_owner("conversation-dashboard-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("conversation-dashboard-owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :dashboard_conversation_summary_loader, fn ->
      {:ok,
       [
         %{
           id: "conversation-summary-1",
           route_id: "repo-conversation-dashboard",
           managed_repo_id: Ecto.UUID.generate(),
           repo_label: "owner/repo-conversation-dashboard",
           role_scope: "work_item_scoped",
           role_attachment_mode: "governed_work",
           role_work_item_id: "work-item-1",
           latest_status: "active",
           active_count: 2,
           clarification_count: 1,
           detail:
             "2 governed conversations active. 1 clarification turn needs an answer. Latest governed work: Review queued operator request.",
           latest_work_item_summary: "Review queued operator request.",
           latest_activity_at: ~U[2026-04-24 14:05:00Z],
           route: "/repos/repo-conversation-dashboard#project-detail-conversation-panel",
           action_label: "Open governed supervision"
         }
       ], nil}
    end)

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?section=conversations", on_error: :warn)

    assert has_element?(view, "#dashboard-conversation-supervision")
    assert has_element?(view, "#dashboard-conversation-summary-note", "route back to canonical repo detail")

    assert has_element?(
             view,
             "#dashboard-conversation-summary-repo-conversation-summary-1",
             "owner/repo-conversation-dashboard"
           )

    assert has_element?(
             view,
             "#dashboard-conversation-summary-role-conversation-summary-1",
             "Governed conversation"
           )

    assert has_element?(
             view,
             "#dashboard-conversation-summary-status-conversation-summary-1",
             "active"
           )

    assert has_element?(
             view,
             "#dashboard-conversation-summary-clarification-conversation-summary-1",
             "1 clarification needed"
           )

    assert has_element?(
             view,
             "#dashboard-conversation-summary-counts-conversation-summary-1",
             "Active governed conversations: 2"
           )

    assert has_element?(
             view,
             "#dashboard-conversation-summary-link-conversation-summary-1[href='/repos/repo-conversation-dashboard#project-detail-conversation-panel']",
             "Open governed supervision"
           )
  end

  test "renders runtime posture summaries in product-oriented rollout language", %{conn: _conn} do
    register_owner("runtime-dashboard-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("runtime-dashboard-owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :dashboard_runtime_evidence_loader, fn ->
      {:ok,
       [
         %{
           id: "runtime-posture-1",
           managed_repo_id: Ecto.UUID.generate(),
           repo_label: "repo-runtime-dashboard",
           status: "degraded",
           summary:
             "Runtime service evidence indicates degraded execution trust. Coding turn delivery repaired through replay recovery.",
           delivery_mode: "replay_recovery",
           reason_code: "live_delivery_detached",
           latest_provider: "github",
           supervision_mode: "guided",
           review_required: true,
           updated_at: DateTime.utc_now()
         }
       ], nil}
    end)

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?section=runtime", on_error: :warn)

    assert has_element?(view, "#dashboard-runtime-evidence")
    assert has_element?(view, "#dashboard-runtime-evidence-fallback")
    assert has_element?(view, "#dashboard-runtime-evidence-summary", "review-required")
    assert has_element?(view, "#dashboard-runtime-evidence-note", "source of truth")
    assert has_element?(view, "#dashboard-runtime-evidence-count-degraded", "1")
    assert has_element?(view, "#dashboard-runtime-evidence-runtime-posture-1", "repo-runtime-dashboard")

    vue = assert_vue_component(view, "DashboardRuntimePostureWidget", id: "dashboard-runtime-posture-widget")

    assert vue.props["counts"] == %{"available" => 0, "blocked" => 0, "degraded" => 1}

    assert Enum.any?(vue.props["runtimeEvidenceSummaries"], fn runtime_summary ->
             runtime_summary["repoLabel"] == "repo-runtime-dashboard" and
               runtime_summary["status"] == "degraded"
           end)

    assert has_element?(
             view,
             "#dashboard-runtime-evidence-item-summary-runtime-posture-1",
             "degraded execution trust"
           )

    assert has_element?(
             view,
             "#dashboard-runtime-evidence-item-details-runtime-posture-1",
             "Delivery: replay recovery"
           )

    assert has_element?(
             view,
             "#dashboard-runtime-evidence-item-details-runtime-posture-1",
             "Latest provider: github"
           )
  end

  test "renders bounded repository memory summaries with canonical follow-up routes", %{conn: _conn} do
    register_owner("memory-dashboard-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("memory-dashboard-owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :dashboard_memory_summary_loader, fn ->
      {:ok,
       [
         %{
           id: "memory-summary-1",
           route_id: "repo-memory-dashboard",
           managed_repo_id: Ecto.UUID.generate(),
           repo_label: "owner/repo-memory-dashboard",
           state: "invalidated",
           label: "Memory graph invalidated",
           detail: "Repository memory graph validation was explicitly invalidated and should be revalidated.",
           remediation: "Validate repository memory graph for the current revision.",
           memory_count: 3,
           provenance_count: 2,
           route: "/repos/repo-memory-dashboard#project-detail-memory-inspection",
           action_label: "Validate memory graph",
           action_needed?: true,
           recovery_available?: true,
           latest_revision: "abc123"
         }
       ], nil}
    end)

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?section=memory", on_error: :warn)

    assert has_element?(view, "#dashboard-memory-summaries")
    assert has_element?(view, "#dashboard-memory-summary-note", "canonical managed-repository surfaces")
    assert has_element?(view, "#dashboard-memory-summary-repo-memory-summary-1", "owner/repo-memory-dashboard")
    assert has_element?(view, "#dashboard-memory-summary-state-memory-summary-1", "Memory graph invalidated")
    assert has_element?(view, "#dashboard-memory-summary-counts-memory-summary-1", "Durable memory: 3")
    assert has_element?(view, "#dashboard-memory-summary-counts-memory-summary-1", "Workflow provenance: 2")
    assert has_element?(view, "#dashboard-memory-summary-action-needed-memory-summary-1", "action needed")

    assert has_element?(
             view,
             "#dashboard-memory-summary-link-memory-summary-1[href=\"/repos/repo-memory-dashboard#project-detail-memory-inspection\"]",
             "Validate memory graph"
           )
  end

  defp create_run(repo_identifier, run_id, started_at, attrs \\ %{}) do
    {:ok, repo_scope} = RepoBridge.repo_scope(repo_identifier)

    {:ok, project} =
      Project.create(
        %{
          name: "dashboard-#{run_id}",
          source_kind: :local,
          local_path: "/tmp/dashboard-#{run_id}"
        },
        actor: Actor.operator_actor()
      )

    workflow_attrs =
      %{
        project_id: project.id,
        managed_repo_id: repo_scope.managed_repo.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render dashboard run summaries"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: started_at
      }

    {:ok, workflow_run} = WorkflowRun.create(workflow_attrs, actor: Actor.operator_actor())

    final_workflow_run =
      workflow_run
      |> maybe_transition_to_running(attrs, started_at)
      |> maybe_transition_to_terminal(attrs, started_at)

    Run.get_by_workflow_run_id(final_workflow_run.id, actor: Actor.operator_actor())
  end

  defp maybe_transition_to_running(workflow_run, attrs, started_at) do
    desired_status = Map.get(attrs, :status, :pending)

    if desired_status in [:running, :awaiting_approval, :completed, :failed, :cancelled] do
      {:ok, workflow_run} =
        WorkflowRun.transition_status(
          workflow_run,
          %{
            to_status: :running,
            current_step: Map.get(attrs, :current_step, "queued"),
            transitioned_at: DateTime.add(started_at, 1, :second)
          },
          actor: Actor.operator_actor()
        )

      workflow_run
    else
      workflow_run
    end
  end

  defp maybe_transition_to_terminal(%WorkflowRun{} = workflow_run, attrs, started_at) do
    case Map.get(attrs, :status, :pending) do
      status when status in [:awaiting_approval, :completed, :failed, :cancelled] ->
        {:ok, workflow_run} =
          WorkflowRun.transition_status(
            workflow_run,
            %{
              to_status: status,
              current_step: Map.get(attrs, :current_step, workflow_run.current_step),
              transitioned_at:
                Map.get(attrs, :completed_at) || DateTime.add(started_at, 60, :second)
            },
            actor: Actor.operator_actor()
          )

        workflow_run

      _other ->
        workflow_run
    end
  end

  defp run_dom_token(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
  end

  defp assert_eventually(assertion_fun, attempts \\ 20)

  defp assert_eventually(assertion_fun, attempts) when attempts > 0 do
    if assertion_fun.() do
      :ok
    else
      receive do
      after
        25 ->
          assert_eventually(assertion_fun, attempts - 1)
      end
    end
  end

  defp assert_eventually(_assertion_fun, 0) do
    flunk("expected condition to become true")
  end
end
