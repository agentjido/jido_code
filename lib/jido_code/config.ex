defmodule JidoCode.Config do
  @moduledoc """
  Configuration management for JidoCode LLM provider settings.

  This module handles reading and validating LLM configuration from application
  environment and environment variables. It integrates with JidoAI's provider
  system to validate provider availability and API key presence.

  ## Configuration

  Configure in `config/runtime.exs`:

      config :jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096

  ## Environment Variables

  Environment variables override config file values:

  - `JIDO_CODE_PROVIDER` - Provider name (e.g., "anthropic", "openai")
  - `JIDO_CODE_MODEL` - Model name (e.g., "claude-3-5-sonnet-20241022")

  Provider-specific API keys are managed by JidoAI's Keyring:

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

  @type config :: %{
          provider: atom(),
          model: String.t(),
          temperature: float(),
          max_tokens: pos_integer()
        }

  @default_temperature 0.7
  @default_max_tokens 4096
  @providers_cache_key {__MODULE__, :providers}

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
         {:ok, model} <- get_model(),
         :ok <- validate_provider(provider),
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

  # Private functions

  defp get_provider do
    provider =
      case System.get_env("JIDO_CODE_PROVIDER") do
        nil -> get_config_value(:provider)
        "" -> get_config_value(:provider)
        env_provider -> String.to_atom(env_provider)
      end

    case provider do
      nil ->
        {:error,
         "No LLM provider configured. Set JIDO_CODE_PROVIDER or configure :jido_code, :llm, :provider"}

      provider when is_atom(provider) ->
        {:ok, provider}

      provider when is_binary(provider) ->
        {:ok, String.to_atom(provider)}
    end
  end

  defp get_model do
    model =
      case System.get_env("JIDO_CODE_MODEL") do
        nil -> get_config_value(:model)
        "" -> get_config_value(:model)
        env_model -> env_model
      end

    case model do
      nil ->
        {:error,
         "No LLM model configured. Set JIDO_CODE_MODEL or configure :jido_code, :llm, :model"}

      model when is_binary(model) ->
        {:ok, model}

      model when is_atom(model) ->
        {:ok, Atom.to_string(model)}
    end
  end

  defp get_temperature do
    case get_config_value(:temperature) do
      nil -> @default_temperature
      temp when is_number(temp) -> temp / 1
      _ -> @default_temperature
    end
  end

  defp get_max_tokens do
    case get_config_value(:max_tokens) do
      nil -> @default_max_tokens
      tokens when is_integer(tokens) -> tokens
      _ -> @default_max_tokens
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
    providers = get_available_providers()

    if provider in providers do
      :ok
    else
      available = providers |> Enum.take(10) |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")

      {:error,
       "Invalid provider '#{provider}'. Available providers include: #{available}... (#{length(providers)} total)"}
    end
  end

  defp get_available_providers do
    # Use persistent_term cache to avoid repeated JidoAI calls
    case :persistent_term.get(@providers_cache_key, :not_cached) do
      :not_cached ->
        providers = fetch_providers()
        :persistent_term.put(@providers_cache_key, providers)
        providers

      cached_providers ->
        cached_providers
    end
  end

  defp fetch_providers do
    # Use ReqLLM registry via Jido.AI.Model.Registry.Adapter
    # This returns all 57+ ReqLLM providers without legacy fallback warnings
    case Jido.AI.Model.Registry.Adapter.list_providers() do
      {:ok, providers} when is_list(providers) ->
        providers

      _ ->
        # Fallback only if ReqLLM registry is completely unavailable
        [:anthropic, :openai, :openrouter, :google, :cloudflare]
    end
  end

  defp validate_api_key(provider) do
    api_key_name = provider_api_key_name(provider)

    # Check environment variable directly first
    env_key = api_key_name |> Atom.to_string() |> String.upcase()

    case System.get_env(env_key) do
      nil ->
        # Try Keyring as fallback
        try_keyring(provider, api_key_name)

      "" ->
        {:error,
         "API key for provider '#{provider}' is empty. Set #{env_key} environment variable."}

      _key ->
        :ok
    end
  end

  defp try_keyring(provider, api_key_name) do
    env_key = api_key_name |> Atom.to_string() |> String.upcase()

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
        # Keyring module error
        {:error,
         "No API key found for provider '#{provider}'. Set #{env_key} environment variable."}
    catch
      :exit, _ ->
        # Keyring GenServer not running
        {:error,
         "No API key found for provider '#{provider}'. Set #{env_key} environment variable."}
    end
  end

  defp provider_api_key_name(provider) do
    :"#{provider}_api_key"
  end
end
