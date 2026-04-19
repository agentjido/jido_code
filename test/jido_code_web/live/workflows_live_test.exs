defmodule JidoCodeWeb.WorkflowsLiveTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    original_workflow_definition_loader =
      Application.get_env(:jido_code, :workflow_manual_definition_loader, :__missing__)

    original_workflow_manual_run_launcher =
      Application.get_env(:jido_code, :workflow_manual_run_launcher, :__missing__)

    on_exit(fn ->
      restore_env(:workflow_manual_definition_loader, original_workflow_definition_loader)
      restore_env(:workflow_manual_run_launcher, original_workflow_manual_run_launcher)
    end)

    :ok
  end

  test "creates manual workflow runs with project trigger and input metadata plus run detail route",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    %{managed_repo: repo} =
      provision_managed_repo!(%{
        name: "repo-workflows",
        github_full_name: "owner/repo-workflows",
        default_branch: "main",
        workspace_settings: %{}
      })

    repo_id = repo.id

    launch_requests = start_supervised!({Agent, fn -> [] end})

    Application.put_env(:jido_code, :workflow_manual_definition_loader, fn ->
      {:ok, [workflow_definition("implement_task", 4)]}
    end)

    Application.put_env(:jido_code, :workflow_manual_run_launcher, fn kickoff_request ->
      Agent.update(launch_requests, fn requests -> [kickoff_request | requests] end)
      {:ok, %{run_id: "run-manual-123"}}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workflows", on_error: :warn)

    assert has_element?(view, "#workflows-manual-run-form")
    assert has_element?(view, "#workflows-project-id")
    assert has_element?(view, "#workflows-workflow-name")
    assert has_element?(view, "#workflows-input-task-summary")
    assert has_element?(view, "#workflows-start-run")
    assert has_element?(view, "#workflows-runs-empty-state")

    view
    |> form("#workflows-manual-run-form",
      run: %{
        repo_id: repo_id,
        workflow_name: "implement_task",
        task_summary: "Ship onboarding copy updates with tests."
      }
    )
    |> render_submit()

    assert has_element?(view, "#workflows-run-feedback-status", "Run creation succeeded.")
    assert has_element?(view, "#workflows-run-feedback-run-id", "run-manual-123")
    assert has_element?(view, "#workflows-run-feedback-workflow-version", "v4")

    assert has_element?(
             view,
             "#workflows-run-feedback-run-link[href='/repos/#{repo_id}/runs/run-manual-123']"
           )

    assert has_element?(view, "#workflows-run-id-run-manual-123", "run-manual-123")
    assert has_element?(view, "#workflows-run-workflow-run-manual-123", "implement_task")
    assert has_element?(view, "#workflows-run-workflow-version-run-manual-123", "v4")
    assert has_element?(view, "#workflows-run-project-run-manual-123", "repo-workflows")
    assert has_element?(view, "#workflows-run-trigger-run-manual-123", "/workflows")

    assert has_element?(
             view,
             "#workflows-run-detail-link-run-manual-123[href='/repos/#{repo_id}/runs/run-manual-123']"
           )

    refute has_element?(view, "#workflows-runs-empty-state")

    recorded_requests = launch_requests |> Agent.get(&Enum.reverse(&1))

    assert [
             %{
               workflow_name: "implement_task",
               workflow_version: 4,
               repo_id: ^repo_id,
               project_id: ^repo_id,
               repository_defaults: %{
                 default_branch: "main",
                 github_full_name: "owner/repo-workflows"
               },
               project_defaults: %{
                 default_branch: "main",
                 github_full_name: "owner/repo-workflows"
               },
               trigger: %{
                 source: "workflows",
                 mode: "manual",
                 source_row: %{
                   route: "/workflows",
                   repo_id: ^repo_id,
                   project_id: ^repo_id,
                   workflow_name: "implement_task",
                   workflow_version: 4
                 }
               },
               inputs: %{"task_summary" => "Ship onboarding copy updates with tests."},
               input_metadata: %{
                 "task_summary" => %{required: true, source: "manual_workflows_ui"}
               },
               initiating_actor: %{id: actor_id}
             }
           ] = recorded_requests

    assert is_binary(actor_id)
    refute actor_id == ""
    assert Map.has_key?(hd(recorded_requests).initiating_actor, :email)
  end

  test "missing required inputs return typed validation errors and do not create partial runs", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    %{managed_repo: repo} =
      provision_managed_repo!(%{
        name: "repo-validation",
        github_full_name: "owner/repo-validation",
        default_branch: "main",
        workspace_settings: %{}
      })

    launcher_invocations = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:jido_code, :workflow_manual_run_launcher, fn _kickoff_request ->
      Agent.update(launcher_invocations, &(&1 + 1))
      {:ok, %{run_id: "unexpected-run"}}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workflows", on_error: :warn)

    view
    |> form("#workflows-manual-run-form",
      run: %{
        repo_id: repo.id,
        workflow_name: "implement_task",
        task_summary: ""
      }
    )
    |> render_submit()

    assert has_element?(view, "#workflows-run-feedback-status", "Run creation failed.")

    assert has_element?(
             view,
             "#workflows-run-feedback-error-type",
             "workflow_run_validation_failed"
           )

    assert has_element?(
             view,
             "#workflows-run-feedback-error-detail",
             "required inputs are missing"
           )

    assert has_element?(view, "#workflows-run-feedback-field-errors", "task_summary")
    assert has_element?(view, "#workflows-run-feedback-field-errors", "required")

    refute has_element?(view, "#workflows-run-feedback-run-id")
    assert has_element?(view, "#workflows-runs-empty-state")
    assert Agent.get(launcher_invocations, & &1) == 0
  end

  defp workflow_definition(name, version) do
    %{
      name: name,
      version: version,
      label: "Implement task",
      description: "Plan and implement an operator-scoped coding task.",
      required_inputs: [
        %{
          name: :task_summary,
          label: "Task summary",
          placeholder: "Describe the task this run should implement."
        }
      ]
    }
  end
end
