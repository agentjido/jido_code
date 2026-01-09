defmodule JidoCode.Config do
  @moduledoc """
  Configuration management for JidoCode LLM provider settings.

  This module handles reading and validating LLM configuration from application
  environment and environment variables. It integrates with Jido.AI's Config
  system for provider and model resolution.

  ## Configuration

  Configure in `config/runtime.exs`:

      config :jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096

  Or configure via Jido.AI:

      config :jido_ai,
        providers: %{
          anthropic: [api_key: {:system, "ANTHROPIC_API_KEY"}],
          openai: [api_key: {:system, "OPENAI_API_KEY"}]
        },
        model_aliases: %{
          fast: "anthropic:claude-haiku-4-5",
          capable: "anthropic:claude-sonnet-4-20250514"
        },
        defaults: %{
          temperature: 0.7,
          max_tokens: 4096
        }

  ## Environment Variables

  Environment variables override config file values:

  - `JIDO_CODE_PROVIDER` - Provider name (e.g., "anthropic", "openai")
  - `JIDO_CODE_MODEL` - Model name (e.g., "claude-3-5-sonnet-20241022")

  Provider-specific API keys are configured via Jido.AI:

  - `ANTHROPIC_API_KEY`
  - `OPENAI_API_KEY`
  - etc.

  ## Examples

      iex> JidoCode.Config.get_llm_config()
      {:ok, %{provider: :anthropic, model: "claude-3-5-sonnet", temperature: 0.7, max_tokens: 4096}}

      iex> JidoCode.Config.get_llm_config()
      {:error, "No LLM provider configured. Set JIDO_CODE_PROVIDER or configure :jido_code, :llm, :provider"}
  """

  require Logger

  alias Jido.AI.Config, as: AIConfig

  @type config :: %{
          provider: atom(),
          model: String.t(),
          temperature: float(),
          max_tokens: pos_integer()
        }

  @default_temperature 0.7
  @default_max_tokens 4096
  @default_provider :anthropic
  @default_model "anthropic:claude-sonnet-4-20250514"

  @fallback_providers [
    :anthropic,
    :openai,
    :openrouter,
    :google,
    :cloudflare,
    :groq,
    :ollama,
    :deepseek,
    :xai,
    :cohere
  ]

  @doc """
  Returns the validated LLM configuration.

  Reads configuration from application environment with environment variable
  overrides, validates provider existence, and checks for API key availability.

  ## Returns

  - `{:ok, config}` - Valid configuration map
  - `{:error, reason}` - Configuration error with descriptive message

  ## Examples

      {:ok, config} = JidoCode.Config.get_llm_config()
      config.provider  # => :anthropic
      config.model     # => "claude-3-5-sonnet-20241022"
  """
  @spec get_llm_config() :: {:ok, config()} | {:error, String.t()}
  def get_llm_config do
    with {:ok, provider} <- get_provider(),
         :ok <- validate_provider(provider),
         {:ok, model} <- get_model(),
         :ok <- validate_api_key(provider) do
      config = %{
        provider: provider,
        model: model,
        temperature: get_temperature(),
        max_tokens: get_max_tokens()
      }

      {:ok, config}
    end
  end

  @doc """
  Returns the validated LLM configuration or raises on error.

  Same as `get_llm_config/0` but raises `RuntimeError` on configuration errors.
  Useful for application startup where missing config should halt the application.

  ## Examples

      config = JidoCode.Config.get_llm_config!()
      # Raises RuntimeError if config is invalid
  """
  @spec get_llm_config!() :: config()
  def get_llm_config! do
    case get_llm_config() do
      {:ok, config} -> config
      {:error, reason} -> raise RuntimeError, reason
    end
  end

  @doc """
  Checks if LLM configuration is valid without raising.

  ## Returns

  - `true` if configuration is valid
  - `false` if configuration is missing or invalid
  """
  @spec configured?() :: boolean()
  def configured? do
    case get_llm_config() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Returns the provider configuration from Jido.AI.Config.

  Delegates to `Jido.AI.Config.get_provider/1` but wraps the result
  for consistency with the JidoCode API.

  ## Examples

      iex> JidoCode.Config.get_provider_config(:anthropic)
      [api_key: "sk-ant-..."]

      iex> JidoCode.Config.get_provider_config(:unknown)
      []
  """
  @spec get_provider_config(atom()) :: keyword()
  def get_provider_config(provider) when is_atom(provider) do
    AIConfig.get_provider(provider)
  end

  @doc """
  Resolves a model alias or passes through a direct model spec.

  Delegates to `Jido.AI.Config.resolve_model/1`.

  ## Examples

      iex> JidoCode.Config.resolve_model(:fast)
      "anthropic:claude-haiku-4-5"

      iex> JidoCode.Config.resolve_model("openai:gpt-4")
      "openai:gpt-4"
  """
  @spec resolve_model(atom() | String.t()) :: String.t()
  def resolve_model(model) when is_atom(model) or is_binary(model) do
    AIConfig.resolve_model(model)
  end

  @doc """
  Returns all configured model aliases.

  Delegates to `Jido.AI.Config.get_model_aliases/0`.

  ## Examples

      iex> JidoCode.Config.get_model_aliases()
      %{fast: "anthropic:claude-haiku-4-5", capable: "anthropic:claude-sonnet-4-20250514", ...}
  """
  @spec get_model_aliases() :: map()
  def get_model_aliases do
    AIConfig.get_model_aliases()
  end

  # Private functions

  defp get_provider do
    case get_env_or_config("JIDO_CODE_PROVIDER", :provider) do
      nil ->
        # Try to get from Jido.AI configuration
        case get_default_provider_from_ai() do
          nil ->
            {:error,
             "No LLM provider configured. Set JIDO_CODE_PROVIDER, configure :jido_code, :llm, :provider, or configure :jido_ai, :providers"}

          provider ->
            {:ok, provider}
        end

      value when is_atom(value) ->
        {:ok, value}

      value when is_binary(value) ->
        try do
          {:ok, String.to_existing_atom(value)}
        rescue
          ArgumentError ->
            {:ok, String.to_atom(value)}
        end
    end
  end

  defp get_default_provider_from_ai do
    # Get the first configured provider from Jido.AI
    providers = Application.get_env(:jido_ai, :providers, %{})

    case Map.keys(providers) do
      [] -> nil
      [first | _] -> first
    end
  end

  defp get_model do
    case get_env_or_config("JIDO_CODE_MODEL", :model) do
      nil ->
        # Return error instead of using default - tests expect explicit model configuration
        {:error,
         "No LLM model configured. Set JIDO_CODE_MODEL or configure :jido_code, :llm, :model"}

      value when is_binary(value) ->
        {:ok, value}

      value when is_atom(value) ->
        {:ok, Atom.to_string(value)}
    end
  end

  # Returns env var value if set and non-empty, otherwise falls back to config
  defp get_env_or_config(env_key, config_key) do
    case System.get_env(env_key) do
      nil -> get_config_value(config_key)
      "" -> get_config_value(config_key)
      value -> value
    end
  end

  defp get_temperature do
    # Check jido_code config first
    case get_config_value(:temperature) do
      nil ->
        @default_temperature

      temp when is_number(temp) ->
        # Clamp to valid range [0.0, 1.0]
        temp |> max(0.0) |> min(1.0)

      _ ->
        @default_temperature
    end
  end

  defp get_max_tokens do
    # Check jido_code config first
    case get_config_value(:max_tokens) do
      nil ->
        @default_max_tokens

      tokens when is_integer(tokens) and tokens > 0 ->
        tokens

      _invalid ->
        # Non-positive or non-integer falls back to default
        @default_max_tokens
    end
  end

  defp get_config_value(key) do
    case Application.get_env(:jido_code, :llm) do
      nil -> nil
      config when is_list(config) -> Keyword.get(config, key)
      config when is_map(config) -> Map.get(config, key)
    end
  end

  defp validate_provider(provider) do
    # Get known providers from ReqLLM or use a known list
    known_providers = get_known_providers()

    if provider in known_providers do
      :ok
    else
      available = known_providers |> Enum.take(10) |> Enum.map_join(", ", &Atom.to_string/1)

      {:error,
       "Invalid provider '#{provider}'. Available providers include: #{available}... (#{length(known_providers)} total)"}
    end
  end

  defp get_known_providers do
    # Use fallback list for known providers
    # In the future, could query ReqLLM.Registry for the full list
    @fallback_providers
  end

  defp validate_api_key(provider) do
    # Check if provider has configuration in Jido.AI
    provider_config = AIConfig.get_provider(provider)

    # Look for api_key in the provider config
    api_key = Keyword.get(provider_config, :api_key)

    cond do
      # API key is set directly in config
      is_binary(api_key) and api_key != "" ->
        :ok

      # No API key in config, check environment variable
      true ->
        env_key = provider_api_key_env(provider)

        case System.get_env(env_key) do
          nil ->
            {:error,
             "No API key found for provider '#{provider}'. Set #{env_key} environment variable or configure :jido_ai, :providers, #{provider}."}

          "" ->
            {:error,
             "API key for provider '#{provider}' is empty. Set #{env_key} environment variable."}

          _key ->
            :ok
        end
    end
  end

  defp provider_api_key_env(provider) do
    # Standard env var names for API keys
    case provider do
      :anthropic -> "ANTHROPIC_API_KEY"
      :openai -> "OPENAI_API_KEY"
      :openrouter -> "OPENROUTER_API_KEY"
      :google -> "GOOGLE_API_KEY"
      :cloudflare -> "CLOUDFLARE_API_KEY"
      :groq -> "GROQ_API_KEY"
      :ollama -> "OLLAMA_BASE_URL"
      _ -> "#{String.upcase(Atom.to_string(provider))}_API_KEY"
    end
  end
end
