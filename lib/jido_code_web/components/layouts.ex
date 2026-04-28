defmodule JidoCodeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use JidoCodeWeb, :html

  alias JidoCodeWeb.OperatorNavigation

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

  slot(:inner_block, required: true)

  def app(assigns) do
    assigns = assign(assigns, :operator_navigation, OperatorNavigation.from_socket(assigns[:socket]))

    ~H"""
    <header class="sticky top-0 z-40 border-b border-base-300/70 bg-base-100/90 backdrop-blur">
      <div class="mx-auto w-full max-w-6xl px-4 py-3 sm:px-6 lg:px-8">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="space-y-2">
            <div class="flex flex-wrap items-center gap-3">
              <.link
                navigate={~p"/"}
                class="text-sm font-bold tracking-[0.12em] uppercase hover:text-primary"
              >
                Jido Code
              </.link>

              <div
                :if={@operator_navigation}
                id="operator-route-identity"
                class="flex flex-wrap items-center gap-2 text-xs"
              >
                <span
                  id="operator-route-badge"
                  class="rounded-full border border-base-300/80 bg-base-200/70 px-2.5 py-1 font-semibold uppercase tracking-[0.16em] text-base-content/70"
                >
                  {@operator_navigation.route_badge}
                </span>
                <span id="operator-route-label" class="font-medium text-base-content/70">
                  {@operator_navigation.route_label}
                </span>
              </div>
            </div>

            <%!-- covers: baseline.surface.nav_trimmed --%>
            <p
              :if={!@operator_navigation}
              class="text-xs font-medium uppercase tracking-[0.2em] text-base-content/45"
            >
              Landing + Auth Only
            </p>
          </div>

          <div class="flex items-center gap-3">
            <.theme_toggle />
          </div>
        </div>

        <div :if={@operator_navigation} class="mt-4 space-y-3">
          <.operator_navigation navigation={@operator_navigation} />
        </div>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8 bg-background">
      <div class="mx-auto max-w-6xl space-y-4">
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

  attr(:navigation, :map, required: true)

  defp operator_navigation(assigns) do
    ~H"""
    <nav
      id={@navigation.id}
      aria-label={@navigation.label}
      class="rounded-2xl border border-base-300/80 bg-base-200/45 p-2"
    >
      <div class="flex flex-wrap gap-2">
        <.link
          :for={destination <- @navigation.major_destinations}
          id={destination.dom_id}
          navigate={destination.navigate}
          aria-current={if destination.selected?, do: "page", else: nil}
          class={[
            "group min-w-[10rem] flex-1 rounded-xl border px-3 py-2 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            destination.selected? &&
              "border-primary/60 bg-primary text-primary-content shadow-sm",
            !destination.selected? &&
              "border-base-300/70 bg-base-100/90 text-base-content hover:border-primary/40 hover:bg-base-100"
          ]}
        >
          <span class="block text-sm font-semibold">{destination.label}</span>
          <span class={[
            "mt-1 block text-xs",
            destination.selected? && "text-primary-content/80",
            !destination.selected? && "text-base-content/65 group-hover:text-base-content/80"
          ]}>
            {destination.summary}
          </span>
        </.link>
      </div>

      <div
        :if={@navigation.context_links != []}
        id="operator-context-nav"
        class="mt-3 flex flex-wrap items-center gap-2 border-t border-base-300/70 pt-3"
      >
        <span class="text-[0.68rem] font-semibold uppercase tracking-[0.18em] text-base-content/50">
          Current Context
        </span>

        <%= for context_link <- @navigation.context_links do %>
          <%= if context_link[:navigate] do %>
            <.link
              id={context_link.id}
              navigate={context_link.navigate}
              class="rounded-full border border-base-300 bg-base-100 px-3 py-1 text-xs font-medium text-base-content/75 transition-colors hover:border-primary/40 hover:text-base-content"
            >
              {context_link.label}
            </.link>
          <% else %>
            <span
              id={context_link.id}
              aria-current={if context_link[:current?], do: "page", else: nil}
              class={[
                "rounded-full border px-3 py-1 text-xs font-medium",
                context_link[:current?] &&
                  "border-primary/50 bg-primary/10 text-base-content",
                !context_link[:current?] &&
                  "border-base-300 bg-base-100 text-base-content/75"
              ]}
            >
              {context_link.label}
            </span>
          <% end %>
        <% end %>
      </div>
    </nav>
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
    <div class="relative flex items-center rounded-md border border-base-300 bg-base-200/70 p-1">
      <div class="absolute left-1 top-1 h-[calc(100%-0.5rem)] w-1/3 rounded-sm border border-base-300 bg-base-100 transition-[left] duration-300 [[data-theme-mode=light]_&]:left-1/3 [[data-theme-mode=dark]_&]:left-2/3" />

      <button
        class="relative z-10 flex w-9 items-center justify-center rounded-sm p-1 text-base-content/70 hover:text-base-content"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        class="relative z-10 flex w-9 items-center justify-center rounded-sm p-1 text-base-content/70 hover:text-base-content"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        class="relative z-10 flex w-9 items-center justify-center rounded-sm p-1 text-base-content/70 hover:text-base-content"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
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
end
