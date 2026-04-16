defmodule JidoCode.LLM.Selection do
  @moduledoc """
  Hierarchical model selection across application, repository, and conversation levels.

  This module provides the core selection and resolution logic for choosing
  LLM providers and models based on a hierarchical configuration system:

  1. Conversation level (highest priority) - explicit opts per conversation
  2. Repository level - per-repository preferences via LLMPreferences
  3. Application level (lowest priority) - global defaults

  Selection includes validation for:
  - Provider availability (enabled for the repo)
  - Model existence in LLMDB
  - Capability requirements
  """

  alias JidoCode.LLM.Discovery
  alias JidoCode.Control.LLMPreferences
  alias JidoCode.Control.ManagedRepo

  @type selection_result :: %{
          provider: atom(),
          model: String.t(),
          llmdb_model: LLMDB.Model.t() | nil,
          source: :conversation | :repository | :application,
          capabilities: map()
        }

  @type resolution_error :: {:error, :provider_not_enabled | :model_not_found | :missing_capability | :invalid_provider}

  @type capabilities :: %{
          optional(:chat) => boolean(),
          optional(:tools) => boolean(),
          optional(:streaming) => boolean(),
          optional(:vision) => boolean()
        }

  @doc """
  Resolve a provider and model selection across the hierarchy.

  Resolution order:
  1. Conversation opts (provider/model keys)
  2. Repository preferences (LLMPreferences for the repo)
  3. Application defaults (config)

  ## Parameters

  - `conversation_opts`: Optional map with :llm_provider and/or :llm_model keys
  - `repo_id`: Optional UUID string of the managed repository
  - `app_opts`: Optional map overriding application config

  ## Returns

  `{:ok, selection_result}` on success, or `{:error, reason}` on failure.

  ## Examples

      iex> JidoCode.LLM.Selection.resolve(%{llm_provider: :anthropic}, repo_id, %{})
      {:ok, %{provider: :anthropic, model: "claude-3-5-sonnet-20250929", ...}}

  """
  @spec resolve(map(), String.t() | nil, map()) :: {:ok, selection_result()} | resolution_error()
  def resolve(conversation_opts \\ %{}, repo_id \\ nil, app_opts \\ %{})

  def resolve(conversation_opts, repo_id, app_opts) do
    with {:ok, provider} <- resolve_provider(conversation_opts, repo_id, app_opts),
         {:ok, model} <- resolve_model(conversation_opts, repo_id, app_opts, provider),
         {:ok, llmdb_model} <- fetch_model_metadata(provider, model),
         :ok <- validate_capabilities(llmdb_model, conversation_opts, repo_id) do
      source = determine_source(conversation_opts, repo_id)
      capabilities = extract_capabilities(llmdb_model)

      {:ok,
       %{
         provider: provider,
         model: model,
         llmdb_model: llmdb_model,
         source: source,
         capabilities: capabilities
       }}
    end
  end

  @doc """
  Get all available models for a repository, filtered by enabled providers and capabilities.

  ## Parameters

  - `repo_id`: Optional UUID string of the managed repository
  - `required_capabilities`: Optional map of required capabilities (e.g., %{chat: true, tools: true})

  ## Returns

  A list of maps with :provider, :model, and :llmdb_model keys.

  ## Examples

      iex> JidoCode.LLM.Selection.available_models(repo_id, %{tools: true})

  """
  @spec available_models(String.t() | nil, capabilities() | nil) :: [
          %{provider: atom(), model: String.t(), llmdb_model: LLMDB.Model.t()}
        ]
  def available_models(repo_id \\ nil, required_capabilities \\ nil)

  def available_models(repo_id, required_capabilities) do
    enabled_providers = enabled_providers_for_repo(repo_id)

    enabled_providers
    |> Enum.flat_map(fn provider ->
      case Discovery.list_models(provider) do
        models when is_list(models) ->
          Enum.map(models, fn model ->
            %{
              provider: provider,
              model: model.id,
              llmdb_model: model
            }
          end)

        _ ->
          []
      end
    end)
    |> Enum.filter(fn
      %{llmdb_model: nil} -> false
      %{llmdb_model: model} -> has_capabilities?(model, required_capabilities)
    end)
  end

  @doc """
  Get the list of enabled providers for a repository.

  Falls back to application default if no repository preferences exist.

  ## Parameters

  - `repo_id`: Optional UUID string of the managed repository

  ## Returns

  A list of provider atoms.

  """
  @spec enabled_providers_for_repo(String.t() | nil) :: [atom()]
  def enabled_providers_for_repo(nil) do
    application_config(:available_providers)
  end

  def enabled_providers_for_repo(repo_id) when is_binary(repo_id) do
    case get_repo_preferences(repo_id) do
      {:ok, prefs} ->
        prefs.enabled_providers || application_config(:available_providers)

      _error ->
        application_config(:available_providers)
    end
  end

  # Provider resolution

  defp resolve_provider(conversation_opts, repo_id, app_opts) do
    cond do
      # Conversation level
      provider = Map.get(conversation_opts, :llm_provider) ->
        validate_provider_enabled(provider, repo_id)

      # Repository level
      repo_id ->
        case get_repo_preferences(repo_id) do
          {:ok, prefs} when is_map(prefs) ->
            provider = prefs.default_provider || application_config(:default_provider, app_opts)
            validate_provider_enabled(provider, repo_id)

          _error ->
            provider = application_config(:default_provider, app_opts)
            validate_provider_enabled(provider, nil)
        end

      # Application level
      true ->
        provider = application_config(:default_provider, app_opts)
        validate_provider_enabled(provider, nil)
    end
  end

  defp validate_provider_enabled(provider, repo_id) when is_atom(provider) do
    enabled_providers = enabled_providers_for_repo(repo_id)

    if provider in enabled_providers do
      {:ok, provider}
    else
      {:error, :provider_not_enabled}
    end
  end

  defp validate_provider_enabled(provider, _repo_id) when is_binary(provider) do
    # Try to convert string to atom safely
    try do
      provider_atom = String.to_existing_atom(provider)
      validate_provider_enabled(provider_atom, nil)
    rescue
      ArgumentError -> {:error, :invalid_provider}
    end
  end

  defp validate_provider_enabled(_provider, _repo_id), do: {:error, :invalid_provider}

  # Model resolution

  defp resolve_model(conversation_opts, repo_id, app_opts, provider) do
    cond do
      # Conversation level
      model = Map.get(conversation_opts, :llm_model) ->
        validate_model_exists(model, provider)

      # Repository level
      repo_id ->
        case get_repo_preferences(repo_id) do
          {:ok, prefs} when is_map(prefs) ->
            model = prefs.default_model || application_config(:default_model, app_opts)
            validate_model_exists(model, provider)

          _error ->
            model = application_config(:default_model, app_opts)
            validate_model_exists(model, provider)
        end

      # Application level
      true ->
        model = application_config(:default_model, app_opts)
        validate_model_exists(model, provider)
    end
  end

  defp validate_model_exists(model_id, provider) when is_binary(model_id) do
    case Discovery.model_info(provider, model_id) do
      {:ok, _model} -> {:ok, model_id}
      :error -> {:error, :model_not_found}
    end
  end

  defp validate_model_exists(_model_id, _provider), do: {:error, :model_not_found}

  # Model metadata fetching

  defp fetch_model_metadata(provider, model_id) do
    case Discovery.model_info(provider, model_id) do
      {:ok, model} -> {:ok, model}
      :error -> {:ok, nil}
    end
  end

  # Capability validation

  defp validate_capabilities(nil, _opts, _repo_id), do: :ok

  defp validate_capabilities(model, opts, repo_id) do
    required_capabilities =
      cond do
        # Conversation level capabilities
        caps = Map.get(opts, :llm_capabilities) -> caps
        # Repository level capabilities
        repo_id ->
          case get_repo_preferences(repo_id) do
            {:ok, prefs} when is_map(prefs) -> prefs.require_capabilities || %{}
            _error -> %{}
          end

        true ->
          %{}
      end

    check_capabilities_met(model, required_capabilities)
  end

  defp check_capabilities_met(model, required_caps) when is_map(required_caps) do
    model_caps = model.capabilities || %{}

    all_met =
      Enum.all?(required_caps, fn {key, required} ->
        case Map.get(model_caps, key) do
          nil -> not required
          actual -> actual == required
        end
      end)

    if all_met do
      :ok
    else
      {:error, :missing_capability}
    end
  end

  defp check_capabilities_met(_model, _required_caps), do: :ok

  # Source determination

  defp determine_source(conversation_opts, repo_id) do
    cond do
      Map.has_key?(conversation_opts, :llm_provider) or Map.has_key?(conversation_opts, :llm_model) ->
        :conversation

      repo_id != nil ->
        :repository

      true ->
        :application
    end
  end

  # Capability extraction

  defp extract_capabilities(nil), do: %{}
  defp extract_capabilities(model), do: model.capabilities || %{}

  # Helper functions

  @doc """
  Check if a model has the required capabilities.

  ## Parameters

  - `model`: LLMDB.Model struct or nil
  - `required_capabilities`: Optional map of required capabilities

  ## Returns

  `true` if the model has all required capabilities, `false` otherwise.

  """
  @spec has_capabilities?(LLMDB.Model.t() | nil, capabilities() | nil) :: boolean()
  def has_capabilities?(nil, _required_caps), do: false

  def has_capabilities?(_model, nil), do: true

  def has_capabilities?(model, required_caps) when is_map(required_caps) do
    model_caps = model.capabilities || %{}

    Enum.all?(required_caps, fn {key, required} ->
      case Map.get(model_caps, key) do
        nil -> not required
        actual -> actual == required
      end
    end)
  end

  @doc """
  Get a human-readable label for a model.

  ## Parameters

  - `provider`: Provider atom
  - `model_id`: Model ID string

  ## Returns

  A human-readable label string.

  """
  @spec model_label(atom(), String.t()) :: String.t()
  def model_label(provider, model_id) do
    case Discovery.model_info(provider, model_id) do
      {:ok, model} ->
        # Try to get a nice display name from the model metadata
        Map.get(model, :display_name, model_id)

      :error ->
        model_id
    end
  end

  # Repository preferences fetching

  defp get_repo_preferences(repo_id) when is_binary(repo_id) do
    try do
      uuid = String.to_existing_atom(repo_id)

      case LLMPreferences.for_managed_repo(uuid, authorize?: false) do
        {:ok, [prefs | _]} when is_list(prefs) -> {:ok, prefs}
        {:ok, prefs} when is_map(prefs) -> {:ok, prefs}
        {:ok, []} -> {:error, :not_found}
        _error -> {:error, :not_found}
      end
    rescue
      _ ->
        {:error, :not_found}
    end
  end

  defp get_repo_preferences(_repo_id), do: {:error, :not_found}

  # Application config helpers

  defp application_config(key, app_opts \\ %{}) do
    # First check runtime app_opts override
    case Map.get(app_opts, key) do
      nil ->
        # Then check application config
        case Application.get_env(:jido_code, :llm) do
          nil -> default_config(key)
          llm_config when is_map(llm_config) -> Map.get(llm_config, key, default_config(key))
          _ -> default_config(key)
        end

      value ->
        value
    end
  end

  defp default_config(:available_providers), do: [:anthropic]
  defp default_config(:default_provider), do: :anthropic

  defp default_config(:default_model) do
    # Try to get a valid model ID from LLMDB
    provider = default_config(:default_provider)

    case Discovery.list_models(provider) do
      [%LLMDB.Model{id: id} | _] -> id
      _ -> "claude-3-5-sonnet-20250929"
    end
  end

  defp default_config(_key), do: nil

  # Validation helpers (for external use)

  @doc """
  Validate that a provider is in the list of available providers.

  """
  @spec validate_provider_in_available(atom(), [atom()]) :: :ok | {:error, :provider_not_available}
  def validate_provider_in_available(provider, available_providers) do
    if provider in available_providers do
      :ok
    else
      {:error, :provider_not_available}
    end
  end

  @doc """
  Validate that a model exists for a given provider.

  """
  @spec validate_model_exists_for_provider(String.t(), atom()) :: :ok | {:error, :model_not_found}
  def validate_model_exists_for_provider(model_id, provider) do
    case Discovery.model_info(provider, model_id) do
      {:ok, _model} -> :ok
      :error -> {:error, :model_not_found}
    end
  end

  @doc """
  Validate that a model meets required capabilities.

  """
  @spec validate_capabilities_met(LLMDB.Model.t(), capabilities()) :: :ok | {:error, :missing_capability}
  def validate_capabilities_met(model, required_caps) do
    model_caps = model.capabilities || %{}

    all_met =
      Enum.all?(required_caps, fn {key, required} ->
        case Map.get(model_caps, key) do
          nil -> not required
          actual -> actual == required
        end
      end)

    if all_met, do: :ok, else: {:error, :missing_capability}
  end

  @doc """
  Format an error reason into a user-friendly message.

  """
  @spec format_error(atom()) :: String.t()
  def format_error(:provider_not_enabled),
    do: "The selected provider is not enabled for this repository."

  def format_error(:model_not_found),
    do: "The selected model was not found for the specified provider."

  def format_error(:missing_capability),
    do: "The selected model does not support the required capabilities."

  def format_error(:invalid_provider),
    do: "The specified provider is invalid."

  def format_error(_reason),
    do: "An unknown error occurred during model selection."
end
