# LLM Provider Configuration

<!-- covers: architecture.llm.multi_provider_support.provider_configuration -->
<!-- covers: architecture.llm.multi_provider_llm_support.hierarchical_configuration -->
<!-- covers: package.jido_code.spec_led_workspace -->

Relates to:
- [Multi-Provider LLM Support ADR](../decisions/jido_code.multi_provider_llm_support.md)
- [LLM Model Selection UI Spec](./llm_model_selection.spec.md)

## Overview

JidoCode will support **all ReqLLM providers** (18+) through a hierarchical configuration system that operates at three levels:

1. **Application Level**: Global provider availability and defaults
2. **Repository Level**: Per-managed-repo provider preferences and constraints
3. **Conversation Level**: Per-conversation model selection

## Provider Discovery

### Provider List

Providers are discovered at runtime from `ReqLLM.Providers.list/0`.

```elixir
# lib/jido_code/llm/discovery.ex
defmodule JidoCode.LLM.Discovery do
  @moduledoc """
  Provider and model discovery backed by req_llm and LLMDB.
  """

  @type provider :: atom()
  @type provider_info :: %{
    id: provider(),
    name: String.t(),
    description: String.t() | nil,
    env_key: String.t() | nil,
    base_url: String.t() | nil
  }

  @spec list_providers() :: [provider_info()]
  def list_providers do
    ReqLLM.Providers.list()
    |> Enum.map(&provider_info/1)
  end

  @spec provider_info(provider()) :: provider_info()
  def provider_info(provider_id) do
    module = ReqLLM.Providers.get!(provider_id)

    %{
      id: provider_id,
      name: provider_name(provider_id),
      description: provider_description(module),
      env_key: ReqLLM.Providers.get_env_key(provider_id),
      base_url: provider_base_url(module)
    }
  end

  @spec list_models(provider()) :: [LLMDB.Model.t()]
  def list_models(provider_id) do
    LLMDB.models(provider_id)
  end

  @spec model_info(provider(), String.t()) :: {:ok, LLMDB.Model.t()} | :error
  def model_info(provider_id, model_id) do
    LLMDB.model(provider_id, model_id)
  end
end
```

### Provider Metadata

Provider metadata includes:

| Field | Type | Description |
|-------|------|-------------|
| `id` | `atom()` | Provider identifier (e.g., `:anthropic`, `:openai`) |
| `name` | `String.t()` | Human-readable display name |
| `description` | `String.t() | nil` | Provider description |
| `env_key` | `String.t() | nil` | Environment variable for API key (e.g., `ANTHROPIC_API_KEY`) |
| `base_url` | `String.t() | nil` | Optional custom base URL for self-hosted/proxy |

## Configuration Levels

### Application Level Configuration

Stored in `config/*.exs`:

```elixir
# config/dev.exs
config :jido_code, :llm,
  # All providers available to req_llm
  available_providers: :all,  # or explicit list: [:anthropic, :openai, :google]

  # Default provider when none specified
  default_provider: :anthropic,

  # Default model when none specified
  default_model: "claude-3-5-sonnet-20250929",

  # Capability requirements for default model
  default_capabilities: [
    chat: true,
    tools: true,
    streaming: true
  ]
```

**Application-level configuration:**
- Defines which providers are **available** for use
- Sets **global defaults** for new repositories
- Cannot be overridden by repository or conversation level
- Updated by administrators only

### Repository Level Configuration

Stored as a governed Ash resource:

```elixir
# lib/jido_code/control/llm_preferences.ex
defmodule JidoCode.Control.LLMPreferences do
  use Ash.Resource,
    domain: JidoCode.Control,
    data_layer: AshPostgres.DataLayer

  @moduledoc """
  Per-repository LLM provider and model preferences.

  Each managed repository can configure:
  - Which providers are enabled (subset of application-available)
  - Default provider and model for conversations
  - Required model capabilities
  """

  attributes do
    uuid_primary_key :id

    belongs_to :managed_repo, JidoCode.Control.ManagedRepo do
      allow_nil? false
      attribute_writable? true
    end

    attribute :enabled_providers, {:array, :atom} do
      default [:anthropic]
      description: "Providers enabled for this repository (must be subset of application available)"
    end

    attribute :default_provider, :atom do
      default :anthropic
      description: "Default provider for conversations in this repository"
    end

    attribute :default_model, :string do
      default "claude-3-5-sonnet-20250929"
      description: "Default model identifier"
    end

    attribute :require_capabilities, :map do
      default %{}
      description: "Required capabilities for models (e.g., %{tools: true, streaming: true})"
    end

    attribute :max_context_length, :integer do
      description: "Maximum context window for models in this repository"
    end

    attribute :allow_custom_models, :boolean do
      default true
      description: "Whether users can specify custom models not in LLMDB"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :managed_repo, JidoCode.Control.ManagedRepo
  end

  actions do
    defaults [:read, :destroy, :create, :update]

    read :for_managed_repo do
      argument :managed_repo_id, :string do
        allow_nil? false
      end

      get do
        argument :managed_repo_id, :string do
          allow_nil? false
        end
      end
    end
  end

  validations do
    validate {Validations, :providers_subset_of_available, []}
    validate {Validations, :default_provider_in_enabled, []}
    validate {Validations, :default_model_exists_for_provider, []}
  end
end
```

**Repository-level configuration:**
- Defines which providers are **enabled** for a specific repository
- Can **restrict** the application-level list
- Sets repository-specific defaults
- Configured by repository owners/maintainers

### Conversation Level Configuration

Stored as metadata on `WorkItem` or in `Conversation` state:

```elixir
# Conversation metadata
%{
  "llm_provider" => "openai",
  "llm_model" => "gpt-4o-mini",
  "llm_capabilities" => %{
    "tools" => true,
    "streaming" => true,
    "json_native" => true
  }
}
```

**Conversation-level configuration:**
- Selects specific provider/model for a conversation
- Must be within repository's enabled providers
- Can specify capability requirements
- Configured by conversation initiator

## Model Selection Resolution

### Resolution Order

Model selection resolves in order with validation at each step:

```
Conversation Level (if specified)
         ↓ (validate: provider enabled, model exists)
Repository Level (if configured)
         ↓ (validate: provider in enabled set, model valid)
Application Level (fallback)
         ↓ (validate: always available)
```

### Selection Algorithm

```elixir
# lib/jido_code/llm/selection.ex
defmodule JidoCode.LLM.Selection do
  @moduledoc """
  Hierarchical LLM model selection and resolution.

  Resolves model selection across three configuration levels:
  1. Conversation (highest precedence)
  2. Repository
  3. Application (fallback)
  """

  @type selection_result :: %{
    provider: atom(),
    model: String.t(),
    llmdb_model: LLMDB.Model.t(),
    source: :conversation | :repository | :application,
    capabilities: map()
  }

  @spec resolve(
    conversation_opts :: map(),
    repo_id :: String.t() | nil,
    app_opts :: map()
  ) :: {:ok, selection_result()} | {:error, term()}
  def resolve(conversation_opts, repo_id, app_opts) do
    with {:ok, provider} <- resolve_provider(conversation_opts, repo_id, app_opts),
         {:ok, model} <- resolve_model(conversation_opts, repo_id, app_opts, provider),
         {:ok, llmdb_model} <- fetch_model_metadata(provider, model),
         {:ok, capabilities} <- validate_capabilities(llmdb_model, conversation_opts, repo_id) do
      source = determine_source(conversation_opts, repo_id)

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

  @spec available_models(
    repo_id :: String.t() | nil,
    capabilities :: keyword()
  ) :: [%{provider: atom(), model: String.t(), label: String.t()}]
  def available_models(repo_id, capabilities \\ []) do
    enabled_providers = enabled_providers_for_repo(repo_id)

    enabled_providers
    |> Enum.flat_map(fn provider ->
      provider
      |> LLMDB.models()
      |> Enum.filter(&has_capabilities?(&1, capabilities))
      |> Enum.map(fn model ->
        %{
          provider: provider,
          model: model.id,
          label: model_label(provider, model)
        }
      end)
    end)
    |> Enum.sort_by(& &1.label)
  end

  defp resolve_provider(conversation_opts, repo_id, app_opts) do
    cond do
      # Conversation level
      provider = conversation_opts["llm_provider"] || conversation_opts[:llm_provider] ->
        provider = String.to_existing_atom(provider)
        validate_provider_enabled(provider, repo_id)

      # Repository level
      repo_id != nil ->
        with {:ok, prefs} <- get_repo_preferences(repo_id),
             true <- is_binary(prefs.default_provider) do
          {:ok, String.to_existing_atom(prefs.default_provider)}
        else
          _ -> {:ok, Keyword.get(app_opts, :default_provider, :anthropic)}
        end

      # Application fallback
      true ->
        {:ok, Keyword.get(app_opts, :default_provider, :anthropic)}
    end
  end

  defp validate_provider_enabled(provider, repo_id) do
    enabled = enabled_providers_for_repo(repo_id)

    if provider in enabled do
      {:ok, provider}
    else
      {:error, {:provider_not_enabled, provider, enabled}}
    end
  end

  defp enabled_providers_for_repo(nil), do: Application.get_env(:jido_code, :llm)[:available_providers] || :all

  defp enabled_providers_for_repo(repo_id) do
    case get_repo_preferences(repo_id) do
      {:ok, prefs} -> prefs.enabled_providers
      :error -> Application.get_env(:jido_code, :llm)[:available_providers] || :all
    end
  end

  defp get_repo_preferences(repo_id) do
    JidoCode.Control.LLMPreferences
    |> Ash.read(for_managed_repo: %{managed_repo_id: repo_id})
    |> case do
      {:ok, [prefs]} -> {:ok, prefs}
      _ -> :error
    end
  end
end
```

## Credential Management

### API Key Storage

API keys continue to use the existing `SecretRefs` system:

```elixir
# Updated: lib/jido_code/security/secret_refs.ex
defmodule JidoCode.SecretRefs do
  @type provider :: atom()  # No longer constrained to :anthropic | :openai

  @doc """
  Get the environment key for a provider.

  Delegates to ReqLLM.Providers.get_env_key/1 for automatic discovery.
  """
  def provider_env_key(provider) when is_atom(provider) do
    ReqLLM.Providers.get_env_key(provider) ||
      :"#{provider}_api_key"
  end

  @doc """
  Build the secret reference name for a provider's API key.

  Maps providers to their canonical secret reference paths.
  """
  def provider_secret_ref_name(provider) when is_atom(provider) do
    "providers/#{provider}_api_key"
  end

  @doc """
  Validate a provider credential value.

  For known providers, uses provider-specific validation.
  For unknown providers, performs basic format validation.
  """
  def valid_provider_credential_value?(provider, value) when is_atom(provider) do
    case provider do
      :anthropic -> valid_anthropic_key?(value)
      :openai -> valid_openai_key?(value)
      :google -> valid_google_key?(value)
      :groq -> valid_groq_key?(value)
      _other -> valid_generic_key?(value)
    end
  end
end
```

### Credential Precedence

API keys are resolved in order:

1. **Per-request** (not recommended, only for testing)
2. **Application config** (`config :req_llm, provider_api_key: "..."`)
3. **Environment variable** (`PROVIDER_API_KEY`)
4. **SecretRefs** (stored securely in database)

## Migration Path

### Phase 1: Discovery (Non-Breaking)

Add discovery modules without changing behavior:

```bash
# Add new files
lib/jido_code/llm/discovery.ex
lib/jido_code/llm/selection.ex
test/jido_code/llm/discovery_test.exs
test/jido_code/llm/selection_test.exs
```

### Phase 2: Credential Extension

Extend `SecretRefs` to accept any atom provider:

```elixir
# Before
@type provider :: :anthropic | :openai

# After
@type provider :: atom()
```

### Phase 3: Database Migration

```bash
# Create migration
mix ecto.gen.migration add_llm_preferences
```

```elixir
defmodule JidoCode.Repo.Migrations.AddLLMPreferences do
  use Ecto.Migration

  def change do
    create table(:llm_preferences, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :managed_repo_id, :uuid, null: false
      add :enabled_providers, {:array, :text}, default: ["anthropic"]
      add :default_provider, :text, default: "anthropic"
      add :default_model, :text, default: "claude-3-5-sonnet-20250929"
      add :require_capabilities, :map, default: "{}"
      add :max_context_length, :integer
      add :allow_custom_models, :boolean, default: true
      timestamps()
    end

    create unique_index(:llm_preferences, [:managed_repo_id])
    create index(:llm_preferences, [:managed_repo_id], name: :llm_preferences_managed_repo_id_index)
  end
end
```

### Phase 4: Feature Flag

```elixir
# config/dev.exs
config :jido_code, :feature_multi_provider_llm, true

# config/prod.exs
config :jido_code, :feature_multi_provider_llm, false  # Rollout gradually
```

## Testing Coverage

### Unit Tests

```elixir
# test/jido_code/llm/discovery_test.exs
defmodule JidoCode.LLM.DiscoveryTest do
  test "list_providers returns all req_llm providers" do
    providers = LLM.Discovery.list_providers()
    assert length(providers) >= 18
    assert Enum.any?(providers, &(&1.id == :anthropic))
    assert Enum.any?(providers, &(&1.id == :openai))
  end

  test "provider_info returns expected metadata" do
    info = LLM.Discovery.provider_info(:anthropic)
    assert info.id == :anthropic
    assert info.name =~ ~i/anthropic/i
    assert info.env_key == "ANTHROPIC_API_KEY"
  end

  test "list_models returns models for a provider" do
    models = LLM.Discovery.list_models(:anthropic)
    assert length(models) > 0
    assert Enum.all?(models, &is_struct(&1, LLMDB.Model))
  end
end

# test/jido_code/llm/selection_test.exs
defmodule JidoCode.LLM.SelectionTest do
  test "resolve with conversation opts uses conversation provider" do
    conversation_opts = %{"llm_provider" => "openai", "llm_model" => "gpt-4o-mini"}
    assert {:ok, result} = LLM.Selection.resolve(conversation_opts, nil, [])
    assert result.provider == :openai
    assert result.source == :conversation
  end

  test "resolve falls back to repository prefs" do
    # Setup repository with prefs
    assert {:ok, result} = LLM.Selection.resolve(%{}, "repo-id", app_opts)
    assert result.source == :repository
  end

  test "resolve falls back to application defaults" do
    assert {:ok, result} = LLM.Selection.resolve(%{}, nil, app_opts)
    assert result.source == :application
  end

  test "available_models filters by capabilities" do
    models = LLM.Selection.available_models("repo-id", tools: true)
    assert Enum.all?(models, fn m ->
      model = LLMDB.model(m.provider, m.model)
      model.capabilities.tools.enabled == true
    end)
  end
end
```

### Integration Tests

```elixir
# test/jido_code/llm/multi_provider_integration_test.exs
defmodule JidoCode.LLM.MultiProviderIntegrationTest do
  test "end-to-end conversation with non-default provider" do
    # Setup repository with openai enabled
    # Create conversation specifying openai:gpt-4o-mini
    # Verify request uses correct provider
  end

  test "provider not enabled is rejected" do
    # Attempt to use disabled provider
    # Verify clear error message
  end
end
```

## Open Questions

1. **Should we cache provider/model lists** or query req_llm each time?
   - Recommendation: Cache with TTL, refresh on application startup

2. **How to handle providers without LLMDB entries** (custom/self-hosted)?
   - Recommendation: Allow `allow_custom_models: true` with manual model specification

3. **Should we expose pricing information** from LLMDB?
   - Recommendation: Yes, for cost-aware model selection

4. **How to handle provider-specific options** (temperature, top_p, etc.)?
   - Recommendation: Provider-specific options via `provider_options` key
