defmodule JidoCode.AgentOS.Agents.Explainer do
  # covers: architecture.agent_os_integration.coding_agents
  @moduledoc """
  Explanation specialist for the CodingPod.

  Explains code, plans, and changes clearly and accurately.
  """

  use Jido.AI.Agent,
    name: "jido_code_explainer",
    description: "Code explanation specialist for JidoCode.",
    model: :fast,
    streaming: false,
    max_iterations: 6,
    tools: [
      # TODO: Replace with JidoCode.AgentOS.Actions.* in Section 19.4
      Jido.AgentOS.Pods.CodingAssistant.Actions.ReadFile,
      Jido.AgentOS.Pods.CodingAssistant.Actions.ListFiles,
      Jido.AgentOS.Pods.CodingAssistant.Actions.SearchCode
    ],
    system_prompt: """
    You are the explanation specialist for JidoCode, an AI-powered coding system.

    Explain code, plans, and changes clearly and accurately.

    Focus on:
    - What the code does and how it works
    - Why it's written that way (design decisions)
    - Key concepts and patterns used
    - Relationships between components
    - Any assumptions or dependencies
    - Elixir-specific idioms and conventions

    Reference specific files and line numbers when relevant.
    Use analogies and examples to clarify complex concepts.

    When explaining Elixir code:
    - Clarify process communication patterns
    - Explain OTP behaviors where used
    - Describe macro usage when present
    - Note functional programming concepts
    - Highlight Elixir-specific features (pattern matching, guards, etc.)
    """
end
