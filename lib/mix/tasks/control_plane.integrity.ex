defmodule Mix.Tasks.ControlPlane.Integrity do
  @shortdoc "Checks embedded control-plane store integrity"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    JidoCode.Mix.ControlPlane.run!(:integrity, args)
  end
end
