defmodule JidoCodeWeb.TestSupport.LiveVueBoundaryLive do
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCodeWeb, :live_view

  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:failure, nil)
      |> assign(:status, "idle")
      |> assign(:task_form, to_form(%{"title" => ""}, as: :task))
      |> allow_upload(:artifact, accept: ~w(.txt), max_entries: 1)
      |> stream(:items, [%{id: "seed-1", label: "Initial item"}])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="hybrid-shell">
      <button id="server-sync" type="button" class="hidden" phx-click="request_sync" phx-value-origin="server">
        Sync
      </button>

      <button id="server-failure" type="button" class="hidden" phx-click="simulate_failure">
        Fail
      </button>

      <.vue_surface
        id="boundary-probe"
        component="BoundaryProbe"
        socket={@socket}
        props={
          %{
            failure: @failure,
            status: @status,
            taskForm: @task_form,
            uploadConfig: @uploads.artifact
          }
        }
        streams={%{items: @streams.items}}
        events={
          %{
            "request-sync" => JS.push("request_sync", value: %{origin: "vue"}),
            "simulate-failure" => "simulate_failure"
          }
        }
      />
    </section>
    """
  end

  @impl true
  def handle_event("request_sync", _params, socket) do
    socket =
      socket
      |> assign(:failure, nil)
      |> assign(:status, "synced")
      |> stream_insert(:items, %{id: "sync-1", label: "Server refresh"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("simulate_failure", _params, socket) do
    {:noreply, assign(socket, :failure, %{kind: "validation", message: "Need a title"})}
  end
end
