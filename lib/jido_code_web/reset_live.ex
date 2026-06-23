defmodule JidoCodeWeb.ResetLive do
  @moduledoc false

  use Phoenix.Component

  defmacro __using__(opts) do
    title = Keyword.fetch!(opts, :title)

    quote bind_quoted: [title: title] do
      use JidoCodeWeb, :live_view

      @reset_page_title title

      @impl true
      def mount(_params, _session, socket) do
        {:ok, assign(socket, page_title: @reset_page_title, route_uri: nil)}
      end

      @impl true
      def handle_params(_params, uri, socket) do
        {:noreply, assign(socket, :route_uri, uri)}
      end

      @impl true
      def render(assigns) do
        JidoCodeWeb.ResetLive.render(assigns)
      end
    end
  end

  def render(assigns) do
    ~H"""
    <main id="jido-code-reset-surface" class="min-h-screen bg-background text-foreground">
      <section class="mx-auto flex min-h-screen w-full max-w-5xl flex-col justify-center px-6 py-16">
        <p class="text-sm font-medium uppercase tracking-wide text-muted-foreground">
          Jido.Code
        </p>
        <h1 class="mt-3 text-3xl font-semibold text-foreground sm:text-4xl">
          {@page_title}
        </h1>
        <p class="mt-4 max-w-2xl text-sm leading-6 text-muted-foreground">
          This route is available for the new frontend rebuild. The previous UI component
          and app layout layer has been removed.
        </p>
      </section>
    </main>
    """
  end
end
