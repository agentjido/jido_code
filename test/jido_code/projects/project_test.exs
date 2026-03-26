defmodule JidoCode.Projects.ProjectTest do
  # covers: setup.onboarding.repo_source_per_project
  use JidoCode.DataCase, async: false

  alias JidoCode.Projects.Project

  test "github projects backfill source identity from github_full_name" do
    {:ok, project} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "main"
      })

    assert project.source_kind == :github
    assert project.source_identifier == "owner/repo-one"
    assert project.github_full_name == "owner/repo-one"
    assert project.local_path == nil
  end

  test "local projects derive source identity and name from the local path" do
    {:ok, project} =
      Project.create(%{
        source_kind: :local,
        local_path: "/Users/example/workspaces/repo-local",
        default_branch: "main"
      })

    assert project.name == "repo-local"
    assert project.source_kind == :local
    assert project.source_identifier == "/Users/example/workspaces/repo-local"
    assert project.local_path == "/Users/example/workspaces/repo-local"
    assert project.github_full_name == nil
  end
end
