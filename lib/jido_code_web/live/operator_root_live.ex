defmodule JidoCodeWeb.OperatorRootLive do
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.root_area_shell_owns_navigation
  @moduledoc false

  use JidoCodeWeb, :live_view

  alias JidoCodeWeb.Areas

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :navigation_items, Areas.navigation_items())}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    area = Areas.area_for_live_action!(socket.assigns.live_action)

    shell_state =
      Areas.shell_state(area.area,
        current_scope: current_scope(socket.assigns),
        connection_status: :connected,
        runtime_status: :ready
      )

    {:noreply,
     socket
     |> assign(:active_area, area.area)
     |> assign(:area, area)
     |> assign(:shell_state, shell_state)
     |> assign(:area_panel, JidoCodeWeb.AreaPanels.panel_for(area.area))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@shell_state.current_scope}
      active_area={@active_area}
      area_state={@shell_state}
      area_panel={@area_panel}
    >
      <section
        id="operator-root-shell"
        data-active-area={@area.id}
        data-route-owner="operator-root-live"
        class="space-y-4"
      >
        <div
          id={"operator-root-#{@area.id}"}
          class="rounded-lg border border-border bg-card p-5"
        >
          <p
            id="operator-root-route-label"
            class="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground"
          >
            {@area.label}
          </p>
          <h1 id="operator-root-title" class="mt-2 text-2xl font-semibold text-foreground">
            {@area.label}
          </h1>
          <p id="operator-root-summary" class="mt-2 max-w-3xl text-sm text-muted-foreground">
            {@area.summary}
          </p>
        </div>

        <nav
          id="operator-root-route-map"
          aria-label="Product area route map"
          class="grid gap-2 sm:grid-cols-2 xl:grid-cols-3"
        >
          <.link
            :for={item <- @navigation_items}
            id={"operator-root-route-#{item.id}"}
            navigate={item.path}
            aria-current={if item.area == @active_area, do: "page", else: nil}
            class={[
              "min-w-0 rounded-lg border px-3 py-2 text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring",
              item.area == @active_area && "border-primary/60 bg-primary text-primary-foreground",
              item.area != @active_area &&
                "border-border bg-card text-foreground hover:border-primary/40 hover:bg-muted"
            ]}
          >
            <span class="block truncate font-semibold">{item.label}</span>
            <span class="mt-1 block truncate text-xs opacity-80">{item.summary}</span>
          </.link>
        </nav>
      </section>
    </Layouts.app>
    """
  end

  defp current_scope(assigns) do
    case Map.get(assigns, :current_user) do
      %{id: id, email: email} -> %{user_id: id, user_email: to_string(email)}
      %{email: email} -> %{user_email: to_string(email)}
      _other -> %{}
    end
  end
end
