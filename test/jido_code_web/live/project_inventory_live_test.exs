defmodule JidoCodeWeb.ProjectInventoryLiveTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "supports repo search and filtering on /repos and preserves query context in repo links",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    %{route_id: repo_alpha_id} =
      provision_managed_repo!(%{
        name: "repo-alpha",
        github_full_name: "owner/repo-alpha",
        default_branch: "main",
        workspace_settings: %{}
      })

    %{route_id: repo_beta_id} =
      provision_managed_repo!(%{
        name: "repo-beta",
        github_full_name: "owner/repo-beta",
        default_branch: "release",
        workspace_settings: %{}
      })

    %{route_id: repo_gamma_id} =
      provision_managed_repo!(%{
        name: "repo-gamma",
        github_full_name: "owner/repo-gamma",
        default_branch: "main",
        workspace_settings: %{}
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos", on_error: :warn)

    assert has_element?(view, "#project-inventory-table")
    assert has_element?(view, "#project-inventory-github-full-name-#{repo_alpha_id}", "owner/repo-alpha")
    assert has_element?(view, "#project-inventory-github-full-name-#{repo_beta_id}", "owner/repo-beta")
    assert has_element?(view, "#project-inventory-github-full-name-#{repo_gamma_id}", "owner/repo-gamma")

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

    refute has_element?(view, "#project-inventory-github-full-name-#{repo_alpha_id}")
    assert has_element?(view, "#project-inventory-github-full-name-#{repo_beta_id}", "owner/repo-beta")
    refute has_element?(view, "#project-inventory-github-full-name-#{repo_gamma_id}")
    assert has_element?(view, "#project-inventory-results-count", "Showing 1 of 3")

    encoded_return_to = URI.encode_www_form(inventory_state_path)

    assert has_element?(
             view,
             "#project-inventory-open-#{repo_beta_id}[href='/repos/#{repo_beta_id}?return_to=#{encoded_return_to}']"
           )
  end

  test "empty search query resets to default inventory results without error noise", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    %{route_id: repo_alpha_id} =
      provision_managed_repo!(%{
        name: "repo-alpha",
        github_full_name: "owner/repo-alpha",
        default_branch: "main",
        workspace_settings: %{}
      })

    %{route_id: repo_beta_id} =
      provision_managed_repo!(%{
        name: "repo-beta",
        github_full_name: "owner/repo-beta",
        default_branch: "release",
        workspace_settings: %{}
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
    assert has_element?(view, "#project-inventory-github-full-name-#{repo_alpha_id}", "owner/repo-alpha")
    refute has_element?(view, "#project-inventory-github-full-name-#{repo_beta_id}")

    view
    |> element("#project-inventory-filters-form")
    |> render_change(%{
      "filters" => %{
        "search" => "   ",
        "default_branch" => "all"
      }
    })

    assert_patch(view, "/repos")
    assert has_element?(view, "#project-inventory-github-full-name-#{repo_alpha_id}", "owner/repo-alpha")
    assert has_element?(view, "#project-inventory-github-full-name-#{repo_beta_id}", "owner/repo-beta")
    assert has_element?(view, "#project-inventory-results-count", "Showing 2 of 2")
    refute has_element?(view, "#project-inventory-filter-validation-notice")
  end

  test "invalid query params reset inventory to defaults without error noise", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    %{route_id: repo_alpha_id} =
      provision_managed_repo!(%{
        name: "repo-alpha",
        github_full_name: "owner/repo-alpha",
        default_branch: "main",
        workspace_settings: %{}
      })

    %{route_id: repo_beta_id} =
      provision_managed_repo!(%{
        name: "repo-beta",
        github_full_name: "owner/repo-beta",
        default_branch: "release",
        workspace_settings: %{}
      })

    invalid_path =
      "/repos?" <>
        URI.encode_query(%{
          "search" => "<script>alert('x')</script>",
          "default_branch" => "unknown-branch"
        })

    {:ok, view, _html} = live(recycle(authed_conn), invalid_path, on_error: :warn)

    assert has_element?(view, "#project-inventory-github-full-name-#{repo_alpha_id}", "owner/repo-alpha")
    assert has_element?(view, "#project-inventory-github-full-name-#{repo_beta_id}", "owner/repo-beta")
    assert has_element?(view, "#project-inventory-results-count", "Showing 2 of 2")
    assert has_element?(view, "#project-inventory-filter-search[value='']")

    assert has_element?(
             view,
             "#project-inventory-filter-default-branch option[value='all'][selected]"
           )

    refute has_element?(view, "#project-inventory-filter-validation-notice")
  end
end
