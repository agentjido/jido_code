defmodule JidoCode.Application do
  @moduledoc """
  OTP Application for JidoCode.

  The supervision tree is organized into three main subsystems:

  1. **Infrastructure** - PubSub, Registry for core communication
  2. **Agents** - Dynamic supervisor for LLM and tool agents
  3. **TUI** - Terminal user interface (started last, optional)

  ## Supervision Strategy

  Uses `:one_for_one` at the top level to ensure independent failure handling.
  Agent crashes don't affect the TUI, and vice versa.

  ## TUI Configuration

  The TUI is not started by default during application startup. To run the TUI:

      JidoCode.TUI.run()

  This allows tests to run without TUI interference and gives control to the
  main script for when to take over the terminal.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Settings cache (must start before anything that might use Settings)
      JidoCode.Settings.Cache,

      # PubSub for agent-TUI communication
      {Phoenix.PubSub, name: JidoCode.PubSub},

      # Registry for agent lookup
      {Registry, keys: :unique, name: JidoCode.AgentRegistry},

      # Tool registry for LLM function calling
      JidoCode.Tools.Registry,

      # Lua sandbox for tool execution
      JidoCode.Tools.Manager,

      # DynamicSupervisor for agent processes
      JidoCode.AgentSupervisor

      # Note: TUI is not started automatically.
      # Call JidoCode.TUI.run() to start the TUI interactively.
    ]

    opts = [strategy: :one_for_one, name: JidoCode.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
