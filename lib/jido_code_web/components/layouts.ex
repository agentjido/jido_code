defmodule JidoCodeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use JidoCodeWeb, :html

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
    ~H"""
    <header class="sticky top-0 z-40 border-b border-base-300/70 bg-base-100/90 backdrop-blur">
      <div class="mx-auto flex w-full max-w-6xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
        <.link navigate={~p"/"} class="text-sm font-bold tracking-[0.12em] uppercase hover:text-primary">
          Jido Code
        </.link>

        <%!-- covers: baseline.surface.nav_trimmed --%>
        <div class="flex items-center gap-3">
          <span class="text-xs font-medium uppercase tracking-[0.2em] text-base-content/45">
            Landing + Auth Only
          </span>
          <.theme_toggle />
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
