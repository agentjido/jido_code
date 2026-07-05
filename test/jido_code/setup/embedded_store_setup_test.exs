defmodule JidoCode.Setup.EmbeddedStoreSetupTest do
  use ExUnit.Case, async: false

  alias JidoCode.ControlPlane.{ProductStore, StoreServer}

  alias JidoCode.Setup.{
    BootstrapStatus,
    OnboardingReset,
    OwnerBootstrap,
    OwnerStore,
    SystemConfig,
    SystemConfigPersistence
  }

  setup do
    store_name = :"setup_embedded_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_setup_embedded_store/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original_store_server = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)
    original_saver = Application.get_env(:jido_code, :system_config_saver, :__missing__)

    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)
    Application.put_env(:jido_code, :system_config_loader, &SystemConfigPersistence.load/0)
    Application.put_env(:jido_code, :system_config_saver, &SystemConfigPersistence.save/1)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original_store_server)
      restore_env(:system_config_loader, original_loader)
      restore_env(:system_config_saver, original_saver)
      File.rm_rf!(path)
    end)

    %{store: store_name}
  end

  test "system config persists setup state through the embedded store" do
    config = %SystemConfig{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{"2" => %{"owner_email" => "owner@example.com"}},
      default_environment: :local,
      workspace_root: "/tmp/jido-workspaces"
    }

    assert {:ok, %SystemConfig{} = saved} = SystemConfig.save(config)
    assert saved.onboarding_step == 3
    assert saved.default_environment == :local

    assert {:ok, %SystemConfig{} = loaded} = SystemConfig.load()
    assert loaded.onboarding_step == 3
    assert loaded.onboarding_state == %{"2" => %{"owner_email" => "owner@example.com"}}
    assert loaded.workspace_root == "/tmp/jido-workspaces"
  end

  test "owner bootstrap creates and discovers the setup owner without Ash reads" do
    assert {:ok, %{mode: :create, owner: nil}} = OwnerBootstrap.status()

    assert {:ok, result} =
             OwnerBootstrap.bootstrap(%{
               "email" => "Owner@Example.com",
               "password" => "owner-password-123",
               "password_confirmation" => "owner-password-123"
             })

    assert result.owner.email == "owner@example.com"
    assert result.owner.is_admin
    assert is_binary(result.token)
    assert result.owner_mode == :created

    assert {:ok, %{mode: :confirm, owner: owner}} = OwnerBootstrap.status()
    assert owner.email == "owner@example.com"

    assert {:ok, _config} =
             SystemConfig.save(%SystemConfig{
               onboarding_completed: false,
               onboarding_step: 3,
               onboarding_state: %{"2" => %{"owner_email" => "owner@example.com"}},
               default_environment: :sprite,
               workspace_root: nil
             })

    assert %{state: :continue_setup, primary_user_email: "owner@example.com"} = BootstrapStatus.current()
  end

  test "full onboarding reset clears store-backed setup owner and managed repo records", %{store: _store} do
    assert {:ok, owner} = OwnerStore.create_owner(%{email: "owner@example.com"})

    assert {:ok, _repo} =
             ProductStore.dispatch(:upsert, :managed_repo,
               record: %{
                 managed_repo_id: "repo-reset",
                 source_key: "github:owner/repo-reset",
                 display_name: "Reset Repo",
                 updated_at: DateTime.utc_now()
               }
             )

    assert {:ok, _config} =
             SystemConfig.save(%SystemConfig{
               onboarding_completed: true,
               onboarding_step: 7,
               onboarding_state: %{"2" => %{"owner_email" => owner.email}},
               default_environment: :sprite,
               workspace_root: nil
             })

    assert {:ok, result} = OnboardingReset.reset(:full)
    assert result.cleared_owner_count == 1
    assert result.cleared_managed_repo_count == 1
    assert result.config.onboarding_step == 1

    assert {:ok, []} = OwnerStore.list_users()
    assert %{state: :bootstrap_required, user_count: 0} = BootstrapStatus.current()
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
