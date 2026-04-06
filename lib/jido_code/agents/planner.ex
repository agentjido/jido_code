defmodule JidoCode.Agents.Planner do
  # covers: architecture.agent_os_integration.coding_agents
  @moduledoc """
  Planning specialist for the CodingPod.

  Generates implementation plans by analyzing the codebase and breaking
  down requests into concrete, actionable steps.
  """

  use Jido.AI.Agent,
    name: "jido_code_planner",
    description: "Planning specialist for JidoCode operations.",
    model: :reasoning,
    streaming: false,
    max_iterations: 10,
    tools: [
      JidoCode.Actions.ReadFile,
      JidoCode.Actions.ListFiles,
      JidoCode.Actions.SearchCode,
      JidoCode.Actions.GitStatus,
      JidoCode.Actions.AddTask,
      JidoCode.Actions.StoreArtifact,
      JidoCode.Actions.KGQuery,
      JidoCode.Actions.KGExplore
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

    Knowledge Graph tools:
    - KGQuery: Query the code knowledge graph to find modules, functions, and relationships
    - KGExplore: Explore relationships from a starting point to discover connections

    Output format:
    1. Summary of the request
    2. Implementation approach
    3. Step-by-step plan with dependencies
    4. Files to be modified
    5. Tests to verify the implementation
    """
end
