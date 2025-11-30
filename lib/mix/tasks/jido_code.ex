defmodule Mix.Tasks.JidoCode do
  @moduledoc """
  Starts the JidoCode TUI application.

  ## Usage

      mix jido_code

  This starts the interactive terminal interface for JidoCode.
  Press Ctrl+C to exit.

  ## Configuration

  Before running, ensure you have configured a provider and model.
  Create `~/.jido_code/settings.json` with:

      {
        "provider": "anthropic",
        "model": "claude-sonnet-4-20250514"
      }

  Or use the `/provider` and `/model` commands within the TUI.
  """

  use Mix.Task

  @shortdoc "Starts the JidoCode TUI"

  @impl Mix.Task
  def run(_args) do
    # Ensure the application is started
    Mix.Task.run("app.start")

    # Start the LLM agent
    {:ok, _pid} =
      JidoCode.AgentSupervisor.start_agent(%{
        name: :llm_agent,
        module: JidoCode.Agents.LLMAgent,
        args: []
      })

    # Run the TUI (blocks until quit)
    JidoCode.TUI.run()
  end
end
