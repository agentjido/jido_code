defmodule JidoCodeWeb.DecisionDetailLive do
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  use JidoCodeWeb, :live_view

  alias JidoCode.Control.{Actor, RepoBridge}
  alias JidoCode.Governance.Decision

  @impl true
  def mount(%{"id" => project_id, "decision_id" => decision_id}, _session, socket) do
    socket =
      case load_decision_state(project_id, decision_id) do
        {:ok, %{scope: scope, decision: decision}} ->
          assign_decision(socket, scope, decision)

        {:error, :not_found} ->
          assign_missing_decision(socket, project_id, decision_id)
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
              Governed decision
            </p>
            <h1 :if={@decision} id="decision-detail-title" class="text-2xl font-semibold">
              {display_string(@decision.decision_key, "Decision detail")}
            </h1>
            <h1 :if={!@decision} id="decision-detail-missing-title" class="text-2xl font-semibold">
              Decision not found
            </h1>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <.link
              :if={run_route(@route_repo_id, @decision && @decision.run_id)}
              navigate={run_route(@route_repo_id, @decision && @decision.run_id)}
              class="link link-primary text-sm"
            >
              Open related run
            </.link>
            <.link
              :if={repo_route(@route_repo_id)}
              navigate={repo_route(@route_repo_id)}
              class="link link-primary text-sm"
            >
              Back to repository
            </.link>
          </div>
        </div>

        <%= if @decision do %>
          <section class="grid gap-4 rounded-xl border border-base-300 bg-base-100 p-6 md:grid-cols-2">
            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">ID</p>
              <p id="decision-detail-id" class="font-mono text-sm">{@decision.id}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Decision key</p>
              <p id="decision-detail-key" class="text-sm">{display_string(@decision.decision_key)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Outcome</p>
              <p id="decision-detail-outcome" class="text-sm">{display_atom(@decision.decision)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Run</p>
              <p id="decision-detail-run-id" class="font-mono text-sm">{display_string(@decision.run_id)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Work item</p>
              <p id="decision-detail-work-item-id" class="font-mono text-sm">
                {display_string(@decision.work_item_id, "Unattached")}
              </p>
            </div>

            <div class="space-y-1 md:col-span-2">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Rationale</p>
              <p id="decision-detail-rationale" class="text-sm">
                {display_string(@decision.rationale, "No rationale recorded.")}
              </p>
            </div>
          </section>
        <% else %>
          <section class="rounded-xl border border-warning/40 bg-warning/10 p-6">
            <p id="decision-detail-missing-detail" class="text-sm text-base-content/80">
              No governed decision with id <span class="font-mono">{@decision_id}</span> is available on this managed-repository route.
            </p>
          </section>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp load_decision_state(project_id, decision_id) do
    with {:ok, scope} <- RepoBridge.repo_scope(project_id),
         managed_repo_id when is_binary(managed_repo_id) <- managed_repo_id(scope),
         {:ok, [%Decision{} = decision]} <-
           Decision.read(
             query: [filter: [id: decision_id, managed_repo_id: managed_repo_id], limit: 1],
             actor: Actor.operator_actor()
           ) do
      {:ok, %{scope: scope, decision: decision}}
    else
      _other -> {:error, :not_found}
    end
  end

  defp assign_decision(socket, scope, %Decision{} = decision) do
    socket
    |> assign(:decision, decision)
    |> assign(:decision_id, decision.id)
    |> assign(:managed_repo_id, managed_repo_id(scope))
    |> assign(:route_repo_id, route_repo_id(scope))
  end

  defp assign_missing_decision(socket, project_id, decision_id) do
    socket
    |> assign(:decision, nil)
    |> assign(:decision_id, decision_id)
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

  defp run_route(repo_id, run_id) when is_binary(repo_id) and is_binary(run_id),
    do: "/repos/#{repo_id}/runs/#{run_id}"

  defp run_route(_repo_id, _run_id), do: nil

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

  defp display_atom(value) when is_atom(value), do: Atom.to_string(value)
  defp display_atom(value), do: display_string(value)

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
