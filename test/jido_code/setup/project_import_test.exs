defmodule JidoCode.Setup.ProjectImportTest do
  # covers: setup.onboarding.repo_source_per_project
  use JidoCode.DataCase, async: false

  alias JidoCode.Projects.Project
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

  test "run/3 creates project records with source identity and default_branch metadata" do
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

    {:ok, [project]} =
      Project.read(query: [filter: [source_kind: :github, source_identifier: "owner/repo-one"], limit: 1])

    assert project.source_kind == :github
    assert project.source_identifier == "owner/repo-one"
    assert project.github_full_name == "owner/repo-one"
    assert project.default_branch == "develop"
    assert project.settings["workspace"]["clone_status"] == "ready"

    assert Enum.map(project.settings["workspace"]["clone_status_history"], & &1["status"]) == [
             "pending",
             "cloning",
             "ready"
           ]

    assert is_binary(project.settings["workspace"]["last_synced_at"])
  end

  test "run/3 does not create duplicate project records for repeat imports" do
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

    {:ok, projects} = Project.read(query: [filter: [github_full_name: "owner/repo-one"]])
    assert length(projects) == 1
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
    assert report.error_type == "project_persistence_create_failed"
    assert report.project_record == nil
    assert report.baseline_metadata == nil

    {:ok, projects} = Project.read(query: [filter: [github_full_name: "owner/repo-one"]])
    assert projects == []
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

    {:ok, [project]} =
      Project.read(query: [filter: [github_full_name: "owner/repo-one"], limit: 1])

    assert project.settings["workspace"]["clone_status"] == "error"
    assert project.settings["workspace"]["last_error_type"] == "baseline_sync_unavailable"
    assert project.settings["workspace"]["retry_instructions"] =~ "Retry step 7"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
