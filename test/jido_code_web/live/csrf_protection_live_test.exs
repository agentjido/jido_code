defmodule JidoCodeWeb.CsrfProtectionLiveTest do
  # covers: architecture.policy_layers.operator_surfaces_propagate_current_actor_for_repo_mutations
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.GitHub.Repo, as: GitHubRepo

  @mutating_methods [:post, :put, :patch, :delete]

  test "browser mutating verbs on /settings require valid csrf tokens", %{conn: _conn} do
    authed_conn = authenticated_owner_conn()

    for method <- @mutating_methods do
      response_conn =
        authed_conn
        |> recycle()
        |> request_with_method(method, ~p"/settings")

      assert response_conn.status in [403, 404]
    end
  end

  test "valid owner session with matching csrf token mutates settings state", %{conn: _conn} do
    authed_conn = authenticated_owner_conn()

    settings_conn = authed_conn |> recycle() |> get(~p"/settings")
    csrf_token = settings_conn |> html_response(200) |> csrf_token_from_html()

    for method <- @mutating_methods do
      response_conn =
        settings_conn
        |> recycle()
        |> put_req_header("x-csrf-token", csrf_token)
        |> request_with_method(method, ~p"/settings")

      assert response_conn.status == 404
    end

    initial_repo_count = repo_count()
    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings", on_error: :warn)

    view
    |> element("button[phx-click='open_add_modal']")
    |> render_click()

    assert has_element?(view, "#add-repo-modal")

    unique_suffix = System.unique_integer([:positive])
    owner = "csrf-owner-#{unique_suffix}"
    name = "csrf-repo-#{unique_suffix}"
    full_name = "#{owner}/#{name}"

    view
    |> form("#add-repo-modal form", %{
      "form" => %{
        "owner" => owner,
        "name" => name
      }
    })
    |> render_submit()

    assert has_element?(view, "#repos-list", full_name)
    assert repo_count() == initial_repo_count + 1
    assert GitHubRepo.get_by_full_name!(full_name)
  end

  test "invalid csrf token blocks /settings mutation attempts and keeps state unchanged", %{
    conn: _conn
  } do
    authed_conn = authenticated_owner_conn()
    initial_repo_count = repo_count()

    response_conn =
      authed_conn
      |> recycle()
      |> put_req_header("x-csrf-token", "invalid-csrf-token")
      |> post(~p"/settings", %{
        "form" => %{
          "owner" => "forged-owner",
          "name" => "forged-repo",
          "webhook_secret" => "forged-secret"
        }
      })

    assert response_conn.status in [403, 404]

    assert repo_count() == initial_repo_count
  end

  defp authenticated_owner_conn do
    unique_suffix = System.unique_integer([:positive])
    email = "owner-#{unique_suffix}@example.com"
    password = "owner-password-123"

    register_owner(email, password)
    authenticate_owner_conn(email, password)
  end

  defp register_owner(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, _owner} =
      Strategy.action(
        strategy,
        :register,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        },
        context: %{token_type: :sign_in}
      )

    :ok
  end

  defp authenticate_owner_conn(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{"email" => email, "password" => password},
        context: %{token_type: :sign_in}
      )

    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:token)

    auth_response = build_conn() |> get(owner_sign_in_with_token_path(strategy, token))
    assert redirected_to(auth_response, 302) == "/"
    recycle(auth_response)
  end

  defp owner_sign_in_with_token_path(strategy, token) do
    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _other -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})
    "#{path}?#{query}"
  end

  defp csrf_token_from_html(html) do
    [_match, csrf_token] = Regex.run(~r/<meta name=\"csrf-token\" content=\"([^\"]+)\"/, html)
    csrf_token
  end

  defp request_with_method(conn, :post, path), do: post(conn, path, %{})
  defp request_with_method(conn, :put, path), do: put(conn, path, %{})
  defp request_with_method(conn, :patch, path), do: patch(conn, path, %{})
  defp request_with_method(conn, :delete, path), do: delete(conn, path, %{})

  defp repo_count, do: GitHubRepo.read!() |> length()
end
