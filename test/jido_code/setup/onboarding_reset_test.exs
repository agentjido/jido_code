defmodule JidoCode.Setup.OnboardingResetTest do
  # covers: setup.onboarding.reset_mix_task
  use ExUnit.Case, async: false

  alias JidoCode.ControlPlane.{ProductStore, StoreServer}
  alias JidoCode.GitHub.ServiceCredentials
  alias JidoCode.Setup.{BootstrapStatus, OnboardingReset, OwnerStore, SystemConfig, SystemConfigPersistence}

  setup do
    store_name = :"onboarding_reset_store_#{System.unique_integer([:positive])}"
    store_path = Path.join(System.tmp_dir!(), "jido_code_onboarding_reset/#{store_name}")
    workspace_root = create_workspace_root!()

    start_supervised!({StoreServer, name: store_name, id: store_name, path: store_path, reset_policy: :reset_on_start})

    original_store_server = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)
    original_saver = Application.get_env(:jido_code, :system_config_saver, :__missing__)

    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)
    Application.put_env(:jido_code, :system_config_loader, &SystemConfigPersistence.load/0)
    Application.put_env(:jido_code, :system_config_saver, &SystemConfigPersistence.save/1)

    assert {:ok, _config} =
             SystemConfig.save(%SystemConfig{
               onboarding_completed: true,
               onboarding_step: 8,
               onboarding_state: %{"7" => %{"selected_repository" => "owner/repo-one"}},
               default_environment: :local,
               workspace_root: workspace_root
             })

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original_store_server)
      restore_env(:system_config_loader, original_loader)
      restore_env(:system_config_saver, original_saver)
      File.rm_rf!(store_path)
    end)

    :ok
  end

  test "full reset returns onboarding to first-run bootstrap and clears onboarding-managed GitHub PAT" do
    bootstrap_owner!()
    import_managed_repo!("owner/repo-one")
    persist_secret_ref!(:onboarding)

    assert {:ok, report} = OnboardingReset.reset(:full)

    assert report.mode == :full
    assert report.owner_email == nil
    assert report.cleared_owner_count == 1
    assert report.cleared_managed_repo_count == 1
    assert report.cleared_onboarding_pat? == true

    assert {:ok, %SystemConfig{} = config} = SystemConfig.load()
    assert config.onboarding_completed == false
    assert config.onboarding_step == 1
    assert config.onboarding_state == %{}
    assert config.default_environment == :sprite
    assert config.workspace_root == nil

    assert BootstrapStatus.current().state == :bootstrap_required
    refute secret_ref_present?()
    assert managed_repo_count() == 0
  end

  test "keep-owner rewinds onboarding to the signed-in setup surface and preserves non-onboarding PAT secrets" do
    bootstrap_owner!()
    import_managed_repo!("owner/repo-two")
    persist_secret_ref!(:rotation)

    assert {:ok, report} = OnboardingReset.reset(:keep_owner)

    assert report.mode == :keep_owner
    assert report.owner_email == "owner@example.com"
    assert report.cleared_owner_count == 0
    assert report.cleared_managed_repo_count == 1
    assert report.cleared_onboarding_pat? == false

    assert {:ok, %SystemConfig{} = config} = SystemConfig.load()
    assert config.onboarding_completed == false
    assert config.onboarding_step == 3
    assert config.default_environment == :sprite
    assert config.workspace_root == nil

    assert config.onboarding_state == %{
             "1" => %{"validated_note" => "System prerequisites verified (welcome flow)."},
             "2" => %{
               "owner_email" => "owner@example.com",
               "owner_mode" => "confirmed",
               "registration_actions_disabled" => true,
               "validated_note" => "Owner account confirmed."
             }
           }

    status = BootstrapStatus.current()
    assert status.state == :continue_setup
    assert status.user_count == 1
    assert status.primary_user_email == "owner@example.com"

    assert secret_ref_present?()
    assert managed_repo_count() == 0
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp bootstrap_owner! do
    assert {:ok, owner} = OwnerStore.create_owner(%{email: "owner@example.com"})
    owner
  end

  defp create_workspace_root! do
    workspace_root =
      Path.join(System.tmp_dir!(), "onboarding-reset-workspace-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace_root)
    on_exit(fn -> File.rm_rf!(workspace_root) end)
    workspace_root
  end

  defp import_managed_repo!(full_name) when is_binary(full_name) do
    repo_id = full_name |> String.replace("/", "-")

    assert {:ok, _outcome} =
             ProductStore.dispatch(:upsert, :managed_repo,
               record: %{
                 managed_repo_id: repo_id,
                 source_key: "github:#{full_name}",
                 display_name: full_name,
                 updated_at: DateTime.utc_now()
               }
             )

    repo_id
  end

  defp persist_secret_ref!(source) do
    assert {:ok, _outcome} =
             ProductStore.dispatch(:create, :secret_ref,
               record: %{
                 secret_ref_id: "github-pat-#{source}",
                 scope: "integration",
                 name: ServiceCredentials.service_secret_ref_name(:pat),
                 provider: "github",
                 updated_at: DateTime.utc_now(),
                 metadata: %{"source" => Atom.to_string(source), "key_version" => 7}
               }
             )
  end

  defp secret_ref_present? do
    case ProductStore.dispatch(:list, :secret_ref, query: %{limit: 500, offset: 0}) do
      {:ok, %{projections: projections}} -> projections != []
      _other -> false
    end
  end

  defp managed_repo_count do
    case ProductStore.dispatch(:list, :managed_repo, query: %{limit: 500, offset: 0}) do
      {:ok, %{metadata: %{total_count: count}}} -> count
      _other -> 0
    end
  end
end
