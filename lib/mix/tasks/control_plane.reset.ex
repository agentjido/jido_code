defmodule Mix.Tasks.ControlPlane.Reset do
  @shortdoc "Resets the embedded control-plane store and reloads ontologies"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    JidoCode.Mix.ControlPlane.run!(:reset, args)
  end
end
