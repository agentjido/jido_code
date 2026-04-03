defmodule JidoCodeWeb.ProjectDetailLiveTest do
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Projects.Project
  alias JidoCode.TestSupport.CodeServer.DriverFake
  alias JidoCode.TestSupport.CodeServer.EngineFake
  alias JidoCode.TestSupport.CodeServer.RuntimeFake

  setup do
    original_fix_workflow_launcher =
      Application.get_env(:jido_code, :workbench_fix_workflow_launcher, :__missing__)

    original_issue_triage_workflow_launcher =
      Application.get_env(:jido_code, :workbench_issue_triage_workflow_launcher, :__missing__)

    original_code_server_runtime_module =
      Application.get_env(:jido_code, :code_server_runtime_module, :__missing__)

    original_code_server_engine_module =
      Application.get_env(:jido_code, :code_server_engine_module, :__missing__)

    original_code_server_driver_module =
      Application.get_env(:jido_code, :code_server_conversation_driver_module, :__missing__)

    on_exit(fn ->
      restore_env(:workbench_fix_workflow_launcher, original_fix_workflow_launcher)

      restore_env(
        :workbench_issue_triage_workflow_launcher,
        original_issue_triage_workflow_launcher
      )

      restore_env(:code_server_runtime_module, original_code_server_runtime_module)
      restore_env(:code_server_engine_module, original_code_server_engine_module)
      restore_env(:code_server_conversation_driver_module, original_code_server_driver_module)
    end)

    :ok
  end

  test "launches supported builtin workflows from /projects/:id with defaults and project-detail traceability",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-ready",
        github_full_name: "owner/repo-ready",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    project_id = project.id
    launch_requests = start_supervised!({Agent, fn -> [] end})

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn kickoff_request ->
      Agent.update(launch_requests, fn requests -> [kickoff_request | requests] end)
      {:ok, %{run_id: "run-fix-123"}}
    end)

    Application.put_env(
      :jido_code,
      :workbench_issue_triage_workflow_launcher,
      fn kickoff_request ->
        Agent.update(launch_requests, fn requests -> [kickoff_request | requests] end)
        {:ok, %{run_id: "run-triage-456"}}
      end
    )

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/projects/#{project_id}", on_error: :warn)

    assert has_element?(view, "#project-detail-workflow-controls")

    assert has_element?(
             view,
             "#project-detail-workflow-name-fix-failing-tests",
             "fix_failing_tests"
           )

    assert has_element?(view, "#project-detail-workflow-name-issue-triage", "issue_triage")
    assert has_element?(view, "#project-detail-launch-fix-failing-tests")
    assert has_element?(view, "#project-detail-launch-issue-triage")
    refute has_element?(view, "#project-detail-launch-disabled-guidance")

    view
    |> element("#project-detail-launch-fix-failing-tests")
    |> render_click()

    assert has_element?(view, "#project-detail-launch-fix-failing-tests-run-id", "run-fix-123")

    assert has_element?(
             view,
             "#project-detail-launch-fix-failing-tests-run-link[href='/projects/#{project_id}/runs/run-fix-123']"
           )

    view
    |> element("#project-detail-launch-issue-triage")
    |> render_click()

    assert has_element?(view, "#project-detail-launch-issue-triage-run-id", "run-triage-456")

    assert has_element?(
             view,
             "#project-detail-launch-issue-triage-run-link[href='/projects/#{project_id}/runs/run-triage-456']"
           )

    recorded_requests = launch_requests |> Agent.get(&Enum.reverse(&1))
    project_route = "/projects/#{project_id}"

    assert [
             %{
               workflow_name: "fix_failing_tests",
               project_id: ^project_id,
               project_defaults: %{
                 default_branch: "main",
                 github_full_name: "owner/repo-ready"
               },
               trigger: %{
                 source: "project_detail",
                 mode: "manual",
                 source_row: %{
                   route: ^project_route,
                   project_id: ^project_id
                 }
               },
               context_item: %{type: :issue},
               initiating_actor: %{id: fix_actor_id}
             },
             %{
               workflow_name: "issue_triage",
               project_id: ^project_id,
               project_defaults: %{
                 default_branch: "main",
                 github_full_name: "owner/repo-ready"
               },
               trigger: %{
                 source: "project_detail",
                 mode: "manual",
                 source_row: %{
                   route: ^project_route,
                   project_id: ^project_id
                 }
               },
               context_item: %{type: :issue},
               initiating_actor: %{id: triage_actor_id}
             }
           ] = recorded_requests

    assert is_binary(fix_actor_id)
    assert fix_actor_id != ""
    assert is_binary(triage_actor_id)
    assert triage_actor_id != ""

    assert Enum.all?(recorded_requests, fn kickoff_request ->
             Map.has_key?(kickoff_request.initiating_actor, :email)
           end)
  end

  test "disables project-detail launch controls with remediation when execution prerequisites are blocked",
       %{
         conn: _conn
       } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-blocked",
        github_full_name: "owner/repo-blocked",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "clone_status" => "error",
            "last_error_type" => "baseline_sync_unavailable",
            "retry_instructions" => "Retry step 7 after baseline sync is repaired."
          }
        }
      })

    launcher_invocations = start_supervised!({Agent, fn -> %{fix: 0, triage: 0} end})

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn _kickoff_request ->
      Agent.update(launcher_invocations, fn state -> Map.update!(state, :fix, &(&1 + 1)) end)
      {:ok, %{run_id: "unexpected-fix-run"}}
    end)

    Application.put_env(
      :jido_code,
      :workbench_issue_triage_workflow_launcher,
      fn _kickoff_request ->
        Agent.update(launcher_invocations, fn state -> Map.update!(state, :triage, &(&1 + 1)) end)
        {:ok, %{run_id: "unexpected-triage-run"}}
      end
    )

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/projects/#{project.id}", on_error: :warn)

    assert has_element?(view, "#project-detail-launch-disabled-guidance")

    assert has_element?(
             view,
             "#project-detail-launch-disabled-fix-failing-tests[aria-disabled='true']",
             "Launch workflow"
           )

    assert has_element?(
             view,
             "#project-detail-launch-disabled-issue-triage[aria-disabled='true']",
             "Launch workflow"
           )

    assert has_element?(view, "#project-detail-launch-disabled-type", "baseline_sync_unavailable")

    assert has_element?(
             view,
             "#project-detail-launch-disabled-detail",
             "clone or baseline sync failed"
           )

    assert has_element?(view, "#project-detail-launch-disabled-remediation", "Retry step 7")
    assert has_element?(view, "#project-detail-conversation-disabled-guidance")
    assert has_element?(view, "#project-detail-conversation-start[disabled]", "Start conversation")
    assert has_element?(view, "#project-detail-conversation-disabled-type", "baseline_sync_unavailable")
    assert has_element?(view, "#project-detail-conversation-disabled-remediation", "Retry step 7")

    refute has_element?(view, "#project-detail-launch-fix-failing-tests")
    refute has_element?(view, "#project-detail-launch-issue-triage")

    assert %{fix: 0, triage: 0} = Agent.get(launcher_invocations, & &1)
  end

  test "renders project conversation panel controls in project detail", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    workspace_path = create_workspace_path!()

    {:ok, project} =
      Project.create(%{
        name: "repo-conversation-ui",
        github_full_name: "owner/repo-conversation-ui",
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

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/projects/#{project.id}", on_error: :warn)

    vue = assert_vue_component(view, "ProjectDetailOverviewWidget", id: "project-detail-overview-widget")

    assert vue.props["githubFullName"] == "owner/repo-conversation-ui"
    assert vue.props["launchReady"] == true
    assert vue.props["conversation"]["status"] == "Idle"
    assert_vue_handler(view, "startConversation", "start_conversation", id: "project-detail-overview-widget")

    assert has_element?(view, "#project-detail-conversation-panel")
    assert has_element?(view, "#project-detail-conversation-start", "Start conversation")
    refute has_element?(view, "#project-detail-conversation-start[disabled]")
    assert has_element?(view, "#project-detail-conversation-stop[disabled]", "Stop conversation")
    assert has_element?(view, "#project-detail-conversation-send[disabled]", "Send")
    assert has_element?(view, "#project-detail-conversation-status", "Idle")
    assert has_element?(view, "#project-detail-conversation-empty", "No conversation messages yet.")
    refute has_element?(view, "#project-detail-conversation-disabled-guidance")
  end

  test "supports conversation start send and stop lifecycle in project detail", %{conn: _conn} do
    Application.put_env(:jido_code, :code_server_runtime_module, RuntimeFake)
    Application.put_env(:jido_code, :code_server_engine_module, EngineFake)
    Application.put_env(:jido_code, :code_server_conversation_driver_module, DriverFake)
    DriverFake.clear()

    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    workspace_path = create_workspace_path!()

    {:ok, project} =
      Project.create(%{
        name: "repo-conversation-lifecycle",
        github_full_name: "owner/repo-conversation-lifecycle",
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

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/projects/#{project.id}", on_error: :warn)

    view
    |> element("#project-detail-conversation-start")
    |> render_click()

    assert has_element?(view, "#project-detail-conversation-status", "Active")
    assert has_element?(view, "#project-detail-conversation-start[disabled]", "Start conversation")
    refute has_element?(view, "#project-detail-conversation-stop[disabled]")
    refute has_element?(view, "#project-detail-conversation-send[disabled]")

    view
    |> form("#project-detail-conversation-form", %{"conversation" => %{"input" => "hello"}})
    |> render_submit()

    assert has_element?(view, "#project-detail-conversation-messages", "hello")
    assert has_element?(view, "#project-detail-conversation-messages", "Ack: hello")

    view
    |> element("#project-detail-conversation-stop")
    |> render_click()

    assert has_element?(view, "#project-detail-conversation-status", "Stopped")
    assert has_element?(view, "#project-detail-conversation-send[disabled]", "Send")
    assert has_element?(view, "#project-detail-conversation-empty", "No conversation messages yet.")
  end

  test "shows typed conversation error when project workspace environment is unsupported", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-conversation-blocked",
        github_full_name: "owner/repo-conversation-blocked",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "sprite",
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/projects/#{project.id}", on_error: :warn)

    assert has_element?(view, "#project-detail-conversation-start[disabled]", "Start conversation")
    assert has_element?(view, "#project-detail-conversation-disabled-guidance")

    assert has_element?(
             view,
             "#project-detail-conversation-disabled-type",
             "code_server_workspace_environment_unsupported"
           )

    assert has_element?(
             view,
             "#project-detail-conversation-disabled-remediation",
             "Switch the project workspace environment to local"
           )
  end

  test "disables conversation controls when local workspace path is missing", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-conversation-missing-workspace-path",
        github_full_name: "owner/repo-conversation-missing-workspace-path",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/projects/#{project.id}", on_error: :warn)

    assert has_element?(view, "#project-detail-conversation-start[disabled]", "Start conversation")
    assert has_element?(view, "#project-detail-conversation-disabled-guidance")
    assert has_element?(view, "#project-detail-conversation-disabled-type", "code_server_workspace_unavailable")
    assert has_element?(view, "#project-detail-conversation-disabled-detail", "workspace path is missing")
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-project-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end
end
