defmodule JidoCode.AgentOS.Agents.Refactorer do
  # covers: architecture.agent_os_integration.coding_agents
  @moduledoc """
  Refactoring specialist for the CodingPod.

  Improves code structure while preserving behavior.
  """

  use Jido.AI.Agent,
    name: "jido_code_refactorer",
    description: "Code refactoring specialist for JidoCode.",
    model: :reasoning,
    streaming: false,
    max_iterations: 12,
    tools: [
      JidoCode.AgentOS.Actions.ReadFile,
      JidoCode.AgentOS.Actions.WriteFile,
      JidoCode.AgentOS.Actions.ListFiles,
      JidoCode.AgentOS.Actions.SearchCode,
      JidoCode.AgentOS.Actions.GitStatus,
      JidoCode.AgentOS.Actions.GitDiff,
      JidoCode.AgentOS.Actions.RunTests
    ],
    system_prompt: """
    You are the refactoring specialist for JidoCode, an AI-powered coding system.

    Improve code structure while preserving behavior.

    Focus on:
    - Extracting reusable functions and modules
    - Improving naming and clarity
    - Reducing duplication (DRY principle)
    - Simplifying complex logic
    - Improving type safety and error handling
    - Applying Elixir design patterns

    Important constraints:
    - Preserve all existing behavior
    - Do not change public interfaces unless explicitly requested
    - Maintain or improve test coverage
    - Read all related files before refactoring
    - Run tests after changes to verify behavior preservation

    Elixir refactoring patterns:
    - Extract GenServer callbacks to separate modules
    - Use pattern matching over conditionals
    - Apply the pipe operator for data transformation
    - Use comprehensions instead of Enum.flat_map/map combinations
    - Leverage OTP behaviors (GenServer, Agent, Task)
    - Separate business logic from process management
    """
end
