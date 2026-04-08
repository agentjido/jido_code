defmodule JidoCodeWeb.WorkbenchLiveTest do
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Orchestration.{RunPubSub, WorkflowRun}
  alias JidoCode.Projects.Project

  setup do
    original_workbench_loader =
      Application.get_env(:jido_code, :workbench_inventory_loader, :__missing__)

    original_fix_workflow_launcher =
      Application.get_env(:jido_code, :workbench_fix_workflow_launcher, :__missing__)

    original_issue_triage_workflow_launcher =
      Application.get_env(:jido_code, :workbench_issue_triage_workflow_launcher, :__missing__)

    original_recent_run_outcome_loader =
      Application.get_env(:jido_code, :workbench_recent_run_outcome_loader, :__missing__)

    original_system_config_loader =
      Application.get_env(:jido_code, :system_config_loader, :__missing__)

    Application.put_env(:jido_code, :system_config_loader, fn ->
      {:ok,
       %{
         onboarding_completed: true,
         onboarding_step: 8,
         onboarding_state: %{},
         default_environment: :sprite,
         workspace_root: nil
       }}
    end)

    on_exit(fn ->
      restore_env(:workbench_inventory_loader, original_workbench_loader)
      restore_env(:workbench_fix_workflow_launcher, original_fix_workflow_launcher)

      restore_env(
        :workbench_issue_triage_workflow_launcher,
        original_issue_triage_workflow_launcher
      )

      restore_env(
        :workbench_recent_run_outcome_loader,
        original_recent_run_outcome_loader
      )

      restore_env(:system_config_loader, original_system_config_loader)
    end)

    :ok
  end

  test "renders cross-project workbench inventory rows with issue and PR counts plus activity summary",
       %{
         conn: _conn
       } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    repo_one_id = "owner-repo-one"
    repo_two_id = "owner-repo-two"

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: repo_one_id,
           name: "repo-one",
           github_full_name: "owner/repo-one",
           open_issue_count: 12,
           open_pr_count: 3,
           recent_activity_summary: "Triaged issues and queued follow-up in the last hour."
         },
         %{
           id: repo_two_id,
           name: "repo-two",
           github_full_name: "owner/repo-two",
           open_issue_count: 4,
           open_pr_count: 1,
           recent_activity_summary: "Last activity: 2026-02-13 16:00:00Z"
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(view, "#workbench-project-table")
    assert has_element?(view, "#workbench-project-name-#{repo_one_id}", "owner/repo-one")
    assert has_element?(view, "#workbench-project-open-issues-#{repo_one_id}", "12")
    assert has_element?(view, "#workbench-project-open-prs-#{repo_one_id}", "3")
    assert has_element?(view, "#workbench-project-issues-github-link-#{repo_one_id}")
    assert has_element?(view, "#workbench-project-issues-project-link-#{repo_one_id}")
    assert has_element?(view, "#workbench-project-prs-github-link-#{repo_one_id}")
    assert has_element?(view, "#workbench-project-prs-project-link-#{repo_one_id}")

    assert has_element?(
             view,
             "#workbench-project-issues-github-link-#{repo_one_id}[href='https://github.com/owner/repo-one/issues']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-github-link-#{repo_one_id}[href='https://github.com/owner/repo-one/pulls']"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-project-link-#{repo_one_id}[href='/repos/#{repo_one_id}']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-project-link-#{repo_one_id}[href='/repos/#{repo_one_id}']"
           )

    assert has_element?(
             view,
             "#workbench-project-recent-activity-#{repo_one_id}",
             "Triaged issues and queued follow-up in the last hour."
           )

    assert has_element?(view, "#workbench-project-name-#{repo_two_id}", "owner/repo-two")
    assert has_element?(view, "#workbench-project-open-issues-#{repo_two_id}", "4")
    assert has_element?(view, "#workbench-project-open-prs-#{repo_two_id}", "1")
    assert has_element?(view, "#workbench-project-issues-github-link-#{repo_two_id}")
    assert has_element?(view, "#workbench-project-issues-project-link-#{repo_two_id}")
    assert has_element?(view, "#workbench-project-prs-github-link-#{repo_two_id}")
    assert has_element?(view, "#workbench-project-prs-project-link-#{repo_two_id}")

    assert has_element?(
             view,
             "#workbench-project-issues-github-link-#{repo_two_id}[href='https://github.com/owner/repo-two/issues']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-github-link-#{repo_two_id}[href='https://github.com/owner/repo-two/pulls']"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-project-link-#{repo_two_id}[href='/repos/#{repo_two_id}']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-project-link-#{repo_two_id}[href='/repos/#{repo_two_id}']"
           )

    assert has_element?(view, "#workbench-project-recent-activity-#{repo_two_id}")

    refute has_element?(view, "#workbench-stale-warning")
  end

  test "renders recent run outcome indicators with run detail links for issue and PR context rows",
       %{
         conn: _conn
       } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-outcomes",
        github_full_name: "owner/repo-run-outcomes",
        default_branch: "main",
        settings: %{
          "inventory" => %{
            "open_issue_count" => 2,
            "open_pr_count" => 1,
            "recent_activity_summary" => "Recent automation signals are available."
          }
        }
      })

    route_id = managed_repo_route_id!(project.id)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, run} =
      create_workbench_run(
        project.id,
        "workbench-recent-run-#{System.unique_integer([:positive])}",
        DateTime.add(now, -180, :second)
      )

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "execute_changes",
        transitioned_at: DateTime.add(now, -120, :second)
      })

    {:ok, completed_run} =
      WorkflowRun.transition_status(run, %{
        to_status: :completed,
        current_step: "publish_pr",
        transitioned_at: DateTime.add(now, -60, :second)
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             view,
             "#workbench-project-issues-run-outcome-#{route_id}-status",
             "completed"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-run-outcome-#{route_id}-link[href='/repos/#{project.id}/runs/#{completed_run.run_id}']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-run-outcome-#{route_id}-status",
             "completed"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-run-outcome-#{route_id}-link[href='/repos/#{project.id}/runs/#{completed_run.run_id}']"
           )
  end

  test "refreshes run outcome indicators after kickoff and terminal run events", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-refresh",
        github_full_name: "owner/repo-run-refresh",
        default_branch: "main",
        settings: %{
          "inventory" => %{
            "open_issue_count" => 3,
            "open_pr_count" => 2,
            "recent_activity_summary" => "Outcome refresh signals are active."
          }
        }
      })

    route_id = managed_repo_route_id!(project.id)
    run_id = "workbench-refresh-run-#{System.unique_integer([:positive])}"
    run_detail_path = "/repos/#{route_id}/runs/#{run_id}"
    loader_state = start_supervised!({Agent, fn -> :initial end}, id: make_ref())

    Application.put_env(:jido_code, :workbench_recent_run_outcome_loader, fn _rows ->
      case Agent.get(loader_state, & &1) do
        :terminal ->
          %{
            route_id => %{
              status: "completed",
              run_id: run_id,
              detail_path: run_detail_path
            }
          }

        _other ->
          %{}
      end
    end)

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn _kickoff_request ->
      {:ok, %{run_id: run_id}}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             view,
             "#workbench-project-issues-run-outcome-#{route_id}-status",
             "No recent run"
           )

    view
    |> element("#workbench-project-issues-fix-action-#{route_id}")
    |> render_click()

    assert has_element?(
             view,
             "#workbench-project-issues-run-outcome-#{route_id}-status",
             "pending"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-run-outcome-#{route_id}-link[href='#{run_detail_path}']"
           )

    Agent.update(loader_state, fn _current_state -> :terminal end)

    assert :ok =
             RunPubSub.broadcast_run_event(run_id, %{
               "event" => "run_completed",
               "run_id" => run_id
             })

    assert_eventually(fn ->
      has_element?(
        view,
        "#workbench-project-issues-run-outcome-#{route_id}-status",
        "completed"
      )
    end)

    assert has_element?(
             view,
             "#workbench-project-prs-run-outcome-#{route_id}-status",
             "completed"
           )
  end

  test "shows unknown run outcome state with refresh guidance when status is unresolved", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-unknown-outcome",
        github_full_name: "owner/repo-unknown-outcome",
        default_branch: "main",
        settings: %{
          "inventory" => %{
            "open_issue_count" => 4,
            "open_pr_count" => 0,
            "recent_activity_summary" => "Run status resolution failed."
          }
        }
      })

    route_id = managed_repo_route_id!(project.id)

    Application.put_env(:jido_code, :workbench_recent_run_outcome_loader, fn _rows ->
      %{
        route_id => %{
          status: "mystery_status",
          run_id: "run-unknown-#{System.unique_integer([:positive])}",
          detail: "Recent run metadata is incomplete.",
          error_type: "workbench_recent_run_status_unresolved",
          guidance: "Refresh workbench data to resolve recent run status."
        }
      }
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             view,
             "#workbench-project-issues-run-outcome-#{route_id}-status",
             "unknown"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-run-outcome-#{route_id}-error-type",
             "workbench_recent_run_status_unresolved"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-run-outcome-#{route_id}-guidance",
             "Refresh workbench data"
           )
  end

  test "shows stale-state warning and recovery actions when workbench data fetch fails", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    # LiveView mounts twice (disconnected + connected), so fail both initial loads
    # and recover on explicit retry.
    loader_state = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      Agent.get_and_update(loader_state, fn
        call_count when call_count < 2 ->
          warning = %{
            error_type: "workbench_data_fetch_failed",
            detail: "GitHub inventory sync timed out and current counts may be stale.",
            remediation: "Retry workbench fetch and review setup diagnostics if the issue persists."
          }

          {{:error, warning}, call_count + 1}

        call_count ->
          rows = [
            %{
              id: "owner-repo-recovered",
              name: "repo-recovered",
              github_full_name: "owner/repo-recovered",
              open_issue_count: 7,
              open_pr_count: 2,
              recent_activity_summary: "Recovery refresh completed."
            }
          ]

          {{:ok, rows, nil}, call_count + 1}
      end)
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(view, "#workbench-stale-warning")
    assert has_element?(view, "#workbench-stale-warning-type", "workbench_data_fetch_failed")
    assert has_element?(view, "#workbench-stale-warning-detail", "counts may be stale")
    assert has_element?(view, "#workbench-stale-warning-remediation", "Retry workbench fetch")
    assert has_element?(view, "#workbench-retry-fetch")
    assert has_element?(view, "#workbench-open-setup-recovery")

    view
    |> element("#workbench-retry-fetch")
    |> render_click()

    refute has_element?(view, "#workbench-stale-warning")

    assert has_element?(
             view,
             "#workbench-project-name-owner-repo-recovered",
             "owner/repo-recovered"
           )

    assert has_element?(view, "#workbench-project-open-issues-owner-repo-recovered", "7")
    assert has_element?(view, "#workbench-project-open-prs-owner-repo-recovered", "2")

    assert has_element?(
             view,
             "#workbench-project-recent-activity-owner-repo-recovered",
             "Recovery refresh completed."
           )
  end

  test "shows disabled link states with explanations when row link targets are unavailable", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "",
           name: "repo-with-missing-links",
           github_full_name: "",
           open_issue_count: 2,
           open_pr_count: 1,
           recent_activity_summary: "No metadata available for links."
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             view,
             "[id^='workbench-project-issues-github-disabled-workbench-row-'][aria-disabled='true']",
             "GitHub issues"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-issues-github-disabled-reason-workbench-row-']",
             "GitHub repository URL is unavailable for this row."
           )

    assert has_element?(
             view,
             "[id^='workbench-project-prs-github-disabled-workbench-row-'][aria-disabled='true']",
             "GitHub PRs"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-prs-github-disabled-reason-workbench-row-']",
             "GitHub repository URL is unavailable for this row."
           )

    assert has_element?(
             view,
             "[id^='workbench-project-issues-project-disabled-workbench-row-'][aria-disabled='true']",
             "Repo detail"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-issues-project-disabled-reason-workbench-row-']",
             "Repo detail link is unavailable for this row."
           )

    assert has_element?(
             view,
             "[id^='workbench-project-prs-project-disabled-workbench-row-'][aria-disabled='true']",
             "Repo detail"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-prs-project-disabled-reason-workbench-row-']",
             "Repo detail link is unavailable for this row."
           )

    refute has_element?(view, "[id^='workbench-project-issues-github-link-workbench-row-']")
    refute has_element?(view, "[id^='workbench-project-prs-github-link-workbench-row-']")
    refute has_element?(view, "[id^='workbench-project-issues-project-link-workbench-row-']")
    refute has_element?(view, "[id^='workbench-project-prs-project-link-workbench-row-']")
  end

  test "issue and PR quick actions kick off fix workflow runs with tracked run links", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-fixable",
        github_full_name: "owner/repo-fixable",
        default_branch: "main",
        settings: %{
          "inventory" => %{
            "open_issue_count" => 5,
            "open_pr_count" => 2,
            "recent_activity_summary" => "Actionable queue."
          }
        }
      })

    project_id = project.id
    route_id = managed_repo_route_id!(project_id)
    launcher_requests = start_supervised!({Agent, fn -> [] end})

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn kickoff_request ->
      Agent.update(launcher_requests, fn requests -> [kickoff_request | requests] end)

      run_id =
        case kickoff_request.context_item.type do
          :issue -> "run-issue-123"
          :pull_request -> "run-pr-456"
        end

      {:ok, %{run_id: run_id}}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(view, "#workbench-project-issues-fix-action-#{route_id}")
    assert has_element?(view, "#workbench-project-prs-fix-action-#{route_id}")

    view
    |> element("#workbench-project-issues-fix-action-#{route_id}")
    |> render_click()

    assert has_element?(
             view,
             "#workbench-project-issues-fix-#{route_id}-run-id",
             "run-issue-123"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-fix-#{route_id}-run-link[href='/repos/#{route_id}/runs/run-issue-123']"
           )

    refute has_element?(view, "#workbench-project-issues-fix-#{route_id}-error-type")

    view
    |> element("#workbench-project-prs-fix-action-#{route_id}")
    |> render_click()

    assert has_element?(view, "#workbench-project-prs-fix-#{route_id}-run-id", "run-pr-456")

    assert has_element?(
             view,
             "#workbench-project-prs-fix-#{route_id}-run-link[href='/repos/#{route_id}/runs/run-pr-456']"
           )

    refute has_element?(view, "#workbench-project-prs-fix-#{route_id}-error-type")

    recorded_requests = launcher_requests |> Agent.get(&Enum.reverse(&1))

    assert [
             %{
               project_id: ^route_id,
               workflow_name: "fix_failing_tests",
               context_item: %{type: :issue}
             },
             %{
               project_id: ^route_id,
               workflow_name: "fix_failing_tests",
               context_item: %{type: :pull_request}
             }
           ] = recorded_requests
  end

  test "issue triage quick action starts issue_triage with manual trigger metadata and initiating actor",
       %{
         conn: _conn
       } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-triageable",
        github_full_name: "owner/repo-triageable",
        default_branch: "main",
        settings: %{
          "inventory" => %{
            "open_issue_count" => 6,
            "open_pr_count" => 1,
            "recent_activity_summary" => "Issue queue needs triage."
          },
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "approval_mode" => "auto_post"
            }
          }
        }
      })

    project_id = project.id
    route_id = managed_repo_route_id!(project_id)
    launcher_requests = start_supervised!({Agent, fn -> [] end})

    Application.put_env(
      :jido_code,
      :workbench_issue_triage_workflow_launcher,
      fn kickoff_request ->
        Agent.update(launcher_requests, fn requests -> [kickoff_request | requests] end)
        {:ok, %{run_id: "run-triage-789"}}
      end
    )

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(view, "#workbench-project-issues-triage-action-#{route_id}")

    view
    |> element("#workbench-project-issues-triage-action-#{route_id}")
    |> render_click()

    assert has_element?(
             view,
             "#workbench-project-issues-triage-#{route_id}-run-id",
             "run-triage-789"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-triage-#{route_id}-run-link[href='/repos/#{route_id}/runs/run-triage-789']"
           )

    refute has_element?(view, "#workbench-project-issues-triage-#{route_id}-error-type")

    recorded_requests = launcher_requests |> Agent.get(&Enum.reverse(&1))

    assert [
             %{
               project_id: ^route_id,
               workflow_name: "issue_triage",
               context_item: %{type: :issue},
               trigger: %{
                 source: "workbench",
                 mode: "manual",
                 source_row: %{
                   route: "/workbench",
                   project_id: ^route_id,
                   context_item_type: :issue
                 },
                 approval_policy: %{
                   mode: "auto_post",
                   post_behavior: "auto_post",
                   auto_post: true,
                   requires_approval: false
                 }
               },
               initiating_actor: %{id: actor_id}
             }
           ] = recorded_requests

    assert Map.has_key?(hd(recorded_requests).initiating_actor, :email)
    assert is_binary(actor_id)
    refute actor_id == ""
  end

  test "triage action disabled by policy shows blocking policy state in workbench UI", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-policy-blocked",
           name: "repo-policy-blocked",
           github_full_name: "owner/repo-policy-blocked",
           open_issue_count: 3,
           open_pr_count: 0,
           recent_activity_summary: "Policy blocks issue triage launches.",
           issue_triage_policy: %{
             enabled: false,
             policy: "support_agent_config.github_issue_bot.enabled",
             error_type: "issue_triage_policy_disabled",
             detail: "Issue triage workflow launches are disabled for this project.",
             remediation: "Enable Issue Bot for this project to allow manual triage launches."
           }
         }
       ], nil}
    end)

    launcher_invocations = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(
      :jido_code,
      :workbench_issue_triage_workflow_launcher,
      fn _kickoff_request ->
        Agent.update(launcher_invocations, &(&1 + 1))
        {:ok, %{run_id: "unexpected-run"}}
      end
    )

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             view,
             "#workbench-project-issues-triage-disabled-owner-repo-policy-blocked[aria-disabled='true']",
             "Kick off issue triage workflow"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-triage-disabled-owner-repo-policy-blocked-type",
             "issue_triage_policy_disabled"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-triage-disabled-owner-repo-policy-blocked-reason",
             "disabled for this project"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-triage-disabled-owner-repo-policy-blocked-remediation",
             "Enable Issue Bot"
           )

    refute has_element?(view, "#workbench-project-issues-triage-action-owner-repo-policy-blocked")
    assert Agent.get(launcher_invocations, & &1) == 0
  end

  test "inline kickoff validation failures render details and do not create runs", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "",
           name: "repo-without-id",
           github_full_name: "owner/repo-without-id",
           open_issue_count: 1,
           open_pr_count: 1,
           recent_activity_summary: "Missing repo scope."
         }
       ], nil}
    end)

    launcher_invocations = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn _kickoff_request ->
      Agent.update(launcher_invocations, &(&1 + 1))
      {:ok, %{run_id: "unexpected-run"}}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(view, "[id^='workbench-project-issues-fix-action-workbench-row-']")
    assert has_element?(view, "[id^='workbench-project-prs-fix-action-workbench-row-']")

    view
    |> element("[id^='workbench-project-issues-fix-action-workbench-row-']")
    |> render_click()

    assert has_element?(
             view,
             "[id^='workbench-project-name-workbench-row-']",
             "owner/repo-without-id"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-issues-fix-workbench-row-'][id$='-status']",
             "Kickoff failed"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-issues-fix-workbench-row-'][id$='-error-type']",
             "workbench_fix_workflow_validation_failed"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-issues-fix-workbench-row-'][id$='-error-detail']",
             "synthetic"
           )

    assert has_element?(
             view,
             "[id^='workbench-project-issues-fix-workbench-row-'][id$='-error-remediation']"
           )

    refute has_element?(
             view,
             "[id^='workbench-project-issues-fix-workbench-row-'][id$='-run-id']"
           )

    assert Agent.get(launcher_invocations, & &1) == 0
  end

  test "network interruption after kickoff resolves explicit run creation state", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-network-resolution",
        github_full_name: "owner/repo-network-resolution",
        default_branch: "main",
        settings: %{
          "inventory" => %{
            "open_issue_count" => 2,
            "open_pr_count" => 1,
            "recent_activity_summary" => "Kickoff retries are active."
          }
        }
      })

    project_id = project.id
    route_id = managed_repo_route_id!(project_id)

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn _kickoff_request ->
      {:error,
       %{
         error_type: "workbench_fix_workflow_kickoff_interrupted",
         detail: "Network interruption occurred after kickoff request.",
         remediation: "Open the resolved run and continue monitoring there.",
         run_creation_state: :created,
         run_id: "run-recovered-789"
       }}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    view
    |> element("#workbench-project-issues-fix-action-#{route_id}")
    |> render_click()

    assert has_element?(
             view,
             "#workbench-project-name-#{route_id}",
             "owner/repo-network-resolution"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-fix-#{route_id}-status",
             "Kickoff confirmed after interruption"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-fix-#{route_id}-run-id",
             "run-recovered-789"
           )

    assert has_element?(
             view,
             "#workbench-project-issues-fix-#{route_id}-run-link[href='/repos/#{route_id}/runs/run-recovered-789']"
           )

    refute has_element?(view, "#workbench-project-issues-fix-#{route_id}-error-type")
  end

  test "applies project, state, and freshness filters without route changes", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    now = DateTime.utc_now()

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-alpha",
           name: "repo-alpha",
           github_full_name: "owner/repo-alpha",
           open_issue_count: 5,
           open_pr_count: 0,
           recent_activity_summary: "Alpha summary",
           recent_activity_at: DateTime.add(now, -45 * 24 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-beta",
           name: "repo-beta",
           github_full_name: "owner/repo-beta",
           open_issue_count: 0,
           open_pr_count: 4,
           recent_activity_summary: "Beta summary",
           recent_activity_at: DateTime.add(now, -2 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-gamma",
           name: "repo-gamma",
           github_full_name: "owner/repo-gamma",
           open_issue_count: 2,
           open_pr_count: 1,
           recent_activity_summary: "Gamma summary",
           recent_activity_at: DateTime.add(now, -10 * 24 * 60 * 60, :second) |> DateTime.to_iso8601()
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    vue = assert_vue_component(view, "WorkbenchSummaryWidget", id: "workbench-summary-widget")

    assert vue.props["inventoryCount"] == 3
    assert vue.props["inventoryTotalCount"] == 3
    assert vue.props["resetVisible"] == false
    assert_vue_handler(view, "resetFilters", "reset_filters", id: "workbench-summary-widget")

    assert has_element?(view, "#workbench-filters-form")
    assert has_element?(view, "#workbench-project-name-owner-repo-alpha", "owner/repo-alpha")
    assert has_element?(view, "#workbench-project-name-owner-repo-beta", "owner/repo-beta")
    assert has_element?(view, "#workbench-project-name-owner-repo-gamma", "owner/repo-gamma")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 3 of 3")

    apply_workbench_filters(view, %{"project_id" => "owner-repo-beta"})

    assert has_element?(view, "#workbench-filters-form")
    assert has_element?(view, "#workbench-project-name-owner-repo-beta", "owner/repo-beta")
    refute has_element?(view, "#workbench-project-name-owner-repo-alpha")
    refute has_element?(view, "#workbench-project-name-owner-repo-gamma")
    assert has_element?(view, "#workbench-filter-chip-project", "owner/repo-beta")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 1 of 3")

    filtered_vue = vue(view, id: "workbench-summary-widget")

    assert filtered_vue.props["inventoryCount"] == 1
    assert filtered_vue.props["resetVisible"] == true

    apply_workbench_filters(view, %{"work_state" => "issues_open"})

    assert has_element?(view, "#workbench-filters-form")
    assert has_element?(view, "#workbench-project-name-owner-repo-alpha", "owner/repo-alpha")
    refute has_element?(view, "#workbench-project-name-owner-repo-beta")
    assert has_element?(view, "#workbench-project-name-owner-repo-gamma", "owner/repo-gamma")
    assert has_element?(view, "#workbench-filter-chip-work-state", "Issues open")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 2 of 3")

    apply_workbench_filters(view, %{"freshness_window" => "stale_30d"})

    assert has_element?(view, "#workbench-filters-form")
    assert has_element?(view, "#workbench-project-name-owner-repo-alpha", "owner/repo-alpha")
    refute has_element?(view, "#workbench-project-name-owner-repo-beta")
    refute has_element?(view, "#workbench-project-name-owner-repo-gamma")
    assert has_element?(view, "#workbench-filter-chip-freshness-window", "Stale for 30+ days")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 1 of 3")
  end

  test "supports backlog and recent activity sort ordering with deterministic results", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    now = DateTime.utc_now()

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-alpha",
           name: "repo-alpha",
           github_full_name: "owner/repo-alpha",
           open_issue_count: 2,
           open_pr_count: 1,
           recent_activity_summary: "Alpha summary",
           recent_activity_at: DateTime.add(now, -2 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-beta",
           name: "repo-beta",
           github_full_name: "owner/repo-beta",
           open_issue_count: 5,
           open_pr_count: 4,
           recent_activity_summary: "Beta summary",
           recent_activity_at: DateTime.add(now, -9 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-gamma",
           name: "repo-gamma",
           github_full_name: "owner/repo-gamma",
           open_issue_count: 1,
           open_pr_count: 0,
           recent_activity_summary: "Gamma summary",
           recent_activity_at: DateTime.add(now, -60 * 60, :second) |> DateTime.to_iso8601()
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             view,
             "#workbench-filter-sort-order option[value='backlog_desc']",
             "Backlog size (highest first)"
           )

    assert has_element?(
             view,
             "#workbench-filter-sort-order option[value='recent_activity_desc']",
             "Recent activity (most recent first)"
           )

    apply_workbench_filters(view, %{"sort_order" => "backlog_desc"})

    assert_project_row_order(view, ["owner-repo-beta", "owner-repo-alpha", "owner-repo-gamma"])

    apply_workbench_filters(view, %{"sort_order" => "backlog_desc"})

    assert_project_row_order(view, ["owner-repo-beta", "owner-repo-alpha", "owner-repo-gamma"])

    apply_workbench_filters(view, %{"sort_order" => "recent_activity_desc"})

    assert_project_row_order(view, ["owner-repo-gamma", "owner-repo-alpha", "owner-repo-beta"])

    assert has_element?(
             view,
             "#workbench-filter-chip-sort-order",
             "Recent activity (most recent first)"
           )
  end

  test "keeps selected sort order after retry refresh events", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    stale_warning = %{
      error_type: "workbench_refresh_state_warning",
      detail: "Refresh is available.",
      remediation: "Use retry to refresh data."
    }

    loader_state = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      Agent.get_and_update(loader_state, fn call_count ->
        rows =
          if call_count < 2 do
            [
              %{
                id: "owner-repo-alpha",
                name: "repo-alpha",
                github_full_name: "owner/repo-alpha",
                open_issue_count: 5,
                open_pr_count: 0,
                recent_activity_summary: "Alpha summary"
              },
              %{
                id: "owner-repo-beta",
                name: "repo-beta",
                github_full_name: "owner/repo-beta",
                open_issue_count: 2,
                open_pr_count: 0,
                recent_activity_summary: "Beta summary"
              },
              %{
                id: "owner-repo-gamma",
                name: "repo-gamma",
                github_full_name: "owner/repo-gamma",
                open_issue_count: 1,
                open_pr_count: 0,
                recent_activity_summary: "Gamma summary"
              }
            ]
          else
            [
              %{
                id: "owner-repo-alpha",
                name: "repo-alpha",
                github_full_name: "owner/repo-alpha",
                open_issue_count: 0,
                open_pr_count: 0,
                recent_activity_summary: "Alpha refreshed summary"
              },
              %{
                id: "owner-repo-beta",
                name: "repo-beta",
                github_full_name: "owner/repo-beta",
                open_issue_count: 4,
                open_pr_count: 2,
                recent_activity_summary: "Beta refreshed summary"
              },
              %{
                id: "owner-repo-gamma",
                name: "repo-gamma",
                github_full_name: "owner/repo-gamma",
                open_issue_count: 3,
                open_pr_count: 0,
                recent_activity_summary: "Gamma refreshed summary"
              }
            ]
          end

        {{:ok, rows, stale_warning}, call_count + 1}
      end)
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    apply_workbench_filters(view, %{"sort_order" => "backlog_desc"})
    assert_project_row_order(view, ["owner-repo-alpha", "owner-repo-beta", "owner-repo-gamma"])

    view
    |> element("#workbench-retry-fetch")
    |> render_click()

    assert_project_row_order(view, ["owner-repo-beta", "owner-repo-gamma", "owner-repo-alpha"])

    assert has_element?(
             view,
             "#workbench-filter-sort-order option[value='backlog_desc'][selected]"
           )

    assert has_element?(view, "#workbench-filter-chip-sort-order", "Backlog size (highest first)")
  end

  test "falls back to default sort order with notice when sort data is malformed", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-beta",
           name: "repo-beta",
           github_full_name: "owner/repo-beta",
           open_issue_count: 3,
           open_pr_count: 1,
           recent_activity_summary: "Beta summary"
         },
         :invalid_row_payload
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    refute has_element?(view, "#workbench-sort-validation-notice")

    apply_workbench_filters(view, %{"sort_order" => "backlog_desc"})

    assert has_element?(view, "#workbench-sort-validation-notice")

    assert has_element?(
             view,
             "#workbench-sort-validation-type",
             "workbench_sort_order_fallback"
           )

    assert has_element?(view, "#workbench-sort-validation-detail", "Backlog size (highest first)")
    assert has_element?(view, "#workbench-filter-chip-sort-order", "Repository name (A-Z)")

    assert has_element?(
             view,
             "#workbench-filter-sort-order option[value='project_name_asc'][selected]"
           )

    assert_project_row_order(view, ["owner-repo-beta", "workbench-row-2"])
  end

  test "invalid filter values reset defaults and show typed validation notice", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-one",
           name: "repo-one",
           github_full_name: "owner/repo-one",
           open_issue_count: 1,
           open_pr_count: 0,
           recent_activity_summary: "Repo one summary"
         },
         %{
           id: "owner-repo-two",
           name: "repo-two",
           github_full_name: "owner/repo-two",
           open_issue_count: 0,
           open_pr_count: 2,
           recent_activity_summary: "Repo two summary"
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    view
    |> element("#workbench-filters-form")
    |> render_change(%{
      "filters" => %{
        "project_id" => "owner-repo-missing",
        "work_state" => "broken-state",
        "freshness_window" => "future-only"
      }
    })

    assert has_element?(view, "#workbench-filter-validation-notice")

    assert has_element?(
             view,
             "#workbench-filter-validation-type",
             "workbench_filter_values_invalid"
           )

    assert has_element?(view, "#workbench-filter-validation-detail", "project_id")
    assert has_element?(view, "#workbench-filter-chip-project", "All repositories")
    assert has_element?(view, "#workbench-filter-chip-work-state", "Any issue or PR state")
    assert has_element?(view, "#workbench-filter-chip-freshness-window", "Any freshness")
    assert has_element?(view, "#workbench-filter-chip-sort-order", "Repository name (A-Z)")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 2 of 2")
    assert has_element?(view, "#workbench-project-name-owner-repo-one", "owner/repo-one")
    assert has_element?(view, "#workbench-project-name-owner-repo-two", "owner/repo-two")
    assert has_element?(view, "#workbench-filter-project option[value='all'][selected]")
    assert has_element?(view, "#workbench-filter-work-state option[value='all'][selected]")
    assert has_element?(view, "#workbench-filter-freshness-window option[value='any'][selected]")

    assert has_element?(
             view,
             "#workbench-filter-sort-order option[value='project_name_asc'][selected]"
           )
  end

  test "preserves filter and sort state across navigation context and restores from workbench URL",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    now = DateTime.utc_now()

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-alpha",
           name: "repo-alpha",
           github_full_name: "owner/repo-alpha",
           open_issue_count: 2,
           open_pr_count: 0,
           recent_activity_summary: "Alpha summary",
           recent_activity_at: DateTime.add(now, -10 * 24 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-beta",
           name: "repo-beta",
           github_full_name: "owner/repo-beta",
           open_issue_count: 0,
           open_pr_count: 3,
           recent_activity_summary: "Beta summary",
           recent_activity_at: DateTime.add(now, -3 * 60 * 60, :second) |> DateTime.to_iso8601()
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    apply_workbench_filters(view, %{
      "project_id" => "owner-repo-beta",
      "work_state" => "prs_open",
      "freshness_window" => "active_24h",
      "sort_order" => "recent_activity_desc"
    })

    workbench_state_path =
      "/workbench?project_id=owner-repo-beta&work_state=prs_open&freshness_window=active_24h&sort_order=recent_activity_desc"

    assert_patch(view, workbench_state_path)
    assert has_element?(view, "#workbench-project-name-owner-repo-beta")
    refute has_element?(view, "#workbench-project-name-owner-repo-alpha")

    encoded_return_to = URI.encode_www_form(workbench_state_path)

    assert has_element?(
             view,
             "#workbench-project-issues-project-link-owner-repo-beta[href='/repos/owner-repo-beta?return_to=#{encoded_return_to}']"
           )

    assert has_element?(
             view,
             "#workbench-project-prs-project-link-owner-repo-beta[href='/repos/owner-repo-beta?return_to=#{encoded_return_to}']"
           )

    {:ok, restored_view, _html} =
      live(recycle(authed_conn), workbench_state_path, on_error: :warn)

    assert has_element?(restored_view, "#workbench-project-name-owner-repo-beta")
    refute has_element?(restored_view, "#workbench-project-name-owner-repo-alpha")
    assert has_element?(restored_view, "#workbench-filter-chip-project", "owner/repo-beta")
    assert has_element?(restored_view, "#workbench-filter-chip-work-state", "PRs open")

    assert has_element?(
             restored_view,
             "#workbench-filter-chip-freshness-window",
             "Active in last 24 hours"
           )

    assert has_element?(
             restored_view,
             "#workbench-filter-chip-sort-order",
             "Recent activity (most recent first)"
           )

    assert has_element?(
             restored_view,
             "#workbench-filter-project option[value='owner-repo-beta'][selected]"
           )

    assert has_element?(
             restored_view,
             "#workbench-filter-work-state option[value='prs_open'][selected]"
           )

    assert has_element?(
             restored_view,
             "#workbench-filter-freshness-window option[value='active_24h'][selected]"
           )

    assert has_element?(
             restored_view,
             "#workbench-filter-sort-order option[value='recent_activity_desc'][selected]"
           )
  end

  test "invalid restored workbench state falls back to defaults with a reset reason notice", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-one",
           name: "repo-one",
           github_full_name: "owner/repo-one",
           open_issue_count: 1,
           open_pr_count: 0,
           recent_activity_summary: "Repo one summary"
         },
         %{
           id: "owner-repo-two",
           name: "repo-two",
           github_full_name: "owner/repo-two",
           open_issue_count: 0,
           open_pr_count: 2,
           recent_activity_summary: "Repo two summary"
         }
       ], nil}
    end)

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        "/workbench?project_id=owner-repo-missing&sort_order=backlog_desc",
        on_error: :warn
      )

    assert has_element?(view, "#workbench-filter-validation-notice")

    assert has_element?(
             view,
             "#workbench-filter-validation-type",
             "workbench_filter_restore_state_invalid"
           )

    assert has_element?(view, "#workbench-filter-validation-detail", "project_id")
    assert has_element?(view, "#workbench-filter-chip-project", "All repositories")
    assert has_element?(view, "#workbench-filter-chip-work-state", "Any issue or PR state")
    assert has_element?(view, "#workbench-filter-chip-freshness-window", "Any freshness")
    assert has_element?(view, "#workbench-filter-chip-sort-order", "Repository name (A-Z)")
    assert has_element?(view, "#workbench-filter-project option[value='all'][selected]")
    assert has_element?(view, "#workbench-filter-work-state option[value='all'][selected]")
    assert has_element?(view, "#workbench-filter-freshness-window option[value='any'][selected]")

    assert has_element?(
             view,
             "#workbench-filter-sort-order option[value='project_name_asc'][selected]"
           )

    assert has_element?(view, "#workbench-project-name-owner-repo-one", "owner/repo-one")
    assert has_element?(view, "#workbench-project-name-owner-repo-two", "owner/repo-two")
  end

  defp create_workbench_run(project_id, run_id, started_at) do
    WorkflowRun.create(%{
      project_id: project_id,
      run_id: run_id,
      workflow_name: "fix_failing_tests",
      workflow_version: 1,
      trigger: %{source: "workbench", mode: "manual"},
      inputs: %{"failure_signal" => "workbench indicator test"},
      input_metadata: %{"failure_signal" => %{required: true, source: "workbench_quick_action"}},
      initiating_actor: %{id: "owner-1", email: "owner@example.com"},
      current_step: "queued",
      started_at: started_at
    })
  end

  defp managed_repo_route_id!(legacy_project_id) do
    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(legacy_project_id, actor: Actor.operator_actor())

    managed_repo.id
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

  defp apply_workbench_filters(view, overrides) do
    filter_params = Map.merge(default_workbench_filter_params(), overrides)

    view
    |> element("#workbench-filters-form")
    |> render_change(%{"filters" => filter_params})
  end

  defp default_workbench_filter_params do
    %{
      "project_id" => "all",
      "work_state" => "all",
      "freshness_window" => "any",
      "sort_order" => "project_name_asc"
    }
  end

  defp assert_project_row_order(view, row_ids) when is_list(row_ids) do
    row_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {row_id, index} ->
      assert has_element?(
               view,
               "#workbench-project-rows tr:nth-child(#{index}) #workbench-project-name-#{row_id}"
             )
    end)
  end
end
