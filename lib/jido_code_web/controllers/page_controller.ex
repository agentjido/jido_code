defmodule JidoCodeWeb.PageController do
  use JidoCodeWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/welcome")
  end

  def register_redirect(conn, _params) do
    redirect(conn, to: ~p"/welcome")
  end

  def index conn, _params do
    render(conn, :index)
  end
end
