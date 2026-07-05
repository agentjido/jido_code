defmodule JidoCodeWeb.TestBrowserSessionController do
  @moduledoc false
  use JidoCodeWeb, :controller

  alias JidoCode.Accounts.SessionTokens
  alias JidoCode.Setup.OwnerStore
  alias JidoCodeWeb.BrowserSetup

  def create(conn, params) do
    redirect_path = Map.get(params, "to", "/setup")
    _password = BrowserSetup.owner_password()
    {:ok, owner} = OwnerStore.get_by_email(BrowserSetup.owner_email())
    {:ok, token} = SessionTokens.issue(owner)

    conn
    |> configure_session(renew: true)
    |> put_session("product_user_token", token)
    |> put_session("product_user_email", to_string(owner.email))
    |> redirect(to: redirect_path)
  end
end
