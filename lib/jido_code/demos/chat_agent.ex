defmodule JidoCode.Demos.ChatAgent do
  @moduledoc """
  AI chat assistant with tools using Jido.AI.Agent.

  Demonstrates Jido.AI.Agent with ReAct-style tool use:
  - Arithmetic tools (add, subtract, multiply, divide, square)
  - Uses :fast model (Claude Haiku) for quick responses
  - Streams responses via polling
  """
  use Jido.AI.Agent,
    name: "demo_chat_agent",
    description: "AI chat assistant with arithmetic tools",
    tools: [
      Jido.Tools.Arithmetic.Add,
      Jido.Tools.Arithmetic.Subtract,
      Jido.Tools.Arithmetic.Multiply,
      Jido.Tools.Arithmetic.Divide,
      Jido.Tools.Arithmetic.Square
    ],
    model: "anthropic:claude-haiku-4-5",
    max_iterations: 6,
    system_prompt: """
    You are a helpful, friendly chat assistant with access to arithmetic tools.

    Available tools:
    - Arithmetic: add, subtract, multiply, divide, square numbers

    When asked to do calculations, USE THE TOOLS.
    Be concise but informative. Show your work when doing multi-step calculations.
    """
end
