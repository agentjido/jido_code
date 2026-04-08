defmodule JidoCode.AgentWorkspace.RuntimeSpecialistRunner do
  # covers: architecture.agent_os_integration.signal_routing_within_pod
  @moduledoc false

  @behaviour JidoCode.AgentWorkspace.SpecialistRunner

  @impl true
  def run(agent_module, pid, instruction, opts)
      when is_atom(agent_module) and is_pid(pid) and is_binary(instruction) and is_list(opts) do
    agent_module.ask_sync(pid, instruction, opts)
  end
end
