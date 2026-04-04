defmodule JidoCode.Control.RepoBridgeTest do
  # covers: architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo, RepoBridge, SourceRepo}
  alias JidoCode.Workbench.ProjectDetail

  test "upsert_managed_repo provisions source repo and managed repo from canonical attrs" do
    {:ok, %{managed_repo: managed_repo, source_repo: source_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "repo-one",
        full_name: "owner/repo-one",
        default_branch: "develop",
        workspace_settings: %{"clone_status" => "ready", "workspace_initialized" => true},
        execution_settings: %{"workflow" => %{"default" => "issue_triage"}},
        integration_settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"enabled" => false, "approval_mode" => "approval_required"}
          }
        }
      })

    assert source_repo.owner == "owner"
    assert source_repo.name == "repo-one"
    assert source_repo.default_branch == "develop"

    assert managed_repo.display_name == "repo-one"
    assert managed_repo.source_repo_id == source_repo.id
    assert managed_repo.legacy_project_id == nil
    assert managed_repo.workspace_settings["clone_status"] == "ready"
    assert managed_repo.execution_settings["workflow"] == %{"default" => "issue_triage"}

    assert managed_repo.integration_settings["support_agent_config"] == %{
             "github_issue_bot" => %{
               "enabled" => false,
               "approval_mode" => "approval_required"
             }
           }
  end

  test "upsert_managed_repo refreshes the canonical projection without duplicating the source repo" do
    {:ok, %{managed_repo: original_managed_repo, source_repo: source_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "repo-one",
        full_name: "owner/repo-one",
        default_branch: "main",
        workspace_settings: %{"clone_status" => "pending"}
      })

    {:ok, %{managed_repo: updated_managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        display_name: "repo-renamed",
        full_name: "owner/repo-one",
        default_branch: "release",
        workspace_settings: %{"clone_status" => "ready"},
        integration_settings: %{"support_agent_config" => %{"github_issue_bot" => %{"enabled" => true}}}
      })

    {:ok, fetched_source_repo} =
      SourceRepo.get_by_provider_and_full_name(:github, "owner/repo-one", actor: Actor.operator_actor())

    {:ok, fetched_managed_repo} =
      ManagedRepo.get_by_source_repo_id(source_repo.id, actor: Actor.operator_actor())

    {:ok, source_repos} =
      SourceRepo.read(query: [filter: [full_name: "owner/repo-one"]], actor: Actor.operator_actor())

    assert length(source_repos) == 1
    assert fetched_source_repo.default_branch == "release"
    assert updated_managed_repo.id == original_managed_repo.id
    assert fetched_managed_repo.id == original_managed_repo.id
    assert fetched_managed_repo.display_name == "repo-renamed"
    assert fetched_managed_repo.workspace_settings["clone_status"] == "ready"

    assert fetched_managed_repo.integration_settings["support_agent_config"] == %{
             "github_issue_bot" => %{"enabled" => true}
           }
  end

  test "repo detail resolves canonical managed repo identifiers through the repo scope" do
    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "repo-managed-route",
        full_name: "owner/repo-managed-route",
        default_branch: "main",
        workspace_settings: %{
          "clone_status" => "ready",
          "workspace_initialized" => true,
          "baseline_synced" => true
        }
      })

    {:ok, detail} = ProjectDetail.load(managed_repo.id)

    assert detail.id == managed_repo.id
    assert detail.managed_repo_id == managed_repo.id
    assert detail.source_repo_id == managed_repo.source_repo_id
    assert detail.github_full_name == "owner/repo-managed-route"
    assert detail.execution_readiness.status == :ready
  end
end
