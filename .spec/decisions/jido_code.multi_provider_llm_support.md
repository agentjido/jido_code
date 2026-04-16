# Multi-Provider LLM Support

**Status:** Proposed
**Date:** 2026-04-16
**Context:** LLM provider support expansion
**Related:** [LLM Provider Configuration Spec](../specs/llm_provider_configuration.spec.md), [LLM Model Selection Spec](../specs/llm_model_selection.spec.md)

## Context

JidoCode currently uses the `req_llm` library for LLM interactions, which supports **18+ providers** and **665+ models** through the LLMDB catalog. However, the application only exposes **2 providers** (Anthropic and OpenAI) to users through a hardcoded provider type system.

### Current State

```elixir
# lib/jido_code/security/secret_refs.ex
@type provider :: :anthropic | :openai
@provider_rotation_options [{"Anthropic", "anthropic"}, {"OpenAI", "openai"}]
```

This creates a significant discrepancy between:
- **Available capability**: 18+ providers via req_llm (Anthropic, OpenAI, Google Gemini, Google Vertex, Amazon Bedrock, Azure, Groq, xAI, OpenRouter, Cerebras, Meta Llama, Z.AI, Zenmux, Venice, vLLM, Alibaba, etc.)
- **Exposed capability**: 2 providers (Anthropic, OpenAI)

### Why This Matters

1. **User Choice**: Different organizations have existing contracts, compliance requirements, or preferences for specific LLM providers
2. **Capability Alignment**: Different providers excel at different tasks (reasoning, speed, cost, modality)
3. **Redundancy**: Multi-provider support reduces vendor lock-in and provides fallback options
4. **Cost Optimization**: Users can choose providers based on pricing for different use cases

## Decision

JidoCode will expose **all ReqLLM providers** and their available models through a configurable, hierarchical system that operates at three levels:

1. **Application Level**: Global provider availability and defaults
2. **Repository Level**: Per-managed-repo provider preferences and constraints
3. **Conversation Level**: Per-conversation model selection (within repo constraints)

### Key Principles

1. **Provider Agnostic**: The application should not hardcode any provider
2. **Dynamic Discovery**: Providers and models are discovered from req_llm/LLMDB at runtime
3. **Hierarchical Configuration**: Lower levels can override higher-level defaults within policy constraints
4. **Credential Safety**: API keys are stored securely through the existing secret_refs system
5. **Capability-Based Selection**: Users select models based on required capabilities (chat, tools, streaming, etc.) not raw IDs

## Implementation

### Phase 1: Provider and Model Discovery

```elixir
# New module: lib/jido_code/llm/discovery.ex
defmodule JidoCode.LLM.Discovery do
  @doc "List all available providers from req_llm"
  def list_providers :: [atom()]

  @doc "Get provider metadata including name, description, and capabilities"
  def provider_info(atom()) :: map()

  @doc "List all models for a provider"
  def list_models(atom()) :: [LLMDB.Model.t()]

  @doc "Get model metadata"
  def model_info(atom(), String.t()) :: LLMDB.Model.t()
end
```

### Phase 2: Credential Management Extension

Extend `SecretRefs` to support all req_llm providers:

```elixir
# Updated: lib/jido_code/security/secret_refs.ex
@type provider :: atom()  # No longer constrained to :anthropic | :openai

def provider_env_key(provider) when is_atom(provider) do
  ReqLLM.Providers.get_env_key(provider) ||
    :"#{provider}_api_key"
end
```

### Phase 3: Configuration Storage

#### Application Level

```elixir
# config/dev.exs, config/prod.exs
config :jido_code, :llm_providers,
  enabled: [:anthropic, :openai, :google, :groq],
  default_provider: :anthropic,
  default_model: "claude-3-5-sonnet-20250929"
```

#### Repository Level (Ash Resource)

```elixir
# lib/jido_code/control/llm_preferences.ex
defmodule JidoCode.Control.LLMPreferences do
  @moduledoc """
  Per-repository LLM provider and model preferences.
  Part of ManagedRepo governed resources.
  """

  use Ash.Resource,
    domain: JidoCode.Control,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id

    attribute :managed_repo_id, :uuid do
      allow_nil? false
    end

    attribute :enabled_providers, {:array, :atom} do
      default [:anthropic]
      description: "Providers allowed for this repository"
    end

    attribute :default_provider, :atom do
      default :anthropic
    end

    attribute :default_model, :string do
      default "claude-3-5-sonnet-20250929"
    end

    attribute :require_capabilities, :map do
      description: "Required model capabilities (e.g., %{tools: true, streaming: true})"
      default %{}
    end
  end

  actions do
    defaults [:read, :destroy]

    read :for_managed_repo do
      argument :managed_repo_id, :string do
        allow_nil? false
      end
      # Returns LLMPreferences for a repo, or application defaults if none set
    end
  end
end
```

#### Conversation Level (Conversation Metadata)

```elixir
# Stored in WorkItem or Conversation metadata
%{
  "llm_provider" => "openai",
  "llm_model" => "gpt-4o-mini",
  "llm_capabilities" => %{"tools" => true, "streaming" => true}
}
```

### Phase 4: Model Selection API

```elixir
# lib/jido_code/llm/selection.ex
defmodule JidoCode.LLM.Selection do
  @doc """
  Select the best model for a given context.

  Resolves in order:
  1. Conversation-level preference (if provided)
  2. Repository-level default (if configured)
  3. Application-level default (fallback)

  Validates that:
  - Provider is enabled at the appropriate level
  - Model exists in LLMDB catalog
  - Model meets required capabilities
  """
  def resolve_model(conversation_opts, repo_opts, app_opts) ::
    {:ok, %{provider: atom(), model: String.t(), llmdb_model: LLMDB.Model.t()}} |
    {:error, term()}

  @doc """
  List available models for a context, filtered by:
  - Enabled providers
  - Required capabilities
  - Repository constraints
  """
  def available_models(repo_id, capabilities \\ []) :: [%{provider: atom(), model: String.t()}]
end
```

### Phase 5: UI Updates

#### Settings Page

```elixir
# lib/jido_code_web/live/llm_settings_live.ex
defmodule JidoCode.LLMSettingsLive do
  @moduledoc """
  LLM provider and model configuration UI.

  Shows:
  - All available providers (discovered from req_llm)
  - Enabled/disabled state per provider
  - API key configuration
  - Default model selection
  """
end
```

#### Repository Detail Page

```elixir
# Add to: lib/jido_code_web/live/managed_repo_detail_live.ex
@doc "LLM preferences section for repository"
def render_llm_preferences(assigns) do
  ~H"""
  <.section>
    <h3>LLM Configuration</h3>
    <.provider_selector available={@all_providers} selected={@repo_prefs.enabled_providers} />
    <.model_selector provider={@repo_prefs.default_provider} model={@repo_prefs.default_model} />
  </.section>
  """
end
```

#### Conversation Composer

```elixir
# Add to: lib/jido_code_web/live/conversation/composer_live.ex
@doc "Model selection dropdown for new conversations"
def render_model_selector(assigns) do
  ~H"""
  <.select name="model" id="conversation-model">
    <%= for {provider, models} <- @available_models do %>
      <optgroup label={provider_name(provider)}>
        <%= for model <- models do %>
          <option value={model_spec(provider, model)} selected={model == @selected}>
            <%= model_name(model) %>
          </option>
        <% end %>
      </optgroup>
    <% end %>
  </.select>
  """
end
```

## Migration Strategy

### Step 1: Discovery Layer (Non-Breaking)

Add `LLM.Discovery` without changing existing behavior. Existing Anthropic/OpenAI usage continues to work.

### Step 2: Credential Extension (Backward Compatible)

Extend `SecretRefs` to accept any atom provider, keeping `:anthropic` and `:openai` as special cases for existing data.

### Step 3: Data Migration

```elixir
# Migration: Add LLMPreferences resource
defmodule JidoCode.Repo.Migrations.AddLLMPreferences do
  def change do
    create table(:llm_preferences) do
      add :managed_repo_id, :uuid, null: false
      add :enabled_providers, {:array, :text}, default: ["anthropic"]
      add :default_provider, :text, default: "anthropic"
      add :default_model, :text, default: "claude-3-5-sonnet-20250929"
      add :require_capabilities, :map, default: %{}
      timestamps()
    end

    create unique_index(:llm_preferences, [:managed_repo_id])
  end
end
```

### Step 4: Feature Flag

```elixir
config :jido_code, :feature_multi_provider_llm, true
```

### Step 5: Gradual Rollout

1. Enable for development environment first
2. Enable for specific beta users
3. Enable for all users with UI rollout
4. Remove old hardcoded provider paths

## Consequences

### Positive

1. **User Choice**: Users can choose from 18+ providers based on their needs
2. **Future-Proof**: New providers added to req_llm are automatically available
3. **Capability-Based**: Users select based on capabilities (tools, streaming, etc.) not implementation details
4. **Organizational Alignment**: Teams can match providers to compliance/cost requirements

### Negative

1. **Complexity**: More configuration options at multiple levels
2. **Testing Surface**: Need to test against more providers
3. **Support Burden**: Users may encounter provider-specific issues
4. **Credential Management**: More API keys to manage securely

### Mitigations

1. **Sensible Defaults**: Application-level defaults ensure immediate usability
2. **Capability Guidance**: UI guides users to appropriate models for their use case
3. **Provider Documentation**: Link to provider documentation from UI
4. **Error Clarity**: Provider-specific errors are surfaced with actionable messages
5. **Testing Strategy**: Focus testing on the abstraction layer, not each provider

## Related Decisions

- [Factory Control Plane](./jido_code.factory_control_plane.md)
- [Runic Execution Model](./jido_code.runic_execution_model.md)
- [Interruptible Conversation Orchestration](./jido_code.interruptible_conversation_orchestration.md)

## References

- [ReqLLM Documentation](https://hexdocs.pm/req_llm)
- [LLMDB Documentation](https://hexdocs.pm/llm_db)
- [Provider Configuration Spec](../specs/llm_provider_configuration.spec.md)
- [Model Selection UI Spec](../specs/llm_model_selection.spec.md)
