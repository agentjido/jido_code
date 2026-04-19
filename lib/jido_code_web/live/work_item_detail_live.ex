defmodule JidoCodeWeb.WorkItemDetailLive do
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  use JidoCodeWeb, :live_view

  alias JidoCode.Control.{Actor, RepoBridge}
  alias JidoCode.Operations.WorkItem

  @impl true
  def mount(%{"id" => project_id, "work_item_id" => work_item_id}, _session, socket) do
    socket =
      case load_work_item_state(project_id, work_item_id) do
        {:ok, %{scope: scope, work_item: work_item}} ->
          assign_work_item(socket, scope, work_item)

        {:error, :not_found} ->
          assign_missing_work_item(socket, project_id, work_item_id)
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section class="mx-auto max-w-5xl space-y-6 py-8">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
              Governed work item
            </p>
            <h1 :if={@work_item} id="work-item-detail-title" class="text-2xl font-semibold">
              {display_string(@work_item.summary, "Work item detail")}
            </h1>
            <h1 :if={!@work_item} id="work-item-detail-missing-title" class="text-2xl font-semibold">
              Work item not found
            </h1>
          </div>

          <.link
            :if={repo_route(@route_repo_id)}
            navigate={repo_route(@route_repo_id)}
            class="link link-primary text-sm"
          >
            Back to repository
          </.link>
        </div>

        <%= if @work_item do %>
          <section class="grid gap-4 rounded-xl border border-base-300 bg-base-100 p-6 md:grid-cols-2">
            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">ID</p>
              <p id="work-item-detail-id" class="font-mono text-sm">{@work_item.id}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Status</p>
              <p id="work-item-detail-status" class="text-sm">{display_term(@work_item.status)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Priority</p>
              <p id="work-item-detail-priority" class="text-sm">{display_term(@work_item.priority)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Category</p>
              <p id="work-item-detail-category" class="text-sm">{display_string(@work_item.category)}</p>
            </div>

            <div class="space-y-1 md:col-span-2">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Summary</p>
              <p id="work-item-detail-summary" class="text-sm">{display_string(@work_item.summary)}</p>
            </div>

            <div class="space-y-1 md:col-span-2">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Recommended action
              </p>
              <p id="work-item-detail-recommended-action" class="text-sm">
                {display_string(@work_item.recommended_action)}
              </p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Managed repo
              </p>
              <p id="work-item-detail-managed-repo" class="font-mono text-sm">
                {display_string(@managed_repo_id)}
              </p>
            </div>
          </section>
        <% else %>
          <section class="rounded-xl border border-warning/40 bg-warning/10 p-6">
            <p id="work-item-detail-missing-detail" class="text-sm text-base-content/80">
              No governed work item with id <span class="font-mono">{@work_item_id}</span> is available on this managed-repository route.
            </p>
          </section>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp load_work_item_state(project_id, work_item_id) do
    with {:ok, scope} <- RepoBridge.repo_scope(project_id),
         managed_repo_id when is_binary(managed_repo_id) <- managed_repo_id(scope),
         {:ok, [%WorkItem{} = work_item]} <-
           WorkItem.read(
             query: [filter: [id: work_item_id, managed_repo_id: managed_repo_id], limit: 1],
             actor: Actor.operator_actor()
           ) do
      {:ok, %{scope: scope, work_item: work_item}}
    else
      _other -> {:error, :not_found}
    end
  end

  defp assign_work_item(socket, scope, %WorkItem{} = work_item) do
    socket
    |> assign(:work_item, work_item)
    |> assign(:work_item_id, work_item.id)
    |> assign(:managed_repo_id, managed_repo_id(scope))
    |> assign(:route_repo_id, route_repo_id(scope))
  end

  defp assign_missing_work_item(socket, project_id, work_item_id) do
    socket
    |> assign(:work_item, nil)
    |> assign(:work_item_id, work_item_id)
    |> assign(:managed_repo_id, nil)
    |> assign(:route_repo_id, normalize_optional_string(project_id))
  end

  defp route_repo_id(scope) when is_map(scope) do
    normalize_optional_string(Map.get(scope, :route_id) || Map.get(scope, "route_id"))
  end

  defp route_repo_id(_scope), do: nil

  defp managed_repo_id(scope) when is_map(scope) do
    normalize_optional_string(Map.get(scope, :managed_repo_id) || Map.get(scope, "managed_repo_id"))
  end

  defp managed_repo_id(_scope), do: nil

  defp repo_route(repo_id) when is_binary(repo_id), do: "/repos/#{repo_id}"
  defp repo_route(_repo_id), do: nil

  defp display_string(value, fallback \\ "Unavailable")

  defp display_string(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      normalized -> normalized
    end
  end

  defp display_string(value, fallback) when is_atom(value), do: value |> Atom.to_string() |> display_string(fallback)
  defp display_string(nil, fallback), do: fallback
  defp display_string(value, _fallback), do: to_string(value)

  defp display_term(value) when is_atom(value), do: Atom.to_string(value)
  defp display_term(value), do: display_string(value)

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil
end
