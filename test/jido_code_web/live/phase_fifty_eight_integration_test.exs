defmodule JidoCodeWeb.PhaseFiftyEightIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: baseline.surface.public_entry_routes
  # covers: baseline.surface.welcome_landing_copy
  # covers: baseline.surface.root_redirects_to_welcome
  # covers: auth.system.ready_state_local_auth_handoff
  # covers: auth.operator_settings.hidden_during_bootstrap_entry
  # covers: setup.onboarding.post_bootstrap_start_surface
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User

  setup do
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)

    on_exit(fn ->
      restore_env(:system_config, original_config)
      restore_env(:system_config_loader, original_loader)
    end)

    Application.delete_env(:jido_code, :system_config_loader)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{},
      default_environment: :sprite,
      workspace_root: nil
    })

    :ok
  end

  test "58.3.1 bootstrap-required and continue-setup routes keep welcome public and setup gated", %{
    conn: conn
  } do
    root_response = get(conn, ~p"/")
    assert redirected_to(root_response, 302) == "/welcome"

    {:ok, bootstrap_view, bootstrap_html} = live(conn, ~p"/welcome", on_error: :warn)

    assert bootstrap_html =~ "Create your admin account"
    refute has_element?(bootstrap_view, "#provider-login-settings")
    assert_live_redirect(live(conn, ~p"/dashboard", on_error: :warn), "/welcome")

    register_owner("phase58-continue-owner@example.com", "owner-password-123")
    Application.put_env(:jido_code, :system_config, continue_setup_config("phase58-continue-owner@example.com"))

    {:ok, sign_in_view, _html} = live(conn, ~p"/sign-in", on_error: :warn)

    sign_in_view
    |> form("form[action='/auth/user/password/sign_in']", %{
      "user" => %{
        "email" => "phase58-continue-owner@example.com",
        "password" => "owner-password-123"
      }
    })
    |> render_submit()

    auth_redirect_path =
      sign_in_view
      |> assert_redirect()
      |> redirect_path()

    auth_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(auth_response, 302) == "/setup"

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase58-continue-owner@example.com", "owner-password-123")

    assert_live_redirect(live(recycle(authed_conn), ~p"/dashboard", on_error: :warn), "/setup")
    assert_live_redirect(live(recycle(authed_conn), ~p"/welcome", on_error: :warn), "/setup")
  end

  test "58.3.2 ready-state auth hands off to dashboard while sign-out returns to public welcome", %{
    conn: conn
  } do
    register_owner("phase58-ready-owner@example.com", "owner-password-123")
    Application.put_env(:jido_code, :system_config, ready_config())

    root_response = get(conn, ~p"/")
    assert redirected_to(root_response, 302) == "/welcome"

    {:ok, sign_in_view, _html} = live(conn, ~p"/sign-in", on_error: :warn)

    sign_in_view
    |> form("form[action='/auth/user/password/sign_in']", %{
      "user" => %{
        "email" => "phase58-ready-owner@example.com",
        "password" => "owner-password-123"
      }
    })
    |> render_submit()

    auth_redirect_path =
      sign_in_view
      |> assert_redirect()
      |> redirect_path()

    auth_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(auth_response, 302) == "/dashboard"

    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{
          "email" => "phase58-ready-owner@example.com",
          "password" => "owner-password-123"
        },
        context: %{token_type: :sign_in}
      )

    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:token)

    return_to_response =
      conn
      |> init_test_session(%{})
      |> put_session(:return_to, "/settings")
      |> get(owner_sign_in_with_token_path(strategy, token))

    assert redirected_to(return_to_response, 302) == "/settings"

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase58-ready-owner@example.com", "owner-password-123")

    {:ok, welcome_view, welcome_html} =
      live(recycle(authed_conn), ~p"/welcome", on_error: :warn)

    assert has_element?(welcome_view, "#welcome-open-dashboard", "Open Dashboard")
    assert has_element?(welcome_view, "#welcome-open-settings", "Open Settings")
    assert has_element?(welcome_view, "#welcome-operator-settings-handoff", "Auth & Integrations Live In Settings")
    assert has_element?(welcome_view, ~s|a[href="/settings/auth"]#welcome-open-auth-settings|, "Open Auth & Integrations")
    refute has_element?(welcome_view, "#provider-login-settings")

    refute welcome_html =~
             "Product routes, demos, setup flows, APIs, and workbench surfaces are commented out until the new spec-led baseline is validated."

    sign_out_response = get(authed_conn, ~p"/sign-out")

    assert redirected_to(sign_out_response, 302) == "/"
    assert redirected_to(sign_out_response |> recycle() |> get(~p"/"), 302) == "/welcome"

    signed_out_html =
      sign_out_response
      |> recycle()
      |> get(~p"/welcome")
      |> html_response(200)

    assert signed_out_html =~ "Sign In"
    refute signed_out_html =~ "phase58-ready-owner@example.com"
    refute signed_out_html =~ "Create your admin account"
  end

  test "58.3.3 phase 58 plan and current-truth specs remain aligned" do
    phase_plan =
      repo_file!(".spec/planning/phase-58-welcome-bootstrap-and-ready-state-routing-foundation.md")

    baseline_spec = repo_file!(".spec/specs/baseline_surface.spec.md")
    auth_spec = repo_file!(".spec/specs/authentication_system.spec.md")
    operator_spec = repo_file!(".spec/specs/operator_auth_settings.spec.md")
    setup_spec = repo_file!(".spec/specs/setup_onboarding.spec.md")
    package_spec = repo_file!(".spec/specs/package.spec.md")

    assert phase_plan =~ "[x] 58 Phase 58 - Welcome Bootstrap And Ready-State Routing Foundation"
    assert phase_plan =~ "[x] 58.1 Section - Default Route And Redirect Ownership"
    assert phase_plan =~ "[x] 58.2 Section - Welcome Surface Slimming And Handoff Copy"
    assert phase_plan =~ "[x] 58.3 Section - Phase Integration Tests"

    assert baseline_spec =~ "test/jido_code_web/live/phase_fifty_eight_integration_test.exs"
    assert auth_spec =~ "test/jido_code_web/live/phase_fifty_eight_integration_test.exs"
    assert operator_spec =~ "test/jido_code_web/live/phase_fifty_eight_integration_test.exs"
    assert setup_spec =~ "test/jido_code_web/live/phase_fifty_eight_integration_test.exs"
    assert package_spec =~ "test/jido_code_web/live/phase_fifty_eight_integration_test.exs"
  end

  defp continue_setup_config(owner_email) do
    %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "System prerequisites verified (welcome flow)."},
        "2" => %{
          "owner_email" => owner_email,
          "owner_mode" => "created",
          "registration_actions_disabled" => true,
          "validated_note" => "Owner account bootstrapped."
        }
      },
      default_environment: :sprite,
      workspace_root: nil
    }
  end

  defp ready_config do
    %{
      onboarding_completed: true,
      onboarding_step: 8,
      onboarding_state: %{},
      default_environment: :sprite,
      workspace_root: nil
    }
  end

  defp assert_live_redirect({:error, {:redirect, %{to: path}}}, expected) when path == expected,
    do: :ok

  defp assert_live_redirect({:error, {:live_redirect, %{to: path}}}, expected)
       when path == expected,
       do: :ok

  defp assert_live_redirect(other, expected) do
    ExUnit.Assertions.flunk("expected live redirect to #{expected}, got: #{inspect(other)}")
  end

  defp redirect_path({path, _flash}) when is_binary(path), do: path
  defp redirect_path(path) when is_binary(path), do: path

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

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
