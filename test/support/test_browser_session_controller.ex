defmodule JidoCodeWeb.TestBrowserSessionController do
  @moduledoc false
  use JidoCodeWeb, :controller

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCodeWeb.BrowserSetup

  def create(conn, params) do
    strategy = Info.strategy!(User, :password)
    redirect_path = Map.get(params, "to", "/setup")

    {:ok, owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{
          "email" => BrowserSetup.owner_email(),
          "password" => BrowserSetup.owner_password()
        },
        context: %{token_type: :sign_in}
      )

    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:token)

    conn
    |> put_session(:return_to, redirect_path)
    |> redirect(to: owner_sign_in_with_token_path(strategy, token))
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
end
