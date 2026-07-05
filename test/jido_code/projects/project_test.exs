defmodule JidoCode.Projects.ProjectTest do
  # covers: setup.onboarding.repo_source_per_project
  # covers: architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.Actor
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

  test "requires an explicit actor when no compatibility policy actor is present" do
    Actor.clear_policy_actor()

    assert {:error, %{type: :forbidden}} =
             Project.create(%{
               name: "repo-policy",
               github_full_name: "owner/repo-policy",
               default_branch: "main"
             })

    assert {:ok, %Project{} = project} =
             Project.create(
               %{
                 name: "repo-policy-explicit",
                 github_full_name: "owner/repo-policy-explicit",
                 default_branch: "main"
               },
               actor: Actor.operator_actor(%{"id" => "operator-1", "email" => "operator-1@example.com"})
             )

    assert project.github_full_name == "owner/repo-policy-explicit"
  end
end
