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

  @doc """
  Reconfigures the agent with new provider/model settings at runtime.

  This performs hot-swapping of the underlying AI agent without restarting
  the LLMAgent GenServer. The new configuration is validated before being
  applied.

  ## Options

  - `:provider` - New provider atom (e.g., `:anthropic`, `:openai`)
  - `:model` - New model name string
  - `:temperature` - New temperature (0.0-1.0)
  - `:max_tokens` - New max tokens

  ## Validation

  The following validations are performed:
  1. Provider must exist in the ReqLLM registry
  2. Model must exist for the specified provider
  3. API key must be available for the provider

  ## Returns

  - `:ok` - Configuration updated successfully
  - `{:error, reason}` - Validation failed or reconfiguration failed

  ## Examples

      # Switch to OpenAI
      :ok = JidoCode.Agents.LLMAgent.configure(pid, provider: :openai, model: "gpt-4o")

      # Invalid provider
      {:error, "Provider :invalid not found..."} = JidoCode.Agents.LLMAgent.configure(pid, provider: :invalid)
  """
  @spec configure(GenServer.server(), keyword()) :: :ok | {:error, String.t()}
  def configure(pid, opts) when is_list(opts) do
    GenServer.call(pid, {:configure, opts})
  end

  @doc """
  Lists available LLM providers from the ReqLLM registry.

  ## Returns

  - `{:ok, providers}` - List of provider atoms
  - `{:error, reason}` - Registry unavailable

  ## Examples

      {:ok, providers} = JidoCode.Agents.LLMAgent.list_providers()
      # => {:ok, [:anthropic, :openai, :google, ...]}
  """
  @spec list_providers() :: {:ok, [atom()]} | {:error, term()}
  def list_providers do
    Jido.AI.Model.Registry.Adapter.list_providers()
  end

  @doc """
  Lists available models for a provider.

  ## Returns

  - `{:ok, models}` - List of model name strings
  - `{:error, reason}` - Provider not found or registry unavailable

  ## Examples

      {:ok, models} = JidoCode.Agents.LLMAgent.list_models(:anthropic)
      # => {:ok, ["claude-3-5-sonnet-20241022", "claude-3-opus-20240229", ...]}
  """
  @spec list_models(atom()) :: {:ok, [String.t()]} | {:error, term()}
  def list_models(provider) when is_atom(provider) do
    case Jido.AI.Model.Registry.Adapter.list_models(provider) do
      {:ok, models} ->
        model_names =
          models
          |> Enum.map(fn model ->
            case model do
              %{model: name} when is_binary(name) -> name
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, model_names}

      {:error, _} = error ->
        error
    end
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
  def handle_call({:configure, opts}, _from, state) do
    # Build new config, merging with current config
    new_config = %{
      provider: Keyword.get(opts, :provider, state.config.provider),
      model: Keyword.get(opts, :model, state.config.model),
      temperature: Keyword.get(opts, :temperature, state.config.temperature),
      max_tokens: Keyword.get(opts, :max_tokens, state.config.max_tokens)
    }

    # Skip validation and restart if config unchanged
    if new_config == state.config do
      {:reply, :ok, state}
    else
      case validate_config(new_config) do
        :ok ->
          # Stop existing AI agent
          stop_ai_agent(state.ai_pid)

          # Start new AI agent with new config
          case start_ai_agent(new_config) do
            {:ok, new_ai_pid} ->
              old_config = state.config
              new_state = %{state | ai_pid: new_ai_pid, config: new_config}

              # Broadcast config change
              broadcast_config_change(old_config, new_config)

              {:reply, :ok, new_state}

            {:error, reason} ->
              # Failed to start new agent - try to restart with old config
              case start_ai_agent(state.config) do
                {:ok, restored_pid} ->
                  {:reply, {:error, "Failed to apply new config: #{inspect(reason)}"},
                   %{state | ai_pid: restored_pid}}

                {:error, _} ->
                  # Critical failure - stop the GenServer
                  {:stop, {:error, :cannot_restore_agent}, {:error, reason}, state}
              end
          end

        {:error, _} = error ->
          {:reply, error, state}
      end
    end
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

  defp broadcast_config_change(old_config, new_config) do
    Phoenix.PubSub.broadcast(@pubsub, @tui_topic, {:config_changed, old_config, new_config})
  end

  defp stop_ai_agent(ai_pid) when is_pid(ai_pid) do
    if Process.alive?(ai_pid) do
      try do
        GenServer.stop(ai_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end
  end

  defp stop_ai_agent(_), do: :ok

  # ============================================================================
  # Validation Functions
  # ============================================================================

  defp validate_config(config) do
    with :ok <- validate_provider(config.provider),
         :ok <- validate_model(config.provider, config.model),
         :ok <- validate_api_key(config.provider) do
      :ok
    end
  end

  defp validate_provider(provider) do
    case Jido.AI.Model.Registry.Adapter.list_providers() do
      {:ok, providers} ->
        if provider in providers do
          :ok
        else
          available =
            providers
            |> Enum.take(10)
            |> Enum.map(&Atom.to_string/1)
            |> Enum.join(", ")

          {:error,
           "Provider '#{provider}' not found. Available providers include: #{available}... (#{length(providers)} total)"}
        end

      {:error, :registry_unavailable} ->
        # Fall back to allowing any provider if registry unavailable
        Logger.warning("Provider registry unavailable, skipping provider validation")
        :ok

      {:error, reason} ->
        {:error, "Failed to validate provider: #{inspect(reason)}"}
    end
  end

  defp validate_model(provider, model) do
    case Jido.AI.Model.Registry.Adapter.model_exists?(provider, model) do
      true ->
        :ok

      false ->
        # Get available models for better error message
        case Jido.AI.Model.Registry.Adapter.list_models(provider) do
          {:ok, models} ->
            available =
              models
              |> Enum.take(5)
              |> Enum.map(fn m -> Map.get(m, :model, "unknown") end)
              |> Enum.join(", ")

            {:error,
             "Model '#{model}' not found for provider '#{provider}'. Available models include: #{available}..."}

          {:error, _} ->
            {:error, "Model '#{model}' not found for provider '#{provider}'"}
        end
    end
  end

  defp validate_api_key(provider) do
    api_key_name = :"#{provider}_api_key"
    env_key = api_key_name |> Atom.to_string() |> String.upcase()

    # Check environment variable directly
    case System.get_env(env_key) do
      nil ->
        # Try Keyring as fallback
        try_keyring_validation(provider, api_key_name, env_key)

      "" ->
        {:error, "API key for provider '#{provider}' is empty. Set #{env_key} environment variable."}

      _key ->
        :ok
    end
  end

  defp try_keyring_validation(provider, api_key_name, env_key) do
    try do
      case Jido.AI.Keyring.get(api_key_name, nil) do
        nil ->
          {:error,
           "No API key found for provider '#{provider}'. Set #{env_key} environment variable."}

        "" ->
          {:error,
           "API key for provider '#{provider}' is empty. Set #{env_key} environment variable."}

        _key ->
          :ok
      end
    rescue
      _ ->
        {:error,
         "No API key found for provider '#{provider}'. Set #{env_key} environment variable."}
    catch
      :exit, _ ->
        {:error,
         "No API key found for provider '#{provider}'. Set #{env_key} environment variable."}
    end
  end
end
