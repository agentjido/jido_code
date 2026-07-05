defmodule Mix.Tasks.ControlPlane.Export do
  @shortdoc "Exports the embedded control-plane store"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    JidoCode.Mix.ControlPlane.run!(:export, args)
  end
end
