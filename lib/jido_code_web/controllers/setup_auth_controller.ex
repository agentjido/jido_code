defmodule JidoCodeWeb.SetupAuthController do
  @moduledoc false

  use JidoCodeWeb, :controller

  alias JidoCode.Accounts.User
  alias JidoCode.Setup.{BootstrapStatus, BootstrapToken, OwnerStore}

  def sign_in(conn, %{"token" => token}) do
    with {:ok, %{"email" => email}} <- BootstrapToken.verify(token),
         {:ok, %User{} = owner} <- OwnerStore.get_by_email(email) do
      conn
      |> configure_session(renew: true)
      |> put_session("product_user_token", token)
      |> put_session("product_user_email", to_string(owner.email))
      |> put_flash(:info, "You are now signed in")
      |> redirect(to: setup_return_to())
    else
      _error ->
        conn
        |> put_flash(:error, "Incorrect email or password")
        |> redirect(to: ~p"/sign-in")
    end
  end

  def sign_in(conn, _params) do
    conn
    |> put_flash(:error, "Incorrect email or password")
    |> redirect(to: ~p"/sign-in")
  end

  defp setup_return_to do
    case BootstrapStatus.current().state do
      :continue_setup -> ~p"/setup"
      :ready -> ~p"/dashboard"
      _other -> ~p"/setup"
    end
  end
end
