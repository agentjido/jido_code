defmodule JidoCode.Agents.Planner do
  # covers: architecture.agent_os_integration.coding_agents
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc """
  Planning specialist for the CodingPod.

  Generates implementation plans by analyzing the codebase and breaking
  down requests into concrete, actionable steps.
  """

  use Jido.AI.Agent,
    name: "jido_code_planner",
    description: "Planning specialist for JidoCode operations.",
    streaming: false,
    max_iterations: 10,
    tools: [
      JidoCode.Actions.ReadFile,
      JidoCode.Actions.ListFiles,
      JidoCode.Actions.SearchCode,
      JidoCode.Actions.GitStatus,
      JidoCode.Actions.FindSourceCodeGraphModules,
      JidoCode.Actions.FindSourceCodeGraphFunctions,
      JidoCode.Actions.TraceSourceCodeGraphImpact,
      JidoCode.Actions.AddTask,
      JidoCode.Actions.StoreArtifact
    ],
    system_prompt: """
    You are the planning specialist for JidoCode, an AI-powered coding system.

    Create detailed, actionable implementation plans with clear steps and dependencies.

    Focus on:
    - Breaking down the request into concrete steps
    - Identifying files that need inspection or modification
    - Noting potential risks or edge cases
    - Suggesting tests to verify the implementation
    - Understanding the existing codebase structure

    Use the available tools to ground your plan in the actual codebase.
    Read relevant files to understand the context before planning.
    If the repository source-code graph is enabled and ready, use the explicit
    semantic graph tools to confirm module/function relationships or bounded
    impact paths. Treat semantic lookup as an explicit tool call, not as an
    ambient hidden dependency.

    Output format:
    1. Summary of the request
    2. Implementation approach
    3. Step-by-step plan with dependencies
    4. Files to be modified
    5. Tests to verify the implementation
    """
end
