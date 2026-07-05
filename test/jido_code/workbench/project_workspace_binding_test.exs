defmodule JidoCode.Workbench.ProjectWorkspaceBindingTest do
  # covers: architecture.factory_control_plane.managed_repos_own_repo_scoped_workspace_binding
  # covers: setup.runtime_environment_defaults.repo_scoped_workspace_binding_is_canonical
  use ExUnit.Case, async: false

  alias JidoCode.Control.{Actor, ManagedRepoStore, RepoBridge, SourceRepoStore}
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Workbench.ProjectWorkspaceBinding

  @managed_env_keys [:system_config]

  setup do
    original_env =
      Enum.map(@managed_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    on_exit(fn ->
      Enum.each(original_env, fn {key, value} ->
        restore_env(key, value)
      end)
    end)

    setup_product_store()
    :ok
  end

  test "update/3 rebinds one managed repository to an explicit absolute local path without changing another repo or setup defaults" do
    default_workspace_root = tmp_workspace_path!("phase63-default-root")
    repo_one_workspace_path = tmp_workspace_path!("phase63-repo-one")
    repo_two_workspace_path = tmp_workspace_path!("phase63-repo-two")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{},
      default_environment: :local,
      workspace_root: default_workspace_root
    })

    {:ok, %{managed_repo: repo_one}} =
      RepoBridge.upsert_managed_repo(%{
        name: "repo-one",
        full_name: "owner/repo-one",
        default_branch: "main",
        workspace_settings: %{
          "clone_status" => "ready",
          "workspace_initialized" => true,
          "baseline_synced" => true
        }
      })

    {:ok, %{managed_repo: repo_two}} =
      RepoBridge.upsert_managed_repo(%{
        name: "repo-two",
        full_name: "owner/repo-two",
        default_branch: "main",
        workspace_settings: %{
          "workspace_environment" => "local",
          "workspace_path" => repo_two_workspace_path,
          "workspace_root" => Path.dirname(repo_two_workspace_path),
          "clone_status" => "ready",
          "workspace_initialized" => true,
          "baseline_synced" => true
        }
      })

    assert {:ok, %{managed_repo: updated_repo_one, workspace_settings: workspace_settings}} =
             ProjectWorkspaceBinding.update(
               repo_one.id,
               %{"workspace_environment" => "local", "workspace_path" => repo_one_workspace_path},
               Actor.operator_actor(%{"id" => "operator-phase63-rebind"})
             )

    assert workspace_settings["workspace_environment"] == "local"
    assert workspace_settings["workspace_path"] == repo_one_workspace_path
    assert workspace_settings["workspace_root"] == Path.dirname(repo_one_workspace_path)
    assert workspace_settings["clone_status"] == "ready"
    assert updated_repo_one.workspace_settings["workspace_path"] == repo_one_workspace_path

    {:ok, reloaded_repo_two} =
      reloaded_managed_repo!("owner/repo-two")

    assert reloaded_repo_two.id == repo_two.id
    assert reloaded_repo_two.workspace_settings["workspace_path"] == repo_two_workspace_path
    assert reloaded_repo_two.workspace_settings["workspace_root"] == Path.dirname(repo_two_workspace_path)

    assert Application.get_env(:jido_code, :system_config).workspace_root == default_workspace_root
  end

  test "update/3 rejects relative repo-scoped local paths and leaves workspace settings unchanged" do
    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "repo-relative",
        full_name: "owner/repo-relative",
        default_branch: "main",
        workspace_settings: %{
          "clone_status" => "ready",
          "workspace_initialized" => true,
          "baseline_synced" => true
        }
      })

    assert {:error, error} =
             ProjectWorkspaceBinding.update(
               managed_repo.id,
               %{"workspace_environment" => "local", "workspace_path" => "relative/path"},
               Actor.operator_actor(%{"id" => "operator-phase63-relative"})
             )

    assert error.error_type == "managed_repo_workspace_path_invalid"
    assert error.detail == "Repo-scoped local workspace path must be absolute."

    {:ok, reloaded_managed_repo} = reloaded_managed_repo!("owner/repo-relative")
    assert reloaded_managed_repo.workspace_settings["workspace_path"] == nil
    assert reloaded_managed_repo.workspace_settings["workspace_root"] == nil
  end

  test "update/3 can clear one repo back to sprite binding without changing another repo or setup defaults" do
    default_workspace_root = tmp_workspace_path!("phase63-default-root-clear")
    repo_one_workspace_path = tmp_workspace_path!("phase63-repo-clear-one")
    repo_two_workspace_path = tmp_workspace_path!("phase63-repo-clear-two")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{},
      default_environment: :local,
      workspace_root: default_workspace_root
    })

    {:ok, %{managed_repo: repo_one}} =
      RepoBridge.upsert_managed_repo(%{
        name: "repo-clear-one",
        full_name: "owner/repo-clear-one",
        default_branch: "main",
        workspace_settings: %{
          "workspace_environment" => "local",
          "workspace_path" => repo_one_workspace_path,
          "workspace_root" => Path.dirname(repo_one_workspace_path),
          "clone_status" => "ready",
          "workspace_initialized" => true,
          "baseline_synced" => true
        }
      })

    {:ok, %{managed_repo: repo_two}} =
      RepoBridge.upsert_managed_repo(%{
        name: "repo-clear-two",
        full_name: "owner/repo-clear-two",
        default_branch: "main",
        workspace_settings: %{
          "workspace_environment" => "local",
          "workspace_path" => repo_two_workspace_path,
          "workspace_root" => Path.dirname(repo_two_workspace_path),
          "clone_status" => "ready",
          "workspace_initialized" => true,
          "baseline_synced" => true
        }
      })

    assert {:ok, %{managed_repo: updated_repo_one, workspace_settings: workspace_settings}} =
             ProjectWorkspaceBinding.update(
               repo_one.id,
               %{"workspace_environment" => "sprite"},
               Actor.operator_actor(%{"id" => "operator-phase63-clear"})
             )

    assert workspace_settings["workspace_environment"] == "sprite"
    assert workspace_settings["workspace_path"] == nil
    assert workspace_settings["workspace_root"] == nil
    assert workspace_settings["clone_status"] == "ready"
    assert updated_repo_one.workspace_settings["workspace_path"] == nil

    {:ok, reloaded_repo_two} = reloaded_managed_repo!("owner/repo-clear-two")
    assert reloaded_repo_two.id == repo_two.id
    assert reloaded_repo_two.workspace_settings["workspace_path"] == repo_two_workspace_path
    assert Application.get_env(:jido_code, :system_config).workspace_root == default_workspace_root
  end

  defp reloaded_managed_repo!(full_name) do
    with {:ok, source_repo} <-
           SourceRepoStore.get_by_provider_and_full_name(:github, full_name),
         {:ok, managed_repo} <-
           ManagedRepoStore.get_by_source_repo_id(source_repo.id) do
      {:ok, managed_repo}
    end
  end

  defp tmp_workspace_path!(prefix) do
    workspace_path =
      Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp setup_product_store do
    store_name = :"workspace_binding_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_workspace_binding/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end
end
