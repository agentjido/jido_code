defmodule JidoCode.Setup.GitHubRepositoryListingTest do
  use ExUnit.Case, async: true

  alias JidoCode.Setup.GitHubRepositoryListing

  @managed_env_keys [:setup_github_repository_fetcher]

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

    :ok
  end

  test "run/2 lists only repositories from credential paths with confirmed access and exposes stable identifiers" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "path" => "github_app",
              "status" => "ready",
              "repository_access" => "confirmed",
              "repositories" => [
                %{"id" => "repo_200", "full_name" => "owner/repo-two"},
                "owner/repo-one"
              ]
            },
            %{
              "path" => "pat",
              "status" => "invalid",
              "repository_access" => "unconfirmed",
              "repositories" => ["owner/private-repo"]
            }
          ]
        }
      }
    }

    report = GitHubRepositoryListing.run(nil, onboarding_state)

    refute GitHubRepositoryListing.blocked?(report)
    assert report.status == :ready

    assert GitHubRepositoryListing.repository_full_names(report) == [
             "owner/repo-one",
             "owner/repo-two"
           ]

    repositories_by_name =
      report.repositories
      |> Enum.map(fn repository -> {repository.full_name, repository} end)
      |> Map.new()

    assert repositories_by_name["owner/repo-one"].id == "repo:owner/repo-one"
    assert repositories_by_name["owner/repo-two"].id == "repo_200"
  end

  test "run/2 surfaces concrete remediation when no GitHub repository path is configured" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "path" => "github_app",
              "name" => "GitHub App",
              "status" => "not_configured",
              "repository_access" => "unconfirmed",
              "detail" =>
                "GitHub App credentials are not fully configured (`GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` are required).",
              "remediation" =>
                "Set `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY`, then retry validation.",
              "error_type" => "github_app_not_configured"
            },
            %{
              "path" => "pat",
              "name" => "Personal Access Token (PAT)",
              "status" => "not_configured",
              "repository_access" => "unconfirmed",
              "detail" => "No GitHub personal access token fallback is configured (`GITHUB_PAT`).",
              "remediation" => "Set `GITHUB_PAT` and retry validation.",
              "error_type" => "github_pat_not_configured"
            }
          ]
        }
      }
    }

    report = GitHubRepositoryListing.run(nil, onboarding_state)

    assert GitHubRepositoryListing.blocked?(report)
    assert report.error_type == "github_repository_fetch_not_configured"
    assert report.detail =~ "GitHub credential validation has no confirmed repository access paths."
    assert report.detail =~ "GitHub App credentials are not fully configured"
    assert report.detail =~ "No GitHub personal access token fallback is configured"
    assert report.remediation =~ "Set `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY`"
    assert report.remediation =~ "Set `GITHUB_PAT` and retry validation."
  end

  test "run/2 preserves previously listed repositories when listing fetch fails" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "path" => "github_app",
              "status" => "ready",
              "repositories" => ["owner/repo-one"]
            }
          ]
        }
      }
    }

    previous_report = GitHubRepositoryListing.run(nil, onboarding_state)
    refute GitHubRepositoryListing.blocked?(previous_report)

    Application.put_env(:jido_code, :setup_github_repository_fetcher, fn _context ->
      {:error, {"github_repository_fetch_timeout", "GitHub API request timed out."}}
    end)

    report = GitHubRepositoryListing.run(previous_report, onboarding_state)

    assert GitHubRepositoryListing.blocked?(report)
    assert report.error_type == "github_repository_fetch_timeout"
    assert report.repositories == previous_report.repositories
    assert report.detail =~ "preserved for retry"
  end

  test "run/2 prefers installation sync repository metadata when available" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "path" => "github_app",
              "status" => "ready",
              "repository_access" => "confirmed",
              "repositories" => ["owner/repo-one"]
            }
          ]
        }
      },
      "7" => %{
        "installation_sync" => %{
          "status" => "ready",
          "event" => "installation_repositories",
          "action" => "added",
          "installation_id" => 321,
          "detail" =>
            "Installation sync processed `installation_repositories.added` and updated accessible repository metadata.",
          "remediation" => "Installation metadata is current.",
          "accessible_repositories" => [
            %{"id" => "repo_100", "full_name" => "owner/repo-three"},
            %{"id" => "repo_101", "full_name" => "owner/repo-four"}
          ]
        }
      }
    }

    report = GitHubRepositoryListing.run(nil, onboarding_state)

    refute GitHubRepositoryListing.blocked?(report)
    assert report.status == :ready
    assert report.detail =~ "installation_repositories.added"

    assert GitHubRepositoryListing.repository_full_names(report) == [
             "owner/repo-four",
             "owner/repo-three"
           ]
  end

  test "run/2 surfaces stale warning and retry guidance from installation sync metadata" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "path" => "github_app",
              "status" => "ready",
              "repository_access" => "confirmed",
              "repositories" => ["owner/repo-one"]
            }
          ]
        }
      },
      "7" => %{
        "installation_sync" => %{
          "status" => "stale",
          "event" => "installation",
          "action" => "created",
          "error_type" => "github_installation_sync_stale",
          "detail" =>
            "Installation sync failed while processing `installation.created`. Repository availability may be stale.",
          "remediation" => "Retry repository refresh in step 7 after confirming GitHub App installation access.",
          "accessible_repositories" => ["owner/repo-one"]
        }
      }
    }

    report = GitHubRepositoryListing.run(nil, onboarding_state)

    assert GitHubRepositoryListing.blocked?(report)
    assert report.status == :blocked
    assert report.error_type == "github_installation_sync_stale"
    assert report.detail =~ "may be stale"
    assert report.remediation =~ "Retry repository refresh in step 7"

    assert GitHubRepositoryListing.repository_full_names(report) == ["owner/repo-one"]
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
