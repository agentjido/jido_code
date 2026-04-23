alias Ecto.Adapters.SQL.Sandbox
alias JidoCode.Repo
alias JidoCodeWeb.BrowserSetup
alias JidoCodeWeb.Endpoint

port = String.to_integer(System.get_env("PORT", "4100"))
endpoint_config = Application.get_env(:jido_code, Endpoint, [])

Application.put_env(:jido_code, :runtime_mode, :prod)
Application.put_env(
  :jido_code,
  Endpoint,
  Keyword.merge(endpoint_config, url: [host: "localhost", port: port, scheme: "http"])
)

Sandbox.mode(Repo, :auto)
BrowserSetup.apply_scenario!("normal")

IO.puts("setup browser server ready on port #{port}")
