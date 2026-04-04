defmodule JidoCode.Setup.ProjectImportPhaseOneIntegrationTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo, SourceRepo}
  alias JidoCode.Governance.PolicySet
  alias JidoCode.Setup.ProjectImport
  alias JidoCode.Workbench.ProjectDetail

  @managed_env_keys [
    :setup_project_importer,
    :setup_project_clone_provisioner,
    :setup_project_baseline_syncer
  ]

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

    Application.delete_env(:jido_code, :setup_project_importer)
    Application.delete_env(:jido_code, :setup_project_clone_provisioner)
    Application.delete_env(:jido_code, :setup_project_baseline_syncer)
    :ok
  end

  test "project import provisions control-plane repo state and preserves project detail compatibility" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "status" => "ready",
              "repositories" => [
                %{"full_name" => "owner/repo-one", "default_branch" => "develop"}
              ]
            }
          ]
        }
      }
    }

    report = ProjectImport.run(nil, "owner/repo-one", onboarding_state)

    refute ProjectImport.blocked?(report)

    {:ok, source_repo} =
      SourceRepo.get_by_provider_and_full_name(:github, "owner/repo-one", actor: Actor.operator_actor())

    {:ok, managed_repo} =
      ManagedRepo.get_by_source_repo_id(source_repo.id, actor: Actor.operator_actor())

    {:ok, policy_set} =
      PolicySet.get_by_managed_repo_name(managed_repo.id, "default", actor: Actor.operator_actor())

    {:ok, detail} = ProjectDetail.load(report.project_record.id)

    assert source_repo.default_branch == "develop"
    assert managed_repo.source_repo_id == source_repo.id
    assert managed_repo.workspace_settings["clone_status"] == "ready"
    assert policy_set.review_policy.mode == "approval_required"
    assert detail.managed_repo_id == managed_repo.id
    assert detail.source_repo_id == source_repo.id
  end

  test "repeat imports preserve managed repo and policy set identity while refreshing repo defaults" do
    first_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "status" => "ready",
              "repositories" => [
                %{"full_name" => "owner/repo-one", "default_branch" => "develop"}
              ]
            }
          ]
        }
      }
    }

    second_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "status" => "ready",
              "repositories" => [
                %{"full_name" => "owner/repo-one", "default_branch" => "release"}
              ]
            }
          ]
        }
      }
    }

    first_report = ProjectImport.run(nil, "owner/repo-one", first_state)
    refute ProjectImport.blocked?(first_report)

    {:ok, first_source_repo} =
      SourceRepo.get_by_provider_and_full_name(:github, "owner/repo-one", actor: Actor.operator_actor())

    {:ok, first_managed_repo} =
      ManagedRepo.get_by_source_repo_id(first_source_repo.id, actor: Actor.operator_actor())

    {:ok, first_policy_set} =
      PolicySet.get_by_managed_repo_name(first_managed_repo.id, "default", actor: Actor.operator_actor())

    second_report = ProjectImport.run(first_report, "owner/repo-one", second_state)
    refute ProjectImport.blocked?(second_report)
    assert second_report.project_record.import_mode == :existing

    {:ok, second_source_repo} =
      SourceRepo.get_by_provider_and_full_name(:github, "owner/repo-one", actor: Actor.operator_actor())

    {:ok, second_managed_repo} =
      ManagedRepo.get_by_source_repo_id(second_source_repo.id, actor: Actor.operator_actor())

    {:ok, second_policy_set} =
      PolicySet.get_by_managed_repo_name(second_managed_repo.id, "default", actor: Actor.operator_actor())

    assert second_source_repo.id == first_source_repo.id
    assert second_source_repo.default_branch == "release"
    assert second_managed_repo.id == first_managed_repo.id
    assert second_policy_set.id == first_policy_set.id
  end

  test "import-provisioned policy sets enforce the new actor boundary without blocking import completion" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "status" => "ready",
              "repositories" => [
                %{"full_name" => "owner/repo-one", "default_branch" => "main"}
              ]
            }
          ]
        }
      }
    }

    report = ProjectImport.run(nil, "owner/repo-one", onboarding_state)

    refute ProjectImport.blocked?(report)

    {:ok, source_repo} =
      SourceRepo.get_by_provider_and_full_name(:github, "owner/repo-one", actor: Actor.operator_actor())

    {:ok, managed_repo} =
      ManagedRepo.get_by_source_repo_id(source_repo.id, actor: Actor.operator_actor())

    assert {:error, %Ash.Error.Forbidden{}} =
             PolicySet.upsert_default_for_managed_repo(
               %{
                 managed_repo_id: managed_repo.id,
                 review_policy: %{
                   mode: "auto_post",
                   requires_human_approval: false,
                   source: "external_attempt"
                 }
               },
               actor: Actor.external_ingress_actor()
             )

    assert {:ok, updated_policy_set} =
             PolicySet.upsert_default_for_managed_repo(
               %{
                 managed_repo_id: managed_repo.id,
                 review_policy: %{
                   mode: "auto_post",
                   requires_human_approval: false,
                   source: "admin_override"
                 }
               },
               actor: Actor.admin_actor()
             )

    assert updated_policy_set.review_policy.mode == "auto_post"
    assert updated_policy_set.review_policy.source == "admin_override"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
