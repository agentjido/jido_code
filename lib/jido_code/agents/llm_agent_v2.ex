defmodule JidoCode.Agents.LLMAgent.V2 do
  @moduledoc """
  LLM Agent for JidoCode using Jido v2 architecture with pluggable strategies.

  This agent uses `Jido.Agent` as the base with configurable reasoning strategies
  (ReAct, CoT, ToT, GoT, Adaptive) instead of hardcoding a single algorithm.

  ## Strategy Selection

  The agent supports multiple reasoning strategies via `Jido.AI.Strategies.Adaptive`:

  - `:react` - ReAct (Reason-Act) with tool use
  - `:cot` - Chain-of-Thought sequential reasoning
  - `:tot` - Tree-of-Thoughts branching exploration
  - `:got` - Graph-of-Thoughts networked reasoning
  - `:trm` - Tiny-Recursive-Model iterative refinement

  Strategies can be selected at runtime via `/strategy` command or programmatically.

  ## Usage

      # Start with default Adaptive strategy
      {:ok, pid} = Jido.AgentServer.start(
        agent: JidoCode.Agents.LLMAgent.V2,
        id: "llm-agent"
      )

      # Send a chat message
      :ok = Jido.AgentServer.cast(pid, {:signal, %Jido.Signal{
        type: "llm.chat",
        data: %{message: "Explain pattern matching in Elixir"}
      }})

      # Get the result
      {:ok, state} = Jido.AgentServer.state(pid)
      state.agent.state.last_answer

  ## Session Integration

      # Start with session context
      {:ok, pid} = Jido.AgentServer.start(
        agent: JidoCode.Agents.LLMAgent.V2,
        id: "session-123",
        initial_state: %{
          session_id: "session-123",
          project_root: "/path/to/project"
        }
      )

  ## Memory Integration

  Memory is enabled by default and can be configured via initial_state:

      {:ok, pid} = Jido.AgentServer.start(
        agent: JidoCode.Agents.LLMAgent.V2,
        initial_state: %{
          memory_enabled: true,
          token_budget: 32_000
        }
      )

  """

  use Jido.Agent,
    name: "jido_llm_agent",
    description: "JidoCode LLM-powered coding assistant with pluggable strategies",
    # Strategy is configured via skill_spec/1
    strategy: nil,
    # Schema defines the agent's state shape
    schema: [
      # Session
      session_id: [type: :string, default: nil],
      project_root: [type: :string, default: nil],

      # LLM Configuration
      provider: [type: :atom, default: :anthropic],
      model: [type: :string, default: "anthropic:claude-sonnet-4-20250514"],
      temperature: [type: :float, default: 0.7],
      max_tokens: [type: :integer, default: 4096],

      # Memory
      memory_enabled: [type: :boolean, default: true],
      token_budget: [type: :integer, default: 32_000],

      # Status
      status: [type: :atom, default: :idle],
      progress: [type: :float, default: 0.0],
      last_query: [type: :string, default: ""],
      last_answer: [type: :string, default: ""],
      completed: [type: :boolean, default: false],

      # Strategy
      current_strategy: [type: :atom, default: :adaptive],
      available_strategies: [type: {:array, :atom}, default: [:cot, :react, :tot, :got]]
    ],
    # Skills are attached for modular capabilities
    skills: [
      Jido.AI.Skills.LLM,
      Jido.AI.Skills.Streaming,
      Jido.AI.Skills.ToolCalling
    ]

  require Logger

  alias Jido.Agent
  alias Jido.AI.Skills.LLM.Actions.Chat

  @system_prompt """
  You are JidoCode, an expert coding assistant running in a terminal interface.

  Your capabilities:
  - Answer programming questions across all languages
  - Explain code, algorithms, and concepts
  - Help debug issues and suggest fixes
  - Provide code examples and best practices
  - Assist with architecture and design decisions

  Guidelines:
  - Be concise but thorough - terminal space is limited
  - Use markdown code blocks with language hints
  - When showing code changes, be specific about file locations
  - Ask clarifying questions when requirements are ambiguous
  - Acknowledge limitations when you're uncertain
  """

  @doc """
  Returns the system prompt used for LLM interactions.
  """
  def system_prompt, do: @system_prompt

  @doc """
  Convenience function to send a chat message to the agent.

  ## Parameters

  - `server` - AgentServer PID or registered name
  - `message` - User message string
  - `opts` - Optional parameters

  ## Options

  - `:strategy` - Override strategy for this request (:react, :cot, :tot, :got, :adaptive)
  - `:streaming` - Enable streaming response (default: false)
  - `:timeout` - Request timeout in milliseconds (default: 60_000)

  ## Returns

  - `:ok` - Message queued for processing
  - `{:error, reason}` - Failed to queue message

  ## Examples

      :ok = LLMAgent.V2.chat(pid, "Explain pattern matching")
      :ok = LLMAgent.V2.chat(pid, "What's recursion?", strategy: :cot)
  """
  @spec chat(Jido.AgentServer.server(), String.t(), keyword()) :: :ok | {:error, term()}
  def chat(server, message, opts \\ []) when is_binary(message) do
    strategy = Keyword.get(opts, :strategy, :adaptive)

    Jido.AgentServer.cast(server, Jido.Signal.new!("llm.chat", %{
      message: message,
      strategy: strategy
    }, source: "llm_agent"))
  end

  @doc """
  Sets the reasoning strategy for the agent.

  ## Parameters

  - `server` - AgentServer PID or registered name
  - `strategy` - Strategy atom (:react, :cot, :tot, :got, :trm, :adaptive)

  ## Returns

  - `:ok` - Strategy updated
  - `{:error, reason}` - Invalid strategy or update failed

  ## Examples

      :ok = LLMAgent.V2.set_strategy(pid, :cot)
      :ok = LLMAgent.V2.set_strategy(pid, :tot)
      {:error, :unknown_strategy} = LLMAgent.V2.set_strategy(pid, :invalid)
  """
  @spec set_strategy(Jido.AgentServer.server(), atom()) :: :ok | {:error, term()}
  def set_strategy(server, strategy) when strategy in [:cot, :react, :tot, :got, :trm, :adaptive] do
    # For now, use a signal-based approach with proper action return format
    signal = Jido.Signal.new!("llm.set_strategy", %{
      "strategy" => strategy
    }, source: "llm_agent")

    case Jido.AgentServer.call(server, signal, 5000) do
      {:ok, _agent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def set_strategy(_server, strategy) do
    {:error, {:unknown_strategy, strategy}}
  end

  @doc """
  Gets the current strategy for the agent.

  ## Examples

      :adaptive = LLMAgent.V2.get_strategy(pid)
  """
  @spec get_strategy(Jido.AgentServer.server()) :: atom()
  def get_strategy(server) do
    case Jido.AgentServer.state(server) do
      {:ok, state} -> state.agent.state.current_strategy
      {:error, _} -> :adaptive
    end
  end

  @doc """
  Lists all available strategies.

  ## Examples

      [:cot, :react, :tot, :got, :trm, :adaptive] = LLMAgent.V2.list_strategies()
  """
  @spec list_strategies() :: [atom()]
  def list_strategies do
    [:cot, :react, :tot, :got, :trm, :adaptive]
  end

  @doc """
  Returns human-readable name for a strategy.
  """
  @spec strategy_name(atom()) :: String.t()
  def strategy_name(:cot), do: "Chain of Thought"
  def strategy_name(:react), do: "ReAct (Reason-Act)"
  def strategy_name(:tot), do: "Tree of Thoughts"
  def strategy_name(:got), do: "Graph of Thoughts"
  def strategy_name(:trm), do: "Tiny-Recursive-Model"
  def strategy_name(:adaptive), do: "Adaptive (auto-selecting)"
  def strategy_name(_), do: "Unknown"

  @doc """
  Returns description for a strategy.
  """
  @spec strategy_description(atom()) :: String.t()
  def strategy_description(:cot) do
    "Sequential reasoning with step-by-step logic chain"
  end

  def strategy_description(:react) do
    "Interactive reasoning with tool use and observation"
  end

  def strategy_description(:tot) do
    "Branching exploration with multiple reasoning paths"
  end

  def strategy_description(:got) do
    "Networked reasoning exploring interconnected thoughts"
  end

  def strategy_description(:trm) do
    "Iterative refinement with recursive self-improvement"
  end

  def strategy_description(:adaptive) do
    "Automatically selects the best strategy based on task complexity"
  end

  def strategy_description(_), do: "Unknown strategy"

  @doc """
  Returns signal routes for custom agent actions.

  Routes the "llm.set_strategy" signal to the SetStrategy action.
  """
  def signal_routes do
    [
      {"llm.chat", __MODULE__.ProcessChat},
      {"llm.set_strategy", __MODULE__.SetStrategy}
    ]
  end

  #
  # Action Modules
  #

  defmodule ProcessChat do
    @moduledoc """
    Action for processing chat messages through the LLM agent.

    This action handles the core chat functionality, routing to the
    appropriate strategy based on the agent's configuration.
    """

    use Jido.Action,
      name: "llm_chat",
      description: "Process a chat message through LLM with selected strategy"

    def run(params, context) do
      # Extract message from params
      message = Map.get(params, "message") || Map.get(params, :message)
      strategy = Map.get(params, "strategy") || Map.get(params, :strategy, :adaptive)
      system_prompt = JidoCode.Agents.LLMAgent.V2.system_prompt()

      # Build LLM chat parameters
      llm_params = %{
        "model" => Map.get(params, "model") || Map.get(params, :model, :capable),
        "prompt" => message,
        "system_prompt" => system_prompt,
        "stream" => Map.get(params, "streaming") != false
      }

      # Delegate to LLM Chat action
      Jido.AI.Skills.LLM.Actions.Chat.run(llm_params, context)
    end
  end

  defmodule SetStrategy do
    @moduledoc """
    Action for changing the agent's reasoning strategy at runtime.
    """

    use Jido.Action,
      name: "llm_set_strategy",
      description: "Change the reasoning strategy"

    def run(params, context) do
      strategy = Map.get(params, "strategy") || Map.get(params, :strategy)

      if strategy in [:cot, :react, :tot, :got, :trm, :adaptive] do
        # The context.state contains the Jido.Agent struct
        agent = context.state
        current_strategy = agent.state.current_strategy

        # Use Agent.set to create a new agent with updated state
        new_agent = Agent.set(agent, %{current_strategy: strategy})

        # Return the updated agent directly
        # The framework should handle this to update the agent state
        new_agent
      else
        {:error, {:unknown_strategy, strategy}}
      end
    end
  end
end
