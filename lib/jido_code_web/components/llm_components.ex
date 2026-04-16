defmodule JidoCodeWeb.LLMComponents do
  @moduledoc """
  LLM-related UI components for provider and model selection.

  Provides components for:
  - Provider cards with credential status
  - Model selector with provider filtering
  - Model picker for conversation composer
  - Error messages for LLM operations
  """
  use Phoenix.Component
  use Gettext, backend: JidoCodeWeb.Gettext

  alias Phoenix.LiveView.JS
  alias JidoCode.LLM.Discovery

  @doc """
  Renders a provider card with credential status and actions.

  ## Attributes

  - `provider`: Atom provider identifier
  - `name`: Human-readable provider name
  - `description`: Optional provider description
  - `env_key`: Environment variable key for API credentials
  - `configured`: Boolean indicating if credentials are configured
  - `rest`: Global HTML attributes

  ## Examples

      <.provider_card
        provider={:anthropic}
        name="Anthropic"
        env_key="ANTHROPIC_API_KEY"
        configured={true}
      />
  """
  attr :id, :string, required: true
  attr :provider, :atom, required: true
  attr :name, :string, required: true
  attr :description, :string, default: nil
  attr :env_key, :string, required: true
  attr :configured, :boolean, default: false
  attr :rest, :global

  slot :actions

  def provider_card(assigns) do
    ~H"""
    <div id={@id} class="card bg-base-100 shadow-sm border border-base-300">
      <div class="card-body p-4">
        <div class="flex items-start justify-between">
          <div class="flex-1">
            <h3 class="card-title text-lg font-semibold flex items-center gap-2">
              <span>{@name}</span>
              <.credential_status configured={@configured} />
            </h3>
            {if @description do
              ~H'''
              <p class="text-sm text-base-content/70 mt-1">{@description}</p>
              '''
            end}
            <p class="text-xs text-base-content/50 mt-1">
              Environment: <code class="text-xs bg-base-200 px-1 py-0.5 rounded">{@env_key}</code>
            </p>
          </div>
          <div class="flex gap-2">
            {render_slot(@actions)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a credential status indicator.

  ## Attributes

  - `configured`: Boolean indicating if credentials are configured

  """
  attr :configured, :boolean, required: true

  def credential_status(assigns) do
    ~H"""
    {if @configured do
      ~H'<span class="badge badge-success badge-sm">Configured</span>'
    else
      ~H'<span class="badge badge-ghost badge-sm">Not configured</span>'
    end}
    """
  end

  @doc """
  Renders a model selector component with provider tabs and model list.

  ## Attributes

  - `id`: Unique identifier for the selector
  - `name`: Form field name
  - `selected_provider`: Currently selected provider atom
  - `selected_model`: Currently selected model ID
  - `repo_id`: Optional repository ID for filtering
  - `required_capabilities`: Optional map of required capabilities
  - `rest`: Global HTML attributes

  ## Examples

      <.model_selector
        id="llm-selector"
        name="conversation[llm_model]"
        selected_provider={:anthropic}
        selected_model="claude-3-5-sonnet-20250929"
        required_capabilities=%{tools: true}
      />
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :selected_provider, :atom, default: nil
  attr :selected_model, :string, default: nil
  attr :repo_id, :string, default: nil
  attr :required_capabilities, :map, default: nil
  attr :rest, :global

  def model_selector(assigns) do
    ~H"""
    <div id={@id} class="model-selector" phx-hook="ModelSelector">
      <input type="hidden" name={@name} id={"#{@id}-input"} value={@selected_model} />
      <input
        type="hidden"
        name={"#{@name}_provider"}
        id={"#{@id}-provider-input"}
        value={@selected_provider && Atom.to_string(@selected_provider)}
      />

      <div class="tabs tabs-boxed mb-3" id={"#{@id}-provider-tabs"}>
        <button
          class={"tab #{if @selected_provider == nil, do: "tab-active", else: ""}"}
          phx-click="select_provider"
          phx-value-provider=""
          phx-target={@myself}
        >
          All Providers
        </button>
        <!-- Provider tabs will be dynamically rendered here -->
      </div>

      <div class="space-y-2 max-h-64 overflow-y-auto" id={"#{@id}-model-list"}>
        <!-- Models will be dynamically rendered here -->
      </div>
    </div>
    """
  end

  @doc """
  Renders a compact model picker for the conversation composer.

  ## Attributes

  - `id`: Component ID
  - `selected`: Currently selected model ID
  - `available_models`: List of available model maps
  - `rest`: Global HTML attributes

  ## Examples

      <.model_picker
        id="model-picker"
        selected={@llm_model}
        available_models={@available_models}
      />
  """
  attr :id, :string, required: true
  attr :selected, :string, default: nil
  attr :available_models, :list, default: []
  attr :rest, :global

  def model_picker(assigns) do
    grouped =
      assigns.available_models
      |> Enum.group_by(& &1.provider)
      |> Enum.sort_by(fn {provider, _} -> Discovery.provider_name(provider) end)

    # Flatten grouped models for easier iteration in HEEx
    flat_models =
      Enum.flat_map(grouped, fn {provider, models} ->
        Enum.map(models, fn model ->
          {provider, model}
        end)
      end)

    assigns = assign(assigns, :flat_models, flat_models)

    ~H"""
    <div class="dropdown dropdown-end" id={@id} phx-hook="ModelPicker">
      <label tabindex="0" class="btn btn-sm gap-2">
        <.icon name="hero-sparkles" class="w-4 h-4" />
        <span class="hidden sm:inline">
          {model_display_name(@selected, @available_models)}
        </span>
        <.icon name="hero-chevron-down" class="w-4 h-4" />
      </label>

      <div
        tabindex="0"
        class="dropdown-content z-[100] menu p-2 shadow-lg bg-base-100 rounded-box w-80 max-h-96 overflow-y-auto"
      >
        <div class="menu-title px-2 py-1">Select Model</div>
        <.render_model_menu models={@flat_models} selected={@selected} />
      </div>
    </div>
    """
  end

  attr :models, :list, required: true
  attr :selected, :string, default: nil

  defp render_model_menu(assigns) do
    # Group and sort models by provider before rendering
    grouped =
      assigns.models
      |> Enum.group_by(fn {p, _m} -> p end, fn {_p, m} -> m end)
      |> Enum.sort_by(fn {p, _ms} -> Discovery.provider_name(p) end)

    assigns = assign(assigns, :flat_with_header, build_header_list(grouped))

    ~H"""
    <div class="menu">
      <div :for={item <- @flat_with_header}>
        <div :if={item.type == :header} class="px-2 py-1 text-sm font-semibold text-base-content/70">
          {item.name}
        </div>
        <.model_picker_item
          :if={item.type == :item}
          model={item.model}
          selected={@selected}
          provider={item.provider}
        />
      </div>
    </div>
    """
  end

  # Build a flat list with header markers for rendering
  defp build_header_list(grouped) do
    Enum.flat_map(grouped, fn {provider, models} ->
      provider_name = Discovery.provider_name(provider)
      [%{type: :header, name: provider_name}] ++
        Enum.map(models, fn model -> %{type: :item, provider: provider, model: model} end)
    end)
  end

  attr :model, :map, required: true
  attr :selected, :string, default: nil
  attr :provider, :atom, required: true

  defp model_picker_item(assigns) do
    is_selected = assigns.selected == assigns.model.model
    provider_str = Atom.to_string(assigns.provider)
    selected_class = if is_selected, do: "active bg-base-300", else: ""

    assigns =
      assigns
      |> assign(:provider_str, provider_str)
      |> assign(:selected_class, selected_class)
      |> assign(:is_selected, is_selected)

    ~H"""
    <button
      class={"menu-item w-full text-left px-2 py-1.5 rounded hover:bg-base-200 #{@selected_class}"}
      phx-click="select_model"
      phx-value-model={@model.model}
      phx-value-provider={@provider_str}
      type="button"
    >
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm">{model_label(@model)}</span>
        <.model_badges model={@model} />
      </div>
    </button>
    """
  end

  @doc """
  Renders capability badges for a model.

  ## Attributes

  - `model`: Model map with llmdb_model containing capabilities

  """
  attr :model, :map, required: true

  def model_badges(assigns) do
    ~H"""
    <div class="flex gap-1">
      {capability_badge(@model.llmdb_model, :chat, "Chat")}
      {capability_badge(@model.llmdb_model, :tools, "Tools")}
      {capability_badge(@model.llmdb_model, :streaming, "Streaming")}
      {capability_badge(@model.llmdb_model, :vision, "Vision")}
    </div>
    """
  end

  defp capability_badge(nil, _capability, _label), do: nil

  defp capability_badge(model, capability, label) do
    caps = model.capabilities || %{}
    value = Map.get(caps, capability)

    if value == true do
      assigns = %{label: label}

      ~H"""
      <span class="badge badge-ghost badge-xs">{@label}</span>
      """
    else
      nil
    end
  end

  @doc """
  Renders an error message for LLM-related failures.

  ## Attributes

  - `error`: Error atom or tuple
  - `rest`: Global HTML attributes

  ## Examples

      <.llm_error error={:provider_not_enabled} />
      <.llm_error error={{:missing_capability, :tools}} />

  """
  attr :error, :any, required: true
  attr :rest, :global

  def llm_error(assigns) do
    ~H"""
    <div class="alert alert-warning" role="alert">
      <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
      <div>
        <h4 class="font-bold">LLM Configuration Error</h4>
        <span class="text-sm">{error_message(@error)}</span>
      </div>
    </div>
    """
  end

  defp error_message(:provider_not_enabled),
    do: "The selected provider is not enabled for this repository."

  defp error_message(:model_not_found),
    do: "The selected model was not found for the specified provider."

  defp error_message({:missing_capability, capability}),
    do: "The selected model does not support the required capability: #{capability}."

  defp error_message({:credential_missing, provider}),
    do: "API credentials for #{provider} are not configured. Please add them in Settings."

  defp error_message(_),
    do: "An error occurred with the LLM configuration."

  defp model_label(%{model: model_id, llmdb_model: %{name: name}}) when is_binary(name),
    do: name

  defp model_label(%{model: model_id}), do: model_id
  defp model_label(model_id) when is_binary(model_id), do: model_id

  defp model_display_name(nil, _available_models), do: "Select Model"

  defp model_display_name(selected_id, available_models) do
    Enum.find_value(available_models, fn
      %{model: ^selected_id, llmdb_model: %{name: name}} when is_binary(name) -> name
      %{model: ^selected_id} -> selected_id
      _ -> nil
    end) || "Select Model"
  end

  @doc """
  Icon helper for LLM provider icons.

  """
  attr :name, :string, required: true
  attr :class, :string, default: "w-5 h-5"

  def icon(assigns) do
    ~H"""
    <svg class={@class} fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d={icon_path(@name)} />
    </svg>
    """
  end

  defp icon_path("hero-sparkles"),
    do: "M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707"

  defp icon_path("hero-chevron-down"), do: "M19 9l-7 7-7-7"

  defp icon_path("hero-exclamation-triangle"),
    do: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"

  defp icon_path(_),
    do: "M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"
end
