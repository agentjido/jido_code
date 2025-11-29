defmodule JidoCode.Commands do
  @moduledoc """
  Parses and executes slash commands from user input.

  Commands allow users to configure the LLM provider and model at runtime
  without restarting the application.

  ## Available Commands

  | Command | Description |
  |---------|-------------|
  | `/help` | List available commands |
  | `/config` | Display current configuration |
  | `/provider <name>` | Set LLM provider (clears model) |
  | `/model <provider>:<model>` | Set both provider and model |
  | `/model <model>` | Set model for current provider |
  | `/models` | List models for current provider (pending) |
  | `/models <provider>` | List models for provider (pending) |
  | `/providers` | List available providers (pending) |

  ## Usage

      alias JidoCode.Commands

      config = %{provider: "anthropic", model: "claude-3-5-sonnet"}

      Commands.execute("/help", config)
      #=> {:ok, "Available commands:\\n...", %{}}

      Commands.execute("/model openai:gpt-4o", config)
      #=> {:ok, "Model set to openai:gpt-4o", %{provider: "openai", model: "gpt-4o"}}

      Commands.execute("/unknown", config)
      #=> {:error, "Unknown command: /unknown. Type /help for available commands."}
  """

  alias Jido.AI.Keyring
  alias Jido.AI.Model.Registry.Adapter, as: RegistryAdapter
  alias JidoCode.Agents.LLMAgent
  alias JidoCode.AgentSupervisor
  alias JidoCode.PubSubTopics
  alias JidoCode.Settings

  @pubsub JidoCode.PubSub

  @type config :: %{provider: String.t() | nil, model: String.t() | nil}
  @type result :: {:ok, String.t(), config()} | {:error, String.t()}

  @help_text """
  Available commands:

    /help                    - Show this help message
    /config                  - Display current configuration
    /provider <name>         - Set LLM provider (clears model)
    /model <provider>:<model> - Set both provider and model
    /model <model>           - Set model for current provider
    /models                  - List models for current provider
    /models <provider>       - List models for a specific provider
    /providers               - List available providers
  """

  @doc """
  Executes a slash command and returns the result.

  ## Parameters

  - `command` - The command string starting with `/`
  - `config` - Current configuration map with :provider and :model keys

  ## Returns

  - `{:ok, message, new_config}` - Command executed successfully
  - `{:error, message}` - Command failed

  ## Examples

      iex> Commands.execute("/help", %{provider: nil, model: nil})
      {:ok, "Available commands:...", %{}}

      iex> Commands.execute("/config", %{provider: "anthropic", model: "claude-3-5-sonnet"})
      {:ok, "Provider: anthropic\\nModel: claude-3-5-sonnet", %{}}
  """
  @spec execute(String.t(), config()) :: result()
  def execute(command, config) when is_binary(command) and is_map(config) do
    command
    |> String.trim()
    |> parse_and_execute(config)
  end

  # ============================================================================
  # Command Parsing
  # ============================================================================

  defp parse_and_execute("/help" <> _, _config) do
    {:ok, String.trim(@help_text), %{}}
  end

  defp parse_and_execute("/config" <> _, config) do
    provider = config[:provider] || config["provider"] || "(not set)"
    model = config[:model] || config["model"] || "(not set)"

    message = "Provider: #{provider}\nModel: #{model}"
    {:ok, message, %{}}
  end

  defp parse_and_execute("/provider " <> rest, _config) do
    provider = String.trim(rest)
    execute_provider_command(provider)
  end

  defp parse_and_execute("/provider", _config) do
    {:error, "Usage: /provider <name>\n\nExample: /provider anthropic"}
  end

  defp parse_and_execute("/model " <> rest, config) do
    model_spec = String.trim(rest)
    execute_model_command(model_spec, config)
  end

  defp parse_and_execute("/model", _config) do
    {:error, "Usage: /model <provider>:<model> or /model <model>\n\nExamples:\n  /model anthropic:claude-3-5-sonnet\n  /model gpt-4o"}
  end

  defp parse_and_execute("/models " <> rest, _config) do
    provider = String.trim(rest)
    execute_models_command(provider)
  end

  defp parse_and_execute("/models", config) do
    provider = config[:provider] || config["provider"]

    if provider do
      execute_models_command(provider)
    else
      {:error, "No provider set. Use /provider <name> first, or /models <provider>"}
    end
  end

  defp parse_and_execute("/providers" <> _, _config) do
    execute_providers_command()
  end

  defp parse_and_execute("/" <> command, _config) do
    # Extract just the command name for error message
    command_name = command |> String.split() |> List.first() || command
    {:error, "Unknown command: /#{command_name}. Type /help for available commands."}
  end

  defp parse_and_execute(text, _config) do
    {:error, "Not a command: #{text}. Commands start with /"}
  end

  # ============================================================================
  # Command Execution
  # ============================================================================

  defp execute_provider_command(provider) do
    case validate_provider(provider) do
      :ok ->
        # Save to settings
        Settings.set(:local, "provider", provider)
        Settings.set(:local, "model", nil)

        new_config = %{provider: provider, model: nil}
        {:ok, "Provider set to #{provider}. Use /models to see available models.", new_config}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_model_command(model_spec, config) do
    cond do
      # Format: provider:model
      String.contains?(model_spec, ":") ->
        [provider | rest] = String.split(model_spec, ":", parts: 2)
        model = Enum.join(rest, ":")
        set_provider_and_model(provider, model)

      # Format: model only (requires provider to be set)
      true ->
        provider = config[:provider] || config["provider"]

        if provider do
          set_model_for_provider(provider, model_spec)
        else
          {:error, "No provider set. Use /model <provider>:<model> or set provider first with /provider <name>"}
        end
    end
  end

  defp set_provider_and_model(provider, model) do
    with :ok <- validate_provider(provider),
         :ok <- validate_model(provider, model),
         :ok <- validate_api_key(provider) do
      # Save to settings
      Settings.set(:local, "provider", provider)
      Settings.set(:local, "model", model)

      new_config = %{provider: provider, model: model}

      # Configure running agent if available
      configure_agent(new_config)

      # Broadcast config change
      broadcast_config_change(new_config)

      {:ok, "Model set to #{provider}:#{model}", new_config}
    end
  end

  defp set_model_for_provider(provider, model) do
    with :ok <- validate_model(provider, model),
         :ok <- validate_api_key(provider) do
      Settings.set(:local, "model", model)

      new_config = %{provider: provider, model: model}

      # Configure running agent if available
      configure_agent(new_config)

      # Broadcast config change
      broadcast_config_change(new_config)

      {:ok, "Model set to #{model}", new_config}
    end
  end

  defp execute_models_command(provider) do
    case validate_provider(provider) do
      :ok ->
        models = Settings.get_models(provider)

        if models == [] do
          {:ok, "No models found for provider: #{provider}", %{}}
        else
          model_list = models |> Enum.take(20) |> Enum.join("\n  ")
          count = length(models)
          suffix = if count > 20, do: "\n  ... and #{count - 20} more", else: ""
          {:ok, "Models for #{provider}:\n  #{model_list}#{suffix}", %{}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_providers_command do
    providers = Settings.get_providers()

    if providers == [] do
      {:ok, "No providers available", %{}}
    else
      provider_list = providers |> Enum.take(20) |> Enum.join("\n  ")
      count = length(providers)
      suffix = if count > 20, do: "\n  ... and #{count - 20} more", else: ""
      {:ok, "Available providers:\n  #{provider_list}#{suffix}", %{}}
    end
  end

  # ============================================================================
  # Validation
  # ============================================================================

  defp validate_provider(provider) do
    case RegistryAdapter.list_providers() do
      {:ok, providers} ->
        # Use String.to_existing_atom/1 to avoid atom exhaustion from user input
        # Fall back to checking if the string matches a known provider atom
        provider_in_list? =
          Enum.any?(providers, fn p -> Atom.to_string(p) == provider end)

        if provider_in_list? do
          :ok
        else
          # Build helpful error message
          similar = find_similar_providers(provider, providers)

          suggestion =
            if similar != [] do
              "\n\nDid you mean: #{Enum.join(similar, ", ")}?"
            else
              "\n\nUse /providers to see available providers."
            end

          {:error, "Unknown provider: #{provider}#{suggestion}"}
        end

      {:error, _} ->
        # If registry is unavailable, allow any provider
        :ok
    end
  end

  defp validate_model(_provider, _model) do
    # Skip model validation for now - the registry may not have complete model lists
    # and users should be able to use any model their API key supports.
    # The actual validation will happen when the LLM call is made.
    :ok
  end

  defp validate_api_key(provider) do
    key_name = provider_to_key_name(provider)

    case Keyring.get(key_name) do
      nil ->
        # Use generic message - don't expose env var names
        {:error, "Provider #{provider} is not configured. Please set up API credentials."}

      "" ->
        # Use generic message - don't expose env var names
        {:error, "Provider #{provider} has empty credentials. Please configure API credentials."}

      _key ->
        :ok
    end
  end

  # Known provider to API key name mapping
  # This whitelist prevents atom exhaustion from arbitrary user input
  @known_provider_keys %{
    "openai" => :openai_api_key,
    "anthropic" => :anthropic_api_key,
    "openrouter" => :openrouter_api_key,
    "azure" => :azure_api_key,
    "google" => :google_api_key,
    "gemini" => :google_api_key,
    "cohere" => :cohere_api_key,
    "mistral" => :mistral_api_key,
    "groq" => :groq_api_key,
    "together" => :together_api_key,
    "fireworks" => :fireworks_api_key,
    "deepseek" => :deepseek_api_key,
    "perplexity" => :perplexity_api_key,
    "xai" => :xai_api_key,
    "ollama" => :ollama_api_key,
    "cerebras" => :cerebras_api_key,
    "sambanova" => :sambanova_api_key
  }

  # Map provider names to their keyring key names
  defp provider_to_key_name(provider) do
    # Use whitelist to prevent atom exhaustion from user input
    case Map.get(@known_provider_keys, provider) do
      nil ->
        # For unknown providers, return a generic key (don't create new atoms)
        # This will likely fail API key validation, which is the correct behavior
        :unknown_provider_api_key

      key ->
        key
    end
  end

  # Simple substring matching for suggestions
  defp find_similar_providers(input, providers) do
    input_lower = String.downcase(input)

    providers
    |> Enum.map(&Atom.to_string/1)
    |> Enum.filter(fn p ->
      p_lower = String.downcase(p)
      String.contains?(p_lower, input_lower) or String.contains?(input_lower, p_lower)
    end)
    |> Enum.take(3)
  end

  # ============================================================================
  # Agent Configuration
  # ============================================================================

  defp configure_agent(config) do
    case AgentSupervisor.lookup_agent(:llm_agent) do
      {:ok, pid} ->
        # Configure the running agent with new settings
        LLMAgent.configure(pid,
          provider: config.provider,
          model: config.model
        )

      {:error, :not_found} ->
        # Agent not running - that's OK, it will use settings when started
        :ok
    end
  end

  defp broadcast_config_change(config) do
    Phoenix.PubSub.broadcast(@pubsub, PubSubTopics.tui_events(), {:config_changed, config})
  end
end
