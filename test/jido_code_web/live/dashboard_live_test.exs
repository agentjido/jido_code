defmodule JidoCodeWeb.DashboardLiveTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  setup do
    original_loader = Application.get_env(:jido_code, :dashboard_run_summary_loader, :__missing__)

    on_exit(fn ->
      restore_env(:dashboard_run_summary_loader, original_loader)
    end)

    :ok
  end

  test "renders recent runs with status and recency indicators", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-dashboard-recent-runs",
        github_full_name: "owner/repo-dashboard-recent-runs",
        default_branch: "main",
        settings: %{}
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, completed_run} =
      create_run(project.id, "dashboard-run-completed", DateTime.add(now, -3_600, :second))

    {:ok, completed_run} =
      WorkflowRun.transition_status(completed_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: DateTime.add(now, -3_540, :second)
      })

    {:ok, _completed_run} =
      WorkflowRun.transition_status(completed_run, %{
        to_status: :completed,
        current_step: "publish_pr",
        transitioned_at: DateTime.add(now, -3_480, :second)
      })

    {:ok, _pending_run} =
      create_run(project.id, "dashboard-run-pending", DateTime.add(now, -120, :second))

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    assert has_element?(view, "#dashboard-run-summaries")
    assert has_element?(view, "#dashboard-run-status-dashboard-run-completed", "completed")
    assert has_element?(view, "#dashboard-run-status-dashboard-run-pending", "pending")
    assert has_element?(view, "#dashboard-run-recency-dashboard-run-completed", "Started")
    assert has_element?(view, "#dashboard-run-recency-dashboard-run-completed", "ago")
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

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)
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

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

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

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    assert has_element?(view, "#dashboard-run-status-#{run_dom_token}", "awaiting_approval")
    assert has_element?(view, "#dashboard-run-governance-#{run_dom_token}", "Stage: approval")
    assert has_element?(view, "#dashboard-run-governance-#{run_dom_token}", "Evidence: 3")
    assert has_element?(view, "#dashboard-run-governance-#{run_dom_token}", "Review: open")
  end

  defp create_run(project_id, run_id, started_at) do
    WorkflowRun.create(%{
      project_id: project_id,
      run_id: run_id,
      workflow_name: "implement_task",
      workflow_version: 1,
      trigger: %{source: "workflows", mode: "manual"},
      inputs: %{"task_summary" => "Render dashboard run summaries"},
      input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
      initiating_actor: %{id: "owner-1", email: "owner@example.com"},
      current_step: "queued",
      started_at: started_at
    })
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

  defp register_owner(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, _owner} =
      Strategy.action(
        strategy,
        :register,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        },
        context: %{token_type: :sign_in}
      )

    :ok
  end

  defp authenticate_owner_conn(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{"email" => email, "password" => password},
        context: %{token_type: :sign_in}
      )

    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:token)

    auth_response = build_conn() |> get(owner_sign_in_with_token_path(strategy, token))
    assert redirected_to(auth_response, 302) == "/"
    session_token = get_session(auth_response, "user_token")
    assert is_binary(session_token)
    {recycle(auth_response), session_token}
  end

  defp owner_sign_in_with_token_path(strategy, token) do
    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _other -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})
    "#{path}?#{query}"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
