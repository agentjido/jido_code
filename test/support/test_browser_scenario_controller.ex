defmodule JidoCodeWeb.TestBrowserScenarioController do
  @moduledoc false
  use JidoCodeWeb, :controller

  alias JidoCodeWeb.BrowserSetup

  def update(conn, %{"mode" => mode}) do
    if BrowserSetup.valid_scenario?(mode) do
      BrowserSetup.apply_scenario!(mode)

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "scenario=#{mode}")
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(400, "invalid scenario")
    end
  end
end
