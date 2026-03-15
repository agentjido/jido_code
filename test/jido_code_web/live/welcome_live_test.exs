defmodule JidoCodeWeb.WelcomeLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  alias JidoCode.Accounts.User
  alias JidoCode.Repo

  import Phoenix.LiveViewTest

  @checked_at ~U[2026-02-13 12:34:56Z]

  setup do
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)
    original_saver = Application.get_env(:jido_code, :system_config_saver, :__missing__)
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_checker = Application.get_env(:jido_code, :setup_prerequisite_checker, :__missing__)
    original_runtime_mode = Application.get_env(:jido_code, :runtime_mode, :__missing__)

    on_exit(fn ->
      restore_env(:system_config_loader, original_loader)
      restore_env(:system_config_saver, original_saver)
      restore_env(:system_config, original_config)
      restore_env(:setup_prerequisite_checker, original_checker)
      restore_env(:runtime_mode, original_runtime_mode)
    end)

    Application.delete_env(:jido_code, :system_config_loader)
    Application.delete_env(:jido_code, :system_config_saver)
    Application.put_env(:jido_code, :runtime_mode, :test)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{}
    })

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      passing_prerequisite_report()
    end)

    reset_owner_state!()

    :ok
  end

  test "renders welcome page with friendly messaging", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/welcome")

    assert html =~ "Welcome to Jido Code"
    assert html =~ "only take a minute"
    assert has_element?(view, "#system-check")
  end

  test "shows system check status and registration form on pass", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/welcome")

    # After connected mount, prereqs should run and pass
    html = render(view)
    assert html =~ "System ready"
    assert has_element?(view, "#welcome-owner-form")
    assert html =~ "Create your admin account"
  end

  test "shows disabled state when prereqs are checking", %{conn: conn} do
    # Use a slow checker to catch the checking state
    test_pid = self()

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      send(test_pid, :checker_called)
      Process.sleep(100)
      passing_prerequisite_report()
    end)

    {:ok, _view, html} = live(conn, ~p"/welcome")

    # Initial static render should show checking state
    assert html =~ "Complete system check first"
  end

  test "shows error details when prereqs fail", %{conn: conn} do
    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      failing_prerequisite_report()
    end)

    {:ok, view, _html} = live(conn, ~p"/welcome")

    html = render(view)
    assert html =~ "system requirements"
    assert html =~ "Show technical details"
    refute has_element?(view, "#welcome-owner-form")
  end

  test "recheck_prereqs reruns checks", %{conn: conn} do
    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      failing_prerequisite_report()
    end)

    {:ok, view, _html} = live(conn, ~p"/welcome")

    # Now switch to passing
    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      passing_prerequisite_report()
    end)

    view |> element("button", "Re-check") |> render_click()
    html = render(view)
    assert html =~ "System ready"
  end

  test "successful owner registration persists steps 1+2 and redirects to auth", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/welcome")

    view
    |> form("#welcome-owner-form", %{
      "owner" => %{
        "email" => "admin@example.com",
        "password" => "secure-password-123",
        "password_confirmation" => "secure-password-123"
      }
    })
    |> render_submit()

    {auth_redirect_path, _flash} = assert_redirect(view)

    assert auth_redirect_path =~ "/auth/"
    assert auth_redirect_path =~ "sign_in_with_token"

    # Verify both steps persisted
    config = Application.get_env(:jido_code, :system_config)
    assert config.onboarding_step == 3
    assert Map.has_key?(config.onboarding_state, "1")
    assert Map.has_key?(config.onboarding_state, "2")
    assert config.onboarding_state["1"]["validated_note"] =~ "System prerequisites"
    assert config.onboarding_state["2"]["owner_email"] == "admin@example.com"
    assert config.onboarding_state["2"]["owner_mode"] == "created"
  end

  test "shows confirm mode when owner already exists", %{conn: conn} do
    create_owner!("existing@example.com", "existing-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{}
    })

    {:ok, view, _html} = live(conn, ~p"/welcome")

    html = render(view)
    assert html =~ "Welcome back"
    assert html =~ "Sign In &amp; Continue"
  end

  test "redirects to dashboard when onboarding is completed", %{conn: conn} do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: true,
      onboarding_step: 8,
      onboarding_state: %{}
    })

    assert {:error, {:live_redirect, %{to: "/dashboard"}}} = live(conn, ~p"/welcome")
  end

  test "redirects to setup when onboarding step >= 3", %{conn: conn} do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 4,
      onboarding_state: %{}
    })

    assert {:error, {:live_redirect, %{to: "/setup"}}} = live(conn, ~p"/welcome")
  end

  test "shows a friendly validation error when password is too short", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/welcome")

    view
    |> form("#welcome-owner-form", %{
      "owner" => %{
        "email" => "admin@example.com",
        "password" => "short",
        "password_confirmation" => "short"
      }
    })
    |> render_submit()

    html = render(view)
    assert has_element?(view, "#welcome-save-error", "at least 8 characters")
    refute html =~ "Bread Crumbs"
  end

  test "rejects malformed owner email addresses with a validation error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/welcome")

    view
    |> form("#welcome-owner-form", %{
      "owner" => %{
        "email" => "not-an-email",
        "password" => "secure-password-123",
        "password_confirmation" => "secure-password-123"
      }
    })
    |> render_submit()

    html = render(view)
    assert has_element?(view, "#welcome-save-error", "valid email address")
    refute html =~ "Bread Crumbs"
  end

  # -- Helpers --

  defp passing_prerequisite_report do
    %{
      checked_at: @checked_at,
      status: :pass,
      checks: [
        %{
          id: "database_connectivity",
          name: "Database connectivity",
          status: :pass,
          detail: "Successfully connected to Postgres.",
          remediation: "Confirm Postgres is reachable.",
          checked_at: @checked_at
        },
        %{
          id: "runtime_token_signing_secret",
          name: "Runtime configuration: TOKEN_SIGNING_SECRET",
          status: :pass,
          detail: "TOKEN_SIGNING_SECRET is configured.",
          remediation: "Set TOKEN_SIGNING_SECRET.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp failing_prerequisite_report do
    %{
      checked_at: @checked_at,
      status: :fail,
      checks: [
        %{
          id: "database_connectivity",
          name: "Database connectivity",
          status: :pass,
          detail: "Successfully connected to Postgres.",
          remediation: "Confirm Postgres is reachable.",
          checked_at: @checked_at
        },
        %{
          id: "runtime_token_signing_secret",
          name: "Runtime configuration: TOKEN_SIGNING_SECRET",
          status: :fail,
          detail: "Required runtime value TOKEN_SIGNING_SECRET is missing.",
          remediation: "Set TOKEN_SIGNING_SECRET in runtime config.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp reset_owner_state! do
    Repo.delete_all(User)
  end

  defp create_owner!(email, password) do
    strategy = AshAuthentication.Info.strategy!(User, :password)

    {:ok, user} =
      AshAuthentication.Strategy.action(
        strategy,
        :register,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        },
        context: %{token_type: :sign_in}
      )

    user
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
