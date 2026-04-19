defmodule JidoCode.WorkflowRuntime.ManualRunKickoffTest do
  use ExUnit.Case, async: false

  alias JidoCode.WorkflowRuntime.ManualRunKickoff

  setup do
    original_definition_loader =
      Application.get_env(:jido_code, :workflow_manual_definition_loader, :__missing__)

    original_repository_loader =
      Application.get_env(:jido_code, :workflow_manual_repository_loader, :__missing__)

    original_project_loader =
      Application.get_env(:jido_code, :workflow_manual_project_loader, :__missing__)

    original_run_launcher =
      Application.get_env(:jido_code, :workflow_manual_run_launcher, :__missing__)

    on_exit(fn ->
      restore_env(:workflow_manual_definition_loader, original_definition_loader)
      restore_env(:workflow_manual_repository_loader, original_repository_loader)
      restore_env(:workflow_manual_project_loader, original_project_loader)
      restore_env(:workflow_manual_run_launcher, original_run_launcher)
    end)

    :ok
  end

  test "kickoff pins workflow version in launch metadata and run result" do
    repo_id = "repo-123"
    requests = start_supervised!({Agent, fn -> [] end})

    Application.put_env(:jido_code, :workflow_manual_definition_loader, fn ->
      {:ok, [workflow_definition("implement_task", 7)]}
    end)

    Application.put_env(:jido_code, :workflow_manual_repository_loader, fn ->
      {:ok,
       [
         %{
           id: repo_id,
           managed_repo_id: repo_id,
           legacy_project_id: repo_id,
           name: "repo-workflows",
           github_full_name: "owner/repo-workflows",
           default_branch: "main"
         }
       ]}
    end)

    Application.put_env(:jido_code, :workflow_manual_run_launcher, fn kickoff_request ->
      Agent.update(requests, fn collected -> [kickoff_request | collected] end)
      {:ok, %{run_id: "run-manual-123", workflow_version: 99}}
    end)

    {:ok, kickoff_run} =
      ManualRunKickoff.kickoff(
        %{
          "repo_id" => repo_id,
          "workflow_name" => "implement_task",
          "task_summary" => "Ship onboarding updates."
        },
        %{id: "owner-1", email: "owner@example.com"}
      )

    assert kickoff_run.run_id == "run-manual-123"
    assert kickoff_run.workflow_name == "implement_task"
    assert kickoff_run.workflow_version == 7
    assert kickoff_run.repo_id == repo_id
    assert kickoff_run.project_id == repo_id
    assert kickoff_run.detail_path == "/repos/#{repo_id}/runs/run-manual-123"

    recorded_requests = requests |> Agent.get(&Enum.reverse(&1))

    assert [
             %{
               workflow_name: "implement_task",
               workflow_version: 7,
               repo_id: ^repo_id,
               project_id: ^repo_id,
               repository_defaults: %{
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
                   workflow_version: 7
                 }
               },
               inputs: %{"task_summary" => "Ship onboarding updates."},
               input_metadata: %{
                 "task_summary" => %{required: true, source: "manual_workflows_ui"}
               },
               initiating_actor: %{id: "owner-1", email: "owner@example.com"}
             }
           ] = recorded_requests
  end

  test "workflow version is pinned per run even when definitions change after kickoff" do
    repo_id = "repo-789"

    definition_version =
      start_supervised!({Agent, fn -> 1 end}, id: :workflow_definition_version_agent)

    requests = start_supervised!({Agent, fn -> [] end}, id: :workflow_definition_requests_agent)

    Application.put_env(:jido_code, :workflow_manual_definition_loader, fn ->
      current_version = Agent.get(definition_version, & &1)
      {:ok, [workflow_definition("implement_task", current_version)]}
    end)

    Application.put_env(:jido_code, :workflow_manual_repository_loader, fn ->
      {:ok,
       [
         %{
           id: repo_id,
           managed_repo_id: repo_id,
           legacy_project_id: repo_id,
           name: "repo-pinned",
           github_full_name: "owner/repo-pinned",
           default_branch: "main"
         }
       ]}
    end)

    Application.put_env(:jido_code, :workflow_manual_run_launcher, fn kickoff_request ->
      Agent.update(requests, fn collected -> [kickoff_request | collected] end)
      {:ok, %{run_id: "run-#{kickoff_request.workflow_version}"}}
    end)

    {:ok, first_run} =
      ManualRunKickoff.kickoff(
        %{
          "repo_id" => repo_id,
          "workflow_name" => "implement_task",
          "task_summary" => "Initial run."
        },
        %{id: "owner-1", email: "owner@example.com"}
      )

    Agent.update(definition_version, fn _current -> 2 end)

    {:ok, second_run} =
      ManualRunKickoff.kickoff(
        %{
          "repo_id" => repo_id,
          "workflow_name" => "implement_task",
          "task_summary" => "Second run."
        },
        %{id: "owner-1", email: "owner@example.com"}
      )

    assert first_run.run_id == "run-1"
    assert first_run.workflow_version == 1
    assert second_run.run_id == "run-2"
    assert second_run.workflow_version == 2

    recorded_requests = requests |> Agent.get(&Enum.reverse(&1))

    assert [
             %{workflow_version: 1, workflow_name: "implement_task"},
             %{workflow_version: 2, workflow_name: "implement_task"}
           ] = recorded_requests
  end

  test "missing required inputs returns typed validation error and does not invoke launcher" do
    repo_id = "repo-456"
    launcher_invocations = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:jido_code, :workflow_manual_repository_loader, fn ->
      {:ok,
       [
         %{
           id: repo_id,
           managed_repo_id: repo_id,
           legacy_project_id: repo_id,
           name: "repo-validation",
           github_full_name: "owner/repo-validation",
           default_branch: "main"
         }
       ]}
    end)

    Application.put_env(:jido_code, :workflow_manual_run_launcher, fn _kickoff_request ->
      Agent.update(launcher_invocations, &(&1 + 1))
      {:ok, %{run_id: "unexpected-run"}}
    end)

    assert {:error, kickoff_error} =
             ManualRunKickoff.kickoff(
               %{
                 "repo_id" => repo_id,
                 "workflow_name" => "implement_task",
                 "task_summary" => ""
               },
               %{id: "owner-1", email: "owner@example.com"}
             )

    assert kickoff_error.error_type == "workflow_run_validation_failed"
    assert kickoff_error.detail =~ "required inputs are missing"

    assert Enum.any?(kickoff_error.field_errors, fn field_error ->
             field_error.field == "task_summary" and field_error.error_type == "required"
           end)

    assert Agent.get(launcher_invocations, & &1) == 0
  end

  test "missing workflow version pinning metadata aborts run creation before launcher" do
    repo_id = "repo-999"
    launcher_invocations = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:jido_code, :workflow_manual_definition_loader, fn ->
      {:ok,
       [
         %{
           name: "implement_task",
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
       ]}
    end)

    Application.put_env(:jido_code, :workflow_manual_repository_loader, fn ->
      {:ok,
       [
         %{
           id: repo_id,
           managed_repo_id: repo_id,
           legacy_project_id: repo_id,
           name: "repo-version-missing",
           github_full_name: "owner/repo-version-missing",
           default_branch: "main"
         }
       ]}
    end)

    Application.put_env(:jido_code, :workflow_manual_run_launcher, fn _kickoff_request ->
      Agent.update(launcher_invocations, &(&1 + 1))
      {:ok, %{run_id: "unexpected-run"}}
    end)

    assert {:error, kickoff_error} =
             ManualRunKickoff.kickoff(
               %{
                 "repo_id" => repo_id,
                 "workflow_name" => "implement_task",
                 "task_summary" => "Ship deterministic workflow metadata."
               },
               %{id: "owner-1", email: "owner@example.com"}
             )

    assert kickoff_error.error_type == "workflow_version_pinning_failed"
    assert kickoff_error.detail =~ "cannot be pinned"
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

  defp restore_env(key, :__missing__) do
    Application.delete_env(:jido_code, key)
  end

  defp restore_env(key, value) do
    Application.put_env(:jido_code, key, value)
  end
end
