defmodule JidoCodeWeb.EvidenceDetailLive do
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  use JidoCodeWeb, :live_view

  alias JidoCode.Control.{Actor, RepoBridge}
  alias JidoCode.Governance.Evidence

  @impl true
  def mount(%{"id" => project_id, "evidence_id" => evidence_id}, _session, socket) do
    socket =
      case load_evidence_state(project_id, evidence_id) do
        {:ok, %{scope: scope, evidence: evidence}} ->
          assign_evidence(socket, scope, evidence)

        {:error, :not_found} ->
          assign_missing_evidence(socket, project_id, evidence_id)
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
              Governed evidence
            </p>
            <h1 :if={@evidence} id="evidence-detail-title" class="text-2xl font-semibold">
              {display_string(@evidence.summary, "Evidence detail")}
            </h1>
            <h1 :if={!@evidence} id="evidence-detail-missing-title" class="text-2xl font-semibold">
              Evidence not found
            </h1>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <.link
              :if={run_route(@route_repo_id, @evidence && @evidence.run_id)}
              navigate={run_route(@route_repo_id, @evidence && @evidence.run_id)}
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

        <%= if @evidence do %>
          <section class="grid gap-4 rounded-xl border border-base-300 bg-base-100 p-6 md:grid-cols-2">
            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">ID</p>
              <p id="evidence-detail-id" class="font-mono text-sm">{@evidence.id}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Key</p>
              <p id="evidence-detail-key" class="text-sm">{display_string(@evidence.key)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Type</p>
              <p id="evidence-detail-type" class="text-sm">{display_string(@evidence.evidence_type)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Source</p>
              <p id="evidence-detail-source" class="text-sm">{display_string(@evidence.source)}</p>
            </div>

            <div class="space-y-1 md:col-span-2">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Summary</p>
              <p id="evidence-detail-summary" class="text-sm">{display_string(@evidence.summary)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Run</p>
              <p id="evidence-detail-run-id" class="font-mono text-sm">{display_string(@evidence.run_id)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Work item</p>
              <p id="evidence-detail-work-item-id" class="font-mono text-sm">
                {display_string(@evidence.work_item_id, "Unattached")}
              </p>
            </div>
          </section>
        <% else %>
          <section class="rounded-xl border border-warning/40 bg-warning/10 p-6">
            <p id="evidence-detail-missing-detail" class="text-sm text-base-content/80">
              No governed evidence with id <span class="font-mono">{@evidence_id}</span> is available on this managed-repository route.
            </p>
          </section>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp load_evidence_state(project_id, evidence_id) do
    with {:ok, scope} <- RepoBridge.repo_scope(project_id),
         managed_repo_id when is_binary(managed_repo_id) <- managed_repo_id(scope),
         {:ok, [%Evidence{} = evidence]} <-
           Evidence.read(
             query: [filter: [id: evidence_id, managed_repo_id: managed_repo_id], limit: 1],
             actor: Actor.operator_actor()
           ) do
      {:ok, %{scope: scope, evidence: evidence}}
    else
      _other -> {:error, :not_found}
    end
  end

  defp assign_evidence(socket, scope, %Evidence{} = evidence) do
    socket
    |> assign(:evidence, evidence)
    |> assign(:evidence_id, evidence.id)
    |> assign(:managed_repo_id, managed_repo_id(scope))
    |> assign(:route_repo_id, route_repo_id(scope))
  end

  defp assign_missing_evidence(socket, project_id, evidence_id) do
    socket
    |> assign(:evidence, nil)
    |> assign(:evidence_id, evidence_id)
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
