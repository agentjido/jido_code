defmodule JidoCode.LLM.Discovery do
  @moduledoc """
  Provider and model discovery backed by req_llm and LLMDB.

  This module provides runtime discovery of all available LLM providers
  and their models through the ReqLLM and LLMDB libraries. It enables
  multi-provider support without hardcoding any provider-specific logic.

  Provider information includes:
  - Provider ID (atom identifier)
  - Human-readable name
  - Description (when available)
  - Environment variable key for API credentials
  - Optional custom base URL for self-hosted/proxy deployments

  Model information includes:
  - Model ID (string identifier)
  - Model metadata from LLMDB including capabilities, context length, etc.
  """

  @type provider :: atom()
  @type provider_info :: %{
          id: provider(),
          name: String.t(),
          description: String.t() | nil,
          env_key: String.t() | nil,
          base_url: String.t() | nil
        }

  @doc """
  List all available providers from ReqLLM.

  Returns a list of provider information maps containing metadata about
  each available provider. The list is dynamically generated from ReqLLM's
  provider registry.

  ## Examples

      iex> JidoCode.LLM.Discovery.list_providers()
      [
        %{id: :anthropic, name: "Anthropic", env_key: "ANTHROPIC_API_KEY", ...},
        %{id: :openai, name: "OpenAI", env_key: "OPENAI_API_KEY", ...},
        ...
      ]

  """
  @spec list_providers() :: [provider_info()]
  def list_providers do
    ReqLLM.Providers.list()
    |> Enum.map(&provider_info/1)
  end

  @doc """
  Get detailed information about a specific provider.

  Returns a map with provider metadata including the canonical name,
  description, environment variable key for API credentials, and
  optional base URL for custom deployments.

  ## Parameters

  - `provider_id`: The atom identifier for the provider (e.g., `:anthropic`)

  ## Returns

  A map containing provider metadata.

  ## Examples

      iex> JidoCode.LLM.Discovery.provider_info(:anthropic)
      %{id: :anthropic, name: "Anthropic", env_key: "ANTHROPIC_API_KEY", ...}

  """
  @spec provider_info(provider()) :: provider_info()
  def provider_info(provider_id) when is_atom(provider_id) do
    module = ReqLLM.Providers.get!(provider_id)

    %{
      id: provider_id,
      name: provider_name(provider_id),
      description: provider_description(module),
      env_key: ReqLLM.Providers.get_env_key(provider_id),
      base_url: provider_base_url(module)
    }
  end

  @doc """
  List all available models for a specific provider.

  Returns a list of LLMDB.Model structs containing metadata about each
  model available through the specified provider.

  ## Parameters

  - `provider_id`: The atom identifier for the provider (e.g., `:anthropic`)

  ## Returns

  A list of LLMDB.Model structs.

  ## Examples

      iex> JidoCode.LLM.Discovery.list_models(:anthropic)
      [%LLMDB.Model{id: "claude-3-5-sonnet-20250929", ...}, ...]

  """
  @spec list_models(provider()) :: [LLMDB.Model.t()]
  def list_models(provider_id) when is_atom(provider_id) do
    LLMDB.models(provider_id)
  end

  @doc """
  Get detailed information about a specific model.

  Returns the LLMDB.Model struct for the specified provider and model ID,
  or `:error` if the model is not found.

  ## Parameters

  - `provider_id`: The atom identifier for the provider
  - `model_id`: The string identifier for the model

  ## Returns

  `{:ok, LLMDB.Model.t()}` if found, or `:error` if not found.

  ## Examples

      iex> JidoCode.LLM.Discovery.model_info(:anthropic, "claude-3-5-sonnet-20250929")
      {:ok, %LLMDB.Model{id: "claude-3-5-sonnet-20250929", ...}}

  """
  @spec model_info(provider(), String.t()) :: {:ok, LLMDB.Model.t()} | :error
  def model_info(provider_id, model_id) when is_atom(provider_id) and is_binary(model_id) do
    case LLMDB.model(provider_id, model_id) do
      {:ok, _model} = result -> result
      _error -> :error
    end
  end

  @doc """
  Get a human-readable display name for a provider.

  Converts provider atom identifiers to formatted display names.

  ## Parameters

  - `provider_id`: The atom identifier for the provider

  ## Returns

  A human-readable string name for the provider.

  ## Examples

      iex> JidoCode.LLM.Discovery.provider_name(:anthropic)
      "Anthropic"

      iex> JidoCode.LLM.Discovery.provider_name(:openai)
      "OpenAI"

  """
  @spec provider_name(provider()) :: String.t()
  def provider_name(provider_id) when is_atom(provider_id) do
    provider_id
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  Get the description for a provider module.

  Extracts the @moduledoc from the provider module if available.

  ## Parameters

  - `module`: The provider module

  ## Returns

  The module documentation string or nil if not available.

  """
  @spec provider_description(module()) :: String.t() | nil
  def provider_description(module) when is_atom(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _annotation, _beam_language, _format, _moduledoc, _doc, docs, _} ->
        # Find the moduledoc entry (usually the first with :moduledoc type)
        Enum.find_value(docs, fn
          {:moduledoc, _line, _doc_language, _doc_mime_type, doc} -> String.trim(doc)
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  @doc """
  Get the base URL for a provider module.

  Returns the configured base URL if the provider supports custom endpoints,
  otherwise returns nil.

  ## Parameters

  - `module`: The provider module

  ## Returns

  The base URL string or nil.

  """
  @spec provider_base_url(module()) :: String.t() | nil
  def provider_base_url(module) when is_atom(module) do
    case function_exported?(module, :base_url, 0) do
      true -> apply(module, :base_url, [])
      false -> nil
    end
  end
end
