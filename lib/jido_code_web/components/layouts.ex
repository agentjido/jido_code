defmodule JidoCodeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use JidoCodeWeb, :html

  alias JidoCodeWeb.Areas

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates("layouts/*")

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  attr(:current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"
  )

  attr(:active_area, :atom,
    default: nil,
    doc: "active product area for the authenticated shell"
  )

  attr(:area_state, :map,
    default: nil,
    doc: "server-authored active area shell state"
  )

  attr(:title, :string,
    default: nil,
    doc: "optional shell title override"
  )

  attr(:subtitle, :string,
    default: nil,
    doc: "optional shell subtitle override"
  )

  attr(:area_panel, :map,
    default: nil,
    doc: "optional root-area overview panel rendered before route content"
  )

  slot(:actions)
  slot(:inner_block, required: true)

  def app(assigns) do
    assigns = assign_area_shell(assigns)

    ~H"""
    <header
      id="operator-app-shell"
      data-active-area={if @area_state, do: @area_state.id}
      class="sticky top-0 z-40 border-b border-border bg-background/95 backdrop-blur"
    >
      <div class="mx-auto flex w-full max-w-7xl flex-col gap-3 px-4 py-3 sm:px-6 lg:px-8">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="min-w-0 space-y-1">
            <.link
              id="operator-shell-brand"
              navigate={~p"/"}
              class="inline-flex items-center gap-2 text-sm font-semibold text-foreground hover:text-primary"
            >
              <span class="inline-flex size-2 rounded-sm bg-primary" />
              <span>Jido Code</span>
            </.link>

            <div id="operator-shell-heading" class="min-w-0">
              <p id="operator-shell-title" class="truncate text-lg font-semibold text-foreground">
                {@shell_title}
              </p>
              <p id="operator-shell-subtitle" class="truncate text-sm text-muted-foreground">
                {@shell_subtitle}
              </p>
            </div>
          </div>

          <div class="flex flex-wrap items-center justify-end gap-2">
            <div :if={@actions != []} id="operator-shell-actions" class="flex flex-wrap items-center gap-2">
              {render_slot(@actions)}
            </div>
            <.theme_toggle />
          </div>
        </div>

        <.area_button_menu :if={@area_state} items={@area_navigation_items} active_area={@active_area} />
        <.area_status_strip :if={@area_state} area_state={@area_state} current_scope={@current_scope} />
      </div>
    </header>

    <main id="operator-shell-content" class="bg-background px-4 py-6 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-7xl space-y-4">
        <.area_overview_panel :if={@area_panel} panel={@area_panel} />
        {render_slot(@inner_block)}
      </div>
    </main>

    <.live_toast_group
      flash={@flash}
      connected={assigns[:socket] != nil}
      corner={:top_right}
      toasts_sync={assigns[:toasts_sync] || []}
    />
    """
  end

  attr(:items, :list, required: true)
  attr(:active_area, :atom, required: true)

  defp area_button_menu(assigns) do
    ~H"""
    <nav
      id="operator-area-menu"
      aria-label="Product areas"
      class="overflow-x-auto rounded-lg border border-border bg-card p-1"
    >
      <div class="flex min-w-max flex-nowrap gap-1 sm:min-w-0 sm:flex-wrap">
        <.link
          :for={item <- @items}
          id={"operator-area-menu-#{item.id}"}
          navigate={item.path}
          aria-current={if item.area == @active_area, do: "page", else: nil}
          class={[
            "inline-flex min-h-10 items-center justify-center rounded-md border px-3 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring",
            item.area == @active_area &&
              "border-primary bg-primary text-primary-foreground shadow-sm",
            item.area != @active_area &&
              "border-transparent text-muted-foreground hover:border-border hover:bg-muted hover:text-foreground"
          ]}
        >
          {item.label}
        </.link>
      </div>
    </nav>
    """
  end

  attr(:area_state, :map, required: true)
  attr(:current_scope, :map, default: nil)

  defp area_status_strip(assigns) do
    ~H"""
    <div
      id="operator-status-strip"
      class="flex flex-wrap items-center gap-2 text-xs text-muted-foreground"
    >
      <span id="operator-status-area" class="ui-badge ui-badge-outline">
        Area: {@area_state.label}
      </span>
      <span id="operator-status-auth" class="ui-badge ui-badge-outline">
        Operator: {scope_label(@current_scope)}
      </span>
      <span id="operator-status-connection" class="ui-badge ui-badge-outline">
        Connection: {status_label(@area_state.connection_status)}
      </span>
      <span id="operator-status-runtime" class="ui-badge ui-badge-outline">
        Runtime: {status_label(@area_state.runtime_status)}
      </span>
      <span
        :for={{warning, index} <- Enum.with_index(@area_state.warnings)}
        id={"operator-status-warning-#{index}"}
        class="ui-badge ui-badge-warning"
      >
        {warning}
      </span>
    </div>
    """
  end

  attr(:panel, :map, required: true)

  defp area_overview_panel(assigns) do
    ~H"""
    <section id={"area-overview-panel-#{@panel.id}"} data-area={@panel.id} class="space-y-4">
      <UI.card class="rounded-lg shadow-none">
        <UI.card_header class="gap-3">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0 space-y-2">
              <UI.badge variant="outline">{@panel.posture}</UI.badge>
              <UI.card_title class="text-xl tracking-normal">{@panel.title}</UI.card_title>
              <UI.card_description class="max-w-3xl">{@panel.summary}</UI.card_description>
            </div>
            <.link
              id={@panel.primary_action.id}
              navigate={@panel.primary_action.path}
              class="inline-flex min-h-10 items-center justify-center rounded-md border border-border bg-background px-4 text-sm font-medium text-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
            >
              {@panel.primary_action.label}
            </.link>
          </div>
        </UI.card_header>

        <UI.card_content class="space-y-4">
          <div id={"area-overview-metrics-#{@panel.id}"} class="grid gap-3 md:grid-cols-3">
            <div
              :for={metric <- @panel.metrics}
              id={"area-overview-metric-#{@panel.id}-#{metric.id}"}
              class="rounded-lg border border-border bg-muted/30 p-3"
            >
              <p class="text-xs font-medium text-muted-foreground">{metric.label}</p>
              <p class="mt-1 text-base font-semibold text-foreground">{metric.value}</p>
              <p class="mt-1 text-xs leading-5 text-muted-foreground">{metric.detail}</p>
            </div>
          </div>

          <UI.separator />

          <div id={"area-overview-sections-#{@panel.id}"} class="grid gap-3 lg:grid-cols-2">
            <div
              :for={section <- @panel.sections}
              id={"area-overview-section-#{@panel.id}-#{section.id}"}
              class="rounded-lg border border-border bg-card p-4"
            >
              <h3 class="text-sm font-semibold text-foreground">{section.title}</h3>
              <p class="mt-2 text-sm leading-6 text-muted-foreground">{section.body}</p>
            </div>
          </div>
        </UI.card_content>

        <UI.card_footer class="flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
          <p class="text-sm text-muted-foreground">Area handoffs</p>
          <div id={"area-overview-handoffs-#{@panel.id}"} class="flex flex-wrap gap-2">
            <.link
              :for={handoff <- @panel.handoffs}
              id={"area-overview-handoff-#{handoff.id}"}
              navigate={handoff.path}
              class="inline-flex min-h-8 items-center rounded-md border border-border px-3 text-xs font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            >
              {handoff.label}
            </.link>
          </div>
        </UI.card_footer>
      </UI.card>
    </section>
    """
  end

  @doc """
  Renders a minimal onboarding layout with no navigation.

  Used for welcome/registration flows where a clean, centered
  experience is preferred.

  ## Examples

      <Layouts.onboarding flash={@flash}>
        <h1>Welcome!</h1>
      </Layouts.onboarding>

  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  slot(:inner_block, required: true)

  def onboarding(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-base-200 via-base-100 to-base-200 flex flex-col items-center justify-center px-4">
      <div class="mb-8 text-center">
        <h1 class="text-2xl font-bold tracking-[0.12em] uppercase opacity-80">Jido Code</h1>
      </div>

      <div class="w-full max-w-lg">
        {render_slot(@inner_block)}
      </div>
    </div>

    <.live_toast_group
      flash={@flash}
      connected={assigns[:socket] != nil}
      corner={:top_right}
      toasts_sync={assigns[:toasts_sync] || []}
    />
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex items-center rounded-md border border-border bg-muted p-1">
      <div class="absolute left-1 top-1 h-[calc(100%-0.5rem)] w-1/3 rounded-sm border border-border bg-background transition-[left] duration-300 [[data-theme-mode=light]_&]:left-1/3 [[data-theme-mode=dark]_&]:left-2/3" />

      <button
        class="relative z-10 flex w-9 items-center justify-center rounded-sm p-1 text-muted-foreground hover:text-foreground"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Use system theme"
        title="Use system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        class="relative z-10 flex w-9 items-center justify-center rounded-sm p-1 text-muted-foreground hover:text-foreground"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Use light theme"
        title="Use light theme"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        class="relative z-10 flex w-9 items-center justify-center rounded-sm p-1 text-muted-foreground hover:text-foreground"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Use dark theme"
        title="Use dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end

  @doc """
  Wrapper component for LiveToast.toast_group that loads the module dynamically.
  """
  attr(:flash, :map, required: true)
  attr(:connected, :boolean, required: true)
  attr(:corner, :atom, default: :bottom_right)
  attr(:toasts_sync, :list, default: [])

  def live_toast_group(assigns) do
    # Dynamically render LiveToast component
    ~H"""
    <div
      id="toast-group-container"
      class="fixed z-50 max-h-screen w-full p-4 md:max-w-[420px] pointer-events-none grid origin-center top-0 right-0 items-start flex-col sm:bottom-auto"
    >
      <.live_component
        :if={@connected}
        module={LiveToast.LiveComponent}
        id="toast-group"
        toasts_sync={@toasts_sync}
        corner={@corner}
        f={@flash}
        kinds={[:info, :error]}
        toast_class_fn={&JidoCodeWeb.Layouts.toast_class_fn/1}
      />
      <div :if={!@connected} id="toast-group-disconnected">
        <div
          :for={{kind, msg} <- @flash}
          class={[
            "group/toast z-100 pointer-events-auto relative w-full items-center justify-between origin-center overflow-hidden rounded-lg p-4 shadow-lg border col-start-1 col-end-1 row-start-1 row-end-2 flex",
            kind == :info && "bg-white text-black",
            kind == :error && "bg-error text-error-content border-error"
          ]}
        >
          <p class="text-sm">{msg}</p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Custom toast class function with improved color contrast for error toasts.
  """
  def toast_class_fn(assigns) do
    [
      # base classes
      "group/toast z-100 pointer-events-auto relative w-full items-center justify-between origin-center overflow-hidden rounded-lg p-4 shadow-lg border col-start-1 col-end-1 row-start-1 row-end-2",
      # start hidden if javascript is enabled
      "[@media(scripting:enabled)]:opacity-0 [@media(scripting:enabled){[data-phx-main]_&}]:opacity-100",
      # used to hide the disconnected flashes
      if(assigns[:rest][:hidden] == true, do: "hidden", else: "flex"),
      # override styles per severity
      assigns[:kind] == :info && "bg-white text-black",
      assigns[:kind] == :error && "bg-error text-error-content border-error"
    ]
  end

  defp assign_area_shell(assigns) do
    active_area = Map.get(assigns, :active_area) || active_area_from_state(Map.get(assigns, :area_state))
    area_state = area_state(Map.get(assigns, :area_state), active_area, Map.get(assigns, :current_scope))

    assigns
    |> assign(:active_area, active_area)
    |> assign(:area_state, area_state)
    |> assign(:area_navigation_items, Areas.navigation_items())
    |> assign(:shell_title, Map.get(assigns, :title) || shell_title(area_state))
    |> assign(:shell_subtitle, Map.get(assigns, :subtitle) || shell_subtitle(area_state))
  end

  defp active_area_from_state(%{active_area: active_area}) when is_atom(active_area), do: active_area
  defp active_area_from_state(_state), do: nil

  defp area_state(%{} = area_state, _active_area, _current_scope), do: area_state

  defp area_state(_area_state, active_area, current_scope) when is_atom(active_area) do
    Areas.shell_state(active_area, current_scope: current_scope, connection_status: :connected)
  end

  defp area_state(_area_state, _active_area, _current_scope), do: nil

  defp shell_title(%{label: label}) when is_binary(label), do: label
  defp shell_title(_area_state), do: "Jido Code"

  defp shell_subtitle(%{summary: summary}) when is_binary(summary), do: summary
  defp shell_subtitle(_area_state), do: "Public bootstrap and setup"

  defp status_label(status) when is_atom(status), do: status |> Atom.to_string() |> String.replace("_", " ")
  defp status_label(status) when is_binary(status), do: String.replace(status, "_", " ")
  defp status_label(status), do: to_string(status)

  defp scope_label(%{user_email: email}) when is_binary(email), do: email
  defp scope_label(%{email: email}) when is_binary(email), do: email
  defp scope_label(%{user_id: user_id}) when is_binary(user_id), do: user_id
  defp scope_label(_current_scope), do: "Session"
end
