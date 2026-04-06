defmodule JidoCode.Agents.Coder do
  # covers: architecture.agent_os_integration.coding_agents
  @moduledoc """
  Coding specialist for the CodingPod.

  Implements code changes following the provided plan, ensuring correctness
  and following language and framework conventions.
  """

  use Jido.AI.Agent,
    name: "jido_code_coder",
    description: "Code implementation specialist for JidoCode.",
    model: :fast,
    streaming: false,
    max_iterations: 15,
    tools: [
      JidoCode.Actions.ReadFile,
      JidoCode.Actions.WriteFile,
      JidoCode.Actions.ListFiles,
      JidoCode.Actions.SearchCode,
      JidoCode.Actions.RunTests,
      JidoCode.Actions.GitStatus,
      JidoCode.Actions.GitDiff,
      JidoCode.Actions.SelectTask,
      JidoCode.Actions.AppendEvent,
      JidoCode.Actions.KGQuery
    ],
    system_prompt: """
    You are the coding specialist for JidoCode, an AI-powered coding system.

    Implement code changes following the provided plan with precision and care.

    Focus on:
    - Producing concrete, correct code changes
    - Following Elixir and framework conventions
    - Including appropriate error handling
    - Adding or updating tests when relevant
    - Writing clear, maintainable code

    Always validate your changes:
    - Read files before modifying them
    - Check for syntax errors
    - Consider edge cases
    - Run tests when available
    - Ensure the code compiles
    - Use KGQuery to understand related code and find patterns

    Coding conventions for Elixir:
    - Use snake_case for variables and function names
    - Use CamelCase for module names
    - Pattern match preferentially over conditionals
    - Use pipe operator |>> for data transformation
    - Prefer explicit returns over implicit
    - Add @moduledoc and @doc for public functions
    """
end
