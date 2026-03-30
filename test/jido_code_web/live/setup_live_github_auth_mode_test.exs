defmodule JidoCodeWeb.SetupLiveGitHubAuthModeTest do
  # covers: auth.github_integration.non_blocking_local_auth
  use JidoCodeWeb.ConnCase, async: false

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User

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

    assert has_element?(view, "#setup-start-choice-github")
    assert has_element?(view, "#setup-start-choice-later")
    refute has_element?(view, "#setup-start-choice-local_repo")
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

  defp authenticate_owner_conn(conn, email, password) do
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

    auth_response = conn |> get(owner_sign_in_with_token_path(strategy, token))
    recycle(auth_response)
  end

  defp owner_sign_in_with_token_path(strategy, token) do
    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _ -> nil
      end)

    path = Path.join("/auth", String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/"))
    query = URI.encode_query(%{"token" => token})

    "#{path}?#{query}"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
