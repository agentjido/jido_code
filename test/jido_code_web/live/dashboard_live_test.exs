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

  setup do
    original_loader = Application.get_env(:jido_code, :dashboard_run_summary_loader, :__missing__)

    original_runtime_loader =
      Application.get_env(:jido_code, :dashboard_runtime_evidence_loader, :__missing__)

    original_memory_loader =
      Application.get_env(:jido_code, :dashboard_memory_summary_loader, :__missing__)

    original_conversation_loader =
      Application.get_env(:jido_code, :dashboard_conversation_summary_loader, :__missing__)

    original_workbench_inventory_loader =
      Application.get_env(:jido_code, :workbench_inventory_loader, :__missing__)

    original_fix_workflow_launcher =
      Application.get_env(:jido_code, :workbench_fix_workflow_launcher, :__missing__)

    original_issue_triage_workflow_launcher =
      Application.get_env(:jido_code, :workbench_issue_triage_workflow_launcher, :__missing__)

    on_exit(fn ->
      restore_env(:dashboard_run_summary_loader, original_loader)
      restore_env(:dashboard_runtime_evidence_loader, original_runtime_loader)
      restore_env(:dashboard_memory_summary_loader, original_memory_loader)
      restore_env(:dashboard_conversation_summary_loader, original_conversation_loader)
      restore_env(:workbench_inventory_loader, original_workbench_inventory_loader)
      restore_env(:workbench_fix_workflow_launcher, original_fix_workflow_launcher)

      restore_env(
        :workbench_issue_triage_workflow_launcher,
        original_issue_triage_workflow_launcher
      )
    end)

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

    {:ok, _completed_run} =
      create_run(route_id, "dashboard-run-completed", DateTime.add(now, -3_600, :second), %{
        status: :completed,
        current_step: "publish_pr",
        current_stage: "publish_pr",
        completed_at: DateTime.add(now, -3_480, :second)
      })

    {:ok, _pending_run} =
      create_run(route_id, "dashboard-run-pending", DateTime.add(now, -120, :second))

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?subject=work&section=runs", on_error: :warn)

    assert has_element?(view, "#dashboard-entry-summary", "authenticated product home")
    assert has_element?(view, ~s|a[href="/settings/auth"]|, "Settings")
    assert has_element?(view, "#dashboard-root[data-dashboard-subject='work'][data-dashboard-section='runs']")
    assert has_element?(view, "#dashboard-shell-section-groups-work[aria-current='page']")
    assert has_element?(view, "#dashboard-section-nav")
    assert has_element?(view, "#dashboard-section-nav-runs[aria-current='page']")
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

  test "renders managed repo inventory overview cards ordered by recent governed work", %{
    conn: _conn
  } do
    register_owner("dashboard-overview-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-overview-owner@example.com", "owner-password-123")

    %{route_id: older_route_id} =
      provision_managed_repo!(%{
        name: "repo-dashboard-overview-older",
        github_full_name: "owner/repo-dashboard-overview-older",
        default_branch: "main",
        settings: %{}
      })

    %{route_id: newer_route_id} =
      provision_managed_repo!(%{
        name: "repo-dashboard-overview-newer",
        github_full_name: "owner/repo-dashboard-overview-newer",
        default_branch: "main",
        settings: %{}
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, _older_run} =
      create_run(older_route_id, "dashboard-overview-older-run", DateTime.add(now, -7_200, :second), %{
        status: :completed,
        current_step: "summarize",
        current_stage: "summarize",
        completed_at: DateTime.add(now, -7_080, :second)
      })

    {:ok, _newer_run} =
      create_run(newer_route_id, "dashboard-overview-newer-run", DateTime.add(now, -900, :second), %{
        status: :running,
        current_step: "implement",
        current_stage: "implement"
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    assert has_element?(view, "#dashboard-root[data-dashboard-subject='work'][data-dashboard-section='overview']")
    assert has_element?(view, "#dashboard-shell-section-groups-work[aria-current='page']")
    assert has_element?(view, "#dashboard-section-nav")
    assert has_element?(view, "#dashboard-sidebar-shell")
    assert has_element?(view, "#dashboard-overview-panel")
    assert has_element?(view, "#dashboard-overview-note", "primary signed-in home for repository inventory")
    refute has_element?(view, "#dashboard-overview-warning")
    refute has_element?(view, "#dashboard-overview-empty-state")
    assert has_element?(view, "#dashboard-overview-repository-list")
    assert has_element?(view, "[id^='dashboard-overview-repository-card-']")
    assert has_element?(view, "#dashboard-overview-workbench-link[href='/workbench']")
    assert has_element?(view, "[id^='dashboard-overview-repository-issues-project-link-']")
    assert has_element?(view, "[id^='dashboard-overview-repository-prs-project-link-']")

    html = render(view)

    assert html =~ "owner/repo-dashboard-overview-newer"
    assert html =~ "owner/repo-dashboard-overview-older"

    assert rendered_fragment_index(html, "owner/repo-dashboard-overview-newer") <
             rendered_fragment_index(html, "owner/repo-dashboard-overview-older")

    refute has_element?(view, "#dashboard-run-summaries")
    refute has_element?(view, "#dashboard-conversation-supervision")
    refute has_element?(view, "#dashboard-memory-summaries")
    refute has_element?(view, "#dashboard-runtime-evidence")
  end

  test "dashboard work overview keeps shared repo-detail and run follow-up paths", %{conn: _conn} do
    register_owner("dashboard-followup-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-followup-owner@example.com", "owner-password-123")

    project_id = "owner-repo-follow-up"
    dashboard_return_to = ~p"/dashboard?#{[subject: "work", section: "overview"]}"
    encoded_return_to = URI.encode_www_form(dashboard_return_to)

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: project_id,
           name: "repo-follow-up",
           github_full_name: "owner/repo-follow-up",
           default_branch: "main",
           open_issue_count: 3,
           open_pr_count: 1,
           recent_activity_summary: "Recent governed work is ready for review.",
           recent_activity_at: DateTime.utc_now() |> DateTime.truncate(:second),
           issue_triage_policy: %{enabled: true},
           semantic_graph_hint: %{
             state: :blocked,
             label: "Workspace binding needed",
             detail: "Repo workspace binding is missing for semantic inspection.",
             remediation: "Open repo detail to repair workspace binding.",
             recovery: %{available?: true, label: "Repair workspace binding"},
             error_type: "semantic_workspace_binding_unavailable"
           },
           memory_graph_hint: %{
             state: :blocked,
             label: "Workspace binding needed",
             detail: "Repo workspace binding is missing for memory inspection.",
             remediation: "Open repo detail to repair workspace binding.",
             recovery: %{available?: true, label: "Repair workspace binding"},
             error_type: "memory_workspace_binding_unavailable"
           }
         }
       ], nil}
    end)

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn _kickoff_request ->
      {:ok, %{run_id: "run-fix-123"}}
    end)

    Application.put_env(:jido_code, :workbench_issue_triage_workflow_launcher, fn _kickoff_request ->
      {:ok, %{run_id: "run-triage-456"}}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)
    html = render(view)
    triage_run_path = "/repos/#{project_id}/runs/run-triage-456?return_to=#{encoded_return_to}"
    fix_run_path = "/repos/#{project_id}/runs/run-fix-123?return_to=#{encoded_return_to}"

    assert has_element?(view, "#dashboard-overview-workbench-link[href='/workbench']")
    assert html =~ ~s(href="/repos/#{project_id}?return_to=#{encoded_return_to}")

    assert has_element?(view, "#dashboard-overview-repository-issues-project-link-#{project_id}")
    assert has_element?(view, "#dashboard-overview-repository-prs-project-link-#{project_id}")
    assert has_element?(view, "#dashboard-overview-repository-semantic-hint-recovery-#{project_id}")
    assert has_element?(view, "#dashboard-overview-repository-memory-hint-recovery-#{project_id}")

    view
    |> element("#dashboard-overview-repository-issues-triage-action-#{project_id}")
    |> render_click()

    assert has_element?(
             view,
             "#dashboard-overview-repository-issues-triage-#{project_id}-run-link[href='#{triage_run_path}']"
           )

    view
    |> element("#dashboard-overview-repository-issues-fix-action-#{project_id}")
    |> render_click()

    assert has_element?(
             view,
             "#dashboard-overview-repository-issues-fix-#{project_id}-run-link[href='#{fix_run_path}']"
           )
  end

  test "dashboard repository links round-trip back to Dashboard Work", %{conn: _conn} do
    register_owner("dashboard-roundtrip-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-roundtrip-owner@example.com", "owner-password-123")

    %{route_id: project_id} =
      provision_managed_repo!(%{
        name: "repo-dashboard-roundtrip",
        github_full_name: "owner/repo-dashboard-roundtrip",
        default_branch: "main",
        settings: %{}
      })

    dashboard_return_to = ~p"/dashboard?#{[subject: "work", section: "overview"]}"

    repo_detail_path =
      JidoCode.ManagedRepoRoutes.project_detail_path(project_id, return_to: dashboard_return_to)

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: project_id,
           name: "repo-dashboard-roundtrip",
           github_full_name: "owner/repo-dashboard-roundtrip",
           default_branch: "main",
           open_issue_count: 1,
           open_pr_count: 0,
           recent_activity_summary: "Dashboard origin should stay explicit.",
           recent_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    view
    |> element("#dashboard-overview-repository-issues-project-link-#{project_id}")
    |> render_click()

    assert_redirect(view, repo_detail_path)

    {:ok, repo_view, _html} = live(recycle(authed_conn), repo_detail_path, on_error: :warn)

    assert has_element?(repo_view, "#project-detail-breadcrumb-return", "Dashboard")

    assert has_element?(repo_view, "#project-detail-return-link", "Back to Dashboard")

    repo_view
    |> element("#project-detail-return-link")
    |> render_click()

    assert_redirect(repo_view, dashboard_return_to)
  end

  test "defaults dashboard selection to work overview and ignores unknown params", %{
    conn: _conn
  } do
    register_owner("dashboard-section-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-section-owner@example.com", "owner-password-123")

    {:ok, overview_view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    assert has_element?(
             overview_view,
             "#dashboard-root[data-dashboard-subject='work'][data-dashboard-section='overview']"
           )

    {:ok, invalid_view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?subject=unknown&section=unknown", on_error: :warn)

    assert has_element?(
             invalid_view,
             "#dashboard-root[data-dashboard-subject='work'][data-dashboard-section='overview']"
           )
  end

  test "route-owned dashboard subject and child selection accepts canonical subject families", %{
    conn: _conn
  } do
    register_owner("dashboard-route-section-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-route-section-owner@example.com", "owner-password-123")

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?subject=work&section=conversations", on_error: :warn)

    assert has_element?(view, "#dashboard-root[data-dashboard-subject='work'][data-dashboard-section='conversations']")
    assert has_element?(view, "#dashboard-shell-section-groups-work[aria-current='page']")
    assert has_element?(view, "#dashboard-conversation-supervision")
    refute has_element?(view, "#dashboard-run-summaries")
    refute has_element?(view, "#dashboard-memory-summaries")

    {:ok, runtime_view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?subject=runtime&section=runtime", on_error: :warn)

    assert has_element?(
             runtime_view,
             "#dashboard-root[data-dashboard-subject='runtime'][data-dashboard-section='runtime']"
           )

    assert has_element?(runtime_view, "#dashboard-shell-section-groups-runtime[aria-current='page']")
    assert has_element?(runtime_view, "#dashboard-runtime-evidence")
    refute has_element?(runtime_view, "#dashboard-conversation-supervision")
    refute has_element?(runtime_view, "#dashboard-memory-summaries")

    {:ok, fallback_view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?section=memory", on_error: :warn)

    assert has_element?(
             fallback_view,
             "#dashboard-root[data-dashboard-subject='knowledge'][data-dashboard-section='memory']"
           )
  end

  test "renders breadcrumbs between route framing and selected pane chrome", %{conn: _conn} do
    register_owner("dashboard-shell-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-shell-owner@example.com", "owner-password-123")

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?subject=work&section=runs", on_error: :warn)

    html = render(view)

    assert rendered_fragment_index(html, ~s(id="dashboard-settings-handoff")) <
             rendered_fragment_index(html, ~s(id="dashboard-shell-breadcrumbs"))

    assert rendered_fragment_index(html, ~s(id="dashboard-shell-breadcrumbs")) <
             rendered_fragment_index(html, ~s(id="dashboard-shell-section-groups"))

    assert rendered_fragment_index(html, ~s(id="dashboard-shell-section-groups")) <
             rendered_fragment_index(html, ~s(id="dashboard-section-nav"))

    assert has_element?(view, "#dashboard-breadcrumb-subject", "Work")
    assert has_element?(view, "#dashboard-breadcrumb-current[aria-current='page']", "Runs")
    assert has_element?(view, "#dashboard-shell-section-groups-work[aria-current='page']")

    assert has_element?(
             view,
             "#dashboard-section-nav-runs[aria-controls='dashboard-pane-runs'][aria-current='page']"
           )

    assert has_element?(view, "#dashboard-pane-runs[role='region']")
    assert has_element?(view, "#dashboard-pane-runs-header")
    assert has_element?(view, "#dashboard-pane-runs-middle")
    assert has_element?(view, "#dashboard-pane-runs-footer")
  end

  test "next_steps section is only selectable when onboarding follow-up is present", %{conn: _conn} do
    register_owner("dashboard-next-steps-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("dashboard-next-steps-owner@example.com", "owner-password-123")

    {:ok, blocked_view, _html} =
      live(
        recycle(authed_conn),
        ~p"/dashboard?subject=work&section=next_steps",
        on_error: :warn
      )

    assert has_element?(
             blocked_view,
             "#dashboard-root[data-dashboard-subject='work'][data-dashboard-section='overview']"
           )

    {:ok, next_steps_view, _html} =
      live(
        recycle(authed_conn),
        ~p"/dashboard?onboarding=completed&subject=work&section=next_steps",
        on_error: :warn
      )

    assert has_element?(
             next_steps_view,
             "#dashboard-root[data-dashboard-subject='work'][data-dashboard-section='next_steps']"
           )

    assert has_element?(next_steps_view, "#dashboard-shell-section-groups-work[aria-current='page']")
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

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?subject=work&section=runs", on_error: :warn)

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

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?subject=work&section=runs", on_error: :warn)

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
           project_id: JidoCode.UUID.generate(),
           managed_repo_id: JidoCode.UUID.generate(),
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

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?subject=work&section=runs", on_error: :warn)

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
           managed_repo_id: JidoCode.UUID.generate(),
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
      live(
        recycle(authed_conn),
        ~p"/dashboard?subject=work&section=conversations",
        on_error: :warn
      )

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
           managed_repo_id: JidoCode.UUID.generate(),
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
      live(
        recycle(authed_conn),
        ~p"/dashboard?subject=runtime&section=runtime",
        on_error: :warn
      )

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
           managed_repo_id: JidoCode.UUID.generate(),
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
      live(
        recycle(authed_conn),
        ~p"/dashboard?subject=knowledge&section=memory",
        on_error: :warn
      )

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
              transitioned_at: Map.get(attrs, :completed_at) || DateTime.add(started_at, 60, :second)
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

  defp rendered_fragment_index(html, fragment) when is_binary(html) and is_binary(fragment) do
    case :binary.match(html, fragment) do
      {index, _length} -> index
      :nomatch -> flunk("expected fragment #{inspect(fragment)} in rendered output")
    end
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
