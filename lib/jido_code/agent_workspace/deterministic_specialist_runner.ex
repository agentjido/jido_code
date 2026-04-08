defmodule JidoCode.AgentWorkspace.DeterministicSpecialistRunner do
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  @moduledoc false

  @behaviour JidoCode.AgentWorkspace.SpecialistRunner

  @impl true
  def run(agent_module, _pid, instruction, opts)
      when is_atom(agent_module) and is_binary(instruction) and is_list(opts) do
    tool_context = Keyword.get(opts, :tool_context, %{})
    workspace_path = Map.get(tool_context, :workspace_path) || "unknown"
    semantic_ready? = get_in(tool_context, [:latest_import_status, :ready?]) || false

    role =
      agent_module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    {:ok,
     %{
       role: role,
       instruction: instruction,
       workspace_path: workspace_path,
       semantic_ready?: semantic_ready?,
       summary: "deterministic #{role} response for #{instruction}"
     }}
  end
end
