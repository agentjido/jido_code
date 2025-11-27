defmodule JidoCode.Application do
  @moduledoc """
  OTP Application for JidoCode.

  The supervision tree is organized into three main subsystems:

  1. **Infrastructure** - PubSub, Registry for core communication
  2. **Agents** - Dynamic supervisor for LLM and tool agents
  3. **TUI** - Terminal user interface (started last)

  ## Supervision Strategy

  Uses `:one_for_one` at the top level to ensure independent failure handling.
  Agent crashes don't affect the TUI, and vice versa.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # PubSub for agent-TUI communication
      {Phoenix.PubSub, name: JidoCode.PubSub},

      # Registry for agent lookup
      {Registry, keys: :unique, name: JidoCode.AgentRegistry},

      # DynamicSupervisor for agent processes
      JidoCode.AgentSupervisor

      # Future children will be added here:
      # - JidoCode.Tools.Manager (Phase 3)
      # - JidoCode.TUI (Phase 4)
    ]

    opts = [strategy: :one_for_one, name: JidoCode.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
