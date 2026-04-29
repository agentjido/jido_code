defmodule JidoCode.Setup.OnboardingResetTest do
  # covers: setup.onboarding.reset_mix_task
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentOS.Manager.PersistedKernel
  alias JidoCode.Accounts.User
  alias JidoCode.Control.{Actor, ManagedRepo, SourceRepo}
  alias JidoCode.GitHub.ServiceCredentials
  alias JidoCode.Security.{SecretRef, SecretRefs}
  alias JidoCode.Setup.{BootstrapStatus, OnboardingReset, ProjectImport, SystemConfig}

  setup do
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    workspace_root = create_workspace_root!()

    on_exit(fn ->
      restore_env(:system_config, original_config)
    end)

    Ecto.Adapters.SQL.query!(
      Repo,
      "TRUNCATE TABLE secret_refs, secret_lifecycle_audits, agent_os_kernel_snapshots, source_repos, users RESTART IDENTITY CASCADE",
      []
    )

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: true,
      onboarding_step: 8,
      onboarding_state: %{"7" => %{"selected_repository" => "owner/repo-one"}},
      default_environment: :local,
      workspace_root: workspace_root
    })

    :ok
  end

  test "full reset returns onboarding to first-run bootstrap and clears onboarding-managed GitHub PAT" do
    bootstrap_owner!()
    managed_repo_id = import_managed_repo!("owner/repo-one")
    persist_kernel_snapshot!(managed_repo_id)

    assert {:ok, _metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: ServiceCredentials.service_secret_ref_name(:pat),
               value: "ghp_onboarding_reset_test",
               source: :onboarding
             })

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

    assert {:error, %{error_type: "secret_ref_missing"}} =
             SecretRefs.operational_secret_value(:integration, "vcs/github/pat")

    assert repo_inventory_counts() == %{managed_repos: 0, source_repos: 0, kernel_snapshots: 0}
  end

  test "keep-owner rewinds onboarding to the signed-in setup surface and preserves non-onboarding PAT secrets" do
    bootstrap_owner!()
    managed_repo_id = import_managed_repo!("owner/repo-two")
    persist_kernel_snapshot!(managed_repo_id)

    assert {:ok, %SecretRef{} = _secret_ref} =
             SecretRef.create(
               %{
                 scope: :integration,
                 name: ServiceCredentials.service_secret_ref_name(:pat),
                 ciphertext: "ciphertext",
                 key_version: 7,
                 source: :rotation,
                 last_rotated_at: ~U[2026-04-24 12:00:00Z]
               },
               authorize?: false
             )

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

    assert {:ok, %SecretRef{source: :rotation, key_version: 7}} =
             SecretRef.get_by_scope_name(
               :integration,
               ServiceCredentials.service_secret_ref_name(:pat),
               authorize?: false
             )

    assert repo_inventory_counts() == %{managed_repos: 0, source_repos: 0, kernel_snapshots: 0}
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp bootstrap_owner! do
    assert {:ok, _owner} =
             User.bootstrap_admin(
               %{
                 email: "owner@example.com",
                 password: "owner-password-123",
                 password_confirmation: "owner-password-123"
               },
               authorize?: false,
               context: %{token_type: :sign_in}
             )
  end

  defp create_workspace_root! do
    workspace_root =
      Path.join(System.tmp_dir!(), "onboarding-reset-workspace-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace_root)
    on_exit(fn -> File.rm_rf!(workspace_root) end)
    workspace_root
  end

  defp import_managed_repo!(full_name) when is_binary(full_name) do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "status" => "ready",
              "repositories" => [
                %{"full_name" => full_name, "default_branch" => "main"}
              ]
            }
          ]
        }
      }
    }

    report = ProjectImport.run(nil, full_name, onboarding_state)

    refute ProjectImport.blocked?(report)
    report.project_record.id
  end

  defp persist_kernel_snapshot!(managed_repo_id) when is_binary(managed_repo_id) do
    attrs = %{
      kernel_name: "managed_repo_#{managed_repo_id}",
      managed_repo_id: managed_repo_id,
      snapshot_data: :erlang.term_to_binary(%{managed_repo_id: managed_repo_id, status: :persisted})
    }

    %PersistedKernel{}
    |> PersistedKernel.changeset(attrs)
    |> Repo.insert!()
  end

  defp repo_inventory_counts do
    {:ok, managed_repos} =
      ManagedRepo.read(query: [sort: [inserted_at: :asc]], actor: Actor.operator_actor())

    {:ok, source_repos} =
      SourceRepo.read(query: [sort: [inserted_at: :asc]], actor: Actor.operator_actor())

    %{
      managed_repos: length(managed_repos),
      source_repos: length(source_repos),
      kernel_snapshots: Repo.aggregate(PersistedKernel, :count, :id)
    }
  end
end
