defmodule JidoCode.Setup.ProjectImportTest do
  # covers: setup.onboarding.repo_source_per_project
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo, SourceRepo}
  alias JidoCode.Setup.ProjectImport

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

  test "run/3 provisions canonical repo records with source identity and default_branch metadata" do
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
    assert report.status == :ready
    assert report.project_record.source_kind == :github
    assert report.project_record.source_identifier == "owner/repo-one"
    assert report.project_record.github_full_name == "owner/repo-one"
    assert report.project_record.local_path == nil
    assert report.project_record.default_branch == "develop"
    assert report.project_record.import_mode == :created
    assert report.project_record.clone_status == :ready
    assert Enum.map(report.project_record.clone_status_history, & &1.status) == [:pending, :cloning, :ready]
    assert %DateTime{} = report.project_record.last_synced_at
    assert report.baseline_metadata.synced_branch == "develop"
    assert %DateTime{} = report.baseline_metadata.last_synced_at

    {:ok, source_repo} =
      SourceRepo.get_by_provider_and_full_name(:github, "owner/repo-one", actor: Actor.operator_actor())

    {:ok, managed_repo} =
      ManagedRepo.get_by_source_repo_id(source_repo.id, actor: Actor.operator_actor())

    assert report.project_record.id == managed_repo.id
    assert source_repo.full_name == "owner/repo-one"
    assert source_repo.default_branch == "develop"
    assert managed_repo.display_name == "repo-one"
    assert managed_repo.workspace_settings["clone_status"] == "ready"

    assert Enum.map(managed_repo.workspace_settings["clone_status_history"], & &1["status"]) == [
             "pending",
             "cloning",
             "ready"
           ]

    assert is_binary(managed_repo.workspace_settings["last_synced_at"])
  end

  test "run/3 does not create duplicate managed repo records for repeat imports" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "status" => "ready",
              "repositories" => ["owner/repo-one"]
            }
          ]
        }
      }
    }

    first_report = ProjectImport.run(nil, "owner/repo-one", onboarding_state)
    second_report = ProjectImport.run(first_report, "owner/repo-one", onboarding_state)

    refute ProjectImport.blocked?(first_report)
    refute ProjectImport.blocked?(second_report)
    assert first_report.project_record.import_mode == :created
    assert second_report.project_record.import_mode == :existing

    {:ok, source_repos} =
      SourceRepo.read(query: [filter: [full_name: "owner/repo-one"]], actor: Actor.operator_actor())

    {:ok, managed_repos} =
      ManagedRepo.read(query: [sort: [inserted_at: :asc]], actor: Actor.operator_actor())

    assert length(source_repos) == 1
    assert length(managed_repos) == 1
    assert first_report.project_record.id == second_report.project_record.id
  end

  test "run/3 reports typed persistence failure and does not expose partial project state" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "status" => "ready",
              "repositories" => [
                %{
                  "full_name" => "owner/repo-one",
                  "default_branch" => String.duplicate("a", 300)
                }
              ]
            }
          ]
        }
      }
    }

    report = ProjectImport.run(nil, "owner/repo-one", onboarding_state)

    assert ProjectImport.blocked?(report)
    assert report.status == :blocked
    assert report.error_type == "repo_persistence_upsert_failed"
    assert report.project_record == nil
    assert report.baseline_metadata == nil

    {:ok, source_repos} =
      SourceRepo.read(query: [filter: [full_name: "owner/repo-one"]], actor: Actor.operator_actor())

    {:ok, managed_repos} =
      ManagedRepo.read(query: [sort: [inserted_at: :asc]], actor: Actor.operator_actor())

    assert source_repos == []
    assert managed_repos == []
  end

  test "run/3 marks clone status error with retry remediation when baseline sync fails" do
    Application.put_env(:jido_code, :setup_project_baseline_syncer, fn _context ->
      {:error, {"baseline_sync_unavailable", "Baseline sync worker timed out before checkout."}}
    end)

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

    assert ProjectImport.blocked?(report)
    assert report.status == :blocked
    assert report.error_type == "baseline_sync_unavailable"
    assert report.remediation =~ "Retry step 7"
    assert report.project_record.clone_status == :error

    assert Enum.map(report.project_record.clone_status_history, & &1.status) == [
             :pending,
             :cloning,
             :error
           ]

    {:ok, source_repo} =
      SourceRepo.get_by_provider_and_full_name(:github, "owner/repo-one", actor: Actor.operator_actor())

    {:ok, managed_repo} =
      ManagedRepo.get_by_source_repo_id(source_repo.id, actor: Actor.operator_actor())

    assert managed_repo.workspace_settings["clone_status"] == "error"
    assert managed_repo.workspace_settings["last_error_type"] == "baseline_sync_unavailable"
    assert managed_repo.workspace_settings["retry_instructions"] =~ "Retry step 7"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
