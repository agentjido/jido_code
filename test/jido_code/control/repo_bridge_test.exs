defmodule JidoCode.Control.RepoBridgeTest do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: package.jido_code.version_controlled_quality_surfaces
  use ExUnit.Case, async: false

  alias JidoCode.Control.{ManagedRepoStore, RepoBridge, SourceRepoStore}
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Workbench.ProjectDetail

  setup do
    setup_product_store()
  end

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
      SourceRepoStore.get_by_provider_and_full_name(:github, "owner/repo-one")

    {:ok, fetched_managed_repo} =
      ManagedRepoStore.get_by_source_repo_id(source_repo.id)

    {:ok, source_repos} = SourceRepoStore.list()

    assert Enum.count(source_repos, &(&1.full_name == "owner/repo-one")) == 1
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
    workspace_path = create_workspace_path!()

    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "repo-managed-route",
        full_name: "owner/repo-managed-route",
        default_branch: "main",
        workspace_settings: %{
          "workspace_environment" => "local",
          "workspace_path" => workspace_path,
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
    assert detail.settings["workspace"]["workspace_path"] == workspace_path
    assert detail.execution_readiness.status == :ready
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(System.tmp_dir!(), "repo-bridge-workspace-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp setup_product_store do
    store_name = :"repo_bridge_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_repo_bridge/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
