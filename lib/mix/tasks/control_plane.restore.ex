defmodule Mix.Tasks.ControlPlane.Restore do
  @shortdoc "Restores the embedded control-plane store from an exported graph file"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    JidoCode.Mix.ControlPlane.run!(:restore, args)
  end
end
