defmodule JidoCode.Setup.ProjectImportTest do
  # covers: setup.onboarding.repo_source_per_project
  # covers: setup.runtime_environment_defaults.import_uses_persisted_runtime_defaults
  use ExUnit.Case, async: false

  alias JidoCode.Control.{ManagedRepoStore, SourceRepoStore}
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Setup.ProjectImport

  @managed_env_keys [
    :system_config,
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
    Application.put_env(:jido_code, :system_config, %{})
    setup_product_store()
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
      SourceRepoStore.get_by_provider_and_full_name(:github, "owner/repo-one")

    {:ok, managed_repo} =
      ManagedRepoStore.get_by_source_repo_id(source_repo.id)

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

    {:ok, source_repos} = SourceRepoStore.list()
    {:ok, managed_repos} = ManagedRepoStore.list()

    assert Enum.count(source_repos, &(&1.full_name == "owner/repo-one")) == 1
    source_repo_ids = Enum.map(source_repos, fn source_repo -> source_repo.id end)
    assert Enum.count(managed_repos, fn managed_repo -> managed_repo.source_repo_id in source_repo_ids end) == 1
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

    {:ok, source_repos} = SourceRepoStore.list()
    {:ok, managed_repos} = ManagedRepoStore.list()

    assert Enum.filter(source_repos, &(&1.full_name == "owner/repo-one")) == []
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
      SourceRepoStore.get_by_provider_and_full_name(:github, "owner/repo-one")

    {:ok, managed_repo} =
      ManagedRepoStore.get_by_source_repo_id(source_repo.id)

    assert managed_repo.workspace_settings["clone_status"] == "error"
    assert managed_repo.workspace_settings["last_error_type"] == "baseline_sync_unavailable"
    assert managed_repo.workspace_settings["retry_instructions"] =~ "Retry step 7"
  end

  test "run/3 uses persisted runtime defaults from system config when provisioning a local workspace" do
    workspace_root = tmp_workspace_path!()

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "3" => %{
          "runtime_environment" => %{
            "mode" => "local",
            "default_environment" => "local",
            "workspace_root" => workspace_root,
            "status" => "ready"
          }
        }
      },
      default_environment: :local,
      workspace_root: workspace_root
    })

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
    assert report.status == :ready
    assert report.baseline_metadata.workspace_environment == :local
    assert report.baseline_metadata.workspace_path == Path.join(workspace_root, "owner__repo-one")
    assert File.dir?(report.baseline_metadata.workspace_path)
  end

  test "run/3 accepts an explicit repo-scoped local workspace path without relying on a shared root" do
    explicit_workspace_path =
      Path.join(tmp_workspace_path!(), "independent-repo-location")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{},
      default_environment: :sprite,
      workspace_root: nil
    })

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
      },
      "7" => %{
        "repository_listing" => %{
          "repositories" => [
            %{
              "full_name" => "owner/repo-one",
              "default_branch" => "main",
              "workspace_path" => explicit_workspace_path
            }
          ]
        }
      }
    }

    report = ProjectImport.run(nil, "owner/repo-one", onboarding_state)

    refute ProjectImport.blocked?(report)
    assert report.status == :ready
    assert report.baseline_metadata.workspace_environment == :local
    assert report.baseline_metadata.workspace_path == explicit_workspace_path
    assert File.dir?(explicit_workspace_path)

    {:ok, source_repo} =
      SourceRepoStore.get_by_provider_and_full_name(:github, "owner/repo-one")

    {:ok, managed_repo} =
      ManagedRepoStore.get_by_source_repo_id(source_repo.id)

    assert managed_repo.workspace_settings["workspace_path"] == explicit_workspace_path
    assert managed_repo.workspace_settings["workspace_root"] == Path.dirname(explicit_workspace_path)
  end

  test "run/3 rejects a relative explicit repo-scoped workspace path" do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{},
      default_environment: :sprite,
      workspace_root: nil
    })

    onboarding_state = %{
      "7" => %{
        "repository_listing" => %{
          "repositories" => [
            %{
              "full_name" => "owner/repo-one",
              "default_branch" => "main",
              "workspace_path" => "relative/repo-one"
            }
          ]
        }
      }
    }

    report = ProjectImport.run(nil, "owner/repo-one", onboarding_state)

    assert ProjectImport.blocked?(report)
    assert report.status == :blocked
    assert report.error_type == "workspace_path_invalid"
    assert report.detail == "Local workspace path must be an absolute path."
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp setup_product_store do
    store_name = :"project_import_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_project_import/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  defp tmp_workspace_path! do
    workspace_path =
      Path.join(System.tmp_dir!(), "project-import-workspace-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end
end
