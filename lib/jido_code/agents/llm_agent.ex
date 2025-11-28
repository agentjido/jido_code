defmodule JidoCode.Agents.LLMAgent do
  @moduledoc """
  LLM Agent for handling chat interactions in JidoCode.

  This agent wraps JidoAI's Agent system to provide a coding assistant
  that can be configured with different LLM providers and models at runtime.

  ## Usage

      # Start with default config from JidoCode.Config
      {:ok, pid} = JidoCode.Agents.LLMAgent.start_link()

      # Start with custom options
      {:ok, pid} = JidoCode.Agents.LLMAgent.start_link(
        provider: :openai,
        model: "gpt-4o",
        temperature: 0.5
      )

      # Send a chat message
      {:ok, response} = JidoCode.Agents.LLMAgent.chat(pid, "How do I reverse a list in Elixir?")

  ## PubSub Integration

  Responses are broadcast to the `"tui.events"` topic with the event type
  `{:llm_response, response}` for TUI consumption.

  ## Supervision

  This agent can be started under the AgentSupervisor for lifecycle management:

      JidoCode.AgentSupervisor.start_agent(%{
        name: :llm_agent,
        module: JidoCode.Agents.LLMAgent,
        args: []
      })
  """

  use GenServer
  require Logger

  alias Jido.AI.Agent, as: AIAgent
  alias Jido.AI.Model
  alias JidoCode.Config

  @pubsub JidoCode.PubSub
  @tui_topic "tui.events"
  @default_timeout 60_000

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

  Answer the user's question: <%= @message %>
  """

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the LLM agent.

  ## Options

  - `:provider` - Override the provider from config (e.g., `:anthropic`, `:openai`)
  - `:model` - Override the model name from config
  - `:temperature` - Override temperature (0.0-1.0)
  - `:max_tokens` - Override max tokens
  - `:name` - GenServer name for registration (optional)

  ## Returns

  - `{:ok, pid}` - Agent started successfully
  - `{:error, reason}` - Failed to start (e.g., invalid config)

  ## Examples

      {:ok, pid} = JidoCode.Agents.LLMAgent.start_link()
      {:ok, pid} = JidoCode.Agents.LLMAgent.start_link(name: {:via, Registry, {MyRegistry, :llm}})
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Sends a chat message to the agent and returns the response.

  The response is also broadcast to the PubSub `"tui.events"` topic.

  ## Parameters

  - `pid` - The agent process
  - `message` - The user's message string
  - `opts` - Options (`:timeout` defaults to 60 seconds)

  ## Returns

  - `{:ok, response}` - Response string from the LLM
  - `{:error, reason}` - Failed to get response

  ## Examples

      {:ok, response} = JidoCode.Agents.LLMAgent.chat(pid, "Explain pattern matching")
  """
  @spec chat(GenServer.server(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat(pid, message, opts \\ []) when is_binary(message) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(pid, {:chat, message}, timeout + 5_000)
  end

  @doc """
  Returns the current model configuration.
  """
  @spec get_config(GenServer.server()) :: map()
  def get_config(pid) do
    GenServer.call(pid, :get_config)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    # Trap exits so we can handle AI agent crashes gracefully
    Process.flag(:trap_exit, true)

    case build_config(opts) do
      {:ok, config} ->
        case start_ai_agent(config) do
          {:ok, ai_pid} ->
            state = %{
              ai_pid: ai_pid,
              config: config
            }

            {:ok, state}

          {:error, reason} ->
            {:stop, reason}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{ai_pid: ai_pid} = state) when pid == ai_pid do
    Logger.warning("AI agent exited: #{inspect(reason)}")
    # Attempt to restart the AI agent
    case start_ai_agent(state.config) do
      {:ok, new_ai_pid} ->
        {:noreply, %{state | ai_pid: new_ai_pid}}

      {:error, _} ->
        {:stop, {:ai_agent_died, reason}, state}
    end
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    # Ignore other exits
    {:noreply, state}
  end

  @impl true
  def handle_call({:chat, message}, _from, state) do
    result = do_chat(state.ai_pid, message)

    # Broadcast to PubSub for TUI
    case result do
      {:ok, response} ->
        broadcast_response(response)

      _ ->
        :ok
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Stop the AI agent if running - catch any errors silently
    if state[:ai_pid] && Process.alive?(state.ai_pid) do
      try do
        GenServer.stop(state.ai_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_config(opts) do
    case Config.get_llm_config() do
      {:ok, base_config} ->
        config = %{
          provider: Keyword.get(opts, :provider, base_config.provider),
          model: Keyword.get(opts, :model, base_config.model),
          temperature: Keyword.get(opts, :temperature, base_config.temperature),
          max_tokens: Keyword.get(opts, :max_tokens, base_config.max_tokens)
        }

        {:ok, config}

      {:error, _reason} = error ->
        # Allow starting with explicit opts even without base config
        if Keyword.has_key?(opts, :provider) and Keyword.has_key?(opts, :model) do
          config = %{
            provider: Keyword.fetch!(opts, :provider),
            model: Keyword.fetch!(opts, :model),
            temperature: Keyword.get(opts, :temperature, 0.7),
            max_tokens: Keyword.get(opts, :max_tokens, 4096)
          }

          {:ok, config}
        else
          error
        end
    end
  end

  defp start_ai_agent(config) do
    model_tuple =
      {config.provider,
       [
         model: config.model,
         temperature: config.temperature,
         max_tokens: config.max_tokens
       ]}

    case Model.from(model_tuple) do
      {:ok, model} ->
        AIAgent.start_link(
          ai: [
            model: model,
            prompt: @system_prompt
          ]
        )

      {:error, reason} ->
        {:error, {:model_error, reason}}
    end
  end

  defp do_chat(ai_pid, message) do
    case AIAgent.chat_response(ai_pid, message, timeout: @default_timeout) do
      {:ok, %{response: response}} when is_binary(response) ->
        {:ok, response}

      {:ok, response} when is_binary(response) ->
        {:ok, response}

      {:ok, %{} = result} ->
        # Handle other response formats
        response = Map.get(result, :response) || Map.get(result, :content) || inspect(result)
        {:ok, response}

      {:error, reason} ->
        Logger.error("LLM chat error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp broadcast_response(response) do
    Phoenix.PubSub.broadcast(@pubsub, @tui_topic, {:llm_response, response})
  end
end
