defmodule JidoCodeWeb.TestSupport.LiveVueHostShellLive do
  use JidoCodeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :label, "LiveVue ready")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="live-vue-host-shell">
      <.vue
        id="shell-probe"
        label={@label}
        v-component="ShellProbe"
        v-socket={@socket}
      />
    </section>
    """
  end
end
