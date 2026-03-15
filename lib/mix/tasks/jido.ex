defmodule Mix.Tasks.Jido do
  use Mix.Task

  @shortdoc "Compatibility alias for mix jidocode"

  @impl Mix.Task
  def run(args) when is_list(args), do: Mix.Task.run("jidocode", args)
end
