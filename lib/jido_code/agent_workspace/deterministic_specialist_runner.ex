defmodule JidoCode.AgentWorkspace.DeterministicSpecialistRunner do
  # covers: architecture.repository_runtime_integration.product_work_entrypoints_route_to_workspace
  @moduledoc false

  @behaviour JidoCode.AgentWorkspace.SpecialistRunner

  alias JidoCode.LLMSelection

  @impl true
  def run(agent_module, _pid, instruction, opts)
      when is_atom(agent_module) and is_binary(instruction) and is_list(opts) do
    tool_context = Keyword.get(opts, :tool_context, %{})
    llm_selection = Keyword.get(opts, :llm_selection)
    workspace_path = Map.get(tool_context, :workspace_path) || "unknown"
    semantic_ready? = get_in(tool_context, [:latest_import_status, :ready?]) || false
    memory_graph = Map.get(tool_context, :memory_graph)
    memory_workflow = memory_graph && Map.get(memory_graph, :workflow)
    memory_ready? = get_in(memory_graph || %{}, [:graph, "ready?"]) || false

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
       memory_workflow: memory_workflow,
       memory_ready?: memory_ready?,
       memory_graph: memory_graph,
       llm_selection: LLMSelection.summary(llm_selection),
       summary: "deterministic #{role} response for #{instruction}"
     }}
  end
end
