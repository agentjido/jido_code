# LLM Model Selection UI

<!-- covers: architecture.llm.multi_provider_support.model_selection_ui -->
<!-- covers: architecture.llm.multi_provider_llm_support.user_interface -->
<!-- covers: package.jido_code.spec_led_workspace -->

Relates to:
- [Multi-Provider LLM Support ADR](../decisions/jido_code.multi_provider_llm_support.md)
- [LLM Provider Configuration Spec](./llm_provider_configuration.spec.md)

## Overview

This spec defines the UI components needed for users to configure and select LLM providers and models at the application, repository, and conversation levels.

## UI Components

### 1. LLM Settings Page (Application Level)

#### Route

```
/settings/llm
```

#### LiveView Module

```elixir
# lib/jido_code_web/live/llm_settings_live.ex
defmodule JidoCode.LLMSettingsLive do
  use JidoCodeWeb, :live_view

  @moduledoc """
  Application-level LLM provider configuration UI.

  Allows administrators to:
  - View all available providers
  - Configure provider credentials (API keys)
  - Set application-wide defaults
  - Test provider connectivity
  """

  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> assign_providers()
      |> assign_credentials()
      |> assign_application_defaults()
    }
  end

  def render(assigns) do
    ~H"""
    <.header>
      <h1>LLM Configuration</h1>
      <p>Configure AI providers for use across your repositories.</p>
    </.header>

    <.section>
      <h2>Available Providers</h2>
      <.provider_list providers={@providers} credentials={@credentials} />
    </.section>

    <.section>
      <h2>Application Defaults</h2>
      <.default_settings_form defaults={@defaults} providers={@providers} />
    </.section>

    <.section>
      <h2>Test Connection</h2>
      <.test_connection_form providers={@providers_with_credentials} />
    </.section>
    """
  end

  defp assign_providers(socket) do
    providers = JidoCode.LLM.Discovery.list_providers()
    assign(socket, :providers, providers)
  end

  defp assign_credentials(socket) do
    # Get stored credentials from SecretRefs
    credentials = JidoCode.SecretRefs.list_provider_credentials()
    assign(socket, :credentials, credentials)
  end
end
```

#### Provider List Component

```elixir
# lib/jido_code_web/components/llm_providers.ex
defmodule JidoCodeWeb.LLMProvidersComponent do
  use Phoenix.Component

  @moduledoc """
  Component for displaying and managing LLM providers.
  """

  attr :providers, :list, required: true
  attr :credentials, :map, required: true

  def provider_list(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <%= for provider <- @providers do %>
        <.provider_card
          provider={provider}
          has_credential={Map.has_key?(@credentials, provider.id)}
          on_credential_change="save_credential"
          on_test="test_provider"
        />
      <% end %>
    </div>
    """
  end

  attr :provider, :map, required: true
  attr :has_credential, :boolean, required: true
  attr :on_credential_change, :string, default: "save_credential"
  attr :on_test, :string, default: "test_provider"

  def provider_card(assigns) do
    ~H"""
    <div class={["border rounded-lg p-4", @has_credential && "border-green-500"]}>
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-lg font-semibold"><%= @provider.name %></h3>
        <.credential_status has_credential={@has_credential} />
      </div>

      <.description provider={@provider} />

      <.credential_form
        provider_id={@provider.id}
        env_key={@provider.env_key}
        has_credential={@has_credential}
        on_change={@on_credential_change}
      />

      <.test_button
        provider_id={@provider.id}
        has_credential={@has_credential}
        on_click={@on_test}
      />
    </div>
    """
  end

  attr :has_credential, :boolean, required: true

  def credential_status(assigns) do
    ~H"""
    <.icon for={@has_credential && "check-circle"} class={[@has_credential && "text-green-500", !@has_credential && "text-gray-400"]} />
    """
  end

  attr :provider, :map, required: true

  def description(assigns) do
    ~H"""
    <%= if @provider.description do %>
      <p class="text-sm text-gray-600 mb-4"><%= @provider.description %></p>
    <% else %>
      <p class="text-sm text-gray-400 mb-4 italic">No description available.</p>
    <% end %>

    <.capability_badges provider={@provider} />
    """
  end

  attr :provider, :map, required: true

  def capability_badges(assigns) do
    # Fetch first model to determine provider capabilities
    models = JidoCode.LLM.Discovery.list_models(@provider.id)
    capabilities = if models != [], do: hd(models).capabilities, else: %{}

    ~H"""
    <div class="flex flex-wrap gap-1">
      <%= if capabilities.chat do %>
        <span class="badge badge-blue">Chat</span>
      <% end %>
      <%= if get_in(capabilities, [:tools, :enabled]) do %>
        <span class="badge badge-purple">Tools</span>
      <% end %>
      <%= if get_in(capabilities, [:streaming, :text]) do %>
        <span class="badge badge-green">Streaming</span>
      <% end %>
    </div>
    """
  end

  attr :provider_id, :atom, required: true
  attr :env_key, :string, default: nil
  attr :has_credential, :boolean, required: true
  attr :on_change, :string, required: true

  def credential_form(assigns) do
    masked_key = if @has_credential, do: "sk-••••••••", else: ""

    ~H"""
    <div class="mt-4 space-y-2">
      <label class="block text-sm font-medium">
        API Key
        <%= if @env_key do %>
          <span class="text-gray-400">(Environment: <%= @env_key %>)</span>
        <% end %>
      </label>

      <.form
        for={:credential}
        phx-submit={@on_change}
        phx-change="validate_credential"
        phx-provider-provider_id={@provider_id}
      >
        <input
          type="password"
          name="api_key"
          value={masked_key}
          placeholder={@env_key || "Enter API key"}
          class="w-full px-3 py-2 border rounded"
          autocomplete="off"
        />

        <.credential_feedback />

        <button
          type="submit"
          class="mt-2 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
        >
          <%= if @has_credential, do: "Update", else: "Save" %>
        </button>
      </.form>
    </div>
    """
  end

  attr :provider_id, :atom, required: true
  attr :has_credential, :boolean, required: true
  attr :on_click, :string, required: true

  def test_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@on_click}
      phx-value-provider_id={@provider_id}
      disabled={!@has_credential}
      class={["mt-2 px-3 py-1 text-sm border rounded",
        !@has_credential && "opacity-50 cursor-not-allowed"
      ]}
    >
      Test Connection
    </button>
    """
  end
end
```

### 2. Repository LLM Preferences (Repository Level)

#### Integration Point

Added to existing `ManagedRepoDetailLive` page:

```elixir
# lib/jido_code_web/live/managed_repo_detail_live.ex
defmodule JidoCodeWeb.ManagedRepoDetailLive do
  # Existing render function
  def render(assigns) do
    ~H"""
    <!-- Existing sections -->

    <.section id="llm-preferences">
      <h2>LLM Configuration</h2>
      <.llm_preferences_form
        repo_id={@managed_repo.id}
        preferences={@llm_preferences}
        available_providers={@all_providers}
      />
    </.section>
    """
  end

  defp assign_llm_preferences(socket) do
    preferences = JidoCode.Control.LLMPreferences
    |> Ash.read(for_managed_repo: %{managed_repo_id: socket.assigns.managed_repo.id})

    prefs = case preferences do
      {:ok, [pref]} -> pref
      _ -> nil
    end

    assign(socket, :llm_preferences, prefs)
  end
end
```

#### LLM Preferences Form Component

```elixir
# lib/jido_code_web/components/llm_preferences_form.ex
defmodule JidoCodeWeb.LLMPreferencesForm do
  use Phoenix.Component

  @moduledoc """
  Form for configuring LLM preferences at the repository level.
  """

  attr :repo_id, :string, required: true
  attr :preferences, :map, required: true
  attr :available_providers, :list, required: true

  def llm_preferences_form(assigns) do
    ~H"""
    <div class="space-y-6">
      <.enabled_providers_section
        repo_id={@repo_id}
        preferences={@preferences}
        available_providers={@available_providers}
      />

      <.default_model_section
        repo_id={@repo_id}
        preferences={@preferences}
      />

      <.capabilities_section
        repo_id={@repo_id}
        preferences={@preferences}
      />

      <.advanced_section
        repo_id={@repo_id}
        preferences={@preferences}
      />
    </div>
    """
  end

  attr :repo_id, :string, required: true
  attr :preferences, :map, required: true
  attr :available_providers, :list, required: true

  def enabled_providers_section(assigns) do
    enabled = get_in(@preferences, [:enabled_providers]) || [:anthropic]

    ~H"""
    <div>
      <h3>Enabled Providers</h3>
      <p class="text-sm text-gray-600 mb-4">
        Select which AI providers can be used for conversations in this repository.
      </p>

      <div class="grid grid-cols-2 md:grid-cols-3 gap-3">
        <%= for provider <- @available_providers do %>
          <.provider_checkbox
            provider={provider}
            enabled={provider.id in enabled}
          />
        <% end %>
      </div>
    </div>
    """
  end

  attr :provider, :map, required: true
  attr :enabled, :boolean, required: true

  def provider_checkbox(assigns) do
    ~H"""
    <label class={["flex items-center p-3 border rounded cursor-pointer hover:bg-gray-50",
      @enabled && "border-blue-500 bg-blue-50"]}>
      <input
        type="checkbox"
        name="enabled_providers[]"
        value={@provider.id}
        checked={@enabled}
        phx-click="toggle_provider"
        phx-value-provider_id={@provider.id}
        class="mr-2"
      />

      <div>
        <div class="font-medium"><%= @provider.name %></div>
        <.provider_badge provider={@provider} />
      </div>
    </label>
    """
  end

  attr :provider, :map, required: true

  def provider_badge(assigns) do
    ~H"""
    <%= if credential_saved?(@provider.id) do %>
      <span class="text-xs text-green-600">✓ Configured</span>
    <% else %>
      <span class="text-xs text-gray-400">Needs API key</span>
    <% end %>
    """
  end

  attr :repo_id, :string, required: true
  attr :preferences, :map, required: true

  def default_model_section(assigns) do
    default_provider = get_in(@preferences, [:default_provider]) || :anthropic
    default_model = get_in(@preferences, [:default_model]) || "claude-3-5-sonnet-20250929"

    ~H"""
    <div>
      <h3>Default Model</h3>
      <p class="text-sm text-gray-600 mb-4">
        The default model will be used for new conversations unless overridden.
      </p>

      <.model_selector
        selected_provider={default_provider}
        selected_model={default_model}
        phx-target={@myself}
        phx-change="model_selected"
      />
    </div>
    """
  end

  attr :repo_id, :string, required: true
  attr :preferences, :map, required: true

  def capabilities_section(assigns) do
    capabilities = get_in(@preferences, [:require_capabilities]) || %{}

    ~H"""
    <div>
      <h3>Required Capabilities</h3>
      <p class="text-sm text-gray-600 mb-4">
        Ensure selected models meet these requirements.
      </p>

      <div class="space-y-2">
        <.capability_checkbox
          capability="tools"
          label="Tool Use"
          description="Model must support function calling"
          checked={get_in(capabilities, [:tools]) == true}
        />

        <.capability_checkbox
          capability="streaming"
          label="Streaming"
          description="Model must support streaming responses"
          checked={get_in(capabilities, [:streaming]) == true}
        />

        <.capability_checkbox
          capability="json_native"
          label="Native JSON"
          description="Model must support structured JSON output"
          checked={get_in(capabilities, [:json_native]) == true}
        />
      </div>
    </div>
    """
  end

  attr :capability, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, required: true
  attr :checked, :boolean, required: true

  def capability_checkbox(assigns) do
    ~H"""
    <label class="flex items-start p-3 border rounded cursor-pointer hover:bg-gray-50">
      <input
        type="checkbox"
        name="capabilities[#{@capability}]"
        checked={@checked}
        phx-click="toggle_capability"
        phx-value-capability={@capability}
        class="mr-3 mt-1"
      />

      <div>
        <div class="font-medium"><%= @label %></div>
        <div class="text-sm text-gray-600"><%= @description %></div>
      </div>
    </label>
    """
  end
end
```

### 3. Model Selector Component

#### Used In

- Repository preferences form
- Conversation composer
- Settings page

```elixir
# lib/jido_code_web/components/model_selector.ex
defmodule JidoCodeWeb.ModelSelector do
  use Phoenix.Component

  @moduledoc """
  Dynamic model selector component with provider grouping and filtering.
  """

  attr :id, :string, default: "model-selector"
  attr :name, :string, default: "model"
  attr :selected_provider, :atom, default: nil
  attr :selected_model, :string, default: nil
  attr :repo_id, :string, default: nil
  attr :capabilities, :list, default: []
  attr :rest, :global

  def model_selector(assigns) do
    models = available_models(assigns.repo_id, assigns.capabilities)

    ~H"""
    <div class={["model-selector", @id]}>
      <.provider_filter
        providers={providers(models)}
        selected={@selected_provider}
      />

      <.model_list
        models={models}
        selected_provider={@selected_provider}
        selected_model={@selected_model}
      />

      <input
        type="hidden"
        name={@name}
        id={@id}
        value={model_value(@selected_provider, @selected_model)}
        phx-hook="ModelSelector"
      />
    </div>
    """
  end

  attr :providers, :list, required: true
  attr :selected, :atom, default: nil

  def provider_filter(assigns) do
    ~H"""
    <div class="flex gap-2 mb-3 overflow-x-auto pb-2">
      <button
        type="button"
        class={"provider-tab", @selected == nil && "active"}
        phx-click="select_provider"
        phx-value-provider="all"
      >
        All Providers
      </button>

      <%= for provider <- @providers do %>
        <button
          type="button"
          class={"provider-tab", @selected == provider.id && "active"}
          phx-click="select_provider"
          phx-value-provider={provider.id}
        >
          <%= provider_name(provider.id) %>
          <span class="count"><%= provider.model_count %></span>
        </button>
      <% end %>
    </div>
    """
  end

  attr :models, :list, required: true
  attr :selected_provider, :atom, default: nil
  attr :selected_model, :string, default: nil

  def model_list(assigns) do
    filtered = filter_by_provider(assigns.models, assigns.selected_provider)

    ~H"""
    <div class="model-list space-y-1 max-h-64 overflow-y-auto">
      <%= for {provider, provider_models} <- group_by_provider(filtered) do %>
        <div class="provider-group">
          <div class="provider-header">
            <%= provider_name(provider) %>
          </div>

          <%= for model <- provider_models do %>
            <.model_option
              provider={provider}
              model={model}
              selected={model_selected?(provider, model.id, @selected_provider, @selected_model)}
            />
          <% end %>
        <% end %>
    </div>
    """
  end

  attr :provider, :atom, required: true
  attr :model, :map, required: true
  attr :selected, :boolean, required: true

  def model_option(assigns) do
    value = model_spec(@provider, @model.id)
    label = model_label(@model)

    ~H"""
    <button
      type="button"
      class={["model-option", @selected && "selected"]}
      data-provider={@provider}
      data-model={@model.id}
      data-value={value}
      phx-click="select_model"
      phx-value-provider={@provider}
      phx-value-model={@model.id}
    >
      <div class="model-info">
        <span class="model-name"><%= label %></span>
        <.model_badges model={@model} />
      </div>

      <div class="model-meta">
        <%= @model.context_length %> tokens
      </div>
    </button>
    """
  end

  attr :model, :map, required: true

  def model_badges(assigns) do
    ~H"""
    <div class="flex gap-1">
      <%= if @model.capabilities.chat do %>
        <span class="badge badge-xs" title="Chat">💬</span>
      <% end %>
      <%= get_in(@model.capabilities, [:tools, :enabled]) do %>
        <span class="badge badge-xs" title="Tool Use">🔧</span>
      <% end %>
      <%= get_in(@model.capabilities, [:streaming, :text]) do %>
        <span class="badge badge-xs" title="Streaming">📡</span>
      <% end %>
      <%= get_in(@model.capabilities, [:json, :native]) do %>
        <span class="badge badge-xs" title="Native JSON">{}</span>
      <% end %>
    </div>
    """
  end
end
```

### 4. Conversation Model Picker

#### Integration Point

Added to conversation composer/chat input:

```elixir
# lib/jido_code_web/live/conversation/composer_live.ex
defmodule JidoCodeWeb.Conversation.ComposerLive do
  def render(assigns) do
    ~H"""
    <div class="conversation-composer">
      <.model_picker
        repo_id={@managed_repo_id}
        work_item_id={@work_item_id}
        selected={@selected_model}
        available_models={@available_models}
        phx-target={@myself}
        phx-change="model_changed"
      />

      <textarea
        id="message-input"
        phx-hook="ConversationComposer"
        class="flex-1"
        placeholder="Type your message..."
      >{@message}</textarea>

      <button type="button" phx-click="send">Send</button>
    </div>
    """
  end
end
```

#### Model Picker Component

```elixir
# lib/jido_code_web/components/model_picker.ex
defmodule JidoCodeWeb.ModelPicker do
  use Phoenix.Component

  @moduledoc """
  Compact model picker for conversation composer.
  Shows current model and allows quick changes.
  """

  attr :repo_id, :string, required: true
  attr :selected, :string, default: nil
  attr :available_models, :list, required: true
  attr :rest, :global

  def model_picker(assigns) do
    current = parse_model_spec(@selected)

    ~H"""
    <div class="model-picker" phx-click="open_model_selector" phx-hook="ModelPicker">
      <div class="current-model">
        <.model_icon model={current} />
        <span class="model-name"><%= model_name(current) %></span>
        <.dropdown_icon />
      </div>

      <.model_popover models={@available_models} selected={current} />
    </div>
    """
  end

  attr :model, :map, required: true

  def model_icon(assigns) do
    ~H"""
    <div class="provider-icon provider-#{@model.provider}">
      <%= case @model.provider do %>
        <% :anthropic -> %>🤖<% # Anthropic icon %>
        <% :openai -> %>🧠<% # OpenAI icon %>
        <% :google -> %>✨<% # Google icon %>
        <% _ -> %>🔮<% # Default icon %>
      <% end %>
    </div>
    """
  end
end
```

## Error Handling

### Validation Errors

```elixir
# Error messages for model selection
defmodule JidoCodeWeb.LLMModelErrors do
  @moduledoc """
  Error messages and rendering for LLM model selection.
  """

  def error_message(:provider_not_enabled) do
    """
    This provider is not enabled for this repository.

    Please either:
    - Enable it in repository settings, or
    - Choose a different provider
    """
  end

  def error_message(:model_not_found) do
    """
    The selected model was not found.

    Please refresh the available models and try again.
    """
  end

  def error_message(:missing_capability, capability) do
    """
    This model does not support the required capability: #{capability}

    Please select a model that supports this capability.
    """
  end

  def error_message(:credential_missing, provider) do
    """
    No API key found for #{provider_name(provider)}.

    Please add your API key in Settings > LLM Configuration.
    """
  end
end
```

### Connection Test Feedback

```elixir
# lib/jido_code_web/live/llm_settings_live.ex
def handle_event("test_provider", %{"provider_id" => provider_id}, socket) do
  send(self(), {:test_provider, provider_id})
  {:noreply, assign(socket, :testing_provider, provider_id)}
end

def handle_info({:test_provider, provider_id}, socket) do
  case JidoCode.LLM.test_connection(provider_id) do
    {:ok, response} ->
      {:noreply,
       socket
       |> put_flash(:info, "Connection to #{provider_id} successful!")
       |> assign(testing_provider: nil, test_result: {:ok, response})}

    {:error, reason} ->
      {:noreply,
       socket
       |> put_flash(:error, "Connection failed: #{format_error(reason)}")
       |> assign(testing_provider: nil, test_result: {:error, reason})}
  end
end
```

## CSS Styling

```scss
// assets/css/llm_selector.scss
.model-selector {
  @apply relative;

  .provider-tab {
    @apply px-4 py-2 rounded-lg border transition-colors;

    &.active {
      @apply bg-blue-100 border-blue-500;
    }

    .count {
      @apply ml-2 text-xs text-gray-500;
    }
  }

  .model-option {
    @apply w-full flex items-center justify-between p-3 rounded-lg border transition-colors;

    &:hover {
      @apply bg-gray-50;
    }

    &.selected {
      @apply bg-blue-50 border-blue-500;
    }

    .model-info {
      @apply flex items-center gap-2;
    }
  }

  .badge {
    @apply px-2 py-0.5 rounded text-xs;

    &.badge-blue { @apply bg-blue-100 text-blue-700; }
    &.badge-purple { @apply bg-purple-100 text-purple-700; }
    &.badge-green { @apply bg-green-100 text-green-700; }
  }
}

.model-picker {
  @apply relative inline-flex items-center gap-2 px-3 py-2 border rounded-lg cursor-pointer;

  .current-model {
    @apply flex items-center gap-2;
  }

  .provider-icon {
    @apply w-6 h-6 flex items-center justify-center rounded-full;
  }
}
```

## Testing Coverage

```elixir
# test/jido_code_web/live/llm_settings_live_test.exs
defmodule JidoCodeWeb.LLMSettingsLiveTest do
  use JidoCodeWeb.ConnCase

  test "lists all available providers" do
    {:ok, view, _html} = live(conn, ~p"/settings/llm")

    assert has_element?(view, "[data-provider-id=anthropic]")
    assert has_element?(view, "[data-provider-id=openai]")
  end

  test "allows saving API key for provider" do
    {:ok, view, _html} = live(conn, ~p"/settings/llm")

    view
    |> form("[data-provider-id=anthropic]", api_key: "sk-test-key")
    |> render_submit("save_credential")

    assert_patched(JidoCode.SecretRefs, :put_credential, [:anthropic_api_key, "sk-test-key"])
  end
end

# test/jido_code_web/components/model_selector_test.exs
defmodule JidoCodeWeb.ModelSelectorTest do
  use JidoCodeWeb.ComponentCase

  test "filters models by provider" do
    models = [
      %{provider: :anthropic, id: "claude-3-5-sonnet"},
      %{provider: :openai, id: "gpt-4o-mini"}
    ]

    html = render_component(&ModelSelector.model_selector/1,
      models: models,
      selected_provider: :anthropic
    )

    assert html =~ "claude-3-5-sonnet"
    refute html =~ "gpt-4o-mini"
  end
end
```

## Open Questions

1. **Should we show pricing information** in the model selector?
   - Recommendation: Yes, as an optional field

2. **How should we handle model versions** (e.g., `claude-3-5-sonnet-20250929`)?
   - Recommendation: Show friendly name, store full ID

3. **Should users be able to favorite models** for quick access?
   - Recommendation: Yes, store as user preferences

4. **How to handle deprecated models** from LLMDB?
   - Recommendation: Show warning, allow but discourage selection
