defmodule Mix.Tasks.ControlPlane.Query do
  @shortdoc "Runs bounded embedded control-plane diagnostic queries"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    JidoCode.Mix.ControlPlane.run!(:query, args)
  end
end
