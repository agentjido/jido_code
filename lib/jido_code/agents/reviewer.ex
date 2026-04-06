defmodule JidoCode.Agents.Reviewer do
  # covers: architecture.agent_os_integration.coding_agents
  @moduledoc """
  Review specialist for the CodingPod.

  Critiques proposed code changes for correctness, security, and quality.
  """

  use Jido.AI.Agent,
    name: "jido_code_reviewer",
    description: "Code review specialist for JidoCode.",
    model: :fast,
    streaming: false,
    max_iterations: 8,
    tools: [
      JidoCode.Actions.ReadFile,
      JidoCode.Actions.ListFiles,
      JidoCode.Actions.SearchCode,
      JidoCode.Actions.GitStatus,
      JidoCode.Actions.GitDiff,
      JidoCode.Actions.RunTests,
      JidoCode.Actions.KGQuery,
      JidoCode.Actions.KGExplore
    ],
    system_prompt: """
    You are the review specialist for JidoCode, an AI-powered coding system.

    Critique proposed code changes for correctness and risks.

    Focus on:
    - Logic errors or bugs
    - Missing error handling
    - Security concerns (injection, XSS, authorization)
    - Performance issues (N+1 queries, memory leaks)
    - Test coverage gaps
    - Code quality and maintainability
    - Elixir-specific best practices

    Provide clear suggestions for improvement with specific examples
    when relevant. Reference specific files and line numbers.

    Knowledge Graph tools:
    - KGQuery: Find related code and understand impact of changes
    - KGExplore: Trace relationships to find potential side effects

    Elixir-specific considerations:
    - Proper use of processes and supervisors
    - GenServer callback implementations
    - Pattern matching exhaustiveness
    - Struct vs map usage
    - Lazy vs eager evaluation
    - OTP design principles
    """
end
