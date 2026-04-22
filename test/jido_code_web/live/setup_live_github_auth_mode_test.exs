defmodule JidoCodeWeb.SetupLiveGitHubAuthModeTest do
  # covers: auth.github_integration.non_blocking_local_auth
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_target = System.get_env("BURRITO_TARGET")

    on_exit(fn ->
      restore_env(:system_config, original_config)
      restore_system_env("BURRITO_TARGET", original_target)
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "2" => %{
          "owner_email" => "owner@example.com",
          "owner_mode" => "created",
          "registration_actions_disabled" => true,
          "validated_note" => "Owner account bootstrapped."
        }
      }
    })

    System.delete_env("BURRITO_TARGET")
    :ok
  end

  test "cloud installs keep GitHub follow-up available without blocking local admin entry", %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-complete-continue", "Continue to dashboard")
    assert has_element?(view, "#setup-start-choice-github")
    assert has_element?(view, "#setup-start-choice-later")
    refute has_element?(view, "#setup-start-choice-local_repo")
  end
end
