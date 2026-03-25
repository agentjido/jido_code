defmodule Mix.Tasks.Command do
  use Mix.Task

  @shortdoc "Run Jido command CLI operations from Mix"

  @moduledoc """
  Direct Mix entrypoint for `jido_command` CLI operations.

  Examples:

      mix command list
      mix command code-review --params '{"target_file":"lib/foo.ex"}'
      mix command dispatch code-review --params '{"target_file":"lib/foo.ex"}'
  """

  @impl Mix.Task
  def run(args) when is_list(args) do
    Jido.Code.Command.Escript.main(args)
  end
end
