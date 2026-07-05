defmodule JidoCodeWeb.Plugs.PublicBootstrapAuthGate do
  # covers: baseline.surface.public_entry_routes
  # covers: baseline.surface.auth_entrypoints_visible
  @moduledoc """
  Redirects public auth entrypoints toward the first-run bootstrap screen.
  """

  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn

  alias JidoCode.Setup.BootstrapStatus
  alias JidoCode.Setup.BootstrapToken
  alias JidoCode.Accounts.SessionTokens

  @magic_auth_paths ["/auth/user/magic_link", "/auth/user/magic_link/request"]

  def init(opts), do: opts

  def call(%Plug.Conn{halted: true} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn = clear_stale_product_session(conn)
    status = BootstrapStatus.current()

    cond do
      register_request?(conn) ->
        redirect_to_welcome(conn)

      sign_in_request?(conn) and status.state == :bootstrap_required ->
        redirect_to_welcome(conn)

      magic_request?(conn) and status.state == :bootstrap_required ->
        redirect_to_welcome(conn)

      true ->
        conn
    end
  end

  defp register_request?(%Plug.Conn{request_path: "/register"}), do: true
  defp register_request?(%Plug.Conn{method: "POST", request_path: "/auth/user/password/register"}), do: true
  defp register_request?(_conn), do: false

  defp sign_in_request?(%Plug.Conn{request_path: "/sign-in"}), do: true
  defp sign_in_request?(_conn), do: false

  defp magic_request?(%Plug.Conn{request_path: request_path}) do
    request_path in @magic_auth_paths or String.starts_with?(request_path, "/magic_link/")
  end

  defp redirect_to_welcome(conn) do
    conn
    |> redirect(to: "/welcome")
    |> halt()
  end

  defp clear_stale_product_session(conn) do
    case get_session(conn, "product_user_token") || get_session(conn, :product_user_token) do
      token when is_binary(token) and token != "" ->
        if valid_product_token?(token) do
          conn
        else
          conn
          |> delete_session("product_user_token")
          |> delete_session(:product_user_token)
          |> delete_session("product_user_email")
          |> delete_session(:product_user_email)
          |> delete_session("user_token")
          |> delete_session(:user_token)
        end

      _other ->
        conn
    end
  end

  defp valid_product_token?(token) do
    match?({:ok, _user}, SessionTokens.verify(token)) or match?({:ok, _claims}, BootstrapToken.verify(token))
  end
end
