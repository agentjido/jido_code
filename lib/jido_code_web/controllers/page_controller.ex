defmodule JidoCodeWeb.PageController do
  use JidoCodeWeb, :controller

  alias JidoCode.Accounts.SessionTokens
  alias JidoCode.Setup.BootstrapStatus

  def home(%Plug.Conn{request_path: "/sign-in"} = conn, _params) do
    case signed_in_product_user?(conn) do
      true -> redirect(conn, to: signed_in_destination())
      false -> redirect(conn, to: ~p"/welcome")
    end
  end

  def home(conn, _params) do
    redirect(conn, to: ~p"/welcome")
  end

  def register_redirect(conn, _params) do
    redirect(conn, to: ~p"/welcome")
  end

  defp signed_in_product_user?(conn) do
    case conn |> get_session("product_user_token") |> SessionTokens.verify() do
      {:ok, _user} -> true
      _other -> false
    end
  end

  defp signed_in_destination do
    case BootstrapStatus.current().state do
      :continue_setup -> ~p"/setup"
      :ready -> ~p"/dashboard"
      _other -> ~p"/welcome"
    end
  end
end
