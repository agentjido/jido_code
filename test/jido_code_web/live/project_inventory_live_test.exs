defmodule JidoCodeWeb.ProjectInventoryLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Projects.Project

  test "supports repo search and filtering on /repos and preserves query context in repo links",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project_alpha} =
      Project.create(%{
        name: "repo-alpha",
        github_full_name: "owner/repo-alpha",
        default_branch: "main",
        settings: %{}
      })

    {:ok, project_beta} =
      Project.create(%{
        name: "repo-beta",
        github_full_name: "owner/repo-beta",
        default_branch: "release",
        settings: %{}
      })

    {:ok, project_gamma} =
      Project.create(%{
        name: "repo-gamma",
        github_full_name: "owner/repo-gamma",
        default_branch: "main",
        settings: %{}
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos", on_error: :warn)

    assert has_element?(view, "#project-inventory-table")
    assert has_element?(view, "#project-inventory-github-full-name-#{project_alpha.id}", "owner/repo-alpha")
    assert has_element?(view, "#project-inventory-github-full-name-#{project_beta.id}", "owner/repo-beta")
    assert has_element?(view, "#project-inventory-github-full-name-#{project_gamma.id}", "owner/repo-gamma")

    view
    |> element("#project-inventory-filters-form")
    |> render_change(%{
      "filters" => %{
        "search" => "beta",
        "default_branch" => "release"
      }
    })

    inventory_state_path = "/repos?search=beta&default_branch=release"
    assert_patch(view, inventory_state_path)

    refute has_element?(view, "#project-inventory-github-full-name-#{project_alpha.id}")
    assert has_element?(view, "#project-inventory-github-full-name-#{project_beta.id}", "owner/repo-beta")
    refute has_element?(view, "#project-inventory-github-full-name-#{project_gamma.id}")
    assert has_element?(view, "#project-inventory-results-count", "Showing 1 of 3")

    encoded_return_to = URI.encode_www_form(inventory_state_path)

    assert has_element?(
             view,
             "#project-inventory-open-#{project_beta.id}[href='/repos/#{project_beta.id}?return_to=#{encoded_return_to}']"
           )
  end

  test "empty search query resets to default inventory results without error noise", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project_alpha} =
      Project.create(%{
        name: "repo-alpha",
        github_full_name: "owner/repo-alpha",
        default_branch: "main",
        settings: %{}
      })

    {:ok, project_beta} =
      Project.create(%{
        name: "repo-beta",
        github_full_name: "owner/repo-beta",
        default_branch: "release",
        settings: %{}
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos", on_error: :warn)

    view
    |> element("#project-inventory-filters-form")
    |> render_change(%{
      "filters" => %{
        "search" => "alpha",
        "default_branch" => "main"
      }
    })

    assert_patch(view, "/repos?search=alpha&default_branch=main")
    assert has_element?(view, "#project-inventory-github-full-name-#{project_alpha.id}", "owner/repo-alpha")
    refute has_element?(view, "#project-inventory-github-full-name-#{project_beta.id}")

    view
    |> element("#project-inventory-filters-form")
    |> render_change(%{
      "filters" => %{
        "search" => "   ",
        "default_branch" => "all"
      }
    })

    assert_patch(view, "/repos")
    assert has_element?(view, "#project-inventory-github-full-name-#{project_alpha.id}", "owner/repo-alpha")
    assert has_element?(view, "#project-inventory-github-full-name-#{project_beta.id}", "owner/repo-beta")
    assert has_element?(view, "#project-inventory-results-count", "Showing 2 of 2")
    refute has_element?(view, "#project-inventory-filter-validation-notice")
  end

  test "invalid query params reset inventory to defaults without error noise", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project_alpha} =
      Project.create(%{
        name: "repo-alpha",
        github_full_name: "owner/repo-alpha",
        default_branch: "main",
        settings: %{}
      })

    {:ok, project_beta} =
      Project.create(%{
        name: "repo-beta",
        github_full_name: "owner/repo-beta",
        default_branch: "release",
        settings: %{}
      })

    invalid_path =
      "/repos?" <>
        URI.encode_query(%{
          "search" => "<script>alert('x')</script>",
          "default_branch" => "unknown-branch"
        })

    {:ok, view, _html} = live(recycle(authed_conn), invalid_path, on_error: :warn)

    assert has_element?(view, "#project-inventory-github-full-name-#{project_alpha.id}", "owner/repo-alpha")
    assert has_element?(view, "#project-inventory-github-full-name-#{project_beta.id}", "owner/repo-beta")
    assert has_element?(view, "#project-inventory-results-count", "Showing 2 of 2")
    assert has_element?(view, "#project-inventory-filter-search[value='']")

    assert has_element?(
             view,
             "#project-inventory-filter-default-branch option[value='all'][selected]"
           )

    refute has_element?(view, "#project-inventory-filter-validation-notice")
  end
end
