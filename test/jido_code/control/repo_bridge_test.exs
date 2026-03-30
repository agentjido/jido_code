defmodule JidoCode.Control.RepoBridgeTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo, SourceRepo}
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.ProjectDetail

  test "project create mirrors identity and split settings into control-plane repo resources" do
    {:ok, project} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "develop",
        settings: %{
          "workspace" => %{"clone_status" => "ready", "workspace_initialized" => true},
          "support_agent_config" => %{
            "github_issue_bot" => %{"enabled" => false, "approval_mode" => "approval_required"}
          },
          "workflow" => %{"default" => "issue_triage"}
        }
      })

    {:ok, source_repo} =
      SourceRepo.get_by_provider_and_full_name(:github, "owner/repo-one",
        actor: Actor.operator_actor()
      )

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert source_repo.owner == "owner"
    assert source_repo.name == "repo-one"
    assert source_repo.default_branch == "develop"

    assert managed_repo.display_name == "repo-one"
    assert managed_repo.source_repo_id == source_repo.id
    assert managed_repo.workspace_settings["clone_status"] == "ready"
    assert managed_repo.execution_settings["workflow"] == %{"default" => "issue_triage"}

    assert managed_repo.integration_settings["support_agent_config"] == %{
             "github_issue_bot" => %{
               "enabled" => false,
               "approval_mode" => "approval_required"
             }
           }
  end

  test "project update refreshes the managed repo projection without duplicating the source repo" do
    {:ok, project} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "main",
        settings: %{"workspace" => %{"clone_status" => "pending"}}
      })

    {:ok, original_managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, updated_project} =
      Project.update(project, %{
        name: "repo-renamed",
        default_branch: "release",
        settings: %{
          "workspace" => %{"clone_status" => "ready"},
          "support_agent_config" => %{"github_issue_bot" => %{"enabled" => true}}
        }
      })

    {:ok, source_repo} =
      SourceRepo.get_by_provider_and_full_name(:github, "owner/repo-one",
        actor: Actor.operator_actor()
      )

    {:ok, updated_managed_repo} =
      ManagedRepo.get_by_legacy_project_id(updated_project.id, actor: Actor.operator_actor())

    {:ok, source_repos} =
      SourceRepo.read(query: [filter: [full_name: "owner/repo-one"]], actor: Actor.operator_actor())

    assert length(source_repos) == 1
    assert source_repo.default_branch == "release"
    assert updated_managed_repo.id == original_managed_repo.id
    assert updated_managed_repo.display_name == "repo-renamed"
    assert updated_managed_repo.workspace_settings["clone_status"] == "ready"

    assert updated_managed_repo.integration_settings["support_agent_config"] == %{
             "github_issue_bot" => %{"enabled" => true}
           }
  end

  test "project detail exposes control-plane identifiers through the transitional project path" do
    {:ok, project} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())
    {:ok, detail} = ProjectDetail.load(project.id)

    assert detail.managed_repo_id == managed_repo.id
    assert detail.source_repo_id == managed_repo.source_repo_id
    assert detail.execution_readiness.status == :ready
  end

  test "workflow runs capture managed repo linkage from the transitional project identifier" do
    {:ok, project} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "phase-one-linkage-run",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Verify managed repo linkage"},
        input_metadata: %{"task_summary" => %{required: true}},
        initiating_actor: %{id: "operator-1", email: "operator@example.com"},
        current_step: "queued",
        started_at: ~U[2026-03-30 12:00:00Z]
      })

    assert run.managed_repo_id == managed_repo.id
  end
end
